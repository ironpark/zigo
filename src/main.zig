const std = @import("std");
const generator = @import("gen/generator.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 5 or args.len > 8) return error.InvalidArguments;
    const semantic_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], allocator, .limited(64 * 1024 * 1024));
    try std.Io.Dir.cwd().createDirPath(init.io, args[2]);
    var output = try std.Io.Dir.cwd().openDir(init.io, args[2], .{ .iterate = true });
    defer output.close(init.io);
    try generator.generate(allocator, init.io, semantic_bytes, output, .{
        .package = args[3],
        .prefix = args[4],
        .go_module = if (args.len >= 6) args[5] else args[3],
        .include_dir = if (args.len >= 7) args[6] else "${SRCDIR}/../../../zig-out/include",
        .library_dir = if (args.len >= 8) args[7] else "${SRCDIR}/../../../zig-out/lib",
    });
}
