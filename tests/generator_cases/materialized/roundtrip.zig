const std = @import("std");
const shim = @import("expected/shim.zig");
const target = @import("zigo_target");

test "generated materialized walker round trips its buffer layout" {
    var builder = try shim.ZigoMaterializedBuilder.init(std.testing.allocator);
    const root_offset = try shim.zigoMaterialize_root(&builder, target.snapshot());
    const buffer = try builder.finish(0, 1, @intCast(root_offset));
    defer std.testing.allocator.free(buffer);

    try std.testing.expectEqual(@as(u64, 0x0001_4f47495a), read(buffer, 0));
    try std.testing.expectEqual(@as(u64, 1), read(buffer, 16));
    try std.testing.expectEqual(@as(u64, buffer.len), read(buffer, 32));
    const root: usize = @intCast(read(buffer, 24));
    try std.testing.expectEqual(@as(u64, 1), read(buffer, root));
    const name_offset: usize = @intCast(read(buffer, root + 16));
    const name_length: usize = @intCast(read(buffer, root + 24));
    try std.testing.expectEqualStrings("root", buffer[name_offset..][0..name_length]);
    const child: usize = @intCast(read(buffer, root + 32));
    try std.testing.expectEqual(@as(u64, 1), read(buffer, child));
    try std.testing.expectEqual(@as(u64, 0), read(buffer, root + 48));
}

fn read(buffer: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, buffer[offset..][0..8], .little);
}
