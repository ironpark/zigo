//! Materialized layout decisions and ABI output slots, independent of emitters.
//! Layouts borrow semantic declarations and use the lowering arena's lifetime.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");

pub fn appendMaterializedReturnOuts(allocator: std.mem.Allocator, params: *std.ArrayList(abi.AbiParam)) !void {
    const byte = try allocator.create(abi.AbiScalar);
    byte.* = .{ .unsigned_int = 8 };
    const many = try allocator.create(abi.AbiScalar);
    many.* = .{ .pointer = .{ .child = byte, .is_const = false, .is_many = true } };
    try params.append(allocator, .{
        .name = "out_result_ptr",
        .role = .return_slice_pointer,
        .scalar = .{ .pointer = .{ .child = many, .is_const = false } },
    });
    const length = try allocator.create(abi.AbiScalar);
    length.* = .usize;
    try params.append(allocator, .{
        .name = "out_result_len",
        .role = .return_slice_length,
        .scalar = .{ .pointer = .{ .child = length, .is_const = false } },
    });
}

pub fn lowerMaterializedLayouts(allocator: std.mem.Allocator, document: semantic.Semantic) ![]const abi.MaterializedLayout {
    var layouts: std.ArrayList(abi.MaterializedLayout) = .empty;
    for (document.types) |*declaration| {
        if (declaration.kind != .materialized) continue;
        const record = try layoutRecord(allocator, document, declaration.fields);
        try layouts.append(allocator, .{
            .owner = declaration,
            .id = @intCast(layouts.items.len),
            .record_size = record.size,
            .fields = record.fields,
        });
    }
    return layouts.toOwnedSlice(allocator);
}

/// Validation has already required every materialized reference to name a
/// registered layout, so the lookup cannot miss.
pub fn materializedLayoutIndex(layouts: []const abi.MaterializedLayout, root: []const u8) usize {
    for (layouts, 0..) |layout, index| if (std.mem.eql(u8, layout.owner.name, root)) return index;
    unreachable;
}

const LaidOutRecord = struct { fields: []const abi.MaterializedLayout.Field, size: usize, alignment: usize };

/// Fields in declaration order, each at its natural alignment; the record
/// itself is padded to 8 so consecutive records and arrays stay aligned.
fn layoutRecord(allocator: std.mem.Allocator, document: semantic.Semantic, members: []const semantic.TypeField) std.mem.Allocator.Error!LaidOutRecord {
    const fields = try allocator.alloc(abi.MaterializedLayout.Field, members.len);
    var cursor: usize = 0;
    var alignment: usize = 1;
    for (members, fields) |member, *field| {
        const node = member.type.?;
        const shape = try shapeOf(allocator, document, node, member.semantic);
        const offset = abi.MaterializedLayout.alignUp(cursor, shape.alignment());
        field.* = .{ .name = member.name, .offset = offset, .node = node, .shape = shape };
        cursor = offset + shape.size();
        alignment = @max(alignment, shape.alignment());
    }
    return .{ .fields = fields, .size = abi.MaterializedLayout.alignUp(cursor, 8), .alignment = @max(alignment, 1) };
}

fn shapeOf(allocator: std.mem.Allocator, document: semantic.Semantic, node: semantic.TypeNode, hint: ?semantic.SemanticHint) std.mem.Allocator.Error!abi.MaterializedLayout.Shape {
    return switch (node) {
        .bool => .{ .scalar = .{ .width = 1 } },
        .int => |integer| .{ .scalar = .{ .width = if (integer.is_usize) 8 else byteWidth(integer.bits) } },
        .float => |float| .{ .scalar = .{ .width = byteWidth(float.bits) } },
        .@"enum" => |value| .{ .scalar = .{ .width = enumWidth(document, value.ref) } },
        .value_struct => |value| blk: {
            const declaration = semantic.typeDecl(document.types, value.ref).?;
            if (declaration.layout == .@"packed") break :blk .{ .scalar = .{ .width = byteWidth(declaration.backing_type.?.int.bits) } };
            const record = try layoutRecord(allocator, document, declaration.fields);
            break :blk .{ .value_struct = .{ .ref = value.ref, .fields = record.fields, .size = record.size, .alignment = record.alignment } };
        },
        .materialized => |value| .{ .node = .{ .ref = value.ref, .pointer = value.pointer, .nullable = value.nullable } },
        .optional => |value| switch (value.child.*) {
            .slice => .{ .string = .{ .bytes = hint == .opaque_bytes, .nullable = true } },
            .materialized => |inner| .{ .node = .{ .ref = inner.ref, .pointer = inner.pointer, .nullable = true } },
            else => blk: {
                const child = try allocator.create(abi.MaterializedLayout.Shape);
                child.* = try shapeOf(allocator, document, value.child.*, hint);
                break :blk .{ .optional = child };
            },
        },
        .slice => |value| blk: {
            if (semantic.isByte(value.element.*)) break :blk .{ .string = .{ .bytes = hint == .opaque_bytes } };
            const element = try allocator.create(abi.MaterializedLayout.Shape);
            element.* = try shapeOf(allocator, document, value.element.*, hint);
            break :blk .{ .sequence = element };
        },
        else => unreachable,
    };
}

/// Smallest power-of-two byte width that holds `bits`, capped at 8.
fn byteWidth(bits: u16) u8 {
    if (bits <= 8) return 1;
    if (bits <= 16) return 2;
    if (bits <= 32) return 4;
    return 8;
}

fn enumWidth(document: semantic.Semantic, name: []const u8) u8 {
    const declaration = semantic.typeDecl(document.types, name) orelse return 8;
    const tag = declaration.tag_type orelse return 8;
    return if (tag == .int) byteWidth(tag.int.bits) else 8;
}
