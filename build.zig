const std = @import("std");
const build_options = @import("src/build_options.zig");
const naming = @import("src/gen/naming.zig");

pub const CgoFlags = struct {
    cflags: []const []const u8 = &.{},
    ldflags: []const []const u8 = &.{},
};

pub const LinkMode = enum { static, dynamic };
pub const Backend = enum { cgo, purego };

pub const Options = struct {
    pub const RawPackage = union(enum) {
        internal,
        colocated,
        path: []const u8,
    };

    name: []const u8,
    module: *std.Build.Module,
    bindings: std.Build.LazyPath,
    source_root: ?std.Build.LazyPath = null,
    go_dir: std.Build.LazyPath,
    go_module: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    prefix: []const u8 = "zg",
    link_mode: LinkMode = .static,
    backend: Backend = .cgo,
    cgo_flags: ?CgoFlags = null,
    abi_base: ?[]const u8 = null,
    raw_package: RawPackage = .internal,
    auto_cleanup: bool = false,
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
    report: *std.Build.Step.Run,
    doctor: *std.Build.Step.Run,
    lib: *std.Build.Step.Compile,
    /// Installs the native binding library into `zig-out/lib`.
    install_library: *std.Build.Step.InstallArtifact,
    /// Target-specific basename of the native binding library.
    library_filename: []const u8,
    semantic_json: std.Build.LazyPath,

    pub const StandardStepOptions = struct {
        /// Prefixes conventional step names for projects with multiple binding sets.
        /// For example, `.name_prefix = "admin"` registers `admin-go` and
        /// `admin-go-check` instead of `go` and `go-check`.
        name_prefix: ?[]const u8 = null,
    };

    pub const StandardSteps = struct {
        update: *std.Build.Step,
        check: *std.Build.Step,
        abi_check: ?*std.Build.Step,
        report: *std.Build.Step,
        doctor: *std.Build.Step,
        library: *std.Build.Step,
    };

    /// Registers conventional user-facing build steps for this binding set.
    pub fn addStandardSteps(self: GoBindings, b: *std.Build, options: StandardStepOptions) StandardSteps {
        if (options.name_prefix) |prefix| {
            if (prefix.len == 0) @panic("Go binding step name_prefix must not be empty");
        }
        const update = b.step(standardStepName(b, options.name_prefix, "go"), "Generate and build Go bindings");
        update.dependOn(&self.update.step);
        const check = b.step(standardStepName(b, options.name_prefix, "go-check"), "Fail if generated Go bindings are stale");
        check.dependOn(&self.check.step);
        const report = b.step(standardStepName(b, options.name_prefix, "go-report"), "Explain the effective Go binding contract");
        report.dependOn(&self.report.step);
        const doctor = b.step(standardStepName(b, options.name_prefix, "go-doctor"), "Check Go binding toolchain prerequisites");
        doctor.dependOn(&self.doctor.step);
        const library = b.step(standardStepName(b, options.name_prefix, "go-lib"), "Build and install the native Go binding library");
        library.dependOn(&self.install_library.step);
        const abi_check = if (self.abi_check) |run| step: {
            const value = b.step(standardStepName(b, options.name_prefix, "abi-check"), "Fail on a breaking Go binding ABI change");
            value.dependOn(&run.step);
            break :step value;
        } else null;
        return .{ .update = update, .check = check, .abi_check = abi_check, .report = report, .doctor = doctor, .library = library };
    }
};

