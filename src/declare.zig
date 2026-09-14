//! Private flat declarations used between authoring normalization and reflection.
//! Public binding files use scope(), declaration entries and typed contracts in author.zig.
const std = @import("std");
const plugin = @import("plugin");

/// One plugin's options on a declaration. `use` captures the value at
/// comptime, so a field the plugin does not have, or a value of the wrong
/// shape, is an ordinary Zig compile error at the declaration rather than a
/// diagnostic long afterwards.
pub const Extension = struct {
    /// Set by `Entry.use` for `zigo.features`. The reflector resolves these
    /// two before it writes them -- an iterator name derived from the method,
    /// the kinds in declaration order -- and then writes them into `ext` like
    /// any other plugin's options.
    builtin: union(enum) { none, iterator: Iterator, implements: ImplementsOptions } = .none,
    /// The plugin's name. It is the key the options travel under in
    /// `semantic.json`, so two plugins cannot collide silently.
    plugin: []const u8,
    /// The captured options, encoded on demand. Reflection is what calls it.
    jsonAlloc: *const fn (std.mem.Allocator) anyerror![]u8,
};

/// `value` as `P`'s options, ready to hang on a declaration. A plugin is
/// anything that names itself and names the type of its options, which is what
/// `zigo.plugin.Plugin` does.
pub fn extension(comptime P: anytype, comptime value: P.Options) Extension {
    return .{
        .plugin = P.name,
        .jsonAlloc = struct {
            fn jsonAlloc(allocator: std.mem.Allocator) anyerror![]u8 {
                // Null is an explicit plugin value, even when the option has a non-null default.
                return std.json.Stringify.valueAlloc(allocator, value, .{});
            }
        }.jsonAlloc,
    };
}

/// What a byte or integer position means to Go.
pub const SemanticHint = enum { c_string, opaque_bytes, utf8_string, codepoint, integer };
pub const Direction = enum { in, inout, out };
/// How much of an `.out` buffer was filled: all of it, or the count the
/// function returns.
/// How much of an out slice the caller may read back. `all` is the whole
/// buffer; `result` is the `usize` the function returns; `returned_slice` is
/// the length of the slice it returns into that same buffer.
pub const Written = enum { all, result, returned_slice };
pub const Retention = enum { borrowed, retained };
pub const Reentrancy = enum { allowed, forbidden };
pub const Thread = enum { caller, any };
pub const Ownership = enum { borrowed, caller, library };
pub const Access = enum { projection, snapshot };
/// Automatic function discovery: which containers are walked, and the
/// resolved paths (`root.name`, `<Type>.name`) left out.
pub const Discovery = struct {
    mode: enum { public, recursive },
    exclude: []const []const u8 = &.{},
};
pub const Codepoints = enum { explicit, infer_u21 };
pub const Strings = enum { explicit, infer_utf8 };

/// What the shim passes for an injected `std.mem.Allocator` or `std.Io`
/// parameter: one of the std allocators by name, or a declaration path
/// resolved against the bound module (`.{ .path = "gpa" }`).
pub const Injection = union(enum) {
    c_allocator,
    page_allocator,
    smp_allocator,
    path: []const u8,
};

/// A user Go type standing in for a scalar or value struct.
pub const GoAdapter = struct {
    /// Go spelling of the type, such as `image.Point` or `Timestamp`.
    type: []const u8,
    /// Function taking `type` and returning the raw mirror.
    to_raw: []const u8,
    /// Function taking the raw mirror and returning `type`.
    from_raw: []const u8,
    /// Import path of the qualifier `type` uses; absent for a same-package type.
    import: ?[]const u8 = null,
};

/// The value handed back to native code when a Go callback panics or fails.
pub const CallbackFailure = struct { result: i128 };

pub const OptionsSpec = struct {
    prefix: ?[]const u8 = null,
    type_name: ?[]const u8 = null,
};

/// One parameter Go passes, in the position it has in the Zig signature
/// once the receiver and injected arguments are removed. Every field is
/// optional: `.{}` keeps the source name and the defaults, `.{ .name = "n" }`
/// only names it, and the rest declare contracts.
pub const Param = struct {
    /// The Go-side name. Absent means the name the source scan found, then
    /// `p<n>`.
    name: ?[]const u8 = null,
    semantic: ?SemanticHint = null,
    direction: Direction = .in,
    written: ?Written = null,
    /// Staging buffer size for a `*std.Io.Reader`/`*std.Io.Writer` parameter.
    buffer: ?u32 = null,
    /// Fields of a struct parameter Go passes individually; the rest keep
    /// their Zig defaults.
    flatten: []const []const u8 = &.{},
    options: ?OptionsSpec = null,
    retention: ?Retention = null,
    /// The callback may return a Go `error` (its Zig result is `i32`).
    go_error: bool = false,
    on_failure: ?CallbackFailure = null,
    reentrancy: ?Reentrancy = null,
    thread: ?Thread = null,
    /// The parameter carrying this callback's Go token, when it is not the
    /// `usize` right after the callback.
    userdata: ?struct { param: []const u8 } = null,
    go: ?GoAdapter = null,
    /// Plugin options, one entry per plugin. Written by `Param.use`.
    ext: []const Extension = &.{},
};

