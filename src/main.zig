const std = @import("std");
const abi_diff = @import("abi_diff");
const cli = @import("gen/cli.zig");
const diagnostic = @import("diagnostic");
const doctor = @import("gen/doctor.zig");
const generator = @import("gen/generator.zig");
const binding_report = @import("gen/report.zig");
const semantic = @import("semantic");
const stream_return = @import("stream_return");
const sync_check = @import("sync_check");
const targets = @import("targets");
const validate = @import("gen/validate/validate.zig");

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

/// One of the two places an output language is chosen -- this one for the
/// CLI, `addGoBindings` in `build.zig` for the build integration. Every layer
/// below reads the target from what it is handed, so a second language is a
/// second `targets.Target` and a way to name it here, not a change to the
/// generator, the validators or the report.
fn outputTarget() targets.Target {
    return targets.default;
}

fn runGenerate(allocator: std.mem.Allocator, io: std.Io, options: cli.Generate) !void {
    const semantic_bytes = try std.Io.Dir.cwd().readFileAlloc(io, options.semantic_path, allocator, .limited(64 * 1024 * 1024));
    const pkg_config_libs = if (options.pkg_config_libs_path) |path|
        std.mem.trim(u8, try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024)), " \r\n\t")
    else
        options.pkg_config_libs;
    const configurations = try @import("plugin").configurationsAlloc(allocator, @import("plugin_registry").configurations, options.plugin_config);
    try std.Io.Dir.cwd().createDirPath(io, options.output_path);
    var output = try std.Io.Dir.cwd().openDir(io, options.output_path, .{ .iterate = true });
    defer output.close(io);
    const errors_lock_bytes = if (options.errors_lock_path) |path|
        try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024))
    else
        null;
    // The CLI keeps its own target record so it does not depend on the emitter.
    const cgo_targets = try allocator.alloc(generator.CgoTarget, options.cgo_targets.len);
    defer allocator.free(cgo_targets);
    for (options.cgo_targets, cgo_targets) |source, *target| target.* = .{ .goos = source.goos, .goarch = source.goarch };
    const target_ldflags = try allocator.alloc(generator.TargetLdflags, options.target_ldflags.len);
    defer allocator.free(target_ldflags);
    for (options.target_ldflags, target_ldflags) |source, *entry| entry.* = .{ .constraint = source.constraint, .flags = source.flags };
    var generation_issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    generator.generate(allocator, io, semantic_bytes, output, .{
        .output_target = outputTarget(),
        .diagnostics = &generation_issues,
        .write_manifest = true,
        .package = options.package,
        .prefix = options.prefix,
        .go_module = options.go_module,
        .cflags_override = if (options.cflags.len == 0) null else options.cflags,
        .ldflags_override = if (options.ldflags.len == 0) null else options.ldflags,
        .extra_ldflags = options.extra_ldflags,
        .ldflags_external = options.ldflags_external,
        .system_ldflags = options.system_ldflags,
        .pkg_config_libs = pkg_config_libs,
        .framework_ldflags = options.framework_ldflags,
        .include_dir = options.include_dir,
        .library_dir = options.library_dir,
        .header_name = options.header_name,
        .raw_package_path = options.raw_package_path,
        .raw_package_name = options.raw_package_name,
        .raw_colocated = options.raw_colocated,
        .go_package = options.go_package,
        .go_package_path = options.go_package_path,
        .go_package_doc = options.go_package_doc,
        .configurations = configurations,
        .errors_lock_bytes = errors_lock_bytes,
        .backend = switch (options.backend) {
            .cgo => .cgo,
            .purego => .purego,
        },
        .link_mode = switch (options.link_mode) {
            .static => .static,
            .dynamic => .dynamic,
        },
        .cgo_targets = cgo_targets,
        .target_ldflags = target_ldflags,
        .library_stem = options.library_stem,
        .library_search_paths = options.library_search_paths,
        .library_env_vars = options.library_env_vars,
        .library_automatic = options.library_automatic,
        .library_exported_api = options.library_exported_api,
        .library_platform_dirs = options.library_platform_dirs,
    }) catch |err| {
        if (generation_issues.items.len == 0) return err;
        var buffer: [2048]u8 = undefined;
        var stderr = std.Io.File.Writer.init(.stderr(), io, &buffer);
        for (generation_issues.items) |found| try found.render(&stderr.interface);
        try stderr.interface.flush();
        std.process.exit(1);
    };
    try formatGenerated(allocator, io, options.output_path, outputTarget(), options.formatter_executable);
}

