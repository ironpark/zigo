//! The binding declaration schema: the types a `bindings.zig` fills in and
//! `zigo.define` takes.
//!
//! Every entry is a real struct or union, so the compiler enforces the
//! grammar: an unknown key, a key on the wrong kind of entry, or a value of
//! the wrong shape is an ordinary Zig compile error at the literal. Defaults
//! live here too, which is what keeps a typical entry to one line.
//!
//! Three spelling rules hold throughout:
//! - Zig things are referenced by value: `.type`, `.receiver`, `.constructs`,
//!   `.destroys` and `Interface.types` take the type itself.
//! - Go things and declaration paths are strings: `.name` is always the Go
//!   name, `.path` always addresses a Zig declaration, and `.covers`,
//!   `.release`, `.string_release` and `.exclude` are paths.
//! - Contracts sit on the thing they describe: a parameter's contract is in
//!   its `Param`, a result's in `Returns`, a callback type's on its entry.
const std = @import("std");

/// One plugin's options on a declaration. `extend` captures the value at
/// comptime, so a field the plugin does not have, or a value of the wrong
/// shape, is an ordinary Zig compile error at the declaration rather than a
/// diagnostic long afterwards.
pub const Extension = struct {
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
                return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
            }
        }.jsonAlloc,
    };
}

/// What a byte or integer position means to Go.
pub const SemanticHint = enum { c_string, opaque_bytes, utf8_string, codepoint, integer };
pub const Direction = enum { in, inout, out };
/// How much of an `.out` buffer was filled: all of it, or the count the
/// function returns.
pub const Written = enum { all, result };
pub const Retention = enum { borrowed, retained };
pub const Reentrancy = enum { allowed, forbidden };
pub const Thread = enum { caller, any };
pub const Ownership = enum { borrowed, caller, library };
pub const Access = enum { projection, snapshot };
pub const Discover = enum { public, recursive };
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
    retention: ?Retention = null,
    /// The callback may return a Go `error` (its Zig result is `i32`).
    go_error: bool = false,
    on_callback_failure: ?CallbackFailure = null,
    reentrancy: ?Reentrancy = null,
    thread: ?Thread = null,
    /// The parameter carrying this callback's Go token, when it is not the
    /// `usize` right after the callback.
    userdata: ?struct { param: []const u8 } = null,
    go: ?GoAdapter = null,
};

/// Everything about a function's result.
pub const Returns = struct {
    ownership: ?Ownership = null,
    semantic: ?SemanticHint = null,
    /// Path of the function that frees a caller-owned result.
    release: ?[]const u8 = null,
    go: ?GoAdapter = null,
};

pub const Iterator = struct { name: []const u8 = "All" };

/// A Go standard interface a handle method also satisfies. The generator adds
/// the interface's method next to the bound one, calling it and adapting the
/// result: `.writer` adds `Write(p []byte) (int, error)`, `.reader` adds
/// `Read(p []byte) (int, error)`, `.writer_to` adds
/// `WriteTo(w io.Writer) (int64, error)`, and `.reader_from` adds
/// `ReadFrom(r io.Reader) (int64, error)`.
pub const Implements = enum { writer, reader, writer_to, reader_from };

pub const Cancel = struct {
    /// The `*const std.atomic.Value(u32)` parameter, by its `Param.name`.
    param: []const u8,
    /// The Zig error raised when the flag was set. Defaults to `Canceled`.
    canceled: ?[]const u8 = null,
};

/// Fields a function-building helper may overlay on an existing entry.
/// `null` keeps the current value.
pub const FunctionOptions = struct {
    name: ?[]const u8 = null,
    doc: ?[]const u8 = null,
    params: ?[]const Param = null,
    returns: ?Returns = null,
    receiver: ?type = null,
    constructs: ?type = null,
    destroys: ?type = null,
    child_of_receiver: ?bool = null,
    iterator: ?Iterator = null,
    implements: ?Implements = null,
    cancel: ?Cancel = null,
    covers: ?[]const []const u8 = null,
    /// Plugin options to add. They are appended, never replaced, so a helper
    /// that extends a function cannot drop what another one attached.
    ext: ?[]const Extension = null,
};

