//! Shared ABI type spellings and scalar conversions. No concrete emitter dependencies.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const target_types = @import("target_types.zig");

pub fn rawGoTypeName(program: abi.Program, node: semantic.TypeNode) []const u8 {
    const scalar = semanticScalar(program, node);
    return switch (scalar) {
        .usize => "uint",
        .isize => "int",
        .bool_u8 => "uint8",
        .signed_int => |bits| switch (bits) {
            8 => "int8",
            16 => "int16",
            32 => "int32",
            64 => "int64",
            else => unreachable,
        },
        .unsigned_int => |bits| switch (bits) {
            8 => "uint8",
            16 => "uint16",
            32 => "uint32",
            64 => "uint64",
            else => unreachable,
        },
        .float => |bits| switch (bits) {
            32 => "float32",
            64 => "float64",
            else => unreachable,
        },
        else => unreachable,
    };
}

pub fn goZero(node: semantic.TypeNode) []const u8 {
    return switch (node) {
        .bool => "false",
        .slice, .opaque_ptr => "nil",
        .materialized => |value| if (value.pointer) "nil" else "0",
        else => "0",
    };
}

pub fn rawGoZero(node: semantic.TypeNode) []const u8 {
    return switch (node) {
        .slice, .opaque_ptr => "nil",
        else => "0",
    };
}

pub fn semanticScalar(program: abi.Program, node: semantic.TypeNode) abi.AbiScalar {
    return switch (node) {
        .void => .void,
        .bool => .bool_u8,
        // The promoted width, matching what lowering put in the ABI, so a
        // narrow integer spells the same C, Zig, and Go type everywhere.
        .int => |value| if (value.is_usize)
            (if (value.signed) .isize else .usize)
        else if (value.signed)
            .{ .signed_int = abi.promotedIntBits(value.bits) }
        else
            .{ .unsigned_int = abi.promotedIntBits(value.bits) },
        .float => |value| .{ .float = value.bits },
        .@"enum" => |value| semanticScalar(program, enumDecl(program, value.ref).tag_type.?),
        .value_struct => if (isPackedValue(program, node))
            semanticScalar(program, enumDecl(program, node.value_struct.ref).backing_type.?)
        else
            unreachable,
        .opaque_ptr => |value| .{ .@"opaque" = handleRecord(program, value.ref) },
        else => unreachable,
    };
}

/// The lowered handle for a semantic type name. Lowering records one for every
/// `opaque` and tagged union, so a missing entry is a malformed program.
pub fn handleRecord(program: abi.Program, name: []const u8) abi.AbiOpaque {
    for (program.handles) |handle| if (std.mem.eql(u8, handle.name, name)) return handle;
    unreachable;
}

/// The lowered enum for a semantic type name, on the same terms as
/// `handleRecord`.
pub fn enumRecord(program: abi.Program, name: []const u8) abi.AbiEnum {
    for (program.enums) |record| if (std.mem.eql(u8, record.name, name)) return record;
    unreachable;
}

pub fn enumDecl(program: abi.Program, name: []const u8) semantic.TypeDecl {
    return semantic.typeDecl(program.types, name) orelse unreachable;
}

pub fn isPackedValue(program: abi.Program, node: semantic.TypeNode) bool {
    return semantic.isPackedValue(program.types, node);
}

pub fn writePackedZigToBackingPrefix(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode) !void {
    const backing = enumDecl(program, node.value_struct.ref).backing_type.?.int;
    try writer.print("@intCast(@as({c}{d}, @bitCast(", .{
        if (backing.signed) @as(u8, 'i') else @as(u8, 'u'),
        backing.bits,
    });
}

pub fn writePackedZigFromBacking(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode, expression: []const u8) !void {
    const backing = enumDecl(program, node.value_struct.ref).backing_type.?.int;
    try writer.print("@bitCast(@as({c}{d}, @truncate({s})))", .{
        if (backing.signed) @as(u8, 'i') else @as(u8, 'u'),
        backing.bits,
        expression,
    });
}

