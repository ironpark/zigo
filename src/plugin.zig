//! The generator's plugin contract. A plugin is an ordinary Zig package that
//! compiles against this file alone: it names itself, owns typed function and
//! type options, validates its own declarations, and adds generated code
//! through hooks.
//!
//! A plugin declares two independent things about what it applies to.
//! `subjects` is the kind of declaration -- function, handle, value and so on.
//! The output language is the `go` and `rust` render slots: a slot holds the
//! visit, the claims answer, the source files and the imports for one
//! language, and a plugin renders for exactly the languages whose slot it
//! filled. There is no list of target names to keep in step with the writers
//! a hook actually calls, because the writers *are* the slot.
//!
//! Semantic transforms run before validation and may change the ABI. Rendering
//! hooks are additive; they cannot modify the shim, header or raw API.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const diagnostic = @import("diagnostic");
const naming = @import("naming");
const targets = @import("targets");

/// Major versions are incompatible; minor versions add capabilities.
pub const ContractVersion = struct { major: u16, minor: u16 };
pub const contract_version: ContractVersion = .{ .major = 7, .minor = 0 };

/// Serialized build configuration; decoded as the registered plugin's Config.
pub const Configuration = struct { name: []const u8, json: []const u8 };

pub fn readConfig(comptime P: Plugin, allocator: std.mem.Allocator, configurations: []const Configuration) !P.Config {
    var json: []const u8 = "{}";
    for (configurations) |entry| {
        if (std.mem.eql(u8, entry.name, P.name)) {
            json = entry.json;
            break;
        }
    }
    return std.json.parseFromSliceLeaky(P.Config, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidPluginConfig,
    };
}

/// The built-in plugins' descriptors and option readers. Built-ins are
/// attached and read through the same contract an added plugin uses.
pub const builtins = @import("plugin/builtins.zig");
pub const interfaces = @import("plugin/interfaces.zig");
pub const session = @import("plugin/session.zig");
const site_module = @import("plugin/site.zig");
pub const site = site_module;
pub const rename = @import("plugin/rename.zig");
/// Reference-typed option fields: `ref.Type`, `ref.Function` and
/// `ref.Interface` name a declaration instead of spelling it as free text.
/// A binding writes them with `api.typeRef(...)`, `api.ref(...)` and the
/// entry `zigo.interface(...)` returned; a hook reads them back through the
/// `resolve*` helpers every context carries.
pub const ref = @import("plugin/ref.zig");
/// The Go formatting helpers that need no generator state. The emitter's
/// writers table points at them; a plugin calls them through its context.
pub const format = @import("plugin/format.zig");

/// The Go AST a hook builds instead of printing Go source. `GoContext.builder`
/// is how a plugin reaches it.
pub const gobuild = @import("plugin/gobuild.zig");
pub const Builder = gobuild.Builder;

/// The Rust AST a hook builds instead of printing Rust source.
/// `RustContext.builder` is how a plugin reaches it.
pub const rustbuild = @import("plugin/rustbuild.zig");
pub const RustBuilder = rustbuild.Builder;

/// Runs before lowering. All allocations and diagnostics belong to the run arena.
pub const DeclarationId = struct {
    kind: enum { document, function, type, package },
    name: []const u8,
    receiver: ?[]const u8 = null,
    namespace: ?[]const u8 = null,
    package: ?[]const u8 = null,

    pub fn function(value: semantic.SemanticFn) DeclarationId {
        return .{ .kind = .function, .name = value.name, .receiver = value.receiver, .namespace = value.namespace, .package = value.package };
    }
    pub fn declaration(value: semantic.TypeDecl) DeclarationId {
        return .{ .kind = .type, .name = value.name, .package = value.package };
    }
};

/// Whether `names`, the capabilities the enabled plugins provide, holds `cap`.
fn hasCapability(names: []const []const u8, comptime cap: Capability) bool {
    for (names) |name| if (std.mem.eql(u8, name, cap.name)) return true;
    return false;
}

/// A named, typed facts contract between plugins. The provider publishes it
/// in `Plugin.provides` and writes facts under it; a consumer names the same
/// capability in `requires` or `uses`, is ordered after every provider of it,
/// and reads those facts without knowing which plugin wrote them.
///
/// Capabilities are compared by `name`, so a provider and a consumer that
/// share a definition share a type. A capability with no data to carry keeps
/// `Facts` at the empty struct and is ordering alone.
pub const Capability = struct {
    name: []const u8,
    /// The value one fact under this capability carries.
    Facts: type,
    /// Whether more than one enabled plugin may provide it. A non-`multi`
    /// capability with two providers is a registration error.
    multi: bool = false,
};

/// The capabilities the generator's own plugins publish, importable by any
/// plugin that wants to read or extend what a built-in records.
pub const capabilities = @import("plugin/capabilities.zig");

/// Whether `P` may write facts under `cap`; a compile error when it may not.
pub fn assertProvides(comptime P: Plugin, comptime cap: Capability) void {
    comptime {
        for (P.provides) |entry| if (std.mem.eql(u8, entry.name, cap.name)) return;
        @compileError("plugin does not provide capability: " ++ P.name ++ " does not provide " ++ cap.name);
    }
}

/// A run-arena-owned, typed store keyed by capability. Keys borrow the
/// document; values must live until generation ends. Rendering receives only
/// a const view of the store.
pub const Facts = struct {
    const Key = struct { owner: []const u8, id: DeclarationId };
    const Value = struct { type_name: []const u8, data: *const anyopaque };
    const KeyContext = struct {
        pub fn hash(_: @This(), key: Key) u64 {
            var hasher = std.hash.Wyhash.init(@intFromEnum(key.id.kind));
            hasher.update(key.owner);
            hasher.update(&.{0});
            hasher.update(key.id.name);
            inline for (.{ key.id.receiver, key.id.namespace, key.id.package }) |part| {
                hasher.update(&.{@intFromBool(part != null)});
                if (part) |text| hasher.update(text);
                hasher.update(&.{0});
            }
            return hasher.final();
        }
        pub fn eql(_: @This(), a: Key, b: Key) bool {
            return a.id.kind == b.id.kind and std.mem.eql(u8, a.owner, b.owner) and std.mem.eql(u8, a.id.name, b.id.name) and semantic.optionalStringEqual(a.id.receiver, b.id.receiver) and semantic.optionalStringEqual(a.id.namespace, b.id.namespace) and semantic.optionalStringEqual(a.id.package, b.id.package);
        }
    };
    entries: std.HashMapUnmanaged(Key, Value, KeyContext, 80) = .empty,

    /// Writes one fact under `cap`. The checked path is `context.provide`,
    /// which also proves the writing plugin provides the capability.
    pub fn put(self: *Facts, allocator: std.mem.Allocator, comptime cap: Capability, id: DeclarationId, value: cap.Facts) !void {
        const key: Key = .{ .owner = cap.name, .id = id };
        if (self.entries.contains(key)) return error.DuplicatePluginFact;
        const stored = try allocator.create(cap.Facts);
        stored.* = value;
        try self.entries.put(allocator, key, .{ .type_name = @typeName(cap.Facts), .data = stored });
    }
    /// Reads the fact `cap` carries for `id`, whichever plugin provided it.
    pub fn get(self: *const Facts, comptime cap: Capability, id: DeclarationId) !?cap.Facts {
        const value = self.entries.get(.{ .owner = cap.name, .id = id }) orelse return null;
        if (!std.mem.eql(u8, value.type_name, @typeName(cap.Facts))) return error.PluginFactTypeMismatch;
        const stored: *const cap.Facts = @ptrCast(@alignCast(value.data));
        return stored.*;
    }
};

/// An immutable input snapshot; returned documents and hook results must live in
/// this run arena. Transform output is checked before validation callbacks or lowering.
pub const TransformContext = struct {
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    configurations: []const Configuration = &.{},
    diagnostics: *std.ArrayList(diagnostic.Diagnostic),
    /// The output language this run generates for.
    target: targets.Target = targets.default,
    /// The capabilities the enabled plugins provide, by name.
    capabilities: []const []const u8 = &.{},

    /// Whether a registered and enabled plugin provides `cap`, which is what
    /// a consumer of a soft capability asks before it looks for facts.
    pub fn provided(self: TransformContext, comptime cap: Capability) bool {
        return hasCapability(self.capabilities, cap);
    }

    pub fn config(self: TransformContext, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.configurations);
    }
    pub fn diagnose(self: TransformContext, issue: diagnostic.Diagnostic) !void {
        try self.diagnostics.append(self.allocator, issue);
    }
    pub fn optionsOf(self: TransformContext, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?Options(P, attachment) {
        return readOptions(P, attachment, self.allocator, ext);
    }
    /// The declarations a reference-typed option names, in the document as it
    /// stands. Rendering contexts answer the same three questions against the
    /// lowered program.
    pub fn resolveType(self: TransformContext, reference: ref.Type) !?*const semantic.TypeDecl {
        return ref.findType(self.document.types, reference);
    }
    pub fn resolveFunction(self: TransformContext, reference: ref.Function) !?*const semantic.SemanticFn {
        return ref.findFunction(self.document.types, self.document.functions, reference);
    }
    pub fn resolveInterface(self: TransformContext, reference: ref.Interface) !?*const semantic.Interface {
        return ref.findInterface(self.document.interfaces orelse &.{}, reference);
    }

    /// new_order[new_index] is the old parameter index. Native argument order
    /// (including injected arguments and the receiver) is preserved across
    /// repeated reorders. The C and public Go parameter order changes.
    pub fn reorderParameters(self: TransformContext, function: semantic.SemanticFn, new_order: []const usize) !semantic.SemanticFn {
        if (new_order.len != function.params.len) return error.InvalidParameterOrder;
        const params = try self.allocator.alloc(semantic.Parameter, new_order.len);
        for (new_order, 0..) |old_index, new_index| {
            if (old_index >= function.params.len) return error.InvalidParameterOrder;
            for (new_order[0..new_index]) |previous| if (previous == old_index) return error.InvalidParameterOrder;
            params[new_index] = function.params[old_index];
            params[new_index].native_index = function.params[old_index].native_index orelse old_index;
        }
        var result = function;
        result.params = params;
        return result;
    }
};

/// Conversion sites supported by the core adapter lowering. A null result
/// preserves the current adapter; a non-null result replaces it. Later plugins
/// see earlier choices. Unsupported adapters are rejected by core validation.
pub const TypeUse = union(enum) {
    declaration: semantic.TypeDecl,
    parameter: struct { function: semantic.SemanticFn, index: usize },
    result: semantic.SemanticFn,
};

/// Which node an `ext` object came off, and so which of the plugin's option
/// types reads it. `function` and `type` are the declaration-level pair;
/// `param`, `result`, `field` and `enum_tag` are the nodes inside one.
pub const Attachment = enum { function, type, param, result, field, enum_tag };