/// One bound function. `.path` is `root.<name>`, `<Type>.<name>`, or
/// `root.<namespace>.<name>`.
pub const Function = struct {
    path: []const u8,
    /// Go name override.
    name: ?[]const u8 = null,
    /// Go doc override; absent takes the Zig doc comment.
    doc: ?[]const u8 = null,
    params: []const Param = &.{},
    returns: Returns = .{},
    /// Makes a free function a method of a registered handle or enum.
    receiver: ?type = null,
    constructs: ?type = null,
    destroys: ?type = null,
    child_of_receiver: bool = false,
    iterator: ?Iterator = null,
    /// A Go standard interface this method also satisfies through a wrapper.
    implements: ?Implements = null,
    cancel: ?Cancel = null,
    /// Declarations this function stands in for in `go-coverage`.
    covers: []const []const u8 = &.{},
    /// Plugin options, one entry per plugin. Written by `extend`.
    ext: []const Extension = &.{},

    /// Return a copy with the supplied DSL options overlaid.
    pub fn with(comptime self: Function, comptime options: FunctionOptions) Function {
        var result = self;
        if (options.name) |value| result.name = value;
        if (options.doc) |value| result.doc = value;
        if (options.params) |value| result.params = value;
        if (options.returns) |value| result.returns = value;
        if (options.receiver) |value| result.receiver = value;
        if (options.constructs) |value| result.constructs = value;
        if (options.destroys) |value| result.destroys = value;
        if (options.child_of_receiver) |value| result.child_of_receiver = value;
        if (options.iterator) |value| result.iterator = value;
        if (options.implements) |value| result.implements = value;
        if (options.cancel) |value| result.cancel = value;
        if (options.covers) |value| result.covers = value;
        if (options.ext) |value| result.ext = result.ext ++ value;
        return result;
    }

    /// Attach `value` as plugin `P`'s options for this function.
    pub fn extend(comptime self: Function, comptime P: anytype, comptime value: P.Options) Function {
        var result = self;
        result.ext = self.ext ++ [_]Extension{extension(P, value)};
        return result;
    }

    /// Mark the function as constructing a handle of `T`.
    pub fn constructor(comptime self: Function, comptime T: type) Function {
        var result = self;
        result.constructs = T;
        return result;
    }

    /// Mark the function as destroying a handle of `T`.
    pub fn destructor(comptime self: Function, comptime T: type) Function {
        var result = self;
        result.destroys = T;
        return result;
    }

    /// Mark the constructed handle as borrowing its receiver's lifetime.
    pub fn childOfReceiver(comptime self: Function) Function {
        var result = self;
        result.child_of_receiver = true;
        return result;
    }

    /// Mark a handle result as owned by the caller.
    pub fn callerOwned(comptime self: Function) Function {
        var result = self;
        result.returns.ownership = .caller;
        return result;
    }

    /// Mark a buffer result as caller-owned and name its release function.
    pub fn releasedBy(comptime self: Function, comptime path: []const u8) Function {
        var result = self;
        result.returns.ownership = .caller;
        result.returns.release = path;
        return result;
    }

    /// Mark a handle result as borrowed from its receiver.
    pub fn borrowed(comptime self: Function) Function {
        var result = self;
        result.returns.ownership = .borrowed;
        return result;
    }
};

/// Free functions attached to one receiver, with a shared name prefix
/// removed from each.
pub const Methods = struct {
    receiver: type,
    strip_prefix: []const u8 = "",
    functions: []const Function,
};

/// A getter (and optionally setter) on a handle, reached by a dotted field
/// path.
pub const HandleField = struct {
    path: []const u8,
    name: ?[]const u8 = null,
    set: bool = false,
    doc: ?[]const u8 = null,
};

