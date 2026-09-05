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
        const fields = try allocator.alloc(abi.MaterializedLayout.Field, declaration.fields.len);
        for (declaration.fields, 0..) |field, index| {
            const node = field.type.?;
            fields[index] = .{
                .name = field.name,
                .offset = index * abi.MaterializedLayout.slot_size,
                .node = node,
                .kind = materializedFieldKind(node),
            };
        }
        try layouts.append(allocator, .{
            .owner = declaration,
            .id = @intCast(layouts.items.len),
            .record_size = fields.len * abi.MaterializedLayout.slot_size,
            .fields = fields,
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

fn materializedFieldKind(node: semantic.TypeNode) abi.MaterializedLayout.Field.Kind {
    return switch (node) {
        .bool, .int, .float, .@"enum" => .scalar,
        .materialized => |value| if (value.pointer) .node_pointer else .node,
        .slice => |value| switch (value.element.*) {
            .materialized => .node_slice,
            .slice => .string_slice,
            .int => |integer| if (integer.bits == 8 and !integer.signed) .string else .scalar_slice,
            else => .scalar_slice,
        },
        else => unreachable,
    };
}
