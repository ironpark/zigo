const std = @import("std");

pub const Int = struct {
    bits: u16,
    is_usize: bool = false,
    signed: bool,
};

pub const Float = struct { bits: u16 };
pub const Ref = struct { ref: []const u8 };
pub const OpaquePtr = struct {
    @"const": bool,
    nullable: bool,
    ref: []const u8,
};
pub const Slice = struct {
    @"const": bool,
    element: *TypeNode,
    /// A sentinel on the Zig slice or many-pointer spelling. The semantic
    /// shape stays a slice so older IR readers can still parse ordinary byte
    /// slices, while string-slice lowering can reproduce the declared element.
    sentinel: ?u8 = null,
    /// True when `sentinel` came from a many pointer (`[*:0]T`) rather than a
    /// sentinel slice (`[:0]T`). Meaningful only when `sentinel` is present.
    sentinel_many: bool = false,
};
pub const Optional = struct { child: *TypeNode };
/// Which direction a `*std.Io.Writer` / `*std.Io.Reader` parameter streams.
/// The two lower to different fixed callback signatures, so the direction is
/// the whole of the type: neither side carries a payload type.
pub const StreamDirection = enum { writer, reader };
pub const IoStream = struct { direction: StreamDirection };
pub const ErrorUnion = struct {
    anyerror: bool = false,
    error_set: []const []const u8,
    payload: *TypeNode,
};
pub const Callback = struct {
    c_callconv: bool = true,
    has_userdata: bool,
    params: []const TypeNode,
    /// The declared callback type this signature was registered under, when
    /// the binding registered one (`.repr = .callback`). It names the Go
    /// type; the signature alone still decides the ABI.
    ref: ?[]const u8 = null,
    @"return": *TypeNode,
};

