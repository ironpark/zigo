const std = @import("std");
const generator = @import("generator");
const snapshot = @import("snapshot.zig");

const CaseOptions = struct {
    /// Which backend the case generates. Most cases are cgo; a case that
    /// exists to pin the purego surface says so here rather than being a
    /// second runner.
    backend: enum { cgo, purego } = .cgo,
    package: []const u8,
    prefix: []const u8,
    go_module: []const u8,
    cflags_override: ?[]const u8 = null,
    ldflags_override: ?[]const u8 = null,
    extra_ldflags: []const u8 = "",
    system_ldflags: []const u8 = "",
    framework_ldflags: []const u8 = "",
    include_dir: []const u8 = "${SRCDIR}/../../../zig-out/include",
    library_dir: []const u8 = "${SRCDIR}/../../../zig-out/lib",
    raw_package_path: []const u8 = "internal/raw",
    raw_package_name: []const u8 = "raw",
    raw_colocated: bool = false,
    go_must_variants: bool = false,
    errors_lock_path: ?[]const u8 = null,
    link_mode: enum { static, dynamic } = .static,
    /// cgo platforms the raw package links for; empty keeps the single line.
    cgo_targets: []const generator.CgoTarget = &.{},
    /// Per-platform appended `#cgo <constraint> LDFLAGS` lines.
    target_ldflags: []const generator.TargetLdflags = &.{},
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
    const errors_lock_bytes = if (options.errors_lock_path) |path|
        try case_dir.readFileAlloc(init.io, path, allocator, .limited(16 * 1024 * 1024))
    else
        null;

    try generator.generate(allocator, init.io, semantic_bytes, output_dir, .{
        .backend = switch (options.backend) {
            .cgo => .cgo,
            .purego => .purego,
        },
        .package = options.package,
        .prefix = options.prefix,
        .go_module = options.go_module,
        .cflags_override = options.cflags_override,
        .ldflags_override = options.ldflags_override,
        .extra_ldflags = options.extra_ldflags,
        .system_ldflags = options.system_ldflags,
        .framework_ldflags = options.framework_ldflags,
        .include_dir = options.include_dir,
        .library_dir = options.library_dir,
        .raw_package_path = options.raw_package_path,
        .raw_package_name = options.raw_package_name,
        .raw_colocated = options.raw_colocated,
        .go_must_variants = options.go_must_variants,
        .errors_lock_bytes = errors_lock_bytes,
        .link_mode = switch (options.link_mode) {
            .static => .static,
            .dynamic => .dynamic,
        },
        .cgo_targets = options.cgo_targets,
        .target_ldflags = options.target_ldflags,
    });

    var result = try snapshot.compare(allocator, init.io, expected_dir, output_dir);
    defer result.deinit(allocator);
    if (result.matches()) return;
    result.render();
    return error.SnapshotMismatch;
}