/// Everything about a function's result.
pub const Returns = struct {
    ownership: ?Ownership = null,
    semantic: ?SemanticHint = null,
    /// Path of the function that frees a caller-owned result.
    release: ?[]const u8 = null,
    go: ?GoAdapter = null,
    /// Plugin options, one entry per plugin. Written by `Returns.use`.
    ext: []const Extension = &.{},
};

/// The built-in features' options are the plugin contract's, so a declaration
/// writes the same type the generator's rules read back out of `ext`.
///
/// An empty iterator name asks for the derived one: `All`, or `AllChecked`
/// over a method whose own name carries the `Checked` suffix.
pub const Iterator = plugin.builtins.iterator.Options;

/// A Go standard interface a handle method also satisfies. The generator adds
/// the interface's method next to the bound one, calling it and adapting the
/// result: `.writer` adds `Write(p []byte) (int, error)`, `.reader` adds
/// `Read(p []byte) (int, error)`, `.writer_to` adds
/// `WriteTo(w io.Writer) (int64, error)`, and `.reader_from` adds
/// `ReadFrom(r io.Reader) (int64, error)`.
pub const Implements = plugin.builtins.Implements;

/// What `.use(zigo.features.implements, ...)` captured: the interfaces and
/// whether the zigo-shaped original stays exported beside the wrappers.
pub const ImplementsOptions = plugin.builtins.implements.Options;

pub const Cancel = struct {
    /// The `*const std.atomic.Value(u32)` parameter, by its `Param.name`.
    param: []const u8,
    /// The Zig error raised when the flag was set. Defaults to `Canceled`.
    canceled: ?[]const u8 = null,
};

/// One bound function. `.path` is `root.<name>`, `<Type>.<name>`, or
/// `root.<namespace>.<name>`.
pub const Function = struct {
    codepoints: ?Codepoints = null,
    strings: ?Strings = null,
    path: []const u8,
    /// Go name override.
    name: ?[]const u8 = null,
    /// Go doc override; absent takes the Zig doc comment.
    doc: ?[]const u8 = null,
    params: []const Param = &.{},
    returns: Returns = .{},
    /// Makes a free function a method of a registered handle or enum.
    receiver: ?type = null,
    force_free: bool = false,
    constructs: ?type = null,
    destroys: ?type = null,
    child_of_receiver: bool = false,
    iterator: ?Iterator = null,
    /// The Go standard interfaces this method also satisfies, each through a
    /// wrapper of its own, and whether the bound method stays exported beside
    /// them.
    implements: ?ImplementsOptions = null,
    cancel: ?Cancel = null,
    /// Declarations this function stands in for in `go-coverage`.
    covers: []const []const u8 = &.{},
    /// The exported C symbol, written as is. Absent derives it from the
    /// prefix, the receiver or namespace, and the Go name -- which doubles
    /// the container when a namespace function is `.name`d after it.
    symbol: ?[]const u8 = null,
    /// Plugin options, one entry per plugin. Written by `use`.
    ext: []const Extension = &.{},
};

/// A getter (and optionally setter) on a handle, reached by a dotted field
/// path.
pub const HandleField = struct {
    path: []const u8,
    name: ?[]const u8 = null,
    set: bool = false,
    doc: ?[]const u8 = null,
    /// Plugin options, one entry per plugin. Written by `use`. The
    /// getter and the setter both carry them, the way they share `doc`.
    ext: []const Extension = &.{},

    /// Attach `value` as plugin `P`'s function options for the accessors
    /// this field synthesizes. A plugin whose `subjects` exclude `.function`
    /// is refused here, where the declaration is written.
    pub fn extend(comptime self: HandleField, comptime P: anytype, comptime value: P.FunctionOptions) HandleField {
        // `P` is a `plugin.Plugin` value from a binding, or a type spelling
        // the same decls in a test; only a value carries `subjects`.
        comptime if (@TypeOf(P) != type and @hasField(@TypeOf(P), "subjects")) {
            var supported = false;
            for (P.subjects) |candidate| if (candidate == .function) {
                supported = true;
            };
            if (!supported) @compileError("zigo plugin " ++ P.name ++ " does not support function");
        };
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.FunctionOptions;
        };
        var result = self;
        result.ext = self.ext ++ [_]Extension{extension(Captured, value)};
        return result;
    }
};