/// The option type `P` declares for `attachment`.
pub fn Options(comptime P: Plugin, comptime attachment: Attachment) type {
    return switch (attachment) {
        .function => P.FunctionOptions,
        .type => P.TypeOptions,
        .param => P.ParamOptions,
        .result => P.ResultOptions,
        .field => P.FieldOptions,
        .enum_tag => P.TagOptions,
    };
}

/// The subject a plugin has to declare in `subjects` to attach to
/// `attachment`. `type` has no single subject -- the declaration's kind is
/// its subject -- so it is resolved through `typeSubject` instead.
pub fn attachmentSubject(attachment: Attachment) ?Subject {
    return switch (attachment) {
        .function => .function,
        .type => null,
        .param => .param,
        .result => .result,
        .field => .field,
        .enum_tag => .enum_tag,
    };
}

pub const ValidateContext = struct {
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    configurations: []const Configuration = &.{},
    diagnostics: *std.ArrayList(diagnostic.Diagnostic),
    facts: *Facts,
    /// The output language this run generates for.
    target: targets.Target = targets.default,
    /// The capabilities the enabled plugins provide, by name.
    capabilities: []const []const u8 = &.{},

    /// Records one fact under `cap`, which `P` has to provide.
    pub fn provide(self: ValidateContext, comptime P: Plugin, comptime cap: Capability, id: DeclarationId, value: cap.Facts) !void {
        comptime assertProvides(P, cap);
        return self.facts.put(self.allocator, cap, id, value);
    }

    /// Whether a registered and enabled plugin provides `cap`, which is what
    /// a consumer of a soft capability asks before it looks for facts.
    pub fn provided(self: ValidateContext, comptime cap: Capability) bool {
        return hasCapability(self.capabilities, cap);
    }

    pub fn diagnose(self: ValidateContext, issue: diagnostic.Diagnostic) !void {
        try self.diagnostics.append(self.allocator, issue);
    }

    pub fn config(self: ValidateContext, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.configurations);
    }

    pub fn optionsOf(self: ValidateContext, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?Options(P, attachment) {
        return readOptions(P, attachment, self.allocator, ext);
    }
    pub fn resolveType(self: ValidateContext, reference: ref.Type) !?*const semantic.TypeDecl {
        return ref.findType(self.document.types, reference);
    }
    pub fn resolveFunction(self: ValidateContext, reference: ref.Function) !?*const semantic.SemanticFn {
        return ref.findFunction(self.document.types, self.document.functions, reference);
    }
    pub fn resolveInterface(self: ValidateContext, reference: ref.Interface) !?*const semantic.Interface {
        return ref.findInterface(self.document.interfaces orelse &.{}, reference);
    }
};

/// What a hook may read about the run: the output target, where the generated
/// packages live, which package is being rendered, the build configuration and
/// the helper gate. The emitter's own knobs -- link flags, library paths, the
/// backend -- are not here: a plugin renders against this view alone, and the
/// generator fills it from its options for every context it hands out.
pub const PluginOptions = struct {
    /// The output language this run generates for.
    target: targets.Target = targets.default,
    /// The Go module path of the generated tree.
    go_module: []const u8 = "",
    /// Public Go package name. Empty derives it from the binding name.
    go_package: []const u8 = "",
    /// Public package path below the module root. Empty defaults to the public
    /// package name; `.` publishes at the module root.
    go_package_path: []const u8 = "",
    /// Module-relative directory of the raw package.
    raw_package_path: []const u8 = "internal/raw",
    /// Whether the raw layer sits inside the public package instead of a
    /// package of its own, which is what decides the qualifier a raw call is
    /// written with.
    raw_colocated: bool = false,
    /// Null renders the legacy single package; empty selects the default package
    /// of a split document; a value selects that named sub-package.
    active_package: ?[]const u8 = null,
    configurations: []const Configuration = &.{},
    /// Which generated helpers the public package references, decided by the
    /// emitter from a rendering of it. Null emits every gated helper, which
    /// only the discovery rendering itself relies on being absent.
    helpers: ?HelperSet = null,
    /// The file being rendered, when the hook runs inside one.
    file: ?FileInfo = null,
    /// The capabilities the enabled plugins provide, by name.
    capabilities: []const []const u8 = &.{},

    /// Whether a gated helper of this name is written.
    pub fn emitsHelper(self: PluginOptions, name: []const u8) bool {
        const set = self.helpers orelse return true;
        return set.contains(set.context, name);
    }
};

/// The emitter's answer to "does the package reference this helper", handed
/// over as a predicate so the set behind it stays the emitter's own.
pub const HelperSet = struct {
    context: *const anyopaque,
    contains: *const fn (*const anyopaque, []const u8) bool,
};

/// Document outputs run once with the full program. Package outputs run once
/// per public package, with that package's function view and active_package.
pub const OutputScope = enum { document, package };
pub const PackageKind = enum { public, external_test, raw };
pub const FileKind = enum { source, test_file };

/// A framed Go body. The path is module-relative and must belong to the chosen
/// package directory. Use sourceFilePathAlloc to construct it. Raw outputs require
/// document scope; external_test outputs require test kind.
pub const SourceFile = struct {
    enabled: ?*const fn (GoContext) anyerror!bool = null,
    scope: OutputScope = .package,
    package: PackageKind = .public,
    kind: FileKind = .source,
    /// Single-line ASCII Go build expression (up to 4096 bytes).
    build_constraint: ?[]const u8 = null,
    imports: ?*const fn (GoContext) anyerror![]const Import = null,
    pathAlloc: *const fn (GoContext) anyerror![]u8,
    render: *const fn (GoContext, *std.Io.Writer) anyerror!void,
};

/// Exact bytes, including empty output and trailing newlines. No Go framing,
/// hooks, helper scan or automatic import inference applies, even for .go paths.
pub const Artifact = struct {
    enabled: ?*const fn (ArtifactContext) anyerror!bool = null,
    scope: OutputScope = .document,
    pathAlloc: *const fn (ArtifactContext) anyerror![]u8,
    render: *const fn (ArtifactContext, *std.Io.Writer) anyerror!void,
};

pub const ArtifactContext = struct {
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: PluginOptions,

    /// The output language this run generates for.
    pub fn target(self: ArtifactContext) targets.Target {
        return self.options.target;
    }
    pub fn config(self: ArtifactContext, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.options.configurations);
    }
    pub fn publicFilePathAlloc(self: ArtifactContext, filename: []const u8) ![]u8 {
        return publicFilePathAllocImpl(self.allocator, self.program, self.options, filename);
    }
};

pub fn sourceFilePathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: PluginOptions, package: PackageKind, filename: []const u8) ![]u8 {
    if (package != .raw) return publicFilePathAlloc(allocator, program, options, filename);
    if (options.raw_package_path.len == 0 or std.mem.eql(u8, options.raw_package_path, ".")) return allocator.dupe(u8, filename);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ options.raw_package_path, filename });
}
const sourceFilePathAllocImpl = sourceFilePathAlloc;

/// Module-relative path for a file in the currently rendered public package.
/// Call from SourceFile.pathAlloc or Artifact.pathAlloc; the caller owns the returned allocation.
pub fn publicFilePathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: PluginOptions, filename: []const u8) ![]u8 {
    const directory = if (options.go_package_path.len != 0)
        try allocator.dupe(u8, options.go_package_path)
    else if (options.go_package.len != 0)
        try allocator.dupe(u8, options.go_package)
    else
        try options.target.packageNameAlloc(allocator, program.package);
    defer allocator.free(directory);
    if (std.mem.eql(u8, directory, ".")) return allocator.dupe(u8, filename);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory, filename });
}

const publicFilePathAllocImpl = publicFilePathAlloc;

pub const ResultOptions = struct {
    /// Drop only the public trailing error; optional presence flags remain.
    omit_error: bool = false,
};

/// A non-standard Go import a hook may write. It is added to a file only when
/// the rendered body actually spells the qualifier, the same rule the built-in
/// imports follow.
pub const Import = struct {
    /// The name the body writes before the dot.
    qualifier: []const u8,
    /// The Go import path.
    path: []const u8,
};

/// The public-package writers a hook needs but cannot reimplement: they answer
/// for package qualification and for the exact spelling a generated signature
/// has. Passed as a table so a plugin compiled as its own module reaches them
/// without importing generator internals. They are also the Go builder's
/// backend: `Expr.type_name`, `Expr.go_type`, `Expr.value_type` and
/// `Signature.function` render through them.
pub const Writers = struct {
    /// The type name as this package spells it, qualified when the type lives
    /// in another generated package.
    writeTypeName: *const fn (GoContext, *std.Io.Writer, []const u8) anyerror!void,
    /// The Go spelling of a semantic type node.
    writeGoType: *const fn (GoContext, *std.Io.Writer, semantic.TypeNode) anyerror!void,
    /// The receiver name a method of this type is written with.
    receiverNameAlloc: *const fn (GoContext, std.mem.Allocator, []const u8) anyerror![]u8,
    /// The parameter list and result of a public function, parentheses
    /// included, exactly as the method being hooked spells them.
    writeSignature: *const fn (GoContext, *std.Io.Writer, abi.AbiFn, SignatureOptions) anyerror!void,
    writeValueType: *const fn (GoContext, *std.Io.Writer, abi.AbiFn) anyerror!void,
    writeDoc: *const fn (*std.Io.Writer, []const u8, []const u8, []const u8) anyerror!void,
    functionInfo: *const fn (GoContext, abi.AbiFn) anyerror!FunctionInfo,
    writeParameters: *const fn (GoContext, *std.Io.Writer, abi.AbiFn) anyerror!void,
    writeResultType: *const fn (GoContext, *std.Io.Writer, abi.AbiFn, ResultOptions) anyerror!usize,
    writeCallArguments: *const fn (GoContext, *std.Io.Writer, abi.AbiFn) anyerror!void,
    /// A Zig name as the generated package spells it: an enum tag or a struct
    /// field becomes its exported member name with `.pascal`, a local or a
    /// parameter its unexported spelling with `.camel`.
    identifierAlloc: *const fn (GoContext, std.mem.Allocator, []const u8, IdentifierStyle) anyerror![]u8,
    /// The callee a public Go body writes to reach one raw function:
    /// `raw.Answer`, or the colocated `zigoRawAnswer` when the raw layer sits
    /// inside the public package. The qualifier is part of it, so the builder
    /// never has to know which layout is in force.
    rawCallNameAlloc: *const fn (GoContext, std.mem.Allocator, abi.AbiFn) anyerror![]u8,
};

