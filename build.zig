const std = @import("std");
const naming = @import("src/gen/naming.zig");

pub const CgoFlags = struct {
    cflags: []const []const u8 = &.{},
    ldflags: []const []const u8 = &.{},
};

pub const LinkMode = enum { static, dynamic };

pub const Options = struct {
    pub const RawPackage = union(enum) {
        internal,
        colocated,
        path: []const u8,
    };

    name: []const u8,
    module: *std.Build.Module,
    bindings: std.Build.LazyPath,
    go_dir: std.Build.LazyPath,
    go_module: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    prefix: []const u8 = "zg",
    link_mode: LinkMode = .static,
    cgo_flags: ?CgoFlags = null,
    abi_base: ?[]const u8 = null,
    raw_package: RawPackage = .internal,
};

const ResolvedRawPackage = struct {
    path: []const u8,
    name: []const u8,
    colocated: bool,
};

pub const GoBindings = struct {
    update: *std.Build.Step.UpdateSourceFiles,
    check: *std.Build.Step.Run,
    abi_check: ?*std.Build.Step.Run,
    lib: *std.Build.Step.Compile,
    semantic_json: std.Build.LazyPath,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = b.option([]const []const u8, "test-filter", "Run only tests or generator cases matching a filter") orelse &.{};
    const zigo = b.addModule("zigo", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generator_modules = createGeneratorModules(b, b.path("src"), target, optimize);
    const generator = addGeneratorWithModules(b, b.path("src/main.zig"), target, optimize, generator_modules);
    b.installArtifact(generator);

    const reflect_walk_module = b.createModule(.{
        .root_source_file = b.path("src/reflect/walk.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = generator_modules.semantic }},
    });
    const reflect_names_module = b.createModule(.{
        .root_source_file = b.path("src/reflect/names.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = generator_modules.semantic }},
    });
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigo", .module = zigo },
            .{ .name = "diagnostic", .module = generator_modules.diagnostic },
            .{ .name = "semantic", .module = generator_modules.semantic },
            .{ .name = "errors_lock", .module = generator_modules.errors_lock },
            .{ .name = "abi_diff", .module = generator_modules.abi_diff },
            .{ .name = "sync_check", .module = generator_modules.sync_check },
            .{ .name = "abi", .module = generator_modules.abi },
            .{ .name = "reflect_walk", .module = reflect_walk_module },
            .{ .name = "reflect_names", .module = reflect_names_module },
        },
    }), .filters = test_filters });
    const run_tests = b.addRunArtifact(tests);
    const generator_tests = b.addTest(.{ .root_module = generator_modules.generator, .filters = test_filters });
    const run_generator_tests = b.addRunArtifact(generator_tests);
    const reflect_walk_tests = b.addTest(.{ .root_module = reflect_walk_module, .filters = test_filters });
    const run_reflect_walk_tests = b.addRunArtifact(reflect_walk_tests);
    const reflect_names_tests = b.addTest(.{ .root_module = reflect_names_module, .filters = test_filters });
    const run_reflect_names_tests = b.addRunArtifact(reflect_names_tests);
    const abi_diff_tests = b.addTest(.{ .root_module = generator_modules.abi_diff, .filters = test_filters });
    const run_abi_diff_tests = b.addRunArtifact(abi_diff_tests);
    const errors_lock_tests = b.addTest(.{ .root_module = generator_modules.errors_lock, .filters = test_filters });
    const run_errors_lock_tests = b.addRunArtifact(errors_lock_tests);
    const diagnostic_tests = b.addTest(.{ .root_module = generator_modules.diagnostic, .filters = test_filters });
    const run_diagnostic_tests = b.addRunArtifact(diagnostic_tests);
    const sync_check_tests = b.addTest(.{ .root_module = generator_modules.sync_check, .filters = test_filters });
    const run_sync_check_tests = b.addRunArtifact(sync_check_tests);
    const cli_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/gen/cli.zig"),
        .target = target,
        .optimize = optimize,
    }), .filters = test_filters });
    const run_cli_tests = b.addRunArtifact(cli_tests);
    const test_step = b.step("test", "Run unit and snapshot harness tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_generator_tests.step);
    test_step.dependOn(&run_reflect_walk_tests.step);
    test_step.dependOn(&run_reflect_names_tests.step);
    test_step.dependOn(&run_abi_diff_tests.step);
    test_step.dependOn(&run_errors_lock_tests.step);
    test_step.dependOn(&run_diagnostic_tests.step);
    test_step.dependOn(&run_sync_check_tests.step);
    test_step.dependOn(&run_cli_tests.step);

    const generator_case_runner = b.addExecutable(.{
        .name = "zigo-generator-case",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/generator_case_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "generator", .module = generator_modules.generator }},
        }),
    });
    addGeneratorCases(b, test_step, generator_case_runner, test_filters);

    const check_step = b.step("check", "Compile all project artifacts without running tests");
    check_step.dependOn(&generator.step);
    check_step.dependOn(&tests.step);
    check_step.dependOn(&generator_tests.step);
    check_step.dependOn(&reflect_walk_tests.step);
    check_step.dependOn(&reflect_names_tests.step);
    check_step.dependOn(&abi_diff_tests.step);
    check_step.dependOn(&errors_lock_tests.step);
    check_step.dependOn(&diagnostic_tests.step);
    check_step.dependOn(&sync_check_tests.step);
    check_step.dependOn(&cli_tests.step);
    check_step.dependOn(&generator_case_runner.step);

    const snapshot_exe = b.addExecutable(.{
        .name = "zigo-snapshot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/snapshot_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_snapshot = b.addRunArtifact(snapshot_exe);
    if (b.args) |args| run_snapshot.addArgs(args);
    const snapshot_step = b.step("snapshot", "Compare or update a snapshot directory tree");
    snapshot_step.dependOn(&run_snapshot.step);
}

fn addGeneratorCases(
    b: *std.Build,
    test_step: *std.Build.Step,
    runner: *std.Build.Step.Compile,
    test_filters: []const []const u8,
) void {
    const cases_path = b.pathFromRoot("tests/generator_cases");
    var directory = std.Io.Dir.cwd().openDir(b.graph.io, cases_path, .{ .iterate = true }) catch |err|
        std.debug.panic("unable to open generator cases at '{s}': {}", .{ cases_path, err });
    defer directory.close(b.graph.io);

    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(b.allocator);
    var iterator = directory.iterate();
    while (iterator.next(b.graph.io) catch |err|
        std.debug.panic("unable to enumerate generator cases at '{s}': {}", .{ cases_path, err })) |entry|
    {
        if (entry.kind != .directory) continue;
        names.append(b.allocator, b.dupe(entry.name)) catch @panic("OOM");
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

    const cases = b.path("tests/generator_cases");
    for (names.items) |name| {
        if (!matchesAnyFilter(name, test_filters)) continue;
        const run = b.addRunArtifact(runner);
        run.setName(b.fmt("generator case ({s})", .{name}));
        run.addDirectoryArg(cases.path(b, name));
        _ = run.addOutputDirectoryArg(b.fmt("{s}-actual", .{name}));
        test_step.dependOn(&run.step);
    }
}

fn matchesAnyFilter(name: []const u8, filters: []const []const u8) bool {
    if (filters.len == 0) return true;
    for (filters) |filter| if (std.mem.find(u8, name, filter) != null) return true;
    return false;
}

/// Adds the Go-binding pipeline to a consuming build graph.
pub fn addGoBindings(b: *std.Build, options: Options) GoBindings {
    const go_package = naming.snakeAlloc(b.allocator, options.name) catch @panic("OOM");
    const raw_package = resolveRawPackage(b, options.raw_package, go_package);
    const zigo_dependency = b.dependencyFromBuildZig(@This(), .{});
    const generator = addGenerator(b, zigo_dependency.path("src/main.zig"), b.graph.host, .Debug);
    const semantic_module = b.createModule(.{
        .root_source_file = zigo_dependency.path("src/gen/ir/semantic.zig"),
        .target = options.target,
        .optimize = .Debug,
    });
    const bindings_module = b.createModule(.{
        .root_source_file = options.bindings,
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "zigo", .module = zigo_dependency.module("zigo") },
            .{ .name = options.name, .module = options.module },
        },
    });
    const reflector = b.addExecutable(.{
        .name = "zigo-reflect",
        .root_module = b.createModule(.{
            .root_source_file = zigo_dependency.path("src/reflect/main.zig"),
            .target = options.target,
            .optimize = .Debug,
            .imports = &.{
                .{ .name = "bindings", .module = bindings_module },
                .{ .name = "semantic", .module = semantic_module },
            },
        }),
    });
    const semantic_run = b.addRunArtifact(reflector);
    const layout_json = semantic_run.addOutputFileArg("layout.json");
    semantic_run.addArgs(&.{ options.name, options.prefix });
    semantic_run.addFileArg(options.bindings);
    const semantic_json = semantic_run.captureStdOut(.{ .basename = "semantic.json", .trim_whitespace = .none });
    // Successful fallback warnings stay captured so Zig does not label a
    // successful command as failed. On a non-zero exit, Step.Run reports the
    // captured enrichment diagnostics with the actual failure.
    _ = semantic_run.captureStdErr(.{ .basename = "warnings.txt", .trim_whitespace = .none });

    const raw_source_dir = options.go_dir.path(b, raw_package.path).getPath(b);
    const include_dir = cgoRelativePath(b, raw_source_dir, b.pathJoin(&.{ b.install_path, "include" }));
    const library_dir = cgoRelativePath(b, raw_source_dir, b.pathJoin(&.{ b.install_path, "lib" }));
    const generate = b.addRunArtifact(generator);
    generate.addArgs(&.{ "generate", "--semantic" });
    generate.addFileArg(semantic_json);
    generate.addArg("--output");
    const generated_dir = generate.addOutputDirectoryArg("bindings");
    const cflags_override = if (options.cgo_flags) |flags| joinFlags(b, flags.cflags) else "";
    const ldflags_override = if (options.cgo_flags) |flags| joinFlags(b, flags.ldflags) else "";
    const system_ldflags = systemLibraryFlags(b, options.module);
    const framework_ldflags = frameworkFlags(b, options.module);
    generate.addArgs(&.{
        "--package",           options.name,
        "--prefix",            options.prefix,
        "--go-module",         options.go_module,
        "--include-dir",       include_dir,
        "--library-dir",       library_dir,
        "--cflags",            cflags_override,
        "--ldflags",           ldflags_override,
        "--system-ldflags",    system_ldflags,
        "--framework-ldflags", framework_ldflags,
        "--raw-package-path",  raw_package.path,
        "--raw-package-name",  raw_package.name,
    });
    if (raw_package.colocated) generate.addArg("--raw-colocated");
    const errors_lock_path = "zigo/errors.lock.json";
    const has_errors_lock = blk: {
        b.build_root.handle.access(b.graph.io, errors_lock_path, .{}) catch |err| switch (err) {
            error.FileNotFound => break :blk false,
            else => @panic("unable to inspect errors.lock.json"),
        };
        break :blk true;
    };
    if (has_errors_lock) {
        generate.addArg("--errors-lock");
        generate.addFileArg(b.path(errors_lock_path));
    }

    const raw_go_path = if (raw_package.colocated)
        b.fmt("{s}/{s}_cgo_gen.go", .{ go_package, go_package })
    else
        b.fmt("{s}/{s}_gen.go", .{ raw_package.path, raw_package.name });
    const public_go_path = b.fmt("{s}/{s}_gen.go", .{ go_package, go_package });
    const public_errors_go_path = b.fmt("{s}/{s}_errors_gen.go", .{ go_package, go_package });
    const public_helpers_go_path = b.fmt("{s}/{s}_helpers_gen.go", .{ go_package, go_package });
    const go_sources_dir = formattedGoSources(b, generated_dir, &.{ raw_go_path, public_go_path, public_errors_go_path, public_helpers_go_path });

    const check = b.addRunArtifact(generator);
    check.addArgs(&.{ "check", "--generated" });
    check.addDirectoryArg(go_sources_dir);
    check.addArg("--source");
    check.addDirectoryArg(options.go_dir);
    const abi_check: ?*std.Build.Step.Run = if (options.abi_base) |abi_base| check: {
        const baseline = b.addSystemCommand(&.{ "git", "show" });
        // The ref can move without changing argv, so this read must not reuse a
        // build-cache entry from an older commit.
        baseline.has_side_effects = true;
        baseline.setCwd(b.path("."));
        baseline.addArg(b.fmt("{s}:./zigo/semantic.json", .{abi_base}));
        const baseline_semantic = baseline.captureStdOut(.{ .basename = "semantic-base.json", .trim_whitespace = .none });
        const run = b.addRunArtifact(generator);
        run.addArgs(&.{ "abi-diff", "--base" });
        run.addFileArg(baseline_semantic);
        run.addArg("--current");
        run.addFileArg(semantic_json);
        run.addArgs(&.{ "--fail-on", "breaking" });
        break :check run;
    } else null;

    const shim_module = b.createModule(.{
        .root_source_file = generated_dir.path(b, "shim.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{.{ .name = "zigo_target", .module = options.module }},
    });
    const lib = b.addLibrary(.{
        .name = b.fmt("{s}_zigo", .{go_package}),
        .linkage = switch (options.link_mode) {
            .static => .static,
            .dynamic => .dynamic,
        },
        .root_module = shim_module,
    });
    lib.root_module.addCSourceFile(.{ .file = generated_dir.path(b, "panic.c"), .flags = &.{"-fno-sanitize=undefined"} });
    lib.root_module.linkSystemLibrary("c", .{});
    const install_lib = b.addInstallArtifact(lib, .{});
    const header_name = b.fmt("zigo_{s}.h", .{go_package});
    const install_header = b.addInstallHeaderFile(generated_dir.path(b, header_name), header_name);
    const update = b.addUpdateSourceFiles();
    update.addCopyFileToSource(go_sources_dir.path(b, raw_go_path), sourcePath(b, options.go_dir, raw_go_path));
    update.addCopyFileToSource(go_sources_dir.path(b, public_go_path), sourcePath(b, options.go_dir, public_go_path));
    update.addCopyFileToSource(go_sources_dir.path(b, public_errors_go_path), sourcePath(b, options.go_dir, public_errors_go_path));
    update.addCopyFileToSource(go_sources_dir.path(b, public_helpers_go_path), sourcePath(b, options.go_dir, public_helpers_go_path));
    update.addCopyFileToSource(generated_dir.path(b, "errors.lock.json"), errors_lock_path);
    update.addCopyFileToSource(semantic_json, "zigo/semantic.json");
    const go_mod_path = sourcePath(b, options.go_dir, "go.mod");
    b.build_root.handle.access(b.graph.io, go_mod_path, .{}) catch |err| switch (err) {
        error.FileNotFound => update.addBytesToSource(b.fmt("module {s}\n\ngo 1.23\n", .{options.go_module}), go_mod_path),
        else => @panic("unable to inspect go.mod"),
    };
    update.step.dependOn(&install_lib.step);
    update.step.dependOn(&install_header.step);
    check.step.dependOn(&lib.step);
    if (abi_check) |run| run.step.dependOn(&lib.step);

    _ = options.target;
    _ = options.optimize;
    _ = options.prefix;
    _ = layout_json;

    return .{ .update = update, .check = check, .abi_check = abi_check, .lib = lib, .semantic_json = semantic_json };
}

fn formattedGoSources(b: *std.Build, generated_dir: std.Build.LazyPath, paths: []const []const u8) std.Build.LazyPath {
    const gofmt = b.findProgram(&.{"gofmt"}, &.{}) catch return generated_dir;
    const formatted = b.addWriteFiles();
    for (paths) |path| {
        const run = b.addSystemCommand(&.{gofmt});
        run.addFileArg(generated_dir.path(b, path));
        const output = run.captureStdOut(.{ .basename = std.fs.path.basename(path), .trim_whitespace = .none });
        _ = formatted.addCopyFile(output, path);
    }
    return formatted.getDirectory();
}

fn resolveRawPackage(b: *std.Build, option: Options.RawPackage, go_package: []const u8) ResolvedRawPackage {
    return switch (option) {
        .internal => .{ .path = "internal/raw", .name = "raw", .colocated = false },
        .colocated => .{ .path = go_package, .name = go_package, .colocated = true },
        .path => |path| blk: {
            validateRawPackagePath(path);
            if (std.mem.eql(u8, path, go_package)) @panic("raw_package.path matches the public package; use .colocated");
            const name = naming.snakeAlloc(b.allocator, std.fs.path.basename(path)) catch @panic("OOM");
            if (!isGoIdentifier(name)) @panic("raw_package.path basename must normalize to a valid Go package name");
            break :blk .{ .path = path, .name = name, .colocated = false };
        },
    };
}

fn validateRawPackagePath(path: []const u8) void {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, '\\') != null)
        @panic("raw_package.path must be a non-empty relative slash-separated path");
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, ".."))
            @panic("raw_package.path must not contain empty, '.' or '..' components");
        for (component) |character| {
            if (!(std.ascii.isAlphanumeric(character) or character == '_' or character == '-' or character == '.'))
                @panic("raw_package.path components may contain only ASCII letters, digits, '_', '-' and '.'");
        }
    }
}