fn standardStepName(b: *std.Build, prefix: ?[]const u8, suffix: []const u8) []const u8 {
    return if (prefix) |value| b.fmt("{s}-{s}", .{ value, suffix }) else suffix;
}

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
    const build_options_module = b.createModule(.{
        .root_source_file = b.path("src/build_options.zig"),
        .target = target,
        .optimize = optimize,
    });
    const emit_module = b.createModule(.{
        .root_source_file = b.path("src/gen/emit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "semantic", .module = generator_modules.semantic },
            .{ .name = "abi", .module = generator_modules.abi },
        },
    });
    const validate_module = b.createModule(.{
        .root_source_file = b.path("src/gen/validate.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "diagnostic", .module = generator_modules.diagnostic },
            .{ .name = "semantic", .module = generator_modules.semantic },
        },
    });
    const lower_module = b.createModule(.{
        .root_source_file = b.path("src/gen/lower.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = generator_modules.abi },
            .{ .name = "semantic", .module = generator_modules.semantic },
        },
    });
    const report_module = b.createModule(.{
        .root_source_file = b.path("src/gen/report.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = generator_modules.abi },
            .{ .name = "semantic", .module = generator_modules.semantic },
        },
    });
    const doctor_module = b.createModule(.{
        .root_source_file = b.path("src/gen/doctor.zig"),
        .target = target,
        .optimize = optimize,
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
    const build_options_tests = b.addTest(.{ .root_module = build_options_module, .filters = test_filters });
    const run_build_options_tests = b.addRunArtifact(build_options_tests);
    const emit_tests = b.addTest(.{ .root_module = emit_module, .filters = test_filters });
    const run_emit_tests = b.addRunArtifact(emit_tests);
    const validate_tests = b.addTest(.{ .root_module = validate_module, .filters = test_filters });
    const run_validate_tests = b.addRunArtifact(validate_tests);
    const lower_tests = b.addTest(.{ .root_module = lower_module, .filters = test_filters });
    const run_lower_tests = b.addRunArtifact(lower_tests);
    const report_tests = b.addTest(.{ .root_module = report_module, .filters = test_filters });
    const run_report_tests = b.addRunArtifact(report_tests);
    const doctor_tests = b.addTest(.{ .root_module = doctor_module, .filters = test_filters });
    const run_doctor_tests = b.addRunArtifact(doctor_tests);
    const test_step = b.step("test", "Run unit and snapshot harness tests");
    const godoc_audit = b.addSystemCommand(&.{ "go", "run", "./tests/godoc_audit/main.go" });
    godoc_audit.addArgs(&.{
        "tests/generator_cases/complex/expected",
        "tests/generator_cases/scalar/expected",
        "examples/01-scalar/go",
        "examples/02-errors/go",
        "examples/03-opaque/go",
        "examples/04-callback/go",
        "examples/05-pipeline/go",
        "examples/06-camel-case/go",
        "examples/07-event-queue/go",
        "examples/08-telemetry-hub/go",
        "examples/09-type-relations/go",
        "examples/10-tagged-union/go",
        "examples/10-tagged-union/go-purego",
    });
    test_step.dependOn(&godoc_audit.step);
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_generator_tests.step);
    test_step.dependOn(&run_reflect_walk_tests.step);
    test_step.dependOn(&run_reflect_names_tests.step);
    test_step.dependOn(&run_abi_diff_tests.step);
    test_step.dependOn(&run_errors_lock_tests.step);
    test_step.dependOn(&run_diagnostic_tests.step);
    test_step.dependOn(&run_sync_check_tests.step);
    test_step.dependOn(&run_cli_tests.step);
    test_step.dependOn(&run_build_options_tests.step);
    test_step.dependOn(&run_emit_tests.step);
    test_step.dependOn(&run_validate_tests.step);
    test_step.dependOn(&run_lower_tests.step);
    test_step.dependOn(&run_report_tests.step);
    test_step.dependOn(&run_doctor_tests.step);
    addProcessContractTests(b, test_step, generator);

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
    check_step.dependOn(&build_options_tests.step);
    check_step.dependOn(&emit_tests.step);
    check_step.dependOn(&validate_tests.step);
    check_step.dependOn(&lower_tests.step);
    check_step.dependOn(&report_tests.step);
    check_step.dependOn(&doctor_tests.step);
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

    const shared_smoke = b.addExecutable(.{
        .name = "zigo-shared-library-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/shared_library_smoke.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const shared_smoke_step = b.step("shared-library-smoke", "Build the native shared-library smoke loader");
    shared_smoke_step.dependOn(&shared_smoke.step);
}

fn addProcessContractTests(b: *std.Build, test_step: *std.Build.Step, generator: *std.Build.Step.Compile) void {
    const help = b.addRunArtifact(generator);
    help.setName("CLI contract (help)");
    help.addArg("--help");
    help.expectExitCode(0);
    help.expectStdOutMatch("usage: zigo-gen <command> [options]");
    test_step.dependOn(&help.step);

    const invalid_arguments = b.addRunArtifact(generator);
    invalid_arguments.setName("CLI contract (invalid arguments)");
    invalid_arguments.addArg("unknown-command");
    invalid_arguments.expectExitCode(2);
    invalid_arguments.expectStdErrMatch("error: the command is missing or unknown");
    test_step.dependOn(&invalid_arguments.step);

    const invalid_semantic = b.addRunArtifact(generator);
    invalid_semantic.setName("CLI contract (invalid semantic)");
    invalid_semantic.addArgs(&.{ "generate", "--semantic" });
    invalid_semantic.addFileArg(b.path("tests/fixtures/zigo007.json"));
    invalid_semantic.addArg("--output");
    _ = invalid_semantic.addOutputDirectoryArg("invalid-semantic-output");
    invalid_semantic.addArgs(&.{ "--package", "bad" });
    invalid_semantic.expectExitCode(1);
    invalid_semantic.expectStdErrMatch("error[ZIGO007]: generated C symbol collides with another declaration");
    test_step.dependOn(&invalid_semantic.step);

    const stale = b.addRunArtifact(generator);
    stale.setName("CLI contract (stale generated files)");
    stale.addArgs(&.{ "check", "--generated" });
    stale.addDirectoryArg(b.path("tests/fixtures/cli/stale/generated"));
    stale.addArg("--source");
    stale.addDirectoryArg(b.path("tests/fixtures/cli/stale/source"));
    stale.expectExitCode(1);
    stale.expectStdErrMatch("generated file content: value_gen.go");
    test_step.dependOn(&stale.step);

    const abi_break = b.addRunArtifact(generator);
    abi_break.setName("CLI contract (breaking ABI)");
    abi_break.addArgs(&.{ "abi-diff", "--base" });
    abi_break.addFileArg(b.path("tests/fixtures/cli/abi/base.json"));
    abi_break.addArg("--current");
    abi_break.addFileArg(b.path("tests/fixtures/cli/abi/current.json"));
    abi_break.addArgs(&.{ "--fail-on", "breaking" });
    abi_break.expectExitCode(1);
    abi_break.expectStdOutMatch("BREAKING: ping: function removed");
    test_step.dependOn(&abi_break.step);

    const report = b.addRunArtifact(generator);
    report.setName("CLI contract (binding report)");
    report.addArgs(&.{ "report", "--semantic" });
    report.addFileArg(b.path("tests/generator_cases/complex/semantic.json"));
    report.addArgs(&.{ "--go-module", "example.com/zigo/pipeline" });
    report.expectExitCode(0);
    report.expectStdOutMatch("Pipeline.process -> (*Pipeline).Process | C zg_pipeline_process");
    report.expectStdOutMatch("return ownership borrowed");
    test_step.dependOn(&report.step);

    const doctor = b.addRunArtifact(generator);
    doctor.setName("CLI contract (doctor failure)");
    doctor.addArgs(&.{ "doctor", "--go", "/definitely/missing/zigo-go", "--gofmt", "/definitely/missing/zigo-gofmt", "--target", "cross" });
    doctor.expectExitCode(1);
    doctor.expectStdOutMatch("FAIL target: cross compilation is not supported");
    doctor.expectStdOutMatch("FAIL go: executable unavailable");
    doctor.expectStdOutMatch("doctor: failed");
    test_step.dependOn(&doctor.step);

    const invalid_project = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "go", "--summary", "none" });
    invalid_project.setName("invalid project contract (ZIGO007)");
    invalid_project.setCwd(b.path("tests/fixtures/invalid-project"));
    invalid_project.has_side_effects = true;
    invalid_project.expectExitCode(1);
    invalid_project.expectStdErrMatch("error[ZIGO007]: generated C symbol collides with another declaration");
    test_step.dependOn(&invalid_project.step);
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
    if (options.backend == .purego) {
        if (options.link_mode != .dynamic) @panic("purego backend requires .link_mode = .dynamic");
        const target = options.target.result;
        if ((target.os.tag != .macos and target.os.tag != .linux) or
            (target.cpu.arch != .aarch64 and target.cpu.arch != .x86_64))
            @panic("purego backend supports native macOS/Linux on amd64/arm64 only");
        if (!isRunnableOnHost(target, b.graph.host.result))
            @panic("purego backend requires the native host target");
    }
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
    if (options.source_root) |source_root| {
        semantic_run.addFileArg(source_root);
    } else {
        semantic_run.addArg("");
    }
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
        "--backend",           @tagName(options.backend),
        "--library-name",      libraryFilename(b, b.fmt("{s}_zigo", .{go_package}), options.target.result, options.link_mode),
    });
    if (raw_package.colocated) generate.addArg("--raw-colocated");
    if (options.auto_cleanup) generate.addArg("--auto-cleanup");
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
    const public_type_go_path = b.fmt("{s}/{s}_type_gen.go", .{ go_package, go_package });
    const public_errors_go_path = b.fmt("{s}/{s}_errors_gen.go", .{ go_package, go_package });
    const public_helpers_go_path = b.fmt("{s}/{s}_helpers_gen.go", .{ go_package, go_package });
    const go_sources_dir = formattedGoSources(b, generated_dir, &.{ raw_go_path, public_go_path, public_type_go_path, public_errors_go_path, public_helpers_go_path });

    const check = b.addRunArtifact(generator);
    check.addArgs(&.{ "check", "--generated" });
    check.addDirectoryArg(go_sources_dir);
    check.addArg("--source");
    check.addDirectoryArg(options.go_dir);
    const report = b.addRunArtifact(generator);
    report.addArgs(&.{ "report", "--semantic" });
    report.addFileArg(semantic_json);
    report.addArgs(&.{ "--go-module", options.go_module, "--raw-package-path", raw_package.path });
    report.addArgs(&.{ "--backend", @tagName(options.backend) });
    if (raw_package.colocated) report.addArg("--raw-colocated");
    if (options.auto_cleanup) report.addArg("--auto-cleanup");
    const doctor = b.addRunArtifact(generator);
    doctor.has_side_effects = true;
    doctor.addArgs(&.{ "doctor", "--target", if (isRunnableOnHost(options.target.result, b.graph.host.result)) "native" else "cross" });
    doctor.addArgs(&.{ "--backend", @tagName(options.backend) });
    if (options.auto_cleanup) doctor.addArg("--auto-cleanup");
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
    update.addCopyFileToSource(go_sources_dir.path(b, public_type_go_path), sourcePath(b, options.go_dir, public_type_go_path));
    update.addCopyFileToSource(go_sources_dir.path(b, public_errors_go_path), sourcePath(b, options.go_dir, public_errors_go_path));
    update.addCopyFileToSource(go_sources_dir.path(b, public_helpers_go_path), sourcePath(b, options.go_dir, public_helpers_go_path));
    update.addCopyFileToSource(generated_dir.path(b, "errors.lock.json"), errors_lock_path);
    update.addCopyFileToSource(semantic_json, "zigo/semantic.json");
    const go_mod_path = sourcePath(b, options.go_dir, "go.mod");
    b.build_root.handle.access(b.graph.io, go_mod_path, .{}) catch |err| switch (err) {
        error.FileNotFound => update.addBytesToSource(b.fmt("module {s}\n\ngo {s}\n{s}", .{
            options.go_module,
            if (options.auto_cleanup) "1.24" else "1.23",
            if (options.backend == .purego) "\nrequire github.com/ebitengine/purego v0.10.2\n" else "",
        }), go_mod_path),
        else => @panic("unable to inspect go.mod"),
    };
    if (options.backend == .purego) {
        const go_mod = b.build_root.handle.readFileAlloc(b.graph.io, go_mod_path, b.allocator, .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => @panic("unable to read go.mod for purego dependency validation"),
        };
        if (go_mod) |contents| {
            if (std.mem.indexOf(u8, contents, "github.com/ebitengine/purego") == null)
                @panic("purego backend requires github.com/ebitengine/purego v0.10.2; run `go get github.com/ebitengine/purego@v0.10.2`");
        }
    }
    update.step.dependOn(&install_lib.step);
    update.step.dependOn(&install_header.step);
    check.step.dependOn(&lib.step);
    if (abi_check) |run| run.step.dependOn(&lib.step);

    _ = options.target;
    _ = options.optimize;
    _ = options.prefix;
    _ = layout_json;

    return .{
        .update = update,
        .check = check,
        .abi_check = abi_check,
        .report = report,
        .doctor = doctor,
        .lib = lib,
        .install_library = install_lib,
        .library_filename = libraryFilename(b, lib.name, options.target.result, options.link_mode),
        .semantic_json = semantic_json,
    };
}