/// The receiver clause of a method header: `(name *Type)` or `(name Type)`.
pub const Receiver = struct {
    name: []const u8,
    type: []const u8,
    pointer: bool = false,
};

/// How `identifierAlloc` spells a name: `SomeName` or `someName`.
pub const IdentifierStyle = enum { pascal, camel };

/// What a `function` node is adjacent to: the method or item the generator
/// just wrote. The names are the ones it used, so a wrapper that calls it can
/// never spell the call differently. Shared by both render slots; where a
/// field names Go below, Rust's answer is the same fact in Rust's spelling.
pub const Method = struct {
    /// The method's exported name in the output language. A declaration a
    /// plugin claimed with `claims` has no method under this name yet: the
    /// name is what the visit is expected to write.
    public_name: []const u8,
    /// The name the generated body was actually written under. The same as
    /// `public_name`, except on a declaration this plugin claimed, where it is
    /// the unexported name the wrapper has to call.
    checked_name: []const u8,
    /// The receiver type, absent for a free function. `Rust` names the handle
    /// type the `impl` block is for.
    receiver: ?[]const u8 = null,
    /// The receiver variable name, absent for a free function. Always `self`
    /// in Rust.
    receiver_name: ?[]const u8 = null,
    /// The public parameter names, indexed by semantic parameter.
    param_names: [][]u8,
    /// The handle type a constructor hands back, when it is one.
    owned_type: ?[]const u8 = null,
    /// Whether the public signature carries a failure channel: Go's trailing
    /// `error`, Rust's `Result`.
    needs_check: bool = false,
};

/// What every rendering context answers for, whatever language it renders:
/// the lowered program, the plugin's view of the options in force, the run
/// arena, and the facts `analyze` recorded. `GoContext` and `RustContext` each
/// carry these four and reach the behaviour here through `base`, so the
/// language-neutral half of the contract is written once and a hook still
/// spells `context.allocator` rather than `context.base.allocator`.
pub const ContextBase = struct {
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: PluginOptions,
    /// What `analyze` recorded, read-only: rendering may not add facts.
    facts: *const Facts = &.{},

    /// The output language this run generates for.
    pub fn target(self: ContextBase) targets.Target {
        return self.options.target;
    }
    /// Whether a registered and enabled plugin provides `cap`, which is what
    /// a consumer of a soft capability asks before it looks for facts.
    pub fn provided(self: ContextBase, comptime cap: Capability) bool {
        return hasCapability(self.options.capabilities, cap);
    }
    pub fn config(self: ContextBase, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.options.configurations);
    }
    pub fn optionsOf(self: ContextBase, comptime P: Plugin, comptime attachment: Attachment, source: anytype) !?Options(P, attachment) {
        return readOptions(P, attachment, self.allocator, extensionsOf(source));
    }
    pub fn publicFilePathAlloc(self: ContextBase, filename: []const u8) ![]u8 {
        return publicFilePathAllocImpl(self.allocator, self.program, self.options, filename);
    }

    /// The declaration a `ref.Type` option names, as the program carries it
    /// after every rename. Null means the reference resolves to nothing,
    /// which core validation has already reported as `<NAME>002`: a hook that
    /// reaches here can treat null as "nothing to write".
    pub fn resolveType(self: ContextBase, reference: ref.Type) !?*const semantic.TypeDecl {
        return ref.findType(self.program.types, reference);
    }
    /// The function a `ref.Function` option names.
    pub fn resolveFunction(self: ContextBase, reference: ref.Function) !?*const semantic.SemanticFn {
        return ref.findFunction(self.program.types, self.program.origins, reference);
    }
    /// The interface a `ref.Interface` option names, as the lowered program
    /// spells it: the methods and the implementing types, not the document's
    /// record of what the binding said.
    pub fn resolveInterface(self: ContextBase, reference: ref.Interface) !?abi.AbiInterface {
        for (self.program.interfaces) |interface| {
            if (std.mem.eql(u8, interface.name, reference.name)) return interface;
        }
        return null;
    }

    /// `P`'s own native symbols, as lowering put them into the program: the
    /// lowered form of what `P.native.symbols` returned, in the order it
    /// returned them. A hook that wraps one reads the symbol here and spells
    /// the call with `Expr.rawCall`, so the two can never disagree about the
    /// name.
    pub fn nativeSymbols(self: ContextBase, comptime P: Plugin) ![]const abi.AbiFn {
        var found: std.ArrayList(abi.AbiFn) = .empty;
        for (self.program.functions) |function| {
            const origin = function.origin.plugin orelse continue;
            if (!std.mem.eql(u8, origin.plugin, P.name)) continue;
            try found.append(self.allocator, function);
        }
        return found.toOwnedSlice(self.allocator);
    }
};

/// What a hook is given besides its builder: the lowered program, the
/// plugin's view of the options in force, the writers table, the facts
/// `analyze` recorded, and -- on the nodes inside a method -- the method the
/// output is being written after.
pub const GoContext = struct {
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: PluginOptions,
    writers: *const Writers,
    /// What `analyze` recorded, read-only: rendering may not add facts.
    facts: *const Facts = &.{},
    /// Set on the `function`, `param` and `result` nodes, which are all
    /// written at the insertion point the method itself left; null in every
    /// other rendering context.
    method: ?Method = null,

    /// The language-neutral half of this context, which is what a helper
    /// that does not write Go asks for.
    pub fn base(self: GoContext) ContextBase {
        return .{ .allocator = self.allocator, .program = self.program, .options = self.options, .facts = self.facts };
    }

    /// The output language this run generates for.
    pub fn target(self: GoContext) targets.Target {
        return self.base().target();
    }
    /// Whether a registered and enabled plugin provides `cap`, which is what
    /// a consumer of a soft capability asks before it looks for facts.
    pub fn provided(self: GoContext, comptime cap: Capability) bool {
        return self.base().provided(cap);
    }
    /// This plugin's own native symbols, as lowering put them into the program.
    pub fn nativeSymbols(self: GoContext, comptime P: Plugin) ![]const abi.AbiFn {
        return self.base().nativeSymbols(P);
    }
    pub fn config(self: GoContext, comptime P: Plugin) !P.Config {
        return self.base().config(P);
    }
    pub fn resolveType(self: GoContext, reference: ref.Type) !?*const semantic.TypeDecl {
        return self.base().resolveType(reference);
    }
    pub fn resolveFunction(self: GoContext, reference: ref.Function) !?*const semantic.SemanticFn {
        return self.base().resolveFunction(reference);
    }
    pub fn resolveInterface(self: GoContext, reference: ref.Interface) !?abi.AbiInterface {
        return self.base().resolveInterface(reference);
    }

    // The writers below render Go source, and that is exactly what the `go`
    // render slot means: a plugin reaches them only from a hook it put in
    // that slot, so they never have to answer for another language.

    pub fn writeTypeName(self: GoContext, writer: *std.Io.Writer, name: []const u8) !void {
        return self.writers.writeTypeName(self, writer, name);
    }

    pub fn writeGoType(self: GoContext, writer: *std.Io.Writer, node: semantic.TypeNode) !void {
        return self.writers.writeGoType(self, writer, node);
    }

    pub fn receiverNameAlloc(self: GoContext, allocator: std.mem.Allocator, type_name: []const u8) ![]u8 {
        return self.writers.receiverNameAlloc(self, allocator, type_name);
    }

    pub fn writeSignature(self: GoContext, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        return self.writers.writeSignature(self, writer, function, .{});
    }

    /// Public parameter list including parentheses. Names are derived outside method hooks.
    pub fn writeParameters(self: GoContext, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        const write = self.writers.writeParameters;
        return write(self, writer, function);
    }

    /// Public results including their leading space and any tuple parentheses.
    /// Returns the number of emitted results, allowing wrappers to choose a
    /// forwarding helper without parsing Go source. Zero results write nothing.
    pub fn writeResultType(self: GoContext, writer: *std.Io.Writer, function: abi.AbiFn, options: ResultOptions) !usize {
        const write = self.writers.writeResultType;
        return write(self, writer, function, options);
    }

    /// Arguments in public parameter order, without parentheses.
    pub fn writeCallArguments(self: GoContext, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        const write = self.writers.writeCallArguments;
        return write(self, writer, function);
    }

    pub fn writeSignatureWith(self: GoContext, writer: *std.Io.Writer, function: abi.AbiFn, options: SignatureOptions) !void {
        return self.writers.writeSignature(self, writer, function, options);
    }
    pub fn writeValueType(self: GoContext, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        return self.writers.writeValueType(self, writer, function);
    }
    pub fn writeDoc(self: GoContext, writer: *std.Io.Writer, public_name: []const u8, zig_name: []const u8, doc: []const u8) !void {
        return self.writers.writeDoc(writer, public_name, zig_name, doc);
    }
    pub fn functionInfo(self: GoContext, function: abi.AbiFn) !FunctionInfo {
        return self.writers.functionInfo(self, function);
    }

    /// Path in this SourceFile's selected package, or the public package in other hooks.
    pub fn sourceFilePathAlloc(self: GoContext, filename: []const u8) ![]u8 {
        const selected_package = if (self.options.file) |file| if (file.source_file) |go| go.package else .public else .public;
        return sourceFilePathAllocImpl(self.allocator, self.program, self.options, selected_package, filename);
    }

    pub fn publicFilePathAlloc(self: GoContext, filename: []const u8) ![]u8 {
        return self.base().publicFilePathAlloc(filename);
    }

    /// `P`'s options on the node whose `ext` this is -- the function being
    /// written, the type being visited, or one of the nodes inside either --
    /// or null when nothing attached `P` there. `source` is the `ext` object
    /// itself or the `Node` carrying it, so a visit reads its own node with
    /// `optionsOf(P, .param, node)`.
    pub fn optionsOf(self: GoContext, comptime P: Plugin, comptime attachment: Attachment, source: anytype) !?Options(P, attachment) {
        return self.base().optionsOf(P, attachment, source);
    }

    /// The Go AST builder a hook composes its output with. Nodes it builds
    /// live on this context's allocator, which the generator backs with the
    /// run arena.
    pub fn builder(self: GoContext) Builder {
        return .{ .allocator = self.allocator, .context = self };
    }

    /// A Zig name as the generated package spells it. The caller owns the result.
    pub fn identifierAlloc(self: GoContext, allocator: std.mem.Allocator, name: []const u8, style: IdentifierStyle) ![]u8 {
        return self.writers.identifierAlloc(self, allocator, name, style);
    }
};

/// How `RustWriters.identifierAlloc` spells a name: `some_name`, `SomeName`
/// or `SOME_NAME`. Rust's three casings, which is one more than Go has, so
/// the Rust slot takes its own style enum rather than borrowing Go's.
pub const RustIdentifierStyle = enum { snake, pascal, screaming };

