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
};
pub const Optional = struct { child: *TypeNode };
pub const ErrorUnion = struct {
    anyerror: bool = false,
    error_set: []const []const u8,
    payload: *TypeNode,
};
pub const Callback = struct {
    has_userdata: bool,
    params: []const TypeNode,
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
                try jw.objectField("has_userdata");
                try jw.write(value.has_userdata);
                try writeKind(jw, "callback");
                try jw.objectField("params");
                try jw.write(value.params);
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
            .has_userdata = try parseField(bool, allocator, object, "has_userdata", options),
            .params = try parseField([]const TypeNode, allocator, object, "params", options),
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

pub const Parameter = struct {
    direction: Direction = .in,
    name: []const u8,
    name_source: NameSource = .fallback,
    retention: Retention = .borrowed,
    semantic: ?SemanticHint = null,
    type: TypeNode,
};

pub const SemanticFn = struct {
    doc: ?[]const u8 = null,
    name: []const u8,
    ownership: Ownership = .borrowed,
    params: []const Parameter,
    receiver: ?[]const u8 = null,
    @"return": TypeNode,
    symbol: []const u8,
};

pub const TypeKind = enum { @"enum", error_set, @"opaque", value_struct };
pub const Layout = enum { @"extern", @"packed" };
pub const TypeField = struct {
    name: []const u8,
    type: ?TypeNode = null,
    value: ?i64 = null,
};
pub const TypeDecl = struct {
    exhaustive: bool = true,
    fields: []const TypeField = &.{},
    kind: TypeKind,
    layout: ?Layout = null,
    name: []const u8,
    tag_type: ?TypeNode = null,
    zig_path: ?[]const u8 = null,
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