fn isGoIdentifier(value: []const u8) bool {
    if (value.len == 0 or std.mem.eql(u8, value, "_") or isGoKeyword(value) or !(std.ascii.isAlphabetic(value[0]) or value[0] == '_')) return false;
    for (value[1..]) |character| if (!(std.ascii.isAlphanumeric(character) or character == '_')) return false;
    return true;
}

fn isGoKeyword(value: []const u8) bool {
    const keywords = [_][]const u8{
        "break",    "default",     "func",   "interface", "select",
        "case",     "defer",       "go",     "map",       "struct",
        "chan",     "else",        "goto",   "package",   "switch",
        "const",    "fallthrough", "if",     "range",     "type",
        "continue", "for",         "import", "return",    "var",
    };
    for (keywords) |keyword| if (std.mem.eql(u8, value, keyword)) return true;
    return false;
}

fn sourcePath(b: *std.Build, directory: std.Build.LazyPath, child: []const u8) []const u8 {
    return switch (directory) {
        .src_path => |source| b.pathJoin(&.{ source.sub_path, child }),
        else => @panic("go_dir must be a source path"),
    };
}

fn cgoRelativePath(b: *std.Build, from: []const u8, to: []const u8) []const u8 {
    const relative = std.fs.path.relative(b.allocator, "", null, from, to) catch @panic("OOM");
    return b.fmt("${{SRCDIR}}/{s}", .{relative});
}