pub const TypeNode = union(enum) {
    bool: void,
    callback: Callback,
    /// The cancellation flag a `.cancel` function polls. Its Zig spelling is
    /// `*const std.atomic.Value(u32)` and it crosses as `const uint32_t *`;
    /// it is its own node because neither the pointer nor the atomic wrapper
    /// is a shape the generic lowering can carry, and because Go builds the
    /// flag itself rather than being handed one.
    cancel_flag: void,
    @"enum": Ref,
    error_union: ErrorUnion,
    float: Float,
    int: Int,
    io_stream: IoStream,
    opaque_ptr: OpaquePtr,
    optional: Optional,
    slice: Slice,
    value_struct: Ref,
    void: void,

    pub fn jsonStringify(self: TypeNode, jw: anytype) !void {
        try jw.beginObject();
        switch (self) {
            .bool => try writeKind(jw, "bool"),
            .cancel_flag => try writeKind(jw, "cancel_flag"),
            .callback => |value| {
                try jw.objectField("c_callconv");
                try jw.write(value.c_callconv);
                try jw.objectField("has_userdata");
                try jw.write(value.has_userdata);
                try writeKind(jw, "callback");
                try jw.objectField("params");
                try jw.write(value.params);
                if (value.ref) |ref| {
                    try jw.objectField("ref");
                    try jw.write(ref);
                }
                try jw.objectField("return");
                try jw.write(value.@"return".*);
            },
            .@"enum" => |value| {
                try writeKind(jw, "enum");
                try jw.objectField("ref");
                try jw.write(value.ref);
            },
            .error_union => |value| {
                if (value.anyerror) {
                    try jw.objectField("anyerror");
                    try jw.write(true);
                }
                try jw.objectField("error_set");
                try jw.write(value.error_set);
                try writeKind(jw, "error_union");
                try jw.objectField("payload");
                try jw.write(value.payload.*);
            },
            .float => |value| {
                try jw.objectField("bits");
                try jw.write(value.bits);
                try writeKind(jw, "float");
            },
            .int => |value| {
                try jw.objectField("bits");
                try jw.write(value.bits);
                try jw.objectField("is_usize");
                try jw.write(value.is_usize);
                try writeKind(jw, "int");
                try jw.objectField("signed");
                try jw.write(value.signed);
            },
            .io_stream => |value| try writeKind(jw, switch (value.direction) {
                .writer => "io_writer",
                .reader => "io_reader",
            }),
            .opaque_ptr => |value| {
                try jw.objectField("const");
                try jw.write(value.@"const");
                try writeKind(jw, "opaque_ptr");
                try jw.objectField("nullable");
                try jw.write(value.nullable);
                try jw.objectField("ref");
                try jw.write(value.ref);
            },
            .optional => |value| {
                try jw.objectField("child");
                try jw.write(value.child.*);
                try writeKind(jw, "optional");
            },
            .slice => |value| {
                try jw.objectField("const");
                try jw.write(value.@"const");
                try jw.objectField("element");
                try jw.write(value.element.*);
                if (value.sentinel) |sentinel| {
                    try jw.objectField("sentinel");
                    try jw.write(sentinel);
                    if (value.sentinel_many) {
                        try jw.objectField("sentinel_many");
                        try jw.write(true);
                    }
                }
                try writeKind(jw, "slice");
            },
            .value_struct => |value| {
                try writeKind(jw, "value_struct");
                try jw.objectField("ref");
                try jw.write(value.ref);
            },
            .void => try writeKind(jw, "void"),
        }
        try jw.endObject();
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!TypeNode {
        const object = switch (source) {
            .object => |object| object,
            else => return error.UnexpectedToken,
        };
        const kind_value = object.get("kind") orelse return error.MissingField;
        const kind = switch (kind_value) {
            .string => |string| string,
            else => return error.UnexpectedToken,
        };
        if (std.mem.eql(u8, kind, "void")) return .{ .void = {} };
        if (std.mem.eql(u8, kind, "bool")) return .{ .bool = {} };
        if (std.mem.eql(u8, kind, "cancel_flag")) return .{ .cancel_flag = {} };
        if (std.mem.eql(u8, kind, "int")) return .{ .int = .{
            .bits = try parseField(u16, allocator, object, "bits", options),
            .is_usize = try parseOptionalField(bool, allocator, object, "is_usize", false, options),
            .signed = try parseField(bool, allocator, object, "signed", options),
        } };
        if (std.mem.eql(u8, kind, "float")) return .{ .float = .{
            .bits = try parseField(u16, allocator, object, "bits", options),
        } };
        if (std.mem.eql(u8, kind, "enum")) return .{ .@"enum" = .{
            .ref = try parseField([]const u8, allocator, object, "ref", options),
        } };
        if (std.mem.eql(u8, kind, "value_struct")) return .{ .value_struct = .{
            .ref = try parseField([]const u8, allocator, object, "ref", options),
        } };
        if (std.mem.eql(u8, kind, "io_writer")) return .{ .io_stream = .{ .direction = .writer } };
        if (std.mem.eql(u8, kind, "io_reader")) return .{ .io_stream = .{ .direction = .reader } };
        if (std.mem.eql(u8, kind, "opaque_ptr")) return .{ .opaque_ptr = .{
            .@"const" = try parseField(bool, allocator, object, "const", options),
            .nullable = try parseField(bool, allocator, object, "nullable", options),
            .ref = try parseField([]const u8, allocator, object, "ref", options),
        } };
        if (std.mem.eql(u8, kind, "slice")) return .{ .slice = .{
            .@"const" = try parseField(bool, allocator, object, "const", options),
            .element = try parseTypePointer(allocator, object, "element", options),
            .sentinel = if (object.get("sentinel")) |value|
                try std.json.parseFromValueLeaky(u8, allocator, value, options)
            else
                null,
            .sentinel_many = try parseOptionalField(bool, allocator, object, "sentinel_many", false, options),
        } };
        if (std.mem.eql(u8, kind, "optional")) return .{ .optional = .{
            .child = try parseTypePointer(allocator, object, "child", options),
        } };
        if (std.mem.eql(u8, kind, "error_union")) return .{ .error_union = .{
            .anyerror = try parseOptionalField(bool, allocator, object, "anyerror", false, options),
            .error_set = try parseField([]const []const u8, allocator, object, "error_set", options),
            .payload = try parseTypePointer(allocator, object, "payload", options),
        } };
        if (std.mem.eql(u8, kind, "callback")) return .{ .callback = .{
            .c_callconv = try parseOptionalField(bool, allocator, object, "c_callconv", true, options),
            .has_userdata = try parseField(bool, allocator, object, "has_userdata", options),
            .params = try parseField([]const TypeNode, allocator, object, "params", options),
            .ref = try parseOptionalField(?[]const u8, allocator, object, "ref", null, options),
            .@"return" = try parseTypePointer(allocator, object, "return", options),
        } };
        return error.InvalidEnumTag;
    }
};

fn writeKind(jw: anytype, kind: []const u8) !void {
    try jw.objectField("kind");
    try jw.write(kind);
}

fn parseField(comptime T: type, allocator: std.mem.Allocator, object: std.json.ObjectMap, name: []const u8, options: std.json.ParseOptions) !T {
    return std.json.parseFromValueLeaky(T, allocator, object.get(name) orelse return error.MissingField, options);
}

fn parseOptionalField(comptime T: type, allocator: std.mem.Allocator, object: std.json.ObjectMap, name: []const u8, default: T, options: std.json.ParseOptions) !T {
    const value = object.get(name) orelse return default;
    return std.json.parseFromValueLeaky(T, allocator, value, options);
}

fn parseTypePointer(allocator: std.mem.Allocator, object: std.json.ObjectMap, name: []const u8, options: std.json.ParseOptions) std.json.ParseFromValueError!*TypeNode {
    const pointer = try allocator.create(TypeNode);
    errdefer allocator.destroy(pointer);
    pointer.* = try TypeNode.jsonParseFromValue(allocator, object.get(name) orelse return error.MissingField, options);
    return pointer;
}

pub const NameSource = enum { ast, fallback, sidecar };
/// A parameter the shim fills in rather than one the caller passes. Zig types
/// like `std.mem.Allocator` have no C representation, so the binding names the
/// value once and every generated signature drops the parameter.
pub const Injection = enum { allocator, io };
pub const Direction = enum { in, inout, out };
pub const Retention = enum { borrowed, retained };
pub const SemanticHint = enum { c_string, opaque_bytes, utf8_string };
pub const Ownership = enum { borrowed, caller, library };
/// How much of an `.out` slice the shim reports back as written. `.all` keeps
/// the whole buffer, `.return` trusts the function's `usize` result.
pub const Written = enum { all, @"return" };

/// A parameter's location in the source that declared it, from
/// `names.zig`'s AST scan. Unlike `SourceLocation` this carries no path: a
/// parameter's path is always its owning function's.
pub const ParamSourceLocation = struct {
    line: u32,
    column: u32,
};

pub const Parameter = struct {
    /// Bytes of shim-side staging buffer behind an `*std.Io.Writer` or
    /// `*std.Io.Reader` parameter, from `param_meta.<name>.buffer`. Only the
    /// buffer size changes; the C signature does not, so this is an ABI
    /// compatible knob rather than part of the shape.
    buffer: ?u32 = null,
    direction: Direction = .in,
    /// Set on the parameter `.cancel = .{ .param = "..." }` named. The type
    /// node says whether the Zig spelling was the one the contract requires;
    /// this says the binding asked for it, so a mismatch can be reported
    /// against the parameter the author meant rather than passed over.
    cancel: ?bool = null,
    /// Opt-in from `param_meta.<name>.go_error`: the Go callback type behind
    /// this parameter returns `(i32, error)` rather than `i32`, and an error
    /// it returns is stored and handed back by the public wrapper. Optional
    /// rather than a plain `bool` so a binding that never asks for it keeps
    /// the field out of `semantic.json` entirely.
    go_error: ?bool = null,
    /// Set when the shim supplies this argument. An injected parameter is
    /// absent from the C and Go signatures, so adding or removing one is a
    /// breaking change even though nothing about the Zig type moved.
    injected: ?Injection = null,
    name: []const u8,
    name_source: NameSource = .fallback,
    retention: Retention = .borrowed,
    semantic: ?SemanticHint = null,
    /// Where the parameter's name token sits in the source `names.zig`
    /// scanned it from. A diagnostic without this falls back to
    /// `semantic.json` for its location, just like a function without
    /// `SemanticFn.source`.
    source: ?ParamSourceLocation = null,
    type: TypeNode,
    written: ?Written = null,

    /// The staging buffer a stream parameter was declared with, or the
    /// default when it kept it.
    pub fn bufferSize(self: Parameter) u32 {
        return self.buffer orelse default_stream_buffer;
    }

    /// Whether the Go callback behind this parameter may return an `error`.
    /// Parameters that never asked never carry the field.
    pub fn goError(self: Parameter) bool {
        return self.go_error orelse false;
    }

    /// The written hint a parameter was declared with. Parameters that keep
    /// the default never carry the field.
    pub fn writtenHint(self: Parameter) Written {
        return self.written orelse .all;
    }
};

/// Which half of a boxed constructor pair a function is. A Zig `init` that
/// returns its value has no C representation, so the shim allocates storage
/// with the binding's allocator and hands Go a pointer; the paired `deinit`
/// frees that storage after running the Zig destructor.
pub const Boxed = enum { create, destroy };

/// The staging buffer a stream parameter gets without asking. 64 KiB is large
/// enough that a Go `Write` costs one boundary crossing per 64 KiB of payload
/// and small enough to sit on the shim's stack.
pub const default_stream_buffer: u32 = 65536;
/// Below this a buffer stops amortizing the boundary crossing; above it the
/// staging array stops being a plausible object at all.
pub const min_stream_buffer: u32 = 4096;
pub const max_stream_buffer: u32 = 16 * 1024 * 1024;
/// Above this the staging buffer is heap allocated rather than declared as a
/// stack array, because a shim frame that large is a stack overflow waiting
/// for a deep call.
pub const stream_heap_threshold: u32 = 256 * 1024;

/// Where a function's name token sits in the source `names.zig` scanned it
/// from. Set at most once per function, the same way `doc` is: the first
/// source file that resolves the declaration wins. A diagnostic sourced from
/// a `SemanticFn` without this field still renders against `semantic.json`,
/// exactly as it did before this field existed.
pub const SourceLocation = struct {
    path: []const u8,
    line: u32,
    column: u32,
};

/// One operation of a stream a Zig method hands out. A `fn writer(self)
/// *std.Io.Writer` has no C representation of its own -- the pointer belongs
/// to the object and outliving it is undefined -- so it is expanded into the
/// operations Go needs to satisfy `io.Writer`/`io.Reader`, each of which asks
/// the object for the stream again rather than storing what it got.
pub const StreamAccessor = struct {
    /// The Zig method that hands the stream over, called afresh every time.
    accessor: []const u8,
    direction: StreamDirection,
    op: Op,

    pub const Op = enum { write, flush, read };
};

pub const SemanticFn = struct {
    /// Set on the two halves of a boxed constructor pair.
    boxed: ?Boxed = null,
    /// Set only when function metadata explicitly says `.returns = .borrowed`.
    /// `ownership` defaults to borrowed for historical documents, so this
    /// separate bit distinguishes a deliberate borrowed-handle contract from
    /// metadata that made no lifetime choice.
    borrowed_return: ?bool = null,
    /// Set only when a receiver constructor returns a handle whose lifetime
    /// must end before the receiver's. Omitted when false so old semantic
    /// documents remain byte-identical.
    child_of_receiver: ?bool = null,
    /// The parameter `.cancel = .{ .param = "..." }` named, verbatim. Kept on
    /// the function so a name that matches nothing can still be reported, and
    /// so `abi-diff` sees the Go signature gain or lose its `ctx`.
    cancel: ?[]const u8 = null,
    /// Set on a function synthesized from a stream-returning method. Never
    /// present in a `semantic.json` on disk: the document records the Zig
    /// method, and the expansion happens between parsing and lowering.
    stream_accessor: ?StreamAccessor = null,
    doc: ?[]const u8 = null,
    has_comptime_params: ?bool = null,
    /// The type a paired constructor is grouped under in Go, when that is not
    /// where the function is declared. `namespace` stays the Zig container the
    /// shim calls through, so a root-level `newTerminal` can be `Terminal`'s
    /// constructor in Go and still be called as `target.newTerminal(...)`.
    go_owner: ?[]const u8 = null,
    name: []const u8,
    /// Public sub-package name. Absent means the binding's default package.
    package: ?[]const u8 = null,
    /// The Zig container the function is declared in, and the owner its C
    /// symbol is built from. Go grouping goes through `goOwner`.
    namespace: ?[]const u8 = null,
    ownership: Ownership = .borrowed,
    params: []const Parameter,
    receiver: ?[]const u8 = null,
    /// How many entries of `params` Zig declared ahead of the receiver. Only
    /// injected arguments can precede it, so this is absent (zero) unless an
    /// allocator or io comes before the handle, as in
    /// `fn free(gpa: Allocator, self: *T) void`. The shim passes `self` at
    /// this position; C and Go never see the difference.
    receiver_at: ?usize = null,
    /// Name of the function that frees a `.returns = .caller` slice result.
    /// Generated Go copies the payload and then calls this symbol, so the
    /// public API never hands native memory to the caller.
    release: ?[]const u8 = null,
    @"return": TypeNode,
    return_semantic: ?SemanticHint = null,
    /// The function declaration's source location, from `names.zig`. Purely
    /// diagnostic: it has no bearing on the generated ABI, so `abi_diff`
    /// ignores it.
    source: ?SourceLocation = null,
    /// The Zig declaration the shim calls, relative to the bound module, when
    /// it is not `<receiver or namespace>.<name>`: a function declared beside
    /// a type rather than inside it, or one `.name` renamed for Go. Absent
    /// whenever the owner and the name already spell the declaration.
    zig_path: ?[]const u8 = null,
    symbol: []const u8,

    /// The type Go groups this function under: the one a binding paired it
    /// with, or the container it was declared in.
    pub fn goOwner(self: SemanticFn) ?[]const u8 {
        return self.go_owner orelse self.namespace;
    }

    pub fn childOfReceiver(self: SemanticFn) bool {
        return self.child_of_receiver orelse false;
    }

    pub fn returnsBorrowedHandle(self: SemanticFn) bool {
        return self.borrowed_return orelse false;
    }
};

pub const TypeKind = enum { callback, @"enum", error_set, @"opaque", tagged_union, value_struct };
pub const Layout = enum { @"extern", @"packed" };
/// How Go reaches a type's contents. This is a separate axis from the type's
/// kind: a tagged union is a tagged union either way, and adding a strategy
/// adds one value here rather than multiplying the kind names.
pub const Access = enum {
    /// Per-variant FFI accessors that check the tag on every read.
    projection,
    /// A zigo-owned snapshot struct carrying the tag and every scalar payload
    /// back in one call, alongside the projections.
    snapshot,
};
pub const TypeField = struct {
    name: []const u8,
    type: ?TypeNode = null,
    value: ?i64 = null,
};
pub const TypeDecl = struct {
    access: ?Access = null,
    exhaustive: bool = true,
    fields: []const TypeField = &.{},
    kind: TypeKind,
    layout: ?Layout = null,
    name: []const u8,
    /// Public sub-package name. Absent means the binding's default package.
    package: ?[]const u8 = null,
    /// Present only when the binding explicitly opts a non-exhaustive Zig
    /// enum into the public surface with `.exhaustive = false`.
    open: ?bool = null,
    tag_type: ?TypeNode = null,
    zig_path: ?[]const u8 = null,

    /// The access strategy a type was registered with. Types that only have
    /// one never carry the field.
    pub fn accessStrategy(self: TypeDecl) Access {
        return self.access orelse .projection;
    }
};
pub const Constructor = struct {
    deinit: []const u8,
    init: []const u8,
    type: []const u8,
};

pub const Package = struct {
    doc: ?[]const u8 = null,
    name: []const u8,
    path: []const u8,
};

pub const Semantic = struct {
    /// The Zig expression the shim passes for `std.mem.Allocator` parameters.
    /// Set by the binding's `.allocator`; without it, a function that takes an
    /// allocator is refused rather than guessed at.
    allocator: ?[]const u8 = null,
    constructors: []const Constructor = &.{},
    /// The `//!` container doc of the bindings file, if it has one. It becomes
    /// the generated Go package doc unless `go_package_doc` overrides it.
    doc: ?[]const u8 = null,
    functions: []const SemanticFn = &.{},
    /// The Zig expression the shim passes for `std.Io` parameters, from the
    /// binding's `.io`.
    io: ?[]const u8 = null,
    ir_version: u32 = 1,
    package: []const u8,
    /// Declared public sub-packages. Empty is omitted so legacy documents are unchanged.
    packages: ?[]const Package = null,
    prefix: []const u8,
    types: []const TypeDecl = &.{},
    zig_version: []const u8,

    pub fn serialize(self: Semantic, allocator: std.mem.Allocator) ![]u8 {
        const body = try std.json.Stringify.valueAlloc(allocator, self, .{
            .emit_null_optional_fields = false,
            .whitespace = .indent_2,
        });
        defer allocator.free(body);
        return std.fmt.allocPrint(allocator, "{s}\n", .{body});
    }

    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(Semantic) {
        var dynamic = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
        defer dynamic.deinit();
        return std.json.parseFromValue(Semantic, allocator, dynamic.value, .{});
    }
};

test "stream parameters round-trip through the semantic document" {
    const document: Semantic = .{
        .functions = &.{.{
            .name = "dump",
            .params = &.{
                .{ .name = "w", .type = .{ .io_stream = .{ .direction = .writer } } },
                .{ .buffer = 8192, .name = "r", .type = .{ .io_stream = .{ .direction = .reader } } },
            },
            .@"return" = .{ .void = {} },
            .symbol = "zg_dump",
        }},
        .package = "stream",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const bytes = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\": \"io_writer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\": \"io_reader\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"buffer\": 8192") != null);

    var parsed = try Semantic.parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    const params = parsed.value.functions[0].params;
    try std.testing.expectEqual(StreamDirection.writer, params[0].type.io_stream.direction);
    try std.testing.expectEqual(@as(?u32, null), params[0].buffer);
    try std.testing.expectEqual(StreamDirection.reader, params[1].type.io_stream.direction);
    try std.testing.expectEqual(@as(u32, 8192), params[1].buffer.?);
}

