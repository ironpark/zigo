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
    @"enum": Ref,
    error_union: ErrorUnion,
    float: Float,
    int: Int,
    opaque_ptr: OpaquePtr,
    optional: Optional,
    slice: Slice,
    value_struct: Ref,
    void: void,

    pub fn jsonStringify(self: TypeNode, jw: anytype) !void {
        try jw.beginObject();
        switch (self) {
            .bool => try writeKind(jw, "bool"),
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
pub const Direction = enum { in, inout, out };
pub const Retention = enum { borrowed, retained };
pub const SemanticHint = enum { c_string, opaque_bytes, utf8_string };
pub const Ownership = enum { borrowed, caller, library };
/// How much of an `.out` slice the shim reports back as written. `.all` keeps
/// the whole buffer, `.return` trusts the function's `usize` result.
pub const Written = enum { all, @"return" };

pub const Parameter = struct {
    direction: Direction = .in,
    name: []const u8,
    name_source: NameSource = .fallback,
    retention: Retention = .borrowed,
    semantic: ?SemanticHint = null,
    type: TypeNode,
    written: ?Written = null,

    /// The written hint a parameter was declared with. Parameters that keep
    /// the default never carry the field.
    pub fn writtenHint(self: Parameter) Written {
        return self.written orelse .all;
    }
};

pub const SemanticFn = struct {
    doc: ?[]const u8 = null,
    has_comptime_params: ?bool = null,
    name: []const u8,
    namespace: ?[]const u8 = null,
    ownership: Ownership = .borrowed,
    params: []const Parameter,
    receiver: ?[]const u8 = null,
    /// Name of the function that frees a `.returns = .caller` slice result.
    /// Generated Go copies the payload and then calls this symbol, so the
    /// public API never hands native memory to the caller.
    release: ?[]const u8 = null,
    @"return": TypeNode,
    return_semantic: ?SemanticHint = null,
    symbol: []const u8,
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

pub const Semantic = struct {
    constructors: []const Constructor = &.{},
    functions: []const SemanticFn = &.{},
    ir_version: u32 = 1,
    package: []const u8,
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
