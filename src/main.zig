const std = @import("std");
const generator = @import("gen/generator.zig");
const semantic = @import("semantic");
const validate = @import("gen/validate.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 5 or args.len > 9) return error.InvalidArguments;
    const semantic_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], allocator, .limited(64 * 1024 * 1024));
    var parsed = try semantic.Semantic.parse(allocator, semantic_bytes);
    defer parsed.deinit();
    if (validate.findIssue(parsed.value)) |issue| issue.emitAndExit(allocator);
    try std.Io.Dir.cwd().createDirPath(init.io, args[2]);
    var output = try std.Io.Dir.cwd().openDir(init.io, args[2], .{ .iterate = true });
    defer output.close(init.io);
    try generator.generate(allocator, init.io, semantic_bytes, output, .{
        .package = args[3],
        .prefix = args[4],
        .go_module = if (args.len >= 6) args[5] else args[3],
        .include_dir = if (args.len >= 7) args[6] else "${SRCDIR}/../../../zig-out/include",
        .library_dir = if (args.len >= 8) args[7] else "${SRCDIR}/../../../zig-out/lib",
        .errors_lock_bytes = if (args.len >= 9) try std.Io.Dir.cwd().readFileAlloc(init.io, args[8], allocator, .limited(16 * 1024 * 1024)) else null,
    });
}