pub fn writeZigType(writer: *std.Io.Writer, program: abi.Program, value: abi.AbiScalar) !void {
    switch (value) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("u8"),
        .usize => try writer.writeAll("usize"),
        .isize => try writer.writeAll("isize"),
        .signed_int => |bits| try writer.print("i{d}", .{bits}),
        .unsigned_int => |bits| try writer.print("u{d}", .{bits}),
        .float => |bits| try writer.print("f{d}", .{bits}),
        .@"opaque" => |handle| try target_types.writeTargetType(writer, program, handle.name),
        .snapshot => |name| try writer.writeAll(name),
        .value_struct => |record| try target_types.writeTargetType(writer, program, record.name),
        .pointer => |pointer| {
            // A `[*c]` pointer is already nullable and has no `?` spelling:
            // `?[*c]T` is rejected outright in a `callconv(.c)` signature.
            // Only `*T` and `[*:0]T` need the marker written out.
            if (pointer.is_optional and (!pointer.is_many or pointer.is_c_string)) try writer.writeByte('?');
            try writer.writeAll(if (pointer.is_c_string) "[*:0]" else if (pointer.is_many) "[*c]" else "*");
            if (pointer.is_const) try writer.writeAll("const ");
            try writeZigType(writer, program, pointer.child.*);
        },
        .callback => |callback| {
            try writer.writeAll("*const fn (");
            for (callback.params, 0..) |parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writeZigType(writer, program, parameter);
            }
            try writer.writeAll(") callconv(.c) ");
            try writeZigType(writer, program, callback.ret.*);
        },
    }
}

pub fn writeCType(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("uint8_t"),
        .usize => try writer.writeAll("size_t"),
        .isize => try writer.writeAll("ptrdiff_t"),
        .signed_int => |bits| try writer.print("int{d}_t", .{bits}),
        .unsigned_int => |bits| try writer.print("uint{d}_t", .{bits}),
        .float => |bits| try writer.writeAll(if (bits == 32) "float" else "double"),
        // The handle's own typedef, so a C consumer cannot hand one type's
        // handle to another's function. The projections already spell it.
        .@"opaque" => |handle| try writer.writeAll(handle.c_name),
        .snapshot => |name| try writer.writeAll(name),
        .value_struct => |record| try writer.writeAll(record.c_name),
        .pointer => |pointer| {
            if (pointer.is_c_string) return writer.writeAll("const char *");
            if (pointer.is_const) try writer.writeAll("const ");
            try writeCType(writer, pointer.child.*);
            try writer.writeAll(" *");
        },
        .callback => unreachable,
    }
}

pub fn writeCParam(writer: *std.Io.Writer, value: abi.AbiScalar, name: []const u8) !void {
    if (value != .callback) {
        try writeCType(writer, value);
        try writer.print(" {s}", .{name});
        return;
    }
    const callback = value.callback;
    try writeCType(writer, callback.ret.*);
    try writer.print(" (*{s})(", .{name});
    if (callback.params.len == 0) try writer.writeAll("void");
    for (callback.params, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        try writeCType(writer, parameter);
    }
    try writer.writeByte(')');
}

pub fn writeCgoType(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("uint8_t"),
        .usize => try writer.writeAll("size_t"),
        .isize => try writer.writeAll("ptrdiff_t"),
        .signed_int => |bits| try writer.print("int{d}_t", .{bits}),
        .unsigned_int => |bits| try writer.print("uint{d}_t", .{bits}),
        .float => |bits| try writer.writeAll(if (bits == 32) "float" else "double"),
        .@"opaque" => try writer.writeAll("void"),
        .snapshot => |name| try writer.writeAll(name),
        .value_struct => |record| try writer.writeAll(record.c_name),
        .pointer => unreachable,
        .callback => unreachable,
    }
}

pub fn writeGoScalar(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .bool_u8 => try writer.writeAll("uint8"),
        .usize => try writer.writeAll("uint"),
        .isize => try writer.writeAll("int"),
        .signed_int => |bits| try writeIntegerName(writer, true, bits, false),
        .unsigned_int => |bits| try writeIntegerName(writer, false, bits, false),
        .float => |bits| try writer.print("float{d}", .{bits}),
        .@"opaque", .pointer => try writer.writeAll("unsafe.Pointer"),
        .callback => try writer.writeAll("uintptr"),
        else => unreachable,
    }
}

pub fn writeIntegerName(writer: *std.Io.Writer, signed: bool, bits: u16, c_name: bool) !void {
    _ = c_name;
    try writer.print("{s}{d}", .{ if (signed) "int" else "uint", bits });
}

pub fn writeAtomicGoName(writer: *std.Io.Writer, node: semantic.TypeNode) !void {
    const integer = node.int;
    try writer.print("{s}{d}", .{ if (integer.signed) "Int" else "Uint", integer.bits });
}
