const std = @import("std");
const shim = @import("expected/shim.zig");
const target = @import("zigo_target");

test "generated materialized walker round trips its buffer layout" {
    var builder = try shim.ZigoMaterializedBuilder.init(std.testing.allocator);
    const root_offset = try shim.zigoMaterialize_root(&builder, target.snapshot());
    const buffer = try builder.finish(0, 1, @intCast(root_offset));
    defer std.testing.allocator.free(buffer);

    try std.testing.expectEqual(@as(u64, 0x0002_4f47495a), read(buffer, 0));
    try std.testing.expectEqual(@as(u64, 1), read(buffer, 16));
    try std.testing.expectEqual(@as(u64, buffer.len), read(buffer, 32));
    const root: usize = @intCast(read(buffer, 24));
    try std.testing.expectEqual(@as(u64, 1), read(buffer, root));
    const name_offset: usize = @intCast(read(buffer, root + 8));
    const name_length: usize = @intCast(read(buffer, root + 16));
    try std.testing.expectEqualStrings("root", buffer[name_offset..][0..name_length]);
    const child: usize = @intCast(read(buffer, root + 24));
    // Leaf: ok is one byte, then the two sequences at their 8-byte alignment.
    try std.testing.expectEqual(@as(u8, 1), buffer[child]);
    try std.testing.expectEqual(@as(u64, 2), read(buffer, child + 16));
    const values: usize = @intCast(read(buffer, child + 8));
    try std.testing.expectEqual(@as(i32, -5), std.mem.readInt(i32, buffer[values + 4 ..][0..4], .little));
    try std.testing.expectEqual(@as(u64, 0), read(buffer, root + 32));
    // Optional scalar: presence byte, value at the child's alignment; optional
    // string: offset 0.
    try std.testing.expectEqual(@as(u8, 1), buffer[root + 56]);
    try std.testing.expectEqual(@as(u32, 7), std.mem.readInt(u32, buffer[root + 60 ..][0..4], .little));
    try std.testing.expectEqual(@as(u64, 0), read(buffer, root + 64));

    var present = target.snapshot();
    present.limit = null;
    present.label = "";
    var second = try shim.ZigoMaterializedBuilder.init(std.testing.allocator);
    const present_offset: usize = @intCast(try shim.zigoMaterialize_root(&second, present));
    const present_buffer = try second.finish(0, 1, present_offset);
    defer std.testing.allocator.free(present_buffer);
    try std.testing.expectEqual(@as(u8, 0), present_buffer[present_offset + 56]);
    // An empty present string still points past the header, so it stays
    // distinguishable from an absent one.
    try std.testing.expect(read(present_buffer, present_offset + 64) != 0);
    try std.testing.expectEqual(@as(u64, 0), read(present_buffer, present_offset + 72));
}

fn read(buffer: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, buffer[offset..][0..8], .little);
}

fn serializeWithFailures(allocator: std.mem.Allocator, is_slice: bool) !void {
    const value = target.snapshot();
    const buffer = if (is_slice)
        try shim.zigoMaterialize_rootBuffer(allocator, &[_]target.Root{value} ** 32, true)
    else
        try shim.zigoMaterialize_rootBuffer(allocator, value, false);
    defer allocator.free(buffer);
    try std.testing.expectEqual(@as(u64, buffer.len), read(buffer, 32));
}

test "materialized serialization frees every partial allocation on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, serializeWithFailures, .{false});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, serializeWithFailures, .{true});
}