pub const RustSignatureOptions = struct {
    /// Write the parameter names as well as the types.
    parameter_names: bool = true,
    /// Write the receiver, when the bound method has one.
    receiver: bool = true,
};

/// Names are allocated from the context's allocator.
pub const RustFunctionInfo = struct {
    /// The function's public Rust name, snake case.
    public_name: []const u8,
    /// Whether the crate publishes this function at all.
    is_public: bool,
    /// Whether the public signature is a `Result`.
    has_error: bool,
};

/// The crate's writers a hook needs but cannot reimplement, the Rust
/// counterpart of `Writers`. They are the Rust builder's backend:
/// `rustbuild.Expr.type_name` and `rustbuild.Signature.function` render
/// through them.
pub const RustWriters = struct {
    /// The type name as the crate spells it.
    writeTypeName: *const fn (RustContext, *std.Io.Writer, []const u8) anyerror!void,
    /// The parameter list and result of a public function, parentheses
    /// included, exactly as the generated item spells them.
    writeSignature: *const fn (RustContext, *std.Io.Writer, abi.AbiFn, RustSignatureOptions) anyerror!void,
    /// The receiver clause a method of this function takes -- `&self`,
    /// `&mut self` or `self` -- or null for an associated function.
    receiverFormAlloc: *const fn (RustContext, std.mem.Allocator, abi.AbiFn) anyerror!?[]u8,
    /// A Zig name as the crate spells it.
    identifierAlloc: *const fn (RustContext, std.mem.Allocator, []const u8, RustIdentifierStyle) anyerror![]u8,
    functionInfo: *const fn (RustContext, abi.AbiFn) anyerror!RustFunctionInfo,
    /// The path a crate body writes to reach one raw function:
    /// `crate::raw::answer`.
    rawCallNameAlloc: *const fn (RustContext, std.mem.Allocator, abi.AbiFn) anyerror![]u8,
};

/// A `use` declaration a Rust hook may write. Like a Go `Import` it is added
/// to a file only when the rendered body spells the path's last segment.
pub const RustImport = struct {
    /// The path after `use`, without the trailing semicolon: `core::fmt::Write`.
    path: []const u8,
};

/// A module the crate declares beside the generated ones. The file is
/// `src/<module>.rs` and `lib.rs` declares and re-exports it, so a plugin
/// never writes a `mod` line and never picks a path a `cargo` build cannot
/// find. Crate scope only: a Cargo crate has no per-package walk.
pub const RustSourceFile = struct {
    enabled: ?*const fn (RustContext) anyerror!bool = null,
    /// The module name, which is also the file stem. A Rust identifier.
    module: []const u8,
    imports: ?*const fn (RustContext) anyerror![]const RustImport = null,
    render: *const fn (RustContext, *std.Io.Writer) anyerror!void,
};

/// What a Rust hook is given besides its builder. The same shape as
/// `GoContext`, with the crate's writers in place of the package's.
pub const RustContext = struct {
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: PluginOptions,
    writers: *const RustWriters,
    /// What `analyze` recorded, read-only: rendering may not add facts.
    facts: *const Facts = &.{},
    /// Set on the `function`, `param` and `result` nodes, which are all
    /// written at the insertion point the generated item itself left.
    method: ?Method = null,

    pub fn base(self: RustContext) ContextBase {
        return .{ .allocator = self.allocator, .program = self.program, .options = self.options, .facts = self.facts };
    }

    /// The output language this run generates for.
    pub fn target(self: RustContext) targets.Target {
        return self.base().target();
    }
    /// Whether a registered and enabled plugin provides `cap`, which is what
    /// a consumer of a soft capability asks before it looks for facts.
    pub fn provided(self: RustContext, comptime cap: Capability) bool {
        return self.base().provided(cap);
    }
    /// This plugin's own native symbols, as lowering put them into the program.
    pub fn nativeSymbols(self: RustContext, comptime P: Plugin) ![]const abi.AbiFn {
        return self.base().nativeSymbols(P);
    }
    pub fn config(self: RustContext, comptime P: Plugin) !P.Config {
        return self.base().config(P);
    }
    pub fn optionsOf(self: RustContext, comptime P: Plugin, comptime attachment: Attachment, source: anytype) !?Options(P, attachment) {
        return self.base().optionsOf(P, attachment, source);
    }
    pub fn resolveType(self: RustContext, reference: ref.Type) !?*const semantic.TypeDecl {
        return self.base().resolveType(reference);
    }
    pub fn resolveFunction(self: RustContext, reference: ref.Function) !?*const semantic.SemanticFn {
        return self.base().resolveFunction(reference);
    }
    pub fn resolveInterface(self: RustContext, reference: ref.Interface) !?abi.AbiInterface {
        return self.base().resolveInterface(reference);
    }

    pub fn writeTypeName(self: RustContext, writer: *std.Io.Writer, name: []const u8) !void {
        return self.writers.writeTypeName(self, writer, name);
    }
    pub fn writeSignature(self: RustContext, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        return self.writers.writeSignature(self, writer, function, .{});
    }
    pub fn writeSignatureWith(self: RustContext, writer: *std.Io.Writer, function: abi.AbiFn, options: RustSignatureOptions) !void {
        return self.writers.writeSignature(self, writer, function, options);
    }
    /// The receiver clause of the generated method, or null when the function
    /// is not one. The caller owns the result.
    pub fn receiverFormAlloc(self: RustContext, allocator: std.mem.Allocator, function: abi.AbiFn) !?[]u8 {
        return self.writers.receiverFormAlloc(self, allocator, function);
    }
    pub fn identifierAlloc(self: RustContext, allocator: std.mem.Allocator, name: []const u8, style: RustIdentifierStyle) ![]u8 {
        return self.writers.identifierAlloc(self, allocator, name, style);
    }
    pub fn functionInfo(self: RustContext, function: abi.AbiFn) !RustFunctionInfo {
        return self.writers.functionInfo(self, function);
    }

    /// The Rust AST builder a hook composes its output with.
    pub fn builder(self: RustContext) RustBuilder {
        return .{ .allocator = self.allocator, .context = self };
    }
};

/// The `ext` object behind what a caller handed `optionsOf`: a `Node` answers
/// for the node it is, and anything else is already the object.
fn extensionsOf(source: anytype) ?semantic.Extensions {
    return if (@TypeOf(source) == Node) source.ext() else source;
}

/// The diagnostic code a plugin reports unreadable options under: its name
/// followed by `001`. Plugin codes never borrow the `ZIGO` prefix, so a
/// diagnostic always says which plugin objected.
pub fn optionsCode(comptime P: anytype) []const u8 {
    return P.name ++ "001";
}

/// The diagnostic code an unresolvable reference in a plugin's options is
/// reported under: its name followed by `002`. Core validation raises it, so
/// a plugin never has to check its own references.
pub fn refCode(comptime P: anytype) []const u8 {
    return P.name ++ "002";
}

/// `P`'s options on a declaration, or null when the declaration did not
/// attach `P`. The result is allocated from `allocator` and never freed
/// individually: the generator backs it with the arena that owns the run.
/// Every context exposes it as `optionsOf`; that is the one way to read it.
/// `ext` with `P`'s options for `attachment` added, serialized exactly the way
/// `use` serializes them on a declaration, so what the reflector or a
/// transform writes is read back by `optionsOf` unchanged. The result is
/// allocated from `allocator`, which is normally the run arena.
pub fn attached(
    comptime P: Plugin,
    comptime attachment: Attachment,
    allocator: std.mem.Allocator,
    ext: ?semantic.Extensions,
    options: Options(P, attachment),
) !semantic.Extensions {
    const previous = (ext orelse semantic.Extensions{}).entries;
    const entries = try allocator.alloc(semantic.Extensions.Entry, previous.len + 1);
    @memcpy(entries[0..previous.len], previous);
    const text = try std.json.Stringify.valueAlloc(allocator, options, .{});
    entries[previous.len] = .{ .plugin = P.name, .options = try std.json.parseFromSliceLeaky(std.json.Value, allocator, text, .{}) };
    return .{ .entries = entries };
}

/// `P`'s options on an `ext` object, for a caller holding no context: the
/// generator's own rules read a built-in's attachment through exactly what a
/// hook reads it through. A hook has `GoContext.optionsOf` and wants that.
pub fn optionsOn(comptime P: Plugin, comptime attachment: Attachment, allocator: std.mem.Allocator, ext: ?semantic.Extensions) !?Options(P, attachment) {
    return readOptions(P, attachment, allocator, ext);
}

fn readOptions(comptime P: Plugin, comptime attachment: Attachment, allocator: std.mem.Allocator, ext: ?semantic.Extensions) !?Options(P, attachment) {
    const options = (ext orelse return null).get(P.name) orelse return null;
    return std.json.parseFromValueLeaky(Options(P, attachment), allocator, options, .{}) catch return error.InvalidPluginOptions;
}

/// One Zig source file a plugin ships for the generated shim to compile. The
/// file is ordinary Zig: it declares plain functions and exports nothing, so
/// the plugin never has to know the C symbol its declaration ends up behind.
/// The generated shim imports it as `module` and writes the `export` wrapper.
pub const NativeSource = struct {
    /// The file's path relative to the plugin's own root source file, so a
    /// plugin package names its sources the way it names its own imports.
    path: []const u8,
    /// The name the shim imports it under. It is also the name a
    /// `NativeSymbol` selects the source by, and it has to be a Zig
    /// identifier that no other plugin uses.
    module: []const u8,
};

/// One C symbol a plugin exports out of its own native source. The signature
/// is spelled in the lowered ABI vocabulary rather than in Zig types, because
/// this symbol never goes through the semantic walk: it is already the C
/// shape the header, the raw packages and `abi-diff` will carry.
pub const NativeSymbol = struct {
    /// The short name. The exported symbol is
    /// `<prefix>_<plugin in lower case>_<name>`, so two plugins can both
    /// contribute a `version` without colliding.
    name: []const u8,
    params: []const abi.AbiParam = &.{},
    /// A plain scalar, or `plugin.c_string` for a NUL-terminated string.
    ret: abi.AbiScalar = .void,
    /// The declaration inside the source that implements it, as a Zig path:
    /// `answer`, or `info.build` for one nested in a container.
    implementation: []const u8,
    /// Which of the plugin's `sources` the implementation lives in, by module
    /// name. Empty selects the plugin's only source, which is what a plugin
    /// shipping one file wants.
    module: []const u8 = "",
    /// The comment written above the declaration in the C header and in the
    /// raw packages.
    doc: ?[]const u8 = null,
};