fn joinFlags(b: *std.Build, flags: []const []const u8) []const u8 {
    return std.mem.join(b.allocator, " ", flags) catch @panic("OOM");
}

fn systemLibraryFlags(b: *std.Build, module: *std.Build.Module) []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    for (module.link_objects.items) |object| switch (object) {
        .system_lib => |library| flags.append(b.allocator, b.fmt("-l{s}", .{library.name})) catch @panic("OOM"),
        else => {},
    };
    return joinFlags(b, flags.items);
}

fn frameworkFlags(b: *std.Build, module: *std.Build.Module) []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    for (module.frameworks.keys()) |framework| {
        flags.append(b.allocator, "-framework") catch @panic("OOM");
        flags.append(b.allocator, framework) catch @panic("OOM");
    }
    return joinFlags(b, flags.items);
}

fn addGenerator(
    b: *std.Build,
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const modules = createGeneratorModules(b, root_source_file.dirname(), target, optimize);
    return addGeneratorWithModules(b, root_source_file, target, optimize, modules);
}

const GeneratorModules = struct {
    semantic: *std.Build.Module,
    abi: *std.Build.Module,
    diagnostic: *std.Build.Module,
    errors_lock: *std.Build.Module,
    abi_diff: *std.Build.Module,
    sync_check: *std.Build.Module,
    generator: *std.Build.Module,
};