/// A hint for one field of a value or materialized struct.
pub const ValueField = struct {
    name: []const u8,
    semantic: ?SemanticHint = null,
    /// Go doc for this field. Absent takes the Zig source's `///`, and
    /// failing that the generated description.
    doc: ?[]const u8 = null,
    /// Plugin options, one entry per plugin. Written by `use`.
    ext: []const Extension = &.{},

    /// Attach `value` as plugin `P`'s field options for this member. A
    /// plugin whose `subjects` exclude `.field` is refused here, where the
    /// declaration is written.
    pub fn use(comptime self: ValueField, comptime P: anytype, comptime value: P.FieldOptions) ValueField {
        comptime checkNodeSubject(P, "field");
        comptime checkDuplicate(self.ext, P.name);
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.FieldOptions;
        };
        var result = self;
        result.ext = self.ext ++ [_]Extension{extension(Captured, value)};
        return result;
    }
};

/// Go doc for one member of a registered enum, by its Zig tag name.
pub const EnumField = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
    /// Plugin options, one entry per plugin. Written by `use`.
    ext: []const Extension = &.{},

    /// Attach `value` as plugin `P`'s tag options for this member. A plugin
    /// whose `subjects` exclude `.enum_tag` is refused here.
    pub fn use(comptime self: EnumField, comptime P: anytype, comptime value: P.TagOptions) EnumField {
        comptime checkNodeSubject(P, "enum_tag");
        comptime checkDuplicate(self.ext, P.name);
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.TagOptions;
        };
        var result = self;
        result.ext = self.ext ++ [_]Extension{extension(Captured, value)};
        return result;
    }
};

/// The subject check every node-level `use` shares. `P` is a `plugin.Plugin`
/// value from a binding, or a type spelling the same decls in a test; only a
/// value carries `subjects`. Tags are compared by name so the DSL's own
/// `Subject` spelling and the plugin contract's pass the same check.
fn checkNodeSubject(comptime P: anytype, comptime subject: []const u8) void {
    if (@TypeOf(P) == type or !@hasField(@TypeOf(P), "subjects")) return;
    for (P.subjects) |candidate| if (std.mem.eql(u8, @tagName(candidate), subject)) return;
    @compileError("zigo plugin " ++ P.name ++ " does not support " ++ subject);
}

fn checkDuplicate(comptime entries: []const Extension, comptime name: []const u8) void {
    for (entries) |existing| if (std.mem.eql(u8, existing.plugin, name))
        @compileError("zigo duplicate plugin attachment: " ++ name);
}

pub const Handle = struct {
    type: type,
    name: ?[]const u8 = null,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    fields: []const HandleField = &.{},
    /// Plugin options, one entry per plugin. Written by `use`.
    ext: []const Extension = &.{},
};

pub const Value = struct {
    type: type,
    name: ?[]const u8 = null,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    go: ?GoAdapter = null,
    fields: []const ValueField = &.{},
    /// Plugin options, one entry per plugin. Written by `use`.
    ext: []const Extension = &.{},
};

pub const Materialized = struct {
    type: type,
    name: ?[]const u8 = null,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    fields: []const ValueField = &.{},
    ext: []const Extension = &.{},
};

pub const Enum = struct {
    type: type,
    name: ?[]const u8 = null,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    /// Generate `Parse<Enum>`, `MarshalText` and `UnmarshalText`.
    text: bool = false,
    /// `false` accepts values outside the named tags.
    exhaustive: bool = true,
    go: ?GoAdapter = null,
    /// Zig methods the generated Go enum makes redundant, for `go-coverage`.
    covers: []const []const u8 = &.{},
    /// Go docs for individual tags. Listing a tag is optional, and a tag left
    /// out takes the Zig source's `///`.
    fields: []const EnumField = &.{},
    /// Plugin options, one entry per plugin. Written by `use`.
    ext: []const Extension = &.{},
};

pub const TaggedUnion = struct {
    type: type,
    name: ?[]const u8 = null,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    access: Access = .projection,
    /// Variants left out of the Go type.
    omit: []const []const u8 = &.{},
    /// Plugin options, one entry per plugin. Written by `use`.
    ext: []const Extension = &.{},
};

/// The hint for one value parameter of a callback, positionally; the
/// userdata slot is not listed.
pub const CallbackParam = struct { semantic: ?SemanticHint = null };

/// Where a callback's userdata sits when it is not the trailing `usize`.
pub const Userdata = union(enum) { first, last, index: usize };

pub const Callback = struct {
    type: type,
    /// Required: a function-pointer alias has no name of its own.
    name: []const u8,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    params: []const CallbackParam = &.{},
    returns: struct { semantic: ?SemanticHint = null } = .{},
    userdata: ?Userdata = null,
    /// Defaults every call site of this type inherits; a `Param` may
    /// override each field.
    retention: ?Retention = null,
    reentrancy: ?Reentrancy = null,
    thread: ?Thread = null,
    on_failure: ?CallbackFailure = null,
    ext: []const Extension = &.{},
};

