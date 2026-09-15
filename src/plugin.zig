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
pub const contract_version: ContractVersion = .{ .major = 6, .minor = 0 };

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

/// A run-arena-owned, typed store. Keys borrow the document; values must live
/// until generation ends. Rendering receives only a const view of the store.
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

    pub fn put(self: *Facts, allocator: std.mem.Allocator, comptime P: Plugin, id: DeclarationId, value: P.Facts) !void {
        const key: Key = .{ .owner = P.name, .id = id };
        if (self.entries.contains(key)) return error.DuplicatePluginFact;
        const stored = try allocator.create(P.Facts);
        stored.* = value;
        try self.entries.put(allocator, key, .{ .type_name = @typeName(P.Facts), .data = stored });
    }
    pub fn get(self: *const Facts, comptime P: Plugin, id: DeclarationId) !?P.Facts {
        const value = self.entries.get(.{ .owner = P.name, .id = id }) orelse return null;
        if (!std.mem.eql(u8, value.type_name, @typeName(P.Facts))) return error.PluginFactTypeMismatch;
        const stored: *const P.Facts = @ptrCast(@alignCast(value.data));
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

    pub fn config(self: TransformContext, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.configurations);
    }
    pub fn diagnose(self: TransformContext, issue: diagnostic.Diagnostic) !void {
        try self.diagnostics.append(self.allocator, issue);
    }
    pub fn optionsOf(self: TransformContext, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?Options(P, attachment) {
        return readOptions(P, attachment, self.allocator, ext);
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

    pub fn diagnose(self: ValidateContext, issue: diagnostic.Diagnostic) !void {
        try self.diagnostics.append(self.allocator, issue);
    }

    pub fn config(self: ValidateContext, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.configurations);
    }

    pub fn optionsOf(self: ValidateContext, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?Options(P, attachment) {
        return readOptions(P, attachment, self.allocator, ext);
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
    pub fn config(self: ContextBase, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.options.configurations);
    }
    pub fn optionsOf(self: ContextBase, comptime P: Plugin, comptime attachment: Attachment, source: anytype) !?Options(P, attachment) {
        return readOptions(P, attachment, self.allocator, extensionsOf(source));
    }
    pub fn publicFilePathAlloc(self: ContextBase, filename: []const u8) ![]u8 {
        return publicFilePathAllocImpl(self.allocator, self.program, self.options, filename);
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
    pub fn config(self: GoContext, comptime P: Plugin) !P.Config {
        return self.base().config(P);
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
    pub fn config(self: RustContext, comptime P: Plugin) !P.Config {
        return self.base().config(P);
    }
    pub fn optionsOf(self: RustContext, comptime P: Plugin, comptime attachment: Attachment, source: anytype) !?Options(P, attachment) {
        return self.base().optionsOf(P, attachment, source);
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
    Facts: type = struct {},
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
    /// Ordering only: absent plugins in after are ignored.
    after: []const []const u8 = &.{},
    /// Required registered and enabled plugins; also run before this plugin.
    requires: []const []const u8 = &.{},
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
            for (entries[0..i]) |previous| if (std.mem.eql(u8, previous.name, entry.name))
                @compileError("duplicate plugin: " ++ entry.name);
            for (entry.requires) |name| {
                var found = false;
                for (entries) |candidate| {
                    if (std.mem.eql(u8, candidate.name, name)) found = true;
                }
                if (!found) @compileError("missing plugin dependency: " ++ entry.name ++ " requires " ++ name);
            }
        }
        var result: [entries.len]Plugin = undefined;
        var used = [_]bool{false} ** entries.len;
        for (0..entries.len) |slot| {
            var found = false;
            for (entries, 0..) |entry, index| {
                if (used[index]) continue;
                var ready = true;
                for (entry.after ++ entry.requires) |dependency| {
                    for (entries, 0..) |candidate, dependency_index| {
                        if (std.mem.eql(u8, candidate.name, dependency) and !used[dependency_index]) ready = false;
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

test "plugin ordering is stable and respects dependencies" {
    const entries = ordered(&.{ .{ .name = "C", .requires = &.{"B"} }, .{ .name = "A" }, .{ .name = "B", .after = &.{ "A", "ABSENT" } } });
    try std.testing.expectEqualStrings("A", entries[0].name);
    try std.testing.expectEqualStrings("B", entries[1].name);
    try std.testing.expectEqualStrings("C", entries[2].name);
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

    pub fn diagnose(self: AnalyzeContext, issue: diagnostic.Diagnostic) !void {
        try self.diagnostics.append(self.render.allocator, issue);
    }

    pub fn config(self: AnalyzeContext, comptime P: Plugin) !P.Config {
        return self.render.config(P);
    }

    pub fn optionsOf(self: AnalyzeContext, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?Options(P, attachment) {
        return readOptions(P, attachment, self.render.allocator, ext);
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

    /// The same for Rust.
    pub fn rustContext(allocator: std.mem.Allocator, program: abi.Program) RustContext {
        return .{ .allocator = allocator, .program = program, .options = .{}, .writers = &rust_writers };
    }

    const rust_writers: RustWriters = .{
        .writeTypeName = struct {
            fn f(_: RustContext, _: *std.Io.Writer, _: []const u8) anyerror!void {
                return error.Unsupported;
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
    };

    const unsupported = struct {
        fn typeName(_: GoContext, _: *std.Io.Writer, _: []const u8) anyerror!void {
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

test "plugin facts preserve typed validation results across copied declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var facts: Facts = .{};
    const p: Plugin = .{ .name = "FACT", .Facts = struct { count: usize } };
    const id: DeclarationId = .{ .kind = .function, .name = "zg_run" };
    try facts.put(arena.allocator(), p, id, .{ .count = 42 });
    const copied = try arena.allocator().dupe(u8, "zg_run");
    try std.testing.expectEqual(@as(usize, 42), (try facts.get(p, .{ .kind = .function, .name = copied })).?.count);
    try std.testing.expect(try facts.get(p, .{ .kind = .type, .name = copied }) == null);
    try std.testing.expectError(error.DuplicatePluginFact, facts.put(arena.allocator(), p, id, .{ .count = 1 }));
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