/// What a plugin's native contribution is: the Zig it ships and the C symbols
/// that Zig stands behind. Both halves are optional in practice -- a plugin
/// may ship a source that only the shim's `comptime` reference pulls in -- but
/// a symbol without a source has nothing to call.
pub const Native = struct {
    sources: []const NativeSource = &.{},
    /// Asked once per generation, before lowering appends the results to the
    /// program. Must be deterministic: the same document and configuration
    /// have to produce the same symbols, since `semantic.json` records them
    /// and `abi-diff` compares two recordings.
    symbols: ?*const fn (NativeContext) anyerror![]const NativeSymbol = null,
};

/// What `Native.symbols` is given: the document as parsed, the configuration
/// the build passed, and the run arena every returned slice must live in.
pub const NativeContext = struct {
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    configurations: []const Configuration = &.{},
    /// The output language this run generates for. The native side is one
    /// library whatever the language is, so a plugin normally ignores it.
    target: targets.Target = targets.default,

    pub fn config(self: NativeContext, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.configurations);
    }
};

/// The exported C symbol of one plugin symbol: the binding's prefix, the
/// plugin's name in lower case, and the symbol's own name. Lowering, the
/// reflector's `plugin_symbols` record and `abi-diff` all spell it here, so
/// there is one rule and no way for the three to disagree.
pub fn nativeSymbolNameAlloc(allocator: std.mem.Allocator, prefix: []const u8, plugin_name: []const u8, name: []const u8) ![]u8 {
    const owner = try std.ascii.allocLowerString(allocator, plugin_name);
    defer allocator.free(owner);
    return std.fmt.allocPrint(allocator, "{s}_{s}_{s}", .{ prefix, owner, name });
}

/// The byte a C string points at. Named because `c_string` below needs an
/// address, and a `comptime` temporary has none that outlives the expression.
const c_string_byte: abi.AbiScalar = .{ .unsigned_int = 8 };

/// The one non-scalar a plugin symbol may hand back: a NUL-terminated string.
///
/// C spells it `const char *`, but neither public side ever sees a pointer:
/// the Go raw package copies the bytes into a `string` and the Rust raw module
/// borrows them as `&'static str`, exactly as both already do for the panic
/// message accessors. That borrow is the contract -- the plugin owns the bytes
/// and has to keep them valid for the life of the process, which is what a
/// `comptime`-built literal is. A buffer the plugin would free is not one of
/// these, and there is no way to spell one: a plugin symbol has no release
/// half for the raw layer to call.
pub const c_string: abi.AbiScalar = .{ .pointer = .{
    .child = &c_string_byte,
    .is_const = true,
    .is_many = true,
    .is_c_string = true,
} };

/// Whether `scalar` is the C string above. Only a return may be one; a
/// parameter is a plain scalar, because the plugin symbol would then have to
/// answer for the lifetime of a string the caller built.
pub fn isNativeCString(scalar: abi.AbiScalar) bool {
    return scalar == .pointer and scalar.pointer.is_c_string;
}

/// The scalars a plugin symbol may be spelled with: the values C carries by
/// itself, with no pointer, aggregate or callback behind them. Anything else
/// is refused with `ZIGO078` rather than lowered into a signature the raw
/// packages would have to guess at.
pub fn nativeScalarSupported(scalar: abi.AbiScalar) bool {
    return switch (scalar) {
        .void, .bool_u8, .isize, .usize => true,
        .signed_int, .unsigned_int => |bits| abi.promotedIntBits(bits) == bits,
        .float => |bits| bits == 32 or bits == 64,
        else => false,
    };
}

/// The canonical spelling of one supported scalar, which is what
/// `plugin_symbols` records a signature with. It is deliberately not C's
/// spelling: the document may not name a backend's types, and the only
/// question `abi-diff` asks of it is whether two recordings are equal.
pub fn writeNativeScalar(writer: *std.Io.Writer, scalar: abi.AbiScalar) !void {
    if (isNativeCString(scalar)) return writer.writeAll("c_string");
    switch (scalar) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("bool"),
        .isize => try writer.writeAll("isize"),
        .usize => try writer.writeAll("usize"),
        .signed_int => |bits| try writer.print("i{d}", .{bits}),
        .unsigned_int => |bits| try writer.print("u{d}", .{bits}),
        .float => |bits| try writer.print("f{d}", .{bits}),
        else => return error.UnsupportedNativeSignature,
    }
}

/// `<return>(<parameters>)`, the whole signature of a plugin symbol on one
/// line. `semantic.json` stores this string, so a changed parameter type is a
/// changed recording and `abi-diff` reports it without lowering anything.
pub fn nativeSignatureAlloc(allocator: std.mem.Allocator, symbol: NativeSymbol) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    errdefer text.deinit();
    try writeNativeScalar(&text.writer, symbol.ret);
    try text.writer.writeByte('(');
    for (symbol.params, 0..) |parameter, index| {
        if (index != 0) try text.writer.writeAll(", ");
        try writeNativeScalar(&text.writer, parameter.scalar);
    }
    try text.writer.writeByte(')');
    return text.toOwnedSlice();
}

test "a plugin symbol's signature records every parameter" {
    const signature = try nativeSignatureAlloc(std.testing.allocator, .{
        .name = "answer",
        .params = &.{ .{ .name = "a", .scalar = .{ .unsigned_int = 32 } }, .{ .name = "b", .scalar = .bool_u8 } },
        .ret = .{ .float = 64 },
        .implementation = "answer",
    });
    defer std.testing.allocator.free(signature);
    try std.testing.expectEqualStrings("f64(u32, bool)", signature);
}

test "the C ABI carries scalars and refuses everything else" {
    try std.testing.expect(nativeScalarSupported(.{ .unsigned_int = 32 }));
    try std.testing.expect(nativeScalarSupported(.usize));
    try std.testing.expect(!nativeScalarSupported(.{ .unsigned_int = 24 }));
    try std.testing.expect(!nativeScalarSupported(.{ .snapshot = "zg_value" }));
    // A C string is not one of them: it is a pointer, and only a return may
    // be one, which is `isNativeCString`'s question rather than this one's.
    try std.testing.expect(!nativeScalarSupported(c_string));
    try std.testing.expect(isNativeCString(c_string));
}

test "a C-string return records its own signature spelling" {
    const signature = try nativeSignatureAlloc(std.testing.allocator, .{
        .name = "build_info",
        .ret = c_string,
        .implementation = "buildInfo",
    });
    defer std.testing.allocator.free(signature);
    try std.testing.expectEqualStrings("c_string()", signature);
}

/// What a plugin attaches to: the kind of declaration, not the output
/// language. The two axes are separate and `targets.Target` is the other one,
/// so this deliberately does not use the word.
pub const Subject = enum {
    function,
    handle,
    value,
    enumeration,
    tagged_union,
    callback,
    materialized,
    error_set,
    /// One parameter of a function.
    param,
    /// One function's result.
    result,
    /// One field of a value, materialized or handle declaration.
    field,
    /// One tag of a registered enum.
    enum_tag,
};

pub fn typeSubject(kind: semantic.TypeKind) Subject {
    return switch (kind) {
        .@"opaque" => .handle,
        .value_struct => .value,
        .@"enum" => .enumeration,
        .tagged_union => .tagged_union,
        .callback => .callback,
        .materialized => .materialized,
        .error_set => .error_set,
    };
}

/// Where a `visit` call is: one node of the program being rendered, or one of
/// the boundaries around it. The emitter walks the program in document order
/// once per render pass and offers every node to every plugin whose
/// `subjects` cover it. The file and package boundaries have no subject of
/// their own, so every plugin that renders for this target sees them.
pub const Node = union(enum) {
    /// Before anything is written into this package's plugin file.
    package_begin,
    /// After it, which is the last thing a package render does.
    package_end,
    /// Inside a public file's package/import frame, before its body.
    file_begin: FileInfo,
    /// The same frame, after the body.
    file_end: FileInfo,
    /// A handle, value struct, enum, tagged union, callback, materialized
    /// struct or error set, after the generator wrote it.
    type: semantic.TypeDecl,
    /// A public function or method, after the generator wrote its body.
    function: abi.AbiFn,
    /// One parameter of that function.
    param: Param,
    /// That function's result.
    result: abi.AbiFn,
    /// One field of a value, materialized or handle declaration.
    field: Member,
    /// One tag of a registered enum.
    enum_tag: Member,

    pub const Param = struct { function: abi.AbiFn, index: usize };
    /// A field and an enum tag are the same IR node; the container's kind is
    /// what decides which of the two a visit is offered.
    pub const Member = struct { declaration: semantic.TypeDecl, index: usize };

    /// The `Subject` a plugin has to declare to be offered this node, or null
    /// for a boundary, which every plugin sees.
    pub fn subject(self: Node) ?Subject {
        return switch (self) {
            .package_begin, .package_end, .file_begin, .file_end => null,
            .type => |declaration| typeSubject(declaration.kind),
            .function => .function,
            .param => .param,
            .result => .result,
            .field => .field,
            .enum_tag => .enum_tag,
        };
    }

    /// Which of the plugin's option types reads this node's `ext`, or null
    /// for a boundary, which carries none.
    pub fn attachment(self: Node) ?Attachment {
        return switch (self) {
            .package_begin, .package_end, .file_begin, .file_end => null,
            .type => .type,
            .function => .function,
            .param => .param,
            .result => .result,
            .field => .field,
            .enum_tag => .enum_tag,
        };
    }

    /// The `ext` object this node carries. `context.optionsOf(P, node)` is
    /// this read under the node's own `attachment`.
    pub fn ext(self: Node) ?semantic.Extensions {
        return switch (self) {
            .package_begin, .package_end, .file_begin, .file_end => null,
            .type => |declaration| declaration.ext,
            .function => |function| function.origin.ext,
            .param => |node| if (node.index < node.function.origin.params.len) node.function.origin.params[node.index].ext else null,
            .result => |function| function.origin.result_ext,
            .field, .enum_tag => |node| if (node.index < node.declaration.fields.len) node.declaration.fields[node.index].ext else null,
        };
    }

    /// Where a diagnostic about this node points. A member names itself under
    /// its container's location, which is why the allocator is needed.
    pub fn site(self: Node, context: ContextBase) !diagnostic.Site {
        return switch (self) {
            .package_begin, .package_end => site_module.documentSite(context.program.package),
            .file_begin, .file_end => |file| site_module.documentSite(file.path),
            .type => |declaration| site_module.typeSite(declaration),
            .function => |function| site_module.functionSite(function.origin.*),
            .param => |node| site_module.paramSite(node.function.origin.*, node.index),
            .result => |function| site_module.resultSite(function.origin.*),
            .field => |node| site_module.fieldSite(node.declaration, context.allocator, node.index),
            .enum_tag => |node| site_module.tagSite(node.declaration, context.allocator, node.index),
        };
    }
};