fn createGeneratorModules(
    b: *std.Build,
    source_root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) GeneratorModules {
    const semantic_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/ir/semantic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const abi_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/ir/abi.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = semantic_module }},
    });
    const diagnostic_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/diagnostic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const errors_lock_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/ir/errors_lock.zig"),
        .target = target,
        .optimize = optimize,
    });
    const abi_diff_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/abi_diff.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = semantic_module }},
    });
    const sync_check_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/sync_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generator_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/generator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "semantic", .module = semantic_module },
            .{ .name = "abi", .module = abi_module },
            .{ .name = "diagnostic", .module = diagnostic_module },
            .{ .name = "errors_lock", .module = errors_lock_module },
        },
    });
    return .{
        .semantic = semantic_module,
        .abi = abi_module,
        .diagnostic = diagnostic_module,
        .errors_lock = errors_lock_module,
        .abi_diff = abi_diff_module,
        .sync_check = sync_check_module,
        .generator = generator_module,
    };
}

fn addGeneratorWithModules(
    b: *std.Build,
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    modules: GeneratorModules,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "zigo-gen",
        .root_module = b.createModule(.{
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "semantic", .module = modules.semantic },
                .{ .name = "abi", .module = modules.abi },
                .{ .name = "diagnostic", .module = modules.diagnostic },
                .{ .name = "errors_lock", .module = modules.errors_lock },
                .{ .name = "abi_diff", .module = modules.abi_diff },
                .{ .name = "sync_check", .module = modules.sync_check },
            },
        }),
    });
}
