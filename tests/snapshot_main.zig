const std = @import("std");
const snapshot = @import("snapshot.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 3 or args.len > 4 or (args.len == 4 and !std.mem.eql(u8, args[3], "--update-snapshots"))) {
        std.debug.print("usage: zigo-snapshot <golden-dir> <actual-dir> [--update-snapshots]\n", .{});
        std.process.exit(2);
    }
    const cwd = std.Io.Dir.cwd();
    var expected = try cwd.openDir(init.io, args[1], .{ .iterate = true });
    defer expected.close(init.io);
    var actual = try cwd.openDir(init.io, args[2], .{ .iterate = true });
    defer actual.close(init.io);
    if (args.len == 4) {
        try snapshot.updateGolden(allocator, init.io, expected, actual);
        return;
    }
    var result = try snapshot.compare(allocator, init.io, expected, actual);
    defer result.deinit(allocator);
    if (!result.matches()) {
        result.render();
        std.process.exit(1);
    }
}