fn libraryFilename(b: *std.Build, name: []const u8, target: std.Target, mode: LinkMode) []const u8 {
    return switch (mode) {
        .static => b.fmt("{s}{s}{s}", .{ target.libPrefix(), name, target.staticLibSuffix() }),
        .dynamic => b.fmt("{s}{s}{s}", .{ target.libPrefix(), name, target.dynamicLibSuffix() }),
    };
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

fn isRunnableOnHost(target: std.Target, host: std.Target) bool {
    return target.cpu.arch == host.cpu.arch and target.os.tag == host.os.tag and target.abi == host.abi;
}

fn resolveRawPackage(b: *std.Build, option: Options.RawPackage, go_package: []const u8) ResolvedRawPackage {
    return switch (option) {
        .internal => .{ .path = "internal/raw", .name = "raw", .colocated = false },
        .colocated => .{ .path = go_package, .name = go_package, .colocated = true },
        .path => |path| blk: {
            if (std.mem.eql(u8, path, go_package)) @panic("raw_package.path matches the public package; use .colocated");
            build_options.validateRawPackagePath(path) catch |err| switch (err) {
                error.InvalidPath => @panic("raw_package.path must be a non-empty relative slash-separated path"),
                error.InvalidComponent => @panic("raw_package.path must not contain empty, '.' or '..' components"),
                error.InvalidCharacter => @panic("raw_package.path components may contain only ASCII letters, digits, '_', '-' and '.'"),
            };
            const name = naming.snakeAlloc(b.allocator, std.fs.path.basename(path)) catch @panic("OOM");
            build_options.validateRawPackageName(name) catch
                @panic("raw_package.path basename must normalize to a valid Go package name");
            break :blk .{ .path = path, .name = name, .colocated = false };
        },
    };
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
