const std = @import("std");

/// Phase 0 provides a successful generator process boundary before the IR pipeline exists.
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len >= 2 and std.mem.eql(u8, args[1], "--semantic-stub")) {
        var buffer: [64]u8 = undefined;
        var stdout = std.Io.File.Writer.init(.stdout(), init.io, &buffer);
        try stdout.interface.writeAll("{}\n");
        try stdout.interface.flush();
    }
}