/// A hint for one field of a value or materialized struct.
pub const ValueField = struct {
    name: []const u8,
    semantic: SemanticHint,
};

pub const Handle = struct {
    type: type,
    name: ?[]const u8 = null,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    fields: []const HandleField = &.{},
    /// Plugin options, one entry per plugin. Written by `extend`.
    ext: []const Extension = &.{},

    /// Attach `value` as plugin `P`'s options for this type.
    pub fn extend(comptime self: @This(), comptime P: anytype, comptime value: P.Options) @This() {
        var result = self;
        result.ext = self.ext ++ [_]Extension{extension(P, value)};
        return result;
    }
};

pub const Value = struct {
    type: type,
    name: ?[]const u8 = null,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    go: ?GoAdapter = null,
    fields: []const ValueField = &.{},
    /// Plugin options, one entry per plugin. Written by `extend`.
    ext: []const Extension = &.{},

    /// Attach `value` as plugin `P`'s options for this type.
    pub fn extend(comptime self: @This(), comptime P: anytype, comptime value: P.Options) @This() {
        var result = self;
        result.ext = self.ext ++ [_]Extension{extension(P, value)};
        return result;
    }
};

pub const Materialized = struct {
    type: type,
    name: ?[]const u8 = null,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    fields: []const ValueField = &.{},
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
    /// Plugin options, one entry per plugin. Written by `extend`.
    ext: []const Extension = &.{},

    /// Attach `value` as plugin `P`'s options for this type.
    pub fn extend(comptime self: @This(), comptime P: anytype, comptime value: P.Options) @This() {
        var result = self;
        result.ext = self.ext ++ [_]Extension{extension(P, value)};
        return result;
    }
};

pub const TaggedUnion = struct {
    type: type,
    name: ?[]const u8 = null,
    /// Go doc override; absent uses the generated description.
    doc: ?[]const u8 = null,
    access: Access = .projection,
    /// Variants left out of the Go type.
    omit: []const []const u8 = &.{},
    /// Plugin options, one entry per plugin. Written by `extend`.
    ext: []const Extension = &.{},

    /// Attach `value` as plugin `P`'s options for this type.
    pub fn extend(comptime self: @This(), comptime P: anytype, comptime value: P.Options) @This() {
        var result = self;
        result.ext = self.ext ++ [_]Extension{extension(P, value)};
        return result;
    }
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
    on_callback_failure: ?CallbackFailure = null,
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

pub const Binding = struct {
    /// The module paths resolve against.
    root: type,
    allocator: ?Injection = null,
    io: ?Injection = null,
    discover: ?Discover = null,
    /// Paths discovery must leave out. Requires `.discover`.
    exclude: []const []const u8 = &.{},
    codepoints: Codepoints = .explicit,
    strings: Strings = .explicit,
    /// Default `Returns.release` for caller-owned string results.
    string_release: ?[]const u8 = null,
    types: []const Type = &.{},
    functions: []const Function = &.{},
    methods: []const Methods = &.{},
    packages: []const Package = &.{},
    interfaces: []const Interface = &.{},
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
        .methods = &.{.{ .receiver = Lib.Key, .strip_prefix = "key", .functions = &.{.{ .path = "root.keyName" }} }},
    };
    comptime {
        std.debug.assert(binding.types[0].zigType() == Lib.Terminal);
        std.debug.assert(std.mem.eql(u8, binding.types[1].goName(), "Key"));
        std.debug.assert(binding.types[0].isHandle() and !binding.types[1].isHandle());
        std.debug.assert(binding.functions[0].constructs.? == Lib.Terminal);
        std.debug.assert(binding.functions[1].params[1].direction == .out);
        std.debug.assert(binding.functions[2].returns.ownership.? == .caller);
        std.debug.assert(binding.methods[0].receiver == Lib.Key);
        std.debug.assert(binding.discover == null and binding.exclude.len == 0);
    }
}
