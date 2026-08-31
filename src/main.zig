const std = @import("std");
const abi_diff = @import("abi_diff");
const cli = @import("gen/cli.zig");
const doctor = @import("gen/doctor.zig");
const generator = @import("gen/generator.zig");
const binding_report = @import("gen/report.zig");
const semantic = @import("semantic");
const sync_check = @import("sync_check");
const validate = @import("gen/validate.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const command_args = if (args.len == 0) &.{} else args[1..];
    if (cli.isHelp(command_args)) {
        var buffer: [2048]u8 = undefined;
        var stdout = std.Io.File.Writer.init(.stdout(), init.io, &buffer);
        try cli.writeUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    }
    const command = cli.parse(command_args) catch |err| {
        var buffer: [2048]u8 = undefined;
        var stderr = std.Io.File.Writer.init(.stderr(), init.io, &buffer);
        try cli.writeParseError(&stderr.interface, err);
        try stderr.interface.flush();
        std.process.exit(2);
    };
    switch (command) {
        .generate => |options| try runGenerate(allocator, init.io, options),
        .check => |options| try runCheck(allocator, init.io, options),
        .abi_diff => |options| try runAbiDiff(allocator, init.io, options),
        .report => |options| try runReport(allocator, init.io, options),
        .doctor => |options| try runDoctor(allocator, init.io, options),
    }
}

fn runGenerate(allocator: std.mem.Allocator, io: std.Io, options: cli.Generate) !void {
    const semantic_bytes = try std.Io.Dir.cwd().readFileAlloc(io, options.semantic_path, allocator, .limited(64 * 1024 * 1024));
    var parsed = try semantic.Semantic.parse(allocator, semantic_bytes);
    defer parsed.deinit();
    if (try validate.findIssue(allocator, parsed.value)) |issue| {
        var buffer: [1024]u8 = undefined;
        var stderr = std.Io.File.Writer.init(.stderr(), io, &buffer);
        try issue.render(&stderr.interface);
        try stderr.interface.flush();
        std.process.exit(1);
    }
    try std.Io.Dir.cwd().createDirPath(io, options.output_path);
    var output = try std.Io.Dir.cwd().openDir(io, options.output_path, .{ .iterate = true });
    defer output.close(io);
    const errors_lock_bytes = if (options.errors_lock_path) |path|
        try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024))
    else
        null;
    try generator.generate(allocator, io, semantic_bytes, output, .{
        .package = options.package,
        .prefix = options.prefix,
        .go_module = options.go_module,
        .cflags_override = if (options.cflags.len == 0) null else options.cflags,
        .ldflags_override = if (options.ldflags.len == 0) null else options.ldflags,
        .system_ldflags = options.system_ldflags,
        .framework_ldflags = options.framework_ldflags,
        .include_dir = options.include_dir,
        .library_dir = options.library_dir,
        .raw_package_path = options.raw_package_path,
        .raw_package_name = options.raw_package_name,
        .raw_colocated = options.raw_colocated,
        .auto_cleanup = options.auto_cleanup,
        .errors_lock_bytes = errors_lock_bytes,
        .backend = switch (options.backend) {
            .cgo => .cgo,
            .purego => .purego,
        },
        .link_mode = switch (options.link_mode) {
            .static => .static,
            .dynamic => .dynamic,
        },
        .library_stem = options.library_stem,
    });
}

fn runCheck(allocator: std.mem.Allocator, io: std.Io, options: cli.Check) !void {
    const cwd = std.Io.Dir.cwd();
    var generated = try cwd.openDir(io, options.generated_path, .{ .iterate = true });
    defer generated.close(io);
    var source = try cwd.openDir(io, options.source_path, .{ .iterate = true });
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

fn runAbiDiff(allocator: std.mem.Allocator, io: std.Io, options: cli.AbiDiff) !void {
    const cwd = std.Io.Dir.cwd();
    const base_bytes = try cwd.readFileAlloc(io, options.base_path, allocator, .limited(64 * 1024 * 1024));
    const current_bytes = try cwd.readFileAlloc(io, options.current_path, allocator, .limited(64 * 1024 * 1024));
    var base = try semantic.Semantic.parse(allocator, base_bytes);
    defer base.deinit();
    var current = try semantic.Semantic.parse(allocator, current_bytes);
    defer current.deinit();
    var report = try abi_diff.diffWithBackends(allocator, base.value, switch (options.base_backend) {
        .cgo => .cgo,
        .purego => .purego,
    }, current.value, switch (options.current_backend) {
        .cgo => .cgo,
        .purego => .purego,
    });
    defer report.deinit(allocator);
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), io, &buffer);
    if (options.json) try report.renderJson(allocator, &stdout.interface) else try report.renderText(&stdout.interface);
    try stdout.interface.flush();
    if (options.fail_on_breaking and report.hasBreaking()) std.process.exit(1);
}

fn runReport(allocator: std.mem.Allocator, io: std.Io, options: cli.Report) !void {
    const semantic_bytes = try std.Io.Dir.cwd().readFileAlloc(io, options.semantic_path, allocator, .limited(64 * 1024 * 1024));
    var parsed = try semantic.Semantic.parse(allocator, semantic_bytes);
    defer parsed.deinit();
    try validate.semanticDocument(allocator, parsed.value);
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), io, &buffer);
    try binding_report.render(allocator, &stdout.interface, parsed.value, .{
        .go_module = options.go_module,
        .raw_package_path = options.raw_package_path,
        .raw_colocated = options.raw_colocated,
        .auto_cleanup = options.auto_cleanup,
        .backend = switch (options.backend) {
            .cgo => .cgo,
            .purego => .purego,
        },
    });
    try stdout.interface.flush();
}

fn runDoctor(allocator: std.mem.Allocator, io: std.Io, options: cli.Doctor) !void {
    var buffer: [2048]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), io, &buffer);
    const healthy = try doctor.run(allocator, io, &stdout.interface, .{
        .go_executable = options.go_executable,
        .gofmt_executable = options.gofmt_executable,
        .native_target = options.native_target,
        .auto_cleanup = options.auto_cleanup,
        .backend = switch (options.backend) {
            .cgo => .cgo,
            .purego => .purego,
        },
        .library_path = options.library_path,
        .go_mod_path = options.go_mod_path,
    });
    try stdout.interface.flush();
    if (!healthy) std.process.exit(1);
}