test "child-of-receiver metadata is emitted only when enabled" {
    const base: SemanticFn = .{
        .name = "newChild",
        .params = &.{},
        .receiver = "Parent",
        .@"return" = .{ .void = {} },
        .symbol = "zg_parent_new_child",
    };
    var dependent = base;
    dependent.child_of_receiver = true;
    const document: Semantic = .{
        .functions = &.{ base, dependent },
        .package = "handles",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const bytes = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "\"child_of_receiver\": true"));
}

test "package metadata is omitted by default and round trips when present" {
    const legacy: Semantic = .{ .package = "sample", .prefix = "zg", .zig_version = "0.16.0" };
    const legacy_bytes = try legacy.serialize(std.testing.allocator);
    defer std.testing.allocator.free(legacy_bytes);
    try std.testing.expect(std.mem.indexOf(u8, legacy_bytes, "\"packages\"") == null);

    const split: Semantic = .{
        .functions = &.{.{ .name = "width", .package = "text", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_width" }},
        .package = "sample",
        .packages = &.{.{ .doc = "Package text handles Unicode.", .name = "text", .path = "text" }},
        .prefix = "zg",
        .types = &.{.{ .kind = .@"enum", .name = "Mode", .package = "text" }},
        .zig_version = "0.16.0",
    };
    const bytes = try split.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var parsed = try Semantic.parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("text", parsed.value.packages.?[0].name);
    try std.testing.expectEqualStrings("text", parsed.value.types[0].package.?);
    try std.testing.expectEqualStrings("text", parsed.value.functions[0].package.?);
}