/// One language's whole rendering surface. The `go` and `rust` slots on a
/// plugin hold one of these each, and the pair is the contract's answer to
/// "which languages does this plugin write": a filled slot renders, an empty
/// one does not, and a hook can only be written against the writers of the
/// slot it sits in.
pub const GoRender = struct {
    /// The one rendering hook. It is called at every `Node` this plugin's
    /// `subjects` cover, in document order, and writes through the builder it
    /// is handed. What the builder took during the call is flushed at that
    /// node's insertion point: after the method for `function`, after the type
    /// for `type`, inside the package/import frame for the file boundaries,
    /// and into `zigo_plugins_gen.go` for the package ones. A `param`,
    /// `result`, `field` or `enum_tag` node is inside a declaration and has no
    /// insertion point of its own, so its output follows the owning function's
    /// or type's. Called on every render pass; must be deterministic and must
    /// not mutate analysis state.
    visit: ?*const fn (GoContext, Node, *Builder) anyerror!void = null,
    /// Whether this node's public surface belongs to this plugin alone.
    /// A claimed declaration still gets its whole generated body, under an
    /// unexported name the visit reads from `Method.checked_name`; what
    /// changes is that nothing exported is written for it, so the plugin's
    /// wrapper replaces the method instead of sitting next to it. The C symbol,
    /// the shim and the raw package are untouched.
    ///
    /// Only a `function` node has a public method to hand over. `true` for any
    /// other node is refused with `ZIGO065`, and two plugins cannot claim one
    /// declaration; the generator refuses that with `ZIGO024`.
    claims: ?*const fn (GoContext, Node) anyerror!bool = null,
    source_files: []const SourceFile = &.{},
    /// Non-standard imports the hooks may write, added where they are used.
    imports: []const Import = &.{},
};

/// The Rust half of the same shape. `visit` walks the same `Node` order the
/// Go one does and flushes at the crate's equivalent insertion points: after
/// each generated `impl` method, after each type item, at the boundaries of
/// each emitted `.rs` file, and into `src/zigo_plugins.rs` for the package
/// boundaries.
pub const RustRender = struct {
    visit: ?*const fn (RustContext, Node, *RustBuilder) anyerror!void = null,
    /// Whether this function's public Rust surface belongs to this plugin
    /// alone, read under the same two rules Go's `claims` is.
    claims: ?*const fn (RustContext, Node) anyerror!bool = null,
    source_files: []const RustSourceFile = &.{},
    /// `use` declarations the hooks may write, added where they are used.
    imports: []const RustImport = &.{},
};

/// A generator plugin. Every field but `name` is optional, so a plugin that
/// only adds a method next to an existing one is four lines long.
pub const Plugin = struct {
    min_contract: ContractVersion = contract_version,
    Config: type = struct {},
    /// Once, before core validation. May remove, replace or synthesize IR.
    transform: ?*const fn (TransformContext) anyerror!semantic.Semantic = null,
    /// Rename registered types and their core IR references after transforms.
    /// Native Zig paths are preserved; generated ABI type identities change.
    /// Plugin-owned extension data is opaque and is not rewritten.
    name_type: ?*const fn (TransformContext, semantic.TypeDecl) anyerror!?[]const u8 = null,
    /// After all transforms and type renames, select existing GoAdapter conversions.
    map_type: ?*const fn (TransformContext, TypeUse) anyerror!?semantic.GoAdapter = null,
    /// Exact exported public name, including constructors; null keeps the
    /// existing name. Native paths, C symbols and raw Go names are unchanged.
    name_function: ?*const fn (TransformContext, semantic.SemanticFn) anyerror!?[]const u8 = null,
    analyze: ?*const fn (AnalyzeContext) anyerror!void = null,
    /// The facts contracts this plugin publishes. It may write facts under
    /// each of them, and every consumer of one runs after it. Two plugins
    /// providing the same capability is a registration error unless the
    /// capability is `multi`.
    provides: []const Capability = &.{},
    /// Capabilities this plugin cannot work without: some registered and
    /// enabled plugin has to provide each one, and every provider runs first.
    requires: []const Capability = &.{},
    /// Capabilities this plugin reads when they are there. A provider that is
    /// registered runs first; an absent one is no error, and the consumer
    /// finds no facts under it. `context.provided(cap)` is the question a
    /// hook asks before it looks.
    uses: []const Capability = &.{},
    /// The plugin's identity: the `ext` key its options travel under, the
    /// prefix of its diagnostic codes, and the suffix of the files it writes.
    /// Spelled in upper case, since the diagnostic codes are.
    name: []const u8,
    /// The declaration options this plugin reads, as a `std.json`-serializable
    /// struct. A plugin that takes none leaves it at the empty struct.
    FunctionOptions: type = struct {},
    TypeOptions: type = struct {},
    /// The node options this plugin reads, in the same shape and for the
    /// same reason as the declaration ones: a parameter, a result, a struct
    /// or handle field, and an enum tag each carry their own `ext`.
    ParamOptions: type = struct {},
    ResultOptions: type = struct {},
    FieldOptions: type = struct {},
    TagOptions: type = struct {},
    /// The node kinds this plugin attaches to. A plugin left at the default
    /// attaches to all of them.
    subjects: []const Subject = &.{ .function, .handle, .value, .enumeration, .tagged_union, .callback, .materialized, .error_set, .param, .result, .field, .enum_tag },
    /// Runs after core and option validation; report any number of diagnostics.
    validate: ?*const fn (ValidateContext) anyerror!void = null,
    /// What this plugin renders for Go, or null when it renders no Go at
    /// all. Filling the slot is what makes the plugin run for the Go target.
    go: ?GoRender = null,
    /// What this plugin renders for Rust, in the same shape. A plugin can
    /// fill both slots, either one, or neither -- a plugin that only
    /// transforms the IR fills neither and still runs for every target.
    rust: ?RustRender = null,
    /// The Zig this plugin ships for the shim to compile and the C symbols it
    /// exports out of it. Target-neutral, like `artifacts`: the native library
    /// is one library whichever language is generated from it, and every
    /// symbol here reaches the header, both Go raw backends, the Rust raw
    /// module and `abi-diff` through the same loops a bound function does.
    native: ?Native = null,
    artifacts: []const Artifact = &.{},

    /// Whether this plugin renders anything for `target`: whether it filled
    /// that target's slot.
    pub fn rendersFor(comptime self: Plugin, target: targets.Target) bool {
        if (std.mem.eql(u8, target.name, targets.go.target.name)) return self.go != null;
        if (std.mem.eql(u8, target.name, targets.rust.target.name)) return self.rust != null;
        return false;
    }

    /// Whether this plugin takes part in a generation for `target` at all --
    /// its transform, its validation, its analysis and its artifacts, none of
    /// which write in a language. A plugin that renders for the target does;
    /// so does one that renders for no target, which is a plugin whose whole
    /// contribution is to the IR.
    pub fn runsFor(comptime self: Plugin, target: targets.Target) bool {
        if (self.go == null and self.rust == null) return true;
        return self.rendersFor(target);
    }

    /// Whether this plugin publishes `cap`.
    pub fn providesCapability(comptime self: Plugin, comptime cap: Capability) bool {
        inline for (self.provides) |entry| if (comptime std.mem.eql(u8, entry.name, cap.name)) return true;
        return false;
    }

    /// The capabilities this plugin is ordered behind: the hard ones and the
    /// soft ones together.
    pub fn dependencies(comptime self: Plugin) []const Capability {
        return self.requires ++ self.uses;
    }

    pub fn supports(comptime self: Plugin, subject: ?Subject) bool {
        const requested = subject orelse return false;
        inline for (self.subjects) |candidate| if (candidate == requested) return true;
        return false;
    }
};

/// Stable topological order. Registration errors are compile-time errors.
pub fn ordered(comptime entries: []const Plugin) [entries.len]Plugin {
    comptime {
        @setEvalBranchQuota(100000);
        for (entries, 0..) |entry, i| {
            if (entry.min_contract.major != contract_version.major or entry.min_contract.minor > contract_version.minor)
                @compileError("incompatible plugin contract: " ++ entry.name);
            if (entry.go) |go| for (go.source_files) |file| {
                if (file.package == .raw and file.scope != .document) @compileError("raw Go files require document scope: " ++ entry.name);
                if (file.package == .external_test and file.kind != .test_file) @compileError("external test Go files require test kind: " ++ entry.name);
                if (file.build_constraint) |constraint| if (!@import("plugin/build_constraint.zig").valid(constraint)) @compileError("invalid Go build constraint: " ++ entry.name);
            };
            if (entry.rust) |rust| for (rust.source_files) |file| {
                if (!targets.rust.words.isIdentifier(file.module)) @compileError("plugin Rust module name is not an identifier: " ++ entry.name);
            };
            if (entry.native) |native| {
                for (native.sources) |source| {
                    if (source.path.len == 0) @compileError("plugin native source has no path: " ++ entry.name);
                    if (std.mem.startsWith(u8, source.path, "/")) @compileError("plugin native source path is not relative: " ++ entry.name);
                    if (!std.zig.isValidId(source.module)) @compileError("plugin native module name is not an identifier: " ++ entry.name);
                    for (native.sources) |other| {
                        if (&other == &source) continue;
                        if (std.mem.eql(u8, other.module, source.module)) @compileError("duplicate plugin native module: " ++ entry.name);
                    }
                }
                if (native.symbols != null and native.sources.len == 0)
                    @compileError("plugin exports native symbols without a source: " ++ entry.name);
            }
            for (entries[0..i]) |previous| if (std.mem.eql(u8, previous.name, entry.name))
                @compileError("duplicate plugin: " ++ entry.name);
            for (entry.provides) |published| {
                if (published.multi) continue;
                for (entries[0..i]) |previous| for (previous.provides) |other| {
                    if (std.mem.eql(u8, other.name, published.name))
                        @compileError("duplicate capability provider: " ++ published.name);
                };
            }
            for (entry.requires) |required| {
                var found = false;
                for (entries) |candidate| {
                    for (candidate.provides) |published| {
                        if (std.mem.eql(u8, published.name, required.name)) found = true;
                    }
                }
                if (!found) @compileError("missing capability provider: " ++ entry.name ++ " requires " ++ required.name);
            }
        }
        var result: [entries.len]Plugin = undefined;
        var used = [_]bool{false} ** entries.len;
        for (0..entries.len) |slot| {
            var found = false;
            for (entries, 0..) |entry, index| {
                if (used[index]) continue;
                var ready = true;
                for (entry.dependencies()) |dependency| {
                    for (entries, 0..) |candidate, dependency_index| {
                        if (used[dependency_index]) continue;
                        for (candidate.provides) |published| {
                            if (std.mem.eql(u8, published.name, dependency.name)) ready = false;
                        }
                    }
                }
                if (!ready) continue;
                result[slot] = entry;
                used[index] = true;
                found = true;
                break;
            }
            if (!found) @compileError("cycle in plugin ordering");
        }
        return result;
    }
}