/// Format only framed source outputs. Artifacts, including ones in the
/// target's own language, keep their exact bytes, and user-owned files in the
/// output tree are untouched.
///
/// Which formatter, which arguments, what to install and which flag overrides
/// it are all the target's record; this function only runs what it is told and
/// reports what came back. A target with no formatter leaves its output as
/// emitted.
fn formatGenerated(
    allocator: std.mem.Allocator,
    io: std.Io,
    output_path: []const u8,
    target: targets.Target,
    executable_override: ?[]const u8,
) !void {
    const formatter = target.formatter orelse return;
    const executable = executable_override orelse formatter.default_executable;
    const manifest_api = @import("output_manifest");
    var directory = try std.Io.Dir.cwd().openDir(io, output_path, .{});
    defer directory.close(io);
    const manifest = (try manifest_api.read(allocator, io, directory)) orelse return error.MissingOutputManifest;
    defer manifest.deinit();
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(allocator);
    try args.append(allocator, executable);
    try args.appendSlice(allocator, formatter.leading_args);
    const leading = args.items.len;
    for (manifest.value.files) |file| {
        // `.go` is the manifest's word for a framed source file in the output
        // language; the manifest is a written document, so its spelling is a
        // wire format and does not move with this refactoring.
        if (file.kind == .go) try args.append(allocator, try std.fs.path.join(allocator, &.{ output_path, file.path }));
    }
    defer for (args.items[leading..]) |path| allocator.free(path);
    if (args.items.len == leading) return;
    const result = std.process.run(allocator, io, .{
        .argv = args.items,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch {
        var buffer: [512]u8 = undefined;
        var stderr = std.Io.File.Writer.init(.stderr(), io, &buffer);
        try stderr.interface.print(
            "generated {s} is formatted with {s}, but '{s}' could not be run; {s} or pass {s}\n",
            .{ target.display_name, formatter.default_executable, executable, formatter.install_hint, formatter.override_flag },
        );
        try stderr.interface.flush();
        std.process.exit(1);
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    var buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.Writer.init(.stderr(), io, &buffer);
    try stderr.interface.print("{s} failed on the generated {s}:\n{s}\n", .{ formatter.default_executable, target.display_name, result.stderr });
    try stderr.interface.flush();
    std.process.exit(1);
}

fn runCheck(allocator: std.mem.Allocator, io: std.Io, options: cli.Check) !void {
    const cwd = std.Io.Dir.cwd();
    var generated = try cwd.openDir(io, options.generated_path, .{ .iterate = true });
    defer generated.close(io);
    var source = try cwd.openDir(io, options.source_path, .{ .iterate = true });
    defer source.close(io);
    var result = try sync_check.compare(allocator, io, generated, source);
    defer result.deinit(allocator);
    for (options.files) |pair| try sync_check.compareFile(allocator, io, &result, cwd, pair.generated_path, cwd, pair.source_path, pair.source_path);
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
    // Lowering assumes a validated document, so a hand-edited or truncated
    // input would panic inside `lower` instead of being reported. Both
    // documents come from outside this run, so both are judged first.
    try rejectInvalidAbiInput(allocator, io, base.value, options.base_path);
    try rejectInvalidAbiInput(allocator, io, current.value, options.current_path);
    var report = try abi_diff.diffForTarget(allocator, base.value, switch (options.base_backend) {
        .cgo => .cgo,
        .purego => .purego,
    }, current.value, switch (options.current_backend) {
        .cgo => .cgo,
        .purego => .purego,
    }, outputTarget());
    defer report.deinit(allocator);
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), io, &buffer);
    if (options.json) try report.renderJson(allocator, &stdout.interface) else try report.renderText(&stdout.interface);
    try stdout.interface.flush();
    if (options.fail_on_breaking and report.hasBreaking()) std.process.exit(1);
}

/// The diagnostics validation builds name `semantic.json`, which says nothing
/// about which of the two `abi-diff` inputs was rejected; the file the user
/// passed takes its place unless the diagnostic already points at a Zig
/// source location.
fn rejectInvalidAbiInput(allocator: std.mem.Allocator, io: std.Io, document: semantic.Semantic, path: []const u8) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const issues = try validate.findIssuesForTarget(scratch.allocator(), document, null, outputTarget());
    if (issues.len == 0) return;
    var buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.Writer.init(.stderr(), io, &buffer);
    for (issues) |found| {
        var issue = found;
        if (issue.site.line == null) issue.site.path = path;
        try issue.render(&stderr.interface);
    }
    try stderr.interface.flush();
    std.process.exit(1);
}

fn runReport(allocator: std.mem.Allocator, io: std.Io, options: cli.Report) !void {
    const semantic_bytes = try std.Io.Dir.cwd().readFileAlloc(io, options.semantic_path, allocator, .limited(64 * 1024 * 1024));
    var parsed = try semantic.Semantic.parse(allocator, semantic_bytes);
    defer parsed.deinit();
    const api = @import("plugin");
    const configurations = try api.configurationsAlloc(allocator, @import("gen/plugins/registry.zig").configurations, options.plugin_config);
    var facts: api.Facts = .{};
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    const document = try generator.prepareDocument(allocator, parsed.value, null, configurations, &facts, &issues, outputTarget());
    if (issues.items.len != 0) {
        var error_buffer: [1024]u8 = undefined;
        var stderr = std.Io.File.Writer.init(.stderr(), io, &error_buffer);
        for (issues.items) |found| {
            var issue = found;
            if (issue.site.line == null) issue.site.path = options.semantic_path;
            try issue.render(&stderr.interface);
        }
        try stderr.interface.flush();
        std.process.exit(1);
    }
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), io, &buffer);
    try binding_report.render(allocator, &stdout.interface, document, .{
        .output_target = outputTarget(),
        .go_module = options.go_module,
        .raw_package_path = options.raw_package_path,
        .raw_colocated = options.raw_colocated,
        .backend = switch (options.backend) {
            .cgo => .cgo,
            .purego => .purego,
        },
        .go_package = options.go_package,
        .go_package_path = options.go_package_path,
        .library_search_paths = options.library_search_paths,
        .library_env_vars = options.library_env_vars,
        .library_automatic = options.library_automatic,
        .library_exported_api = options.library_exported_api,
        .library_platform_dirs = options.library_platform_dirs,
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
