const std = @import("std");
const abi_diff = @import("abi_diff");
const generator = @import("gen/generator.zig");
const semantic = @import("semantic");
const sync_check = @import("sync_check");
const validate = @import("gen/validate.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "--check")) return runCheck(allocator, init.io, args);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "--abi-diff")) return runAbiDiff(allocator, init.io, args);
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

fn runCheck(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len != 4) return error.InvalidArguments;
    const cwd = std.Io.Dir.cwd();
    var generated = try cwd.openDir(io, args[2], .{ .iterate = true });
    defer generated.close(io);
    var source = try cwd.openDir(io, args[3], .{ .iterate = true });
    defer source.close(io);
    var result = try sync_check.compare(allocator, io, generated, source);
    defer result.deinit(allocator);
    if (result.matches()) return;
    var buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.Writer.init(.stderr(), io, &buffer);
    try result.render(&stderr.interface);
    try stderr.interface.flush();
    std.process.exit(1);
}

fn runAbiDiff(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len < 4) return error.InvalidArguments;
    var json = false;
    var fail_breaking = false;
    var index: usize = 4;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--json")) {
            json = true;
        } else if (std.mem.eql(u8, args[index], "--fail-on") and index + 1 < args.len and std.mem.eql(u8, args[index + 1], "breaking")) {
            fail_breaking = true;
            index += 1;
        } else return error.InvalidArguments;
    }
    const cwd = std.Io.Dir.cwd();
    const base_bytes = try cwd.readFileAlloc(io, args[2], allocator, .limited(64 * 1024 * 1024));
    const current_bytes = try cwd.readFileAlloc(io, args[3], allocator, .limited(64 * 1024 * 1024));
    var base = try semantic.Semantic.parse(allocator, base_bytes);
    defer base.deinit();
    var current = try semantic.Semantic.parse(allocator, current_bytes);
    defer current.deinit();
    var report = try abi_diff.diff(allocator, base.value, current.value);
    defer report.deinit(allocator);
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), io, &buffer);
    if (json) try report.renderJson(allocator, &stdout.interface) else try report.renderText(&stdout.interface);
    try stdout.interface.flush();
    if (fail_breaking and report.hasBreaking()) std.process.exit(1);
}
