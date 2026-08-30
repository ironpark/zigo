const std = @import("std");
const generator = @import("generator");
const snapshot = @import("snapshot.zig");

const CaseOptions = struct {
    package: []const u8,
    prefix: []const u8,
    go_module: []const u8,
    cflags_override: ?[]const u8 = null,
    ldflags_override: ?[]const u8 = null,
    system_ldflags: []const u8 = "",
    framework_ldflags: []const u8 = "",
    include_dir: []const u8 = "${SRCDIR}/../../../zig-out/include",
    library_dir: []const u8 = "${SRCDIR}/../../../zig-out/lib",
    raw_package_path: []const u8 = "internal/raw",
    raw_package_name: []const u8 = "raw",
    raw_colocated: bool = false,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.InvalidArguments;

    var case_dir = try std.Io.Dir.cwd().openDir(init.io, args[1], .{ .iterate = true });
    defer case_dir.close(init.io);
    var output_dir = try std.Io.Dir.cwd().openDir(init.io, args[2], .{ .iterate = true });
    defer output_dir.close(init.io);
    var expected_dir = try case_dir.openDir(init.io, "expected", .{ .iterate = true });
    defer expected_dir.close(init.io);

    const semantic_bytes = try case_dir.readFileAlloc(init.io, "semantic.json", allocator, .limited(64 * 1024 * 1024));
    const options_bytes = try case_dir.readFileAlloc(init.io, "options.json", allocator, .limited(1024 * 1024));
    var parsed_options = try std.json.parseFromSlice(CaseOptions, allocator, options_bytes, .{});
    defer parsed_options.deinit();
    const options = parsed_options.value;

    try generator.generate(allocator, init.io, semantic_bytes, output_dir, .{
        .package = options.package,
        .prefix = options.prefix,
        .go_module = options.go_module,
        .cflags_override = options.cflags_override,
        .ldflags_override = options.ldflags_override,
        .system_ldflags = options.system_ldflags,
        .framework_ldflags = options.framework_ldflags,
        .include_dir = options.include_dir,
        .library_dir = options.library_dir,
        .raw_package_path = options.raw_package_path,
        .raw_package_name = options.raw_package_name,
        .raw_colocated = options.raw_colocated,
    });

    var result = try snapshot.compare(allocator, init.io, expected_dir, output_dir);
    defer result.deinit(allocator);
    if (result.matches()) return;
    result.render();
    return error.SnapshotMismatch;
}