const test_alpha: Capability = .{ .name = "test.alpha", .Facts = struct {} };
const test_beta: Capability = .{ .name = "test.beta", .Facts = struct {} };
const test_absent: Capability = .{ .name = "test.absent", .Facts = struct {} };
const test_shared: Capability = .{ .name = "test.shared", .Facts = struct {}, .multi = true };

test "plugin ordering is stable and puts every provider before its consumers" {
    const entries = ordered(&.{
        .{ .name = "C", .requires = &.{test_beta} },
        .{ .name = "A", .provides = &.{test_alpha} },
        .{ .name = "B", .provides = &.{test_beta}, .uses = &.{ test_alpha, test_absent } },
    });
    try std.testing.expectEqualStrings("A", entries[0].name);
    try std.testing.expectEqualStrings("B", entries[1].name);
    try std.testing.expectEqualStrings("C", entries[2].name);
}

test "a soft capability with no provider orders the consumer normally" {
    const entries = ordered(&.{ .{ .name = "B", .uses = &.{test_absent} }, .{ .name = "A" } });
    try std.testing.expectEqualStrings("B", entries[0].name);
    try std.testing.expectEqualStrings("A", entries[1].name);
}

test "a multi capability takes several providers and orders after all of them" {
    const entries = ordered(&.{
        .{ .name = "C", .uses = &.{test_shared} },
        .{ .name = "A", .provides = &.{test_shared} },
        .{ .name = "B", .provides = &.{test_shared} },
    });
    try std.testing.expectEqualStrings("A", entries[0].name);
    try std.testing.expectEqualStrings("B", entries[1].name);
    try std.testing.expectEqualStrings("C", entries[2].name);
}

test "a plugin publishes only the capabilities it lists" {
    const provider: Plugin = .{ .name = "P", .provides = &.{test_alpha} };
    try std.testing.expect(provider.providesCapability(test_alpha));
    try std.testing.expect(!provider.providesCapability(test_beta));
}

test "plugin config decodes defaults and rejects unknown fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const p: Plugin = .{ .name = "CONFIG", .Config = struct { enabled: bool = false } };
    try std.testing.expect(!(try readConfig(p, arena.allocator(), &.{})).enabled);
    try std.testing.expect((try readConfig(p, arena.allocator(), &.{.{ .name = "CONFIG", .json = "{\"enabled\":true}" }})).enabled);
    try std.testing.expectError(error.InvalidPluginConfig, readConfig(p, arena.allocator(), &.{.{ .name = "CONFIG", .json = "{\"typo\":true}" }}));
}

pub const SignatureOptions = struct { parameter_names: bool = true, omit_error: bool = false };
/// Names are allocated from GoContext.allocator. The caller owns go_name.
pub const FunctionInfo = struct { public_name: []const u8, is_public: bool, has_error: bool };

/// Once per generation, after lowering and before any package is rendered.
pub const AnalyzeContext = struct {
    /// The language-neutral view. `analyze` runs once per generation whatever
    /// the target is, so this is the half every implementation can read.
    render: ContextBase,
    /// The rendering context of the target being generated for, in the slot
    /// that names its language. An analysis that has to spell a generated
    /// signature reads the one it was written against and finds the other
    /// null.
    go: ?GoContext = null,
    rust: ?RustContext = null,
    facts: *Facts,
    diagnostics: *std.ArrayList(diagnostic.Diagnostic),

    /// The output language this run generates for.
    pub fn target(self: AnalyzeContext) targets.Target {
        return self.render.target();
    }

    /// Records one fact under `cap`, which `P` has to provide.
    pub fn provide(self: AnalyzeContext, comptime P: Plugin, comptime cap: Capability, id: DeclarationId, value: cap.Facts) !void {
        comptime assertProvides(P, cap);
        return self.facts.put(self.render.allocator, cap, id, value);
    }

    /// Whether a registered and enabled plugin provides `cap`, which is what
    /// a consumer of a soft capability asks before it looks for facts.
    pub fn provided(self: AnalyzeContext, comptime cap: Capability) bool {
        return self.render.provided(cap);
    }

    pub fn diagnose(self: AnalyzeContext, issue: diagnostic.Diagnostic) !void {
        try self.diagnostics.append(self.render.allocator, issue);
    }

    pub fn config(self: AnalyzeContext, comptime P: Plugin) !P.Config {
        return self.render.config(P);
    }

    pub fn optionsOf(self: AnalyzeContext, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?Options(P, attachment) {
        return readOptions(P, attachment, self.render.allocator, ext);
    }
    pub fn resolveType(self: AnalyzeContext, reference: ref.Type) !?*const semantic.TypeDecl {
        return self.render.resolveType(reference);
    }
    pub fn resolveFunction(self: AnalyzeContext, reference: ref.Function) !?*const semantic.SemanticFn {
        return self.render.resolveFunction(reference);
    }
    pub fn resolveInterface(self: AnalyzeContext, reference: ref.Interface) !?abi.AbiInterface {
        return self.render.resolveInterface(reference);
    }
};

/// Support for a plugin's own unit tests: a rendering context whose
/// formatting helpers work and whose generator-backed writers -- the ones
/// that spell types, signatures and parameter names -- report
/// `error.Unsupported`, since only the generator can answer for those.
pub const testing = struct {
    /// A Go rendering context whose generator-backed writers report
    /// `error.Unsupported`.
    pub fn goContext(allocator: std.mem.Allocator, program: abi.Program) GoContext {
        return .{ .allocator = allocator, .program = program, .options = .{}, .writers = &writers };
    }

    /// The same for Rust, except that `writeTypeName` really answers: the
    /// crate's spelling of a registered type is derivable without the
    /// generator, and an `impl` block is the shape a Rust hook most often
    /// writes.
    pub fn rustContext(allocator: std.mem.Allocator, program: abi.Program) RustContext {
        return .{ .allocator = allocator, .program = program, .options = .{}, .writers = &rust_writers };
    }

    const rust_writers: RustWriters = .{
        // The one generator-backed Rust writer a unit test can answer for on
        // its own. The crate spells a registered type `crate::` plus its
        // PascalCase name and nothing else -- no package qualification, no
        // adapter -- so `identifierAlloc` reproduces it exactly, and a plugin
        // that renders an `impl` for a bound type stays testable without the
        // generator. The other three read the lowered ABI shape, which only
        // the generator has.
        .writeTypeName = struct {
            fn f(context: RustContext, writer: *std.Io.Writer, name: []const u8) anyerror!void {
                const converted = try rustbuild.identifierAlloc(context, context.allocator, name, .pascal);
                defer context.allocator.free(converted);
                return writer.print("crate::{s}", .{converted});
            }
        }.f,
        .writeSignature = struct {
            fn f(_: RustContext, _: *std.Io.Writer, _: abi.AbiFn, _: RustSignatureOptions) anyerror!void {
                return error.Unsupported;
            }
        }.f,
        .receiverFormAlloc = struct {
            fn f(_: RustContext, _: std.mem.Allocator, _: abi.AbiFn) anyerror!?[]u8 {
                return error.Unsupported;
            }
        }.f,
        .identifierAlloc = rustbuild.identifierAlloc,
        .functionInfo = struct {
            fn f(_: RustContext, _: abi.AbiFn) anyerror!RustFunctionInfo {
                return error.Unsupported;
            }
        }.f,
        // The raw path of a plugin's own symbol, which a unit test can
        // answer for: lowering gives such a symbol no receiver and no
        // namespace, so `raw.rs` names its wrapper by case-converting the
        // function's name and nothing else. Any other function needs the
        // lowered shape, which only the generator has.
        .rawCallNameAlloc = struct {
            fn f(context: RustContext, allocator: std.mem.Allocator, function: abi.AbiFn) anyerror![]u8 {
                if (function.origin.plugin == null) return error.Unsupported;
                const converted = try rustbuild.identifierAlloc(context, allocator, function.origin.name, .snake);
                defer allocator.free(converted);
                return std.fmt.allocPrint(allocator, "crate::raw::{s}", .{converted});
            }
        }.f,
    };

    const writers: Writers = .{
        .writeTypeName = unsupported.typeName,
        .writeGoType = unsupported.goType,
        .receiverNameAlloc = unsupported.receiverName,
        .writeSignature = unsupported.signature,
        .writeValueType = unsupported.function,
        .writeDoc = unsupported.doc,
        .functionInfo = unsupported.info,
        .writeParameters = unsupported.function,
        .writeResultType = unsupported.results,
        .writeCallArguments = unsupported.function,
        .identifierAlloc = format.identifierAlloc,
        .rawCallNameAlloc = pluginRawCallName,
    };

    /// The Go counterpart of the Rust table's entry above, under the same
    /// restriction: a plugin symbol alone, whose raw name is the Pascal
    /// spelling of its function name.
    fn pluginRawCallName(context: GoContext, allocator: std.mem.Allocator, function: abi.AbiFn) anyerror![]u8 {
        if (function.origin.plugin == null) return error.Unsupported;
        const converted = try format.identifierAlloc(context, allocator, function.origin.name, .pascal);
        defer allocator.free(converted);
        return std.fmt.allocPrint(allocator, "raw.{s}", .{converted});
    }

    const unsupported = struct {
        fn typeName(_: GoContext, _: *std.Io.Writer, _: []const u8) anyerror!void {
            return error.Unsupported;
        }
        fn rawCallName(_: GoContext, _: std.mem.Allocator, _: abi.AbiFn) anyerror![]u8 {
            return error.Unsupported;
        }
        fn goType(_: GoContext, _: *std.Io.Writer, _: semantic.TypeNode) anyerror!void {
            return error.Unsupported;
        }
        fn receiverName(_: GoContext, _: std.mem.Allocator, _: []const u8) anyerror![]u8 {
            return error.Unsupported;
        }
        fn signature(_: GoContext, _: *std.Io.Writer, _: abi.AbiFn, _: SignatureOptions) anyerror!void {
            return error.Unsupported;
        }
        fn function(_: GoContext, _: *std.Io.Writer, _: abi.AbiFn) anyerror!void {
            return error.Unsupported;
        }
        fn doc(_: *std.Io.Writer, _: []const u8, _: []const u8, _: []const u8) anyerror!void {
            return error.Unsupported;
        }
        fn info(_: GoContext, _: abi.AbiFn) anyerror!FunctionInfo {
            return error.Unsupported;
        }
        fn results(_: GoContext, _: *std.Io.Writer, _: abi.AbiFn, _: ResultOptions) anyerror!usize {
            return error.Unsupported;
        }
    };
};

pub fn packageMatches(package: ?[]const u8, active: ?[]const u8) bool {
    const selection = active orelse return true;
    return std.mem.eql(u8, package orelse "", selection);
}

pub fn writeCommentLine(writer: *std.Io.Writer, line: []const u8) !void {
    if (line.len == 0) return writer.writeAll("//\n");
    try writer.print("// {s}\n", .{line});
}

/// Parse a name-to-config JSON object, then merge build defaults by plugin name.
/// All returned strings belong to allocator (a run arena).
pub fn configurationsAlloc(allocator: std.mem.Allocator, defaults: []const Configuration, json: []const u8) ![]const Configuration {
    const value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, json, .{});
    if (value != .object) return error.InvalidPluginConfig;
    var result: std.ArrayList(Configuration) = .empty;
    var entries = value.object.iterator();
    while (entries.next()) |entry| {
        if (entry.value_ptr.* != .object) return error.InvalidPluginConfig;
        try result.append(allocator, .{ .name = entry.key_ptr.*, .json = try std.json.Stringify.valueAlloc(allocator, entry.value_ptr.*, .{}) });
    }
    for (defaults) |entry| {
        if (!value.object.contains(entry.name)) try result.append(allocator, entry);
    }
    return result.toOwnedSlice(allocator);
}