/// A registered type. The variant is what `.repr` used to say, and it is
/// what decides which keys the entry can carry.
pub const Type = union(enum) {
    handle: Handle,
    value: Value,
    materialized: Materialized,
    enumeration: Enum,
    tagged_union: TaggedUnion,
    callback: Callback,

    pub fn zigType(comptime self: Type) type {
        return switch (self) {
            inline else => |entry| entry.type,
        };
    }

    /// The Go name: the explicit `.name`, else the short Zig type name.
    pub fn goName(comptime self: Type) []const u8 {
        return switch (self) {
            .callback => |entry| entry.name,
            inline else => |entry| entry.name orelse shortTypeName(@typeName(entry.type)),
        };
    }

    /// Whether the entry produces a Go handle (opaque or tagged union).
    pub fn isHandle(comptime self: Type) bool {
        return self == .handle or self == .tagged_union;
    }
};

pub const Package = struct {
    path: []const u8,
    name: ?[]const u8 = null,
    doc: ?[]const u8 = null,
    /// Registered type names; a trailing `*` is a prefix pattern.
    types: []const []const u8 = &.{},
    /// Function paths.
    functions: []const []const u8 = &.{},
    /// Namespaces, exact or `prefix*`.
    namespaces: []const []const u8 = &.{},
    /// Pull every reachable registered type into this package.
    closure: bool = false,
};

pub const Interface = struct {
    name: []const u8,
    /// Zig method names every listed type shares.
    methods: []const []const u8,
    /// Registered handle types.
    types: []const type,
    closer: bool = true,
    doc: ?[]const u8 = null,
};

/// A session: the primary handle a Go container owns, and the dependent child
/// handles it hands out. Resolved to Zig types, like every other declaration
/// here; the reflector turns them into registered opaque names.
/// One dependent child of a session, resolved to its Zig type. `accessor`
/// is the whole accessor name, for a type whose plural is not `type ++ "s"`.
pub const SessionChild = struct {
    type: type,
    accessor: ?[]const u8 = null,
};

pub const Session = struct {
    name: []const u8,
    primary: type,
    children: []const SessionChild,
    doc: ?[]const u8 = null,
};

pub const Binding = struct {
    /// The module paths resolve against.
    root: type,
    allocator: ?Injection = null,
    io: ?Injection = null,
    discovery: ?Discovery = null,
    codepoints: Codepoints = .explicit,
    strings: Strings = .explicit,
    /// Default `Returns.release` for caller-owned string results.
    string_release: ?[]const u8 = null,
    types: []const Type = &.{},
    functions: []const Function = &.{},
    packages: []const Package = &.{},
    interfaces: []const Interface = &.{},
    sessions: []const Session = &.{},
};

pub fn shortTypeName(full_name: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, full_name, '.')) |index| full_name[index + 1 ..] else full_name;
}

test "a binding literal coerces, keeps defaults, and exposes type values" {
    const Lib = struct {
        pub const Terminal = struct { cols: u16 };
        pub const Key = enum(u8) { a, b };
    };
    const out_buffer: Param = .{ .name = "dst", .direction = .out, .written = .result };
    const binding: Binding = comptime .{
        .root = Lib,
        .allocator = .smp_allocator,
        .io = .{ .path = "io" },
        .types = &.{
            .{ .handle = .{ .type = Lib.Terminal, .fields = &.{.{ .path = "cols" }} } },
            .{ .enumeration = .{ .type = Lib.Key, .text = true } },
        },
        .functions = &.{
            .{ .path = "Terminal.init", .constructs = Lib.Terminal, .params = &.{.{ .name = "opts", .flatten = &.{ "cols", "rows" } }} },
            .{ .path = "root.render", .params = &.{ .{ .name = "text", .semantic = .utf8_string }, out_buffer } },
            .{ .path = "root.take", .returns = .{ .ownership = .caller, .release = "root.free" }, .covers = &.{"Terminal.take"} },
        },
    };
    comptime {
        std.debug.assert(binding.types[0].zigType() == Lib.Terminal);
        std.debug.assert(std.mem.eql(u8, binding.types[1].goName(), "Key"));
        std.debug.assert(binding.types[0].isHandle() and !binding.types[1].isHandle());
        std.debug.assert(binding.functions[0].constructs.? == Lib.Terminal);
        std.debug.assert(binding.functions[1].params[1].direction == .out);
        std.debug.assert(binding.functions[2].returns.ownership.? == .caller);
        std.debug.assert(binding.discovery == null);
    }
}

// Shared native callback layout for authoring and reflection.
pub const callback_layout = @import("callback_layout.zig");
