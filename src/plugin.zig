//! The generator's plugin contract. A plugin is an ordinary Zig package that
//! compiles against this file alone: it names itself, owns typed function and
//! type options, validates its own declarations, and adds generated code
//! through hooks.
//!
//! A plugin declares two independent things about what it applies to.
//! `subjects` is the kind of declaration -- function, handle, value and so on.
//! `output_targets` is the output language, and it defaults to Go alone,
//! because the rendering surface a plugin writes through writes Go. A plugin
//! whose `output_targets` exclude the resolved target contributes nothing.
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
pub const contract_version: ContractVersion = .{ .major = 4, .minor = 0 };

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

pub const interfaces = @import("plugin/interfaces.zig");
pub const session = @import("plugin/session.zig");
pub const site = @import("plugin/site.zig");
pub const rename = @import("plugin/rename.zig");
/// The Go formatting helpers behind `Context.writeFuncHeader`,
/// `writeMethodHeader`, `identifierAlloc` and `writeStringLiteral`. The
/// emitter's writers table points at them; a plugin calls them through its
/// context.
pub const format = @import("plugin/format.zig");

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
    pub fn optionsOf(self: TransformContext, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?(if (attachment == .function) P.FunctionOptions else P.TypeOptions) {
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

pub const Attachment = enum { function, type };

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

    pub fn optionsOf(self: ValidateContext, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?(if (attachment == .function) P.FunctionOptions else P.TypeOptions) {
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
    enabled: ?*const fn (Context) anyerror!bool = null,
    scope: OutputScope = .package,
    package: PackageKind = .public,
    kind: FileKind = .source,
    /// Single-line ASCII Go build expression (up to 4096 bytes).
    build_constraint: ?[]const u8 = null,
    imports: ?*const fn (Context) anyerror![]const Import = null,
    pathAlloc: *const fn (Context) anyerror![]u8,
    render: *const fn (Context, *std.Io.Writer) anyerror!void,
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
/// without importing generator internals.
pub const Writers = struct {
    /// The type name as this package spells it, qualified when the type lives
    /// in another generated package.
    writeTypeName: *const fn (Context, *std.Io.Writer, []const u8) anyerror!void,
    /// The Go spelling of a semantic type node.
    writeGoType: *const fn (Context, *std.Io.Writer, semantic.TypeNode) anyerror!void,
    /// The receiver name a method of this type is written with.
    receiverNameAlloc: *const fn (Context, std.mem.Allocator, []const u8) anyerror![]u8,
    /// The parameter list and result of a public function, parentheses
    /// included, exactly as the method being hooked spells them.
    writeSignature: *const fn (Context, *std.Io.Writer, abi.AbiFn, SignatureOptions) anyerror!void,
    writeValueType: *const fn (Context, *std.Io.Writer, abi.AbiFn) anyerror!void,
    writeDoc: *const fn (*std.Io.Writer, []const u8, []const u8, []const u8) anyerror!void,
    functionInfo: *const fn (Context, abi.AbiFn) anyerror!FunctionInfo,
    writeParameters: *const fn (Context, *std.Io.Writer, abi.AbiFn) anyerror!void,
    writeResultType: *const fn (Context, *std.Io.Writer, abi.AbiFn, ResultOptions) anyerror!usize,
    writeCallArguments: *const fn (Context, *std.Io.Writer, abi.AbiFn) anyerror!void,
    /// `func Name(params) results {`, without a trailing newline, so a
    /// one-line body can follow on the same line.
    writeFuncHeader: *const fn (Context, *std.Io.Writer, []const u8, []const u8, []const u8) anyerror!void,
    /// `func (r *T) Name(params) results {`, the method form of the above.
    writeMethodHeader: *const fn (Context, *std.Io.Writer, Receiver, []const u8, []const u8, []const u8) anyerror!void,
    /// A Zig name as the generated package spells it: an enum tag or a struct
    /// field becomes its exported member name with `.pascal`, a local or a
    /// parameter its unexported spelling with `.camel`.
    identifierAlloc: *const fn (Context, std.mem.Allocator, []const u8, IdentifierStyle) anyerror![]u8,
    /// A Go string literal, quotes and escapes included.
    writeStringLiteral: *const fn (*std.Io.Writer, []const u8) anyerror!void,
};

/// The receiver clause of a method header: `(name *Type)` or `(name Type)`.
pub const Receiver = struct {
    name: []const u8,
    type: []const u8,
    pointer: bool = false,
};

/// How `identifierAlloc` spells a name: `SomeName` or `someName`.
pub const IdentifierStyle = enum { pascal, camel };

/// What a `method_hook` is adjacent to: the method the generator just wrote.
/// The names are the ones the method itself used, so a wrapper that calls it
/// can never spell the call differently.
pub const Method = struct {
    /// The method's exported name in the output language. A declaration a
    /// plugin claimed with `replaces_method` has no method under this name
    /// yet: the name is what the hook is expected to write.
    public_name: []const u8,
    /// The name the generated body was actually written under. The same as
    /// `public_name`, except on a declaration this plugin claimed, where it is
    /// the unexported name the wrapper has to call.
    checked_name: []const u8,
    /// The Go receiver type, absent for a free function.
    receiver: ?[]const u8 = null,
    /// The receiver variable name, absent for a free function.
    receiver_name: ?[]const u8 = null,
    /// The Go parameter names, indexed by semantic parameter.
    param_names: [][]u8,
    /// The handle type a constructor hands back, when it is one.
    owned_type: ?[]const u8 = null,
    /// Whether the method's Go signature carries an `error`.
    needs_check: bool = false,
};

/// What a hook is given besides its writer: the lowered program, the plugin's
/// view of the options in force, the writers table, the facts `analyze`
/// recorded, and -- for `method_hook` -- the method the hook is being written
/// after.
pub const Context = struct {
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: PluginOptions,
    writers: *const Writers,
    /// What `analyze` recorded, read-only: rendering may not add facts.
    facts: *const Facts = &.{},
    /// Set for method_hook, null in other rendering contexts.
    method: ?Method = null,

    /// The output language this run generates for.
    pub fn target(self: Context) targets.Target {
        return self.options.target;
    }
    pub fn config(self: Context, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.options.configurations);
    }

    // The writers below render Go source. They are not target-generic and
    // renaming them would not make them so: there is one emitter, and it is
    // Go's. A plugin that calls any of them belongs to the default
    // `output_targets = &.{"go"}` and will not be run for another language.

    pub fn writeTypeName(self: Context, writer: *std.Io.Writer, name: []const u8) !void {
        return self.writers.writeTypeName(self, writer, name);
    }

    pub fn writeGoType(self: Context, writer: *std.Io.Writer, node: semantic.TypeNode) !void {
        return self.writers.writeGoType(self, writer, node);
    }

    pub fn receiverNameAlloc(self: Context, allocator: std.mem.Allocator, type_name: []const u8) ![]u8 {
        return self.writers.receiverNameAlloc(self, allocator, type_name);
    }

    pub fn writeSignature(self: Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        return self.writers.writeSignature(self, writer, function, .{});
    }

    /// Public parameter list including parentheses. Names are derived outside method hooks.
    pub fn writeParameters(self: Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        const write = self.writers.writeParameters;
        return write(self, writer, function);
    }

    /// Public results including their leading space and any tuple parentheses.
    /// Returns the number of emitted results, allowing wrappers to choose a
    /// forwarding helper without parsing Go source. Zero results write nothing.
    pub fn writeResultType(self: Context, writer: *std.Io.Writer, function: abi.AbiFn, options: ResultOptions) !usize {
        const write = self.writers.writeResultType;
        return write(self, writer, function, options);
    }

    /// Arguments in public parameter order, without parentheses.
    pub fn writeCallArguments(self: Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        const write = self.writers.writeCallArguments;
        return write(self, writer, function);
    }

    pub fn writeSignatureWith(self: Context, writer: *std.Io.Writer, function: abi.AbiFn, options: SignatureOptions) !void {
        return self.writers.writeSignature(self, writer, function, options);
    }
    pub fn writeValueType(self: Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        return self.writers.writeValueType(self, writer, function);
    }
    pub fn writeDoc(self: Context, writer: *std.Io.Writer, public_name: []const u8, zig_name: []const u8, doc: []const u8) !void {
        return self.writers.writeDoc(writer, public_name, zig_name, doc);
    }
    pub fn functionInfo(self: Context, function: abi.AbiFn) !FunctionInfo {
        return self.writers.functionInfo(self, function);
    }

    /// Path in this SourceFile's selected package, or the public package in other hooks.
    pub fn sourceFilePathAlloc(self: Context, filename: []const u8) ![]u8 {
        const selected_package = if (self.options.file) |file| if (file.source_file) |go| go.package else .public else .public;
        return sourceFilePathAllocImpl(self.allocator, self.program, self.options, selected_package, filename);
    }

    pub fn publicFilePathAlloc(self: Context, filename: []const u8) ![]u8 {
        return publicFilePathAllocImpl(self.allocator, self.program, self.options, filename);
    }

    /// `P`'s options on the declaration whose `ext` this is -- the function
    /// being written or the type being hooked -- or null when the declaration
    /// did not attach `P`.
    pub fn optionsOf(self: Context, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?(if (attachment == .function) P.FunctionOptions else P.TypeOptions) {
        return readOptions(P, attachment, self.allocator, ext);
    }

    /// `func Name(params) results {` without a trailing newline; `params`
    /// is written between the parentheses and `results` after them as given,
    /// so a tuple result carries its own parentheses.
    pub fn writeFuncHeader(self: Context, writer: *std.Io.Writer, name: []const u8, params: []const u8, results: []const u8) !void {
        return self.writers.writeFuncHeader(self, writer, name, params, results);
    }

    /// The method form of `writeFuncHeader`.
    pub fn writeMethodHeader(self: Context, writer: *std.Io.Writer, receiver: Receiver, name: []const u8, params: []const u8, results: []const u8) !void {
        return self.writers.writeMethodHeader(self, writer, receiver, name, params, results);
    }

    /// A Zig name as the generated package spells it. The caller owns the result.
    pub fn identifierAlloc(self: Context, allocator: std.mem.Allocator, name: []const u8, style: IdentifierStyle) ![]u8 {
        return self.writers.identifierAlloc(self, allocator, name, style);
    }

    /// `text` as a Go string literal, quotes and escapes included.
    pub fn writeStringLiteral(self: Context, writer: *std.Io.Writer, text: []const u8) !void {
        return self.writers.writeStringLiteral(writer, text);
    }
};

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
fn readOptions(comptime P: Plugin, comptime attachment: Attachment, allocator: std.mem.Allocator, ext: ?semantic.Extensions) !?(if (attachment == .function) P.FunctionOptions else P.TypeOptions) {
    const attached = (ext orelse return null).get(P.name) orelse return null;
    return std.json.parseFromValueLeaky(if (attachment == .function) P.FunctionOptions else P.TypeOptions, allocator, attached, .{}) catch return error.InvalidPluginOptions;
}

/// What a plugin attaches to: the kind of declaration, not the output
/// language. The two axes are separate and `targets.Target` is the other one,
/// so this deliberately does not use the word.
pub const Subject = enum { function, handle, value, enumeration, tagged_union, callback, materialized, error_set };

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
    /// The declaration kinds this plugin attaches to. A plugin left at the
    /// default attaches to all of them.
    subjects: []const Subject = &.{ .function, .handle, .value, .enumeration, .tagged_union, .callback, .materialized, .error_set },
    /// The output languages this plugin can render for, by `targets.Target`
    /// name. The default is Go alone, because the rendering surface a plugin
    /// writes through -- `Context.writeGoType` and its siblings -- writes Go.
    /// A plugin whose list excludes the resolved target contributes nothing:
    /// no transform, no diagnostic, no output file. That is what lets those
    /// writers stay Go's without the contract pretending otherwise.
    output_targets: []const []const u8 = &.{"go"},
    /// Runs after core and option validation; report any number of diagnostics.
    validate: ?*const fn (ValidateContext) anyerror!void = null,
    /// Written after each public method, into the file that owns it.
    method_hook: ?*const fn (Context, *std.Io.Writer, abi.AbiFn) anyerror!void = null,
    /// Whether this declaration's public surface belongs to this plugin alone.
    /// A claimed declaration still gets its whole generated body, under an
    /// unexported name the `method_hook` reads from `Method.checked_name`; what
    /// changes is that nothing exported is written for it, so the hook's
    /// wrapper replaces the method instead of sitting next to it. The C symbol,
    /// the shim and the raw package are untouched.
    ///
    /// Two plugins cannot claim one declaration; the generator refuses it.
    replaces_method: ?*const fn (Context, abi.AbiFn) anyerror!bool = null,
    /// Written after each handle, value struct and enum, into the file that
    /// owns it.
    type_hook: ?*const fn (Context, *std.Io.Writer, semantic.TypeDecl) anyerror!void = null,
    /// Body boundaries, inside the package/import frame. Called on every render
    /// pass; must be deterministic and must not mutate analysis state.
    file_hook: ?*const fn (Context, *std.Io.Writer, FileInfo, FilePhase) anyerror!void = null,
    /// One contribution per package per render pass, in zigo_plugins_gen.go.
    package_hook: ?*const fn (Context, *std.Io.Writer) anyerror!void = null,
    source_files: []const SourceFile = &.{},
    artifacts: []const Artifact = &.{},

    /// Non-standard imports the hooks may write, added where they are used.
    imports: []const Import = &.{},

    /// Whether this plugin runs at all for `target`.
    pub fn rendersFor(comptime self: Plugin, target: targets.Target) bool {
        inline for (self.output_targets) |candidate| if (std.mem.eql(u8, candidate, target.name)) return true;
        return false;
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
            for (entry.source_files) |file| {
                if (file.package == .raw and file.scope != .document) @compileError("raw Go files require document scope: " ++ entry.name);
                if (file.package == .external_test and file.kind != .test_file) @compileError("external test Go files require test kind: " ++ entry.name);
                if (file.build_constraint) |constraint| if (!@import("plugin/build_constraint.zig").valid(constraint)) @compileError("invalid Go build constraint: " ++ entry.name);
            }
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
/// Names are allocated from Context.allocator. The caller owns go_name.
pub const FunctionInfo = struct { public_name: []const u8, is_public: bool, has_error: bool };

/// Once per generation, after lowering and before any package is rendered.
pub const AnalyzeContext = struct {
    render: Context,
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

    pub fn optionsOf(self: AnalyzeContext, comptime P: Plugin, comptime attachment: Attachment, ext: ?semantic.Extensions) !?(if (attachment == .function) P.FunctionOptions else P.TypeOptions) {
        return readOptions(P, attachment, self.render.allocator, ext);
    }
};

/// Support for a plugin's own unit tests: a rendering context whose
/// formatting helpers work and whose generator-backed writers -- the ones
/// that spell types, signatures and parameter names -- report
/// `error.Unsupported`, since only the generator can answer for those.
pub const testing = struct {
    pub fn context(allocator: std.mem.Allocator, program: abi.Program) Context {
        return .{ .allocator = allocator, .program = program, .options = .{}, .writers = &writers };
    }

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
        .writeFuncHeader = format.writeFuncHeader,
        .writeMethodHeader = format.writeMethodHeader,
        .identifierAlloc = format.identifierAlloc,
        .writeStringLiteral = format.writeStringLiteral,
    };

    const unsupported = struct {
        fn typeName(_: Context, _: *std.Io.Writer, _: []const u8) anyerror!void {
            return error.Unsupported;
        }
        fn goType(_: Context, _: *std.Io.Writer, _: semantic.TypeNode) anyerror!void {
            return error.Unsupported;
        }
        fn receiverName(_: Context, _: std.mem.Allocator, _: []const u8) anyerror![]u8 {
            return error.Unsupported;
        }
        fn signature(_: Context, _: *std.Io.Writer, _: abi.AbiFn, _: SignatureOptions) anyerror!void {
            return error.Unsupported;
        }
        fn function(_: Context, _: *std.Io.Writer, _: abi.AbiFn) anyerror!void {
            return error.Unsupported;
        }
        fn doc(_: *std.Io.Writer, _: []const u8, _: []const u8, _: []const u8) anyerror!void {
            return error.Unsupported;
        }
        fn info(_: Context, _: abi.AbiFn) anyerror!FunctionInfo {
            return error.Unsupported;
        }
        fn results(_: Context, _: *std.Io.Writer, _: abi.AbiFn, _: ResultOptions) anyerror!usize {
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

pub const FilePhase = enum { begin, end };
pub const FileInfo = struct {
    source_file: ?SourceFile = null,
    path: []const u8,
    owner: []const u8 = "generator",
    kind: enum { api, enums, structs, handles, runtime, errors, tagged_union, plugin, package },
};

test "validation and transformation contexts read both declaration option types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const p: Plugin = .{ .name = "LOOKUP", .FunctionOptions = struct { enabled: bool }, .TypeOptions = struct { enabled: bool } };
    const options = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"enabled\":true}", .{});
    const value: semantic.Extensions = .{ .entries = &.{.{ .plugin = "LOOKUP", .options = options }} };
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    var facts: Facts = .{};
    const validate: ValidateContext = .{ .allocator = allocator, .document = .{ .package = "test", .prefix = "test", .zig_version = "0.16.0", .types = &.{}, .functions = &.{} }, .diagnostics = &issues, .facts = &facts };
    const transform: TransformContext = .{ .allocator = allocator, .document = validate.document, .diagnostics = &issues };
    const render = testing.context(allocator, .{ .package = "test", .prefix = "test", .functions = &.{} });
    const analyze: AnalyzeContext = .{ .render = render, .facts = &facts, .diagnostics = &issues };
    inline for (.{ Attachment.function, Attachment.type }) |attachment| {
        try std.testing.expect((try validate.optionsOf(p, attachment, value)).?.enabled);
        try std.testing.expect((try transform.optionsOf(p, attachment, value)).?.enabled);
        try std.testing.expect((try render.optionsOf(p, attachment, value)).?.enabled);
        try std.testing.expect((try analyze.optionsOf(p, attachment, value)).?.enabled);
        try std.testing.expect(try render.optionsOf(p, attachment, null) == null);
    }
}

test "the test context formats headers, identifiers and literals like the generator" {
    const context = testing.context(std.testing.allocator, .{ .package = "test", .prefix = "test", .functions = &.{} });
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try context.writeFuncHeader(&output.writer, "ModeValues", "", "[]Mode");
    try context.writeMethodHeader(&output.writer, .{ .name = "value", .type = "Mode", .pointer = true }, "UnmarshalJSON", "data []byte", "error");
    try context.writeMethodHeader(&output.writer, .{ .name = "value", .type = "Mode" }, "IsKnown", "", "");
    try context.writeStringLiteral(&output.writer, "tab\t\"quoted\"");
    try std.testing.expectEqualStrings("func ModeValues() []Mode {func (value *Mode) UnmarshalJSON(data []byte) error {func (value Mode) IsKnown() {\"tab\\t\\\"quoted\\\"\"", output.written());
    const pascal = try context.identifierAlloc(std.testing.allocator, "low_water", .pascal);
    defer std.testing.allocator.free(pascal);
    try std.testing.expectEqualStrings("LowWater", pascal);
    const camel = try context.identifierAlloc(std.testing.allocator, "low_water", .camel);
    defer std.testing.allocator.free(camel);
    try std.testing.expectEqualStrings("lowWater", camel);
    try std.testing.expectError(error.Unsupported, context.writeTypeName(&output.writer, "Mode"));
}