const test_count: Capability = .{ .name = "test.count", .Facts = struct { count: usize } };

test "capability facts preserve typed results across copied declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var facts: Facts = .{};
    const id: DeclarationId = .{ .kind = .function, .name = "zg_run" };
    try facts.put(arena.allocator(), test_count, id, .{ .count = 42 });
    const copied = try arena.allocator().dupe(u8, "zg_run");
    try std.testing.expectEqual(@as(usize, 42), (try facts.get(test_count, .{ .kind = .function, .name = copied })).?.count);
    try std.testing.expect(try facts.get(test_count, .{ .kind = .type, .name = copied }) == null);
    try std.testing.expectError(error.DuplicatePluginFact, facts.put(arena.allocator(), test_count, id, .{ .count = 1 }));
}

test "one plugin reads what another provided, and a mistyped capability is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const provider: Plugin = .{ .name = "PROVIDER", .provides = &.{test_count} };
    const consumer: Plugin = .{ .name = "CONSUMER", .uses = &.{test_count} };
    const entries = ordered(&.{ consumer, provider });
    try std.testing.expectEqualStrings("PROVIDER", entries[0].name);

    var facts: Facts = .{};
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    const render = testing.goContext(allocator, .{ .package = "test", .prefix = "test", .functions = &.{} });
    const analyze: AnalyzeContext = .{ .render = render.base(), .go = render, .facts = &facts, .diagnostics = &issues };
    const id: DeclarationId = .{ .kind = .function, .name = "zg_run" };
    try analyze.provide(provider, test_count, id, .{ .count = 7 });
    // The consumer names the capability, not the plugin behind it.
    try std.testing.expectEqual(@as(usize, 7), (try analyze.facts.get(test_count, id)).?.count);

    // A capability of the same name carrying another type reads nothing.
    const mistyped: Capability = .{ .name = test_count.name, .Facts = struct { count: bool } };
    try std.testing.expectError(error.PluginFactTypeMismatch, facts.get(mistyped, id));
}

test "a context answers whether a capability has an enabled provider" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    var facts: Facts = .{};
    const document: semantic.Semantic = .{ .package = "test", .prefix = "test", .zig_version = "0.16.0", .types = &.{}, .functions = &.{} };
    const present: ValidateContext = .{ .allocator = arena.allocator(), .document = document, .diagnostics = &issues, .facts = &facts, .capabilities = &.{test_count.name} };
    var absent = present;
    absent.capabilities = &.{};
    try std.testing.expect(present.provided(test_count));
    try std.testing.expect(!absent.provided(test_count));
    try std.testing.expect(!present.provided(test_alpha));
}

pub const FileInfo = struct {
    source_file: ?SourceFile = null,
    /// The Rust module this file is, when a plugin's `rust` slot declared it.
    rust_source_file: ?RustSourceFile = null,
    path: []const u8,
    owner: []const u8 = "generator",
    /// What the emitter wrote into this file. `raw` and `buffer` are the two
    /// the Rust crate has and the Go tree does not: Go's raw layer is a
    /// package of its own rather than a public file, and Go copies a native
    /// buffer instead of owning one.
    kind: enum { api, enums, structs, handles, runtime, errors, tagged_union, raw, buffer, plugin, package },
};

test "validation and transformation contexts read every attachment's option type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const Enabled = struct { enabled: bool };
    const p: Plugin = .{
        .name = "LOOKUP",
        .FunctionOptions = Enabled,
        .TypeOptions = Enabled,
        .ParamOptions = Enabled,
        .ResultOptions = Enabled,
        .FieldOptions = Enabled,
        .TagOptions = Enabled,
    };
    const options = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"enabled\":true}", .{});
    const value: semantic.Extensions = .{ .entries = &.{.{ .plugin = "LOOKUP", .options = options }} };
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    var facts: Facts = .{};
    const validate: ValidateContext = .{ .allocator = allocator, .document = .{ .package = "test", .prefix = "test", .zig_version = "0.16.0", .types = &.{}, .functions = &.{} }, .diagnostics = &issues, .facts = &facts };
    const transform: TransformContext = .{ .allocator = allocator, .document = validate.document, .diagnostics = &issues };
    const render = testing.goContext(allocator, .{ .package = "test", .prefix = "test", .functions = &.{} });
    const analyze: AnalyzeContext = .{ .render = render.base(), .go = render, .facts = &facts, .diagnostics = &issues };
    inline for (.{ Attachment.function, .type, .param, .result, .field, .enum_tag }) |attachment| {
        try std.testing.expect((try validate.optionsOf(p, attachment, value)).?.enabled);
        try std.testing.expect((try transform.optionsOf(p, attachment, value)).?.enabled);
        try std.testing.expect((try render.optionsOf(p, attachment, value)).?.enabled);
        try std.testing.expect((try analyze.optionsOf(p, attachment, value)).?.enabled);
        try std.testing.expect(try render.optionsOf(p, attachment, null) == null);
    }
}

test "every node answers for its subject, its attachment, its ext and its site" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const options = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"enabled\":true}", .{});
    const extensions: semantic.Extensions = .{ .entries = &.{.{ .plugin = "LOOKUP", .options = options }} };
    var origin: semantic.SemanticFn = .{
        .ext = extensions,
        .name = "bump",
        .params = &.{.{ .name = "by", .type = .{ .bool = {} }, .ext = extensions }},
        .receiver = "Counter",
        .result_ext = extensions,
        .@"return" = .{ .void = {} },
        .source = .{ .path = "src/root.zig", .line = 7, .column = 1 },
        .symbol = "zg_counter_bump",
    };
    const function: abi.AbiFn = .{ .origin = &origin, .symbol = "zg_counter_bump", .params = &.{}, .ret = .void };
    const declaration: semantic.TypeDecl = .{
        .fields = &.{.{ .name = "idle", .value = 0, .ext = extensions }},
        .kind = .@"enum",
        .name = "Mode",
        .ext = extensions,
        .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
    };
    const context = testing.goContext(allocator, .{ .package = "meter", .prefix = "zg", .functions = &.{} });
    const p: Plugin = .{ .name = "LOOKUP", .FunctionOptions = struct { enabled: bool }, .ParamOptions = struct { enabled: bool }, .TagOptions = struct { enabled: bool } };

    const nodes = [_]Node{
        .package_begin,
        .{ .file_begin = .{ .path = "meter/meter_gen.go", .kind = .api } },
        .{ .type = declaration },
        .{ .function = function },
        .{ .param = .{ .function = function, .index = 0 } },
        .{ .result = function },
        .{ .enum_tag = .{ .declaration = declaration, .index = 0 } },
    };
    const subjects = [_]?Subject{ null, null, .enumeration, .function, .param, .result, .enum_tag };
    const attachments = [_]?Attachment{ null, null, .type, .function, .param, .result, .enum_tag };
    const declarations = [_][]const u8{ "meter", "meter/meter_gen.go", "Mode", "bump", "by", "bump", "Mode.idle" };
    for (nodes, subjects, attachments, declarations) |node, subject, attachment, named| {
        try std.testing.expectEqual(subject, node.subject());
        try std.testing.expectEqual(attachment, node.attachment());
        try std.testing.expectEqual(attachment == null, node.ext() == null);
        try std.testing.expectEqualStrings(named, (try node.site(context.base())).declaration);
    }
    // A node hands `optionsOf` its own `ext`, which is what lets a visit read
    // the node it was called for without spelling the field.
    try std.testing.expect((try context.optionsOf(p, .function, nodes[3])).?.enabled);
    try std.testing.expect((try context.optionsOf(p, .param, nodes[4])).?.enabled);
    try std.testing.expect((try context.optionsOf(p, .enum_tag, nodes[6])).?.enabled);
    try std.testing.expect(try context.optionsOf(p, .function, nodes[0]) == null);
}

test "the test context builds declarations, identifiers and literals like the generator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context = testing.goContext(arena.allocator(), .{ .package = "test", .prefix = "test", .functions = &.{} });
    const b = context.builder();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try b.render(&output.writer, &.{
        try b.func(.{
            .name = "ModeValues",
            .signature = .{ .explicit = .{ .results = &.{try b.sliceOf(b.ident("Mode"))} } },
            .body = &.{try b.ret(&.{.nil})},
            .single_line = true,
        }),
        try b.func(.{
            .receiver = .{ .name = "value", .type = "Mode", .pointer = true },
            .name = "UnmarshalJSON",
            .signature = .{ .explicit = .{
                .params = &.{.{ .names = &.{"data"}, .type = try b.sliceOf(b.ident("byte")) }},
                .results = &.{b.ident("error")},
            } },
            .body = &.{try b.ret(&.{b.string("tab\t\"quoted\"")})},
        }),
    }, .{});
    try std.testing.expectEqualStrings(
        "func ModeValues() []Mode { return nil }\n" ++
            "\nfunc (value *Mode) UnmarshalJSON(data []byte) error {\n\treturn \"tab\\t\\\"quoted\\\"\"\n}\n",
        output.written(),
    );
    const pascal = try context.identifierAlloc(std.testing.allocator, "low_water", .pascal);
    defer std.testing.allocator.free(pascal);
    try std.testing.expectEqualStrings("LowWater", pascal);
    const camel = try context.identifierAlloc(std.testing.allocator, "low_water", .camel);
    defer std.testing.allocator.free(camel);
    try std.testing.expectEqualStrings("lowWater", camel);
    try std.testing.expectError(error.Unsupported, context.writeTypeName(&output.writer, "Mode"));
}

test {
    _ = ref;
}
