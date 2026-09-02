const std = @import("std");
const build_options = @import("src/build_options.zig");
const naming = @import("src/gen/naming.zig");
const go_walk = @import("src/gen/go_walk.zig");

pub const CgoFlags = struct {
    cflags: []const []const u8 = &.{},
    ldflags: []const []const u8 = &.{},
};

const LinkMode = enum { static, dynamic };
const Backend = enum { cgo, purego };

/// How the Go side reaches the native library. One axis, because the two it
/// replaced could describe combinations that do not exist: purego never links
/// statically, and it never goes through cgo.
pub const Link = enum {
    /// cgo against a static archive.
    cgo_static,
    /// cgo against a shared library.
    cgo_dynamic,
    /// No cgo. Symbols are resolved at run time from a shared library.
    purego,

    fn backend(self: Link) Backend {
        return if (self == .purego) .purego else .cgo;
    }

    fn linkMode(self: Link) LinkMode {
        return if (self == .cgo_static) .static else .dynamic;
    }
};

/// How a generated purego package finds its shared library at run time.
pub const LibraryLoading = build_options.LibraryLoading;

pub const Options = struct {
    name: []const u8,
    module: *std.Build.Module,
    bindings: std.Build.LazyPath,
    source_root: ?std.Build.LazyPath = null,
    go_dir: std.Build.LazyPath,
    go_module: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    prefix: []const u8 = "zg",
    link: Link = .cgo_static,
    cgo_flags: ?CgoFlags = null,
    abi_base: ?[]const u8 = null,
    /// Slash-separated path of the raw package inside `go_dir`. Setting it to
    /// the public package path colocates the two.
    raw_package: []const u8 = "internal/raw",
    /// `gofmt` used to format generated Go. Defaults to the one on `PATH`.
    gofmt: ?[]const u8 = null,
    /// Public Go package name. Defaults to the snake_case binding name, which
    /// can contain underscores; set it to choose an idiomatic Go name. The C
    /// header and the native library keep the binding name either way.
    go_package: ?[]const u8 = null,
    /// Body of the generated `// Package ...` doc. Null falls back to the `//!`
    /// container doc of the bindings file, then to a default sentence.
    go_package_doc: ?[]const u8 = null,
    /// purego-only run-time loading policy. The default requires an explicit
    /// `LoadLibrary` call and consults `ZIGO_LIBRARY_PATH`.
    library_loading: LibraryLoading = .{},
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
    /// Full path `install_library` writes the native binding library to.
    /// Zig installs a shared library to `bin` on Windows and `lib` everywhere
    /// else, so this is what a consumer should use rather than joining a
    /// directory of its own choosing with `library_filename`.
    library_path: []const u8,
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
        /// Aggregate validation step: staleness, toolchain, native library and,
        /// when `abi_base` is set, the ABI comparison.
        verify: *std.Build.Step,
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
        const verify = b.step(standardStepName(b, options.name_prefix, "go-verify"), "Validate generated bindings, toolchain, and the native library");
        verify.dependOn(check);
        verify.dependOn(library);
        verify.dependOn(doctor);
        if (abi_check) |value| verify.dependOn(value);
        return .{ .update = update, .check = check, .abi_check = abi_check, .report = report, .doctor = doctor, .library = library, .verify = verify };
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
        .imports = &.{
            .{ .name = "naming", .module = generator_modules.naming },
            .{ .name = "semantic", .module = generator_modules.semantic },
        },
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
            .{ .name = "naming", .module = generator_modules.naming },
            .{ .name = "semantic", .module = generator_modules.semantic },
            .{ .name = "abi", .module = generator_modules.abi },
        },
    });
    const validate_module = b.createModule(.{
        .root_source_file = b.path("src/gen/validate.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "naming", .module = generator_modules.naming },
            .{ .name = "diagnostic", .module = generator_modules.diagnostic },
            .{ .name = "semantic", .module = generator_modules.semantic },
        },
    });
    const lower_module = b.createModule(.{
        .root_source_file = b.path("src/gen/lower.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "naming", .module = generator_modules.naming },
            .{ .name = "abi", .module = generator_modules.abi },
            .{ .name = "semantic", .module = generator_modules.semantic },
        },
    });
    const report_module = b.createModule(.{
        .root_source_file = b.path("src/gen/report.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "naming", .module = generator_modules.naming },
            .{ .name = "abi", .module = generator_modules.abi },
            .{ .name = "semantic", .module = generator_modules.semantic },
        },
    });
    const doctor_module = b.createModule(.{
        .root_source_file = b.path("src/gen/doctor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = build_options_module },
            .{ .name = "dynamic_library", .module = generator_modules.dynamic_library },
        },
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
    // naming is a shared module now, so its tests run here once instead of
    // once per module that used to import the file.
    const naming_tests = b.addTest(.{ .root_module = generator_modules.naming, .filters = test_filters });
    const run_naming_tests = b.addRunArtifact(naming_tests);
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
    const dynamic_library_tests = b.addTest(.{ .root_module = generator_modules.dynamic_library, .filters = test_filters });
    const run_dynamic_library_tests = b.addRunArtifact(dynamic_library_tests);
    const test_step = b.step("test", "Run unit and snapshot harness tests");
    const godoc_audit = b.addSystemCommand(&.{ "go", "run", "./tests/godoc_audit/main.go" });
    godoc_audit.addArgs(&.{
        "tests/generator_cases/complex/expected",
        "tests/generator_cases/scalar/expected",
        "tests/generator_cases/union_snapshot/expected",
        "tests/generator_cases/value_struct/expected",
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
        "examples/04-callback/go-purego",
        "examples/07-event-queue/go-purego",
        "examples/08-telemetry-hub/go-purego",
    });
    test_step.dependOn(&godoc_audit.step);
    // The `symbol` field is the linker name consumers read out of
    // `semantic.json`, so it has to stay unique and match what the generated
    // bindings actually call.
    const symbol_audit = b.addSystemCommand(&.{ "go", "run", "./tests/symbol_audit/main.go" });
    symbol_audit.addArgs(&.{
        "examples/01-scalar",
        "examples/02-errors",
        "examples/03-opaque",
        "examples/04-callback",
        "examples/05-pipeline",
        "examples/06-camel-case",
        "examples/07-event-queue",
        "examples/08-telemetry-hub",
        "examples/09-type-relations",
        "examples/10-tagged-union",
    });
    test_step.dependOn(&symbol_audit.step);
    // The generated layout guard is only worth anything if a divergent layout
    // actually stops the Go build. This fixture is the golden's public struct
    // with its fields swapped, so compiling it has to fail.
    const layout_guard = b.addSystemCommand(&.{ "go", "build", "./..." });
    layout_guard.setName("divergent struct layout fails the Go build");
    layout_guard.setCwd(b.path("tests/layout_guard"));
    layout_guard.expectExitCode(1);
    layout_guard.expectStdErrMatch("index 2 out of bounds");
    test_step.dependOn(&layout_guard.step);
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_generator_tests.step);
    test_step.dependOn(&run_reflect_walk_tests.step);
    test_step.dependOn(&run_reflect_names_tests.step);
    test_step.dependOn(&run_naming_tests.step);
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
    test_step.dependOn(&run_dynamic_library_tests.step);
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
    check_step.dependOn(&dynamic_library_tests.step);
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
            .imports = &.{.{ .name = "dynamic_library", .module = generator_modules.dynamic_library }},
        }),
    });
    // The smoke loader only runs on POSIX, but it shares the loader helper with
    // the doctor probe, so it must compile wherever `check` does.
    check_step.dependOn(&shared_smoke.step);
    const run_shared_smoke = b.addRunArtifact(shared_smoke);
    run_shared_smoke.has_side_effects = true;
    if (b.args) |args| run_shared_smoke.addArgs(args);
    const shared_smoke_step = b.step("shared-library-smoke", "Load an installed shared library and check its exported symbols");
    shared_smoke_step.dependOn(&run_shared_smoke.step);
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

    const union_repr_abi = b.addRunArtifact(generator);
    union_repr_abi.setName("CLI contract (tagged-union representation ABI rules)");
    union_repr_abi.addArgs(&.{ "abi-diff", "--base" });
    union_repr_abi.addFileArg(b.path("tests/fixtures/cli/abi/union_repr_base.json"));
    union_repr_abi.addArg("--current");
    union_repr_abi.addFileArg(b.path("tests/fixtures/cli/abi/union_repr_current.json"));
    union_repr_abi.addArgs(&.{ "--fail-on", "breaking" });
    union_repr_abi.expectExitCode(1);
    union_repr_abi.expectStdOutMatch("ABI COMPATIBLE: Projected: tagged-union variant appended");
    union_repr_abi.expectStdOutMatch("BREAKING: Snapshotted: tagged-union variant appended to a value snapshot");
    test_step.dependOn(&union_repr_abi.step);

    const value_struct_abi = b.addRunArtifact(generator);
    value_struct_abi.setName("CLI contract (extern struct field ABI rules)");
    value_struct_abi.addArgs(&.{ "abi-diff", "--base" });
    value_struct_abi.addFileArg(b.path("tests/fixtures/cli/abi/value_struct_base.json"));
    value_struct_abi.addArg("--current");
    value_struct_abi.addFileArg(b.path("tests/fixtures/cli/abi/value_struct_current.json"));
    value_struct_abi.addArgs(&.{ "--fail-on", "breaking" });
    value_struct_abi.expectExitCode(1);
    value_struct_abi.expectStdOutMatch("BREAKING: Config: type definition changed");
    test_step.dependOn(&value_struct_abi.step);

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
    doctor.expectStdOutMatch("FAIL target: the cgo backend cannot be validated from a cross build");
    doctor.expectStdOutMatch("FAIL go: executable unavailable");
    doctor.expectStdOutMatch("FAIL gofmt: unavailable");
    doctor.expectStdOutMatch("doctor: failed");
    test_step.dependOn(&doctor.step);

    const purego_doctor = b.addRunArtifact(generator);
    purego_doctor.setName("CLI contract (purego deployment doctor)");
    purego_doctor.addArgs(&.{ "doctor", "--backend", "purego", "--target", "native", "--library", "/definitely/missing/zigo-library.so", "--go-mod" });
    purego_doctor.addFileArg(b.path("tests/fixtures/doctor/go.mod"));
    purego_doctor.expectExitCode(1);
    purego_doctor.expectStdOutMatch("FAIL purego module: ");
    purego_doctor.expectStdOutMatch("go get github.com/ebitengine/purego@v0.10.2");
    purego_doctor.expectStdOutMatch("is missing; run `zig build go-lib`");
    test_step.dependOn(&purego_doctor.step);

    const invalid_project = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "go", "--summary", "none" });
    invalid_project.setName("invalid project contract (ZIGO007)");
    invalid_project.setCwd(b.path("tests/fixtures/invalid-project"));
    invalid_project.has_side_effects = true;
    invalid_project.expectExitCode(1);
    invalid_project.expectStdErrMatch("error[ZIGO007]: generated C symbol collides with another declaration");
    test_step.dependOn(&invalid_project.step);

    // Reflection observes the build host, so a `c_long` field is 8 bytes here
    // and 4 on Windows. Natively the shim's guards are trivially true; for a
    // Windows target they must fail the compile with a message that names the
    // struct and the cause. On a Windows host there is nothing to diverge
    // from, so the pair only makes sense on a POSIX host.
    if (b.graph.host.result.os.tag != .windows) {
        const divergence_native = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "lib", "--summary", "none" });
        divergence_native.setName("ABI guard holds natively");
        divergence_native.setCwd(b.path("tests/fixtures/abi-divergence"));
        divergence_native.has_side_effects = true;
        divergence_native.expectExitCode(0);
        test_step.dependOn(&divergence_native.step);

        const divergence_cross = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "lib", "-Dtarget=x86_64-windows-gnu", "--summary", "none" });
        divergence_cross.setName("ABI guard rejects a divergent target");
        divergence_cross.setCwd(b.path("tests/fixtures/abi-divergence"));
        divergence_cross.has_side_effects = true;
        divergence_cross.expectExitCode(1);
        divergence_cross.expectStdErrMatch("zigo ABI guard: @sizeOf(Sizes) is 8 on this target, but zigo reflected 16 on the build host.");
        divergence_cross.expectStdErrMatch("replace it with a fixed-width type.");
        test_step.dependOn(&divergence_cross.step);
    }
}

fn addGeneratorCases(
    b: *std.Build,
    test_step: *std.Build.Step,
    runner: *std.Build.Step.Compile,
    test_filters: []const []const u8,
) void {
    const cases_path = b.pathFromRoot("tests/generator_cases");
    var directory = std.Io.Dir.cwd().openDir(b.graph.io, cases_path, .{ .iterate = true }) catch |err| switch (err) {
        // A consumer's copy of this package carries only what `.paths`
        // lists -- build.zig, build.zig.zon and src -- so the cases are not
        // there, and the consumer never runs this test step. Register
        // nothing rather than fail its whole build graph.
        error.FileNotFound => return,
        else => std.debug.panic("unable to open generator cases at '{s}': {}", .{ cases_path, err }),
    };
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
        addGoldenArtifactChecks(b, test_step, cases.path(b, name), name);
    }
}

/// Compiles the committed golden native artifacts. The tree comparison alone
/// only proves the bytes are stable, so a `panic.c` that does not compile can be
/// pinned as the expectation; this catches that before an example does.
fn addGoldenArtifactChecks(
    b: *std.Build,
    test_step: *std.Build.Step,
    case: std.Build.LazyPath,
    name: []const u8,
) void {
    const expected = case.path(b, "expected");
    const compile_panic = b.addSystemCommand(&.{ b.graph.zig_exe, "cc", "-c" });
    compile_panic.setName(b.fmt("golden panic.c compiles ({s})", .{name}));
    compile_panic.addPrefixedDirectoryArg("-I", expected);
    compile_panic.addFileArg(expected.path(b, "panic.c"));
    _ = compile_panic.addPrefixedOutputFileArg("-o", b.fmt("{s}-panic.o", .{name}));
    compile_panic.expectExitCode(0);
    test_step.dependOn(&compile_panic.step);

    // The shim imports the user's module, so it cannot be compiled standalone.
    // Parsing still rejects a shim the emitters rendered as invalid Zig.
    const parse_shim = b.addSystemCommand(&.{ b.graph.zig_exe, "ast-check" });
    parse_shim.setName(b.fmt("golden shim.zig parses ({s})", .{name}));
    parse_shim.addFileArg(expected.path(b, "shim.zig"));
    parse_shim.expectExitCode(0);
    test_step.dependOn(&parse_shim.step);
}

fn matchesAnyFilter(name: []const u8, filters: []const []const u8) bool {
    if (filters.len == 0) return true;
    for (filters) |filter| if (std.mem.find(u8, name, filter) != null) return true;
    return false;
}

/// Adds the Go-binding pipeline to a consuming build graph.
pub fn addGoBindings(b: *std.Build, options: Options) GoBindings {
    const backend = options.link.backend();
    const link_mode = options.link.linkMode();
    build_options.validateLibraryLoading(options.library_loading, backend == .purego) catch |err| switch (err) {
        error.UnsupportedBackend => @panic("library_loading is only supported by .link = .purego"),
        error.EmptySearchPath => @panic("library_loading.search_paths entries must not be empty"),
        error.InvalidSearchPath => @panic("library_loading.search_paths entries must not contain quotes, backslashes or control characters"),
        error.InvalidEnvironmentName => @panic("library_loading.env_vars entries must be ASCII letters, digits and underscores, and must not start with a digit"),
    };
    if (backend == .purego) {
        if (!build_options.puregoTargetSupported(options.target.result))
            @panic("`.link = .purego` supports macOS, Linux and Windows on amd64/arm64 only");
    }
    const artifact_package = naming.snakeAlloc(b.allocator, options.name) catch @panic("OOM");
    // Names the native artifact; the generator spells the same stem into the
    // `#cgo LDFLAGS` line, so both must come from this one string.
    const library_stem = b.fmt("{s}_zigo", .{artifact_package});
    const go_package = if (options.go_package) |value| blk: {
        naming.validateGoPackageName(value) catch
            @panic("go_package must be a valid Go package identifier");
        break :blk value;
    } else artifact_package;
    const raw_package = resolveRawPackage(b, options.raw_package, go_package);
    const zigo_dependency = b.dependencyFromBuildZig(@This(), .{});
    const generator = addGenerator(b, zigo_dependency.path("src/main.zig"), b.graph.host, .Debug);
    // Reflection runs the bindings module as an executable on the host, so the
    // whole reflection pipeline builds for `b.graph.host` even when the library
    // targets another platform. The generated Go tree is platform-independent;
    // reflected layouts are pinned by the shim's comptime ABI guards, which fail
    // the target compile if a C-variable type diverges.
    const semantic_module = b.createModule(.{
        .root_source_file = zigo_dependency.path("src/gen/ir/semantic.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const naming_module = b.createModule(.{
        .root_source_file = zigo_dependency.path("src/gen/naming.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const bindings_module = b.createModule(.{
        .root_source_file = options.bindings,
        .target = b.graph.host,
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
            .target = b.graph.host,
            .optimize = .Debug,
            .imports = &.{
                .{ .name = "bindings", .module = bindings_module },
                .{ .name = "naming", .module = naming_module },
                .{ .name = "semantic", .module = semantic_module },
            },
        }),
    });
    const semantic_run = b.addRunArtifact(reflector);
    semantic_run.addArgs(&.{ options.name, options.prefix });
    semantic_run.addFileArg(options.bindings);
    // An absent source root is an absent argument, not an empty one.
    if (options.source_root) |source_root| semantic_run.addFileArg(source_root);
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
    // Generation formats its own Go, so the set of generated files never has to
    // be spelled out here.
    if (options.gofmt) |gofmt| generate.addArgs(&.{ "--gofmt", gofmt });
    const cflags_override = if (options.cgo_flags) |flags| joinFlags(b, flags.cflags) else "";
    const ldflags_override = if (options.cgo_flags) |flags| joinFlags(b, flags.ldflags) else "";
    const system_ldflags = systemLibraryFlags(b, options.module);
    const framework_ldflags = frameworkFlags(b, options.module);
    const pkg_config_libs = pkgConfigLibraries(b, options.module);
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
        "--pkg-config-libs",   pkg_config_libs,
        "--raw-package-path",  raw_package.path,
        "--raw-package-name",  raw_package.name,
        "--backend",           @tagName(backend),
        "--library-stem",      library_stem,
        "--link-mode",         @tagName(link_mode),
        "--go-package",        go_package,
        "--go-package-doc",    options.go_package_doc orelse "",
    });
    if (backend == .purego) addLibraryLoadingArgs(b, generate, options.library_loading);
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

    const check = b.addRunArtifact(generator);
    check.addArgs(&.{ "check", "--generated" });
    check.addDirectoryArg(generated_dir);
    check.addArg("--source");
    check.addDirectoryArg(options.go_dir);
    const report = b.addRunArtifact(generator);
    report.addArgs(&.{ "report", "--semantic" });
    report.addFileArg(semantic_json);
    report.addArgs(&.{ "--go-module", options.go_module, "--raw-package-path", raw_package.path, "--go-package", go_package });
    report.addArgs(&.{ "--backend", @tagName(backend) });
    if (backend == .purego) addLibraryLoadingArgs(b, report, options.library_loading);
    if (raw_package.colocated) report.addArg("--raw-colocated");
    const doctor = b.addRunArtifact(generator);
    doctor.has_side_effects = true;
    doctor.addArgs(&.{ "doctor", "--target", if (isRunnableOnHost(options.target.result, b.graph.host.result)) "native" else "cross" });
    doctor.addArgs(&.{ "--backend", @tagName(backend) });
    // Report the same gofmt the update step will format with.
    if (options.gofmt) |gofmt| doctor.addArgs(&.{ "--gofmt", gofmt });
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
        run.addArgs(&.{ "--base-backend", @tagName(backend), "--current-backend", @tagName(backend) });
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
        .name = library_stem,
        .linkage = switch (link_mode) {
            .static => .static,
            .dynamic => .dynamic,
        },
        .root_module = shim_module,
    });
    lib.root_module.addCSourceFile(.{ .file = generated_dir.path(b, "panic.c"), .flags = &.{"-fno-sanitize=undefined"} });
    lib.root_module.linkSystemLibrary("c", .{});
    // Zig names a Windows static archive `<name>.lib`, but the generated cgo
    // `#cgo LDFLAGS` line spells the archive `lib<name>.a` on every host so the
    // emitted block stays identical across targets. `zig cc` links a `.a`
    // archive on Windows just as happily, so rename the install instead of
    // teaching the generator a per-OS filename.
    const static_windows_archive = link_mode == .static and
        options.target.result.os.tag == .windows;
    const install_lib = b.addInstallArtifact(lib, .{
        .dest_sub_path = if (static_windows_archive)
            b.fmt("lib{s}.a", .{library_stem})
        else
            null,
    });
    const header_name = b.fmt("zigo_{s}.h", .{artifact_package});
    // A purego binding set declares the `_purego_v1` entry points, so it must not
    // overwrite the cgo header when both backends install into one prefix.
    const installed_header_name = if (backend == .purego)
        b.fmt("zigo_{s}_purego.h", .{artifact_package})
    else
        header_name;
    const install_header = b.addInstallHeaderFile(generated_dir.path(b, header_name), installed_header_name);
    const publish = PublishGeneratedGo.create(b, generated_dir, sourcePath(b, options.go_dir, "."));
    const update = b.addUpdateSourceFiles();
    update.step.dependOn(&publish.step);
    update.addCopyFileToSource(generated_dir.path(b, "errors.lock.json"), errors_lock_path);
    update.addCopyFileToSource(semantic_json, "zigo/semantic.json");
    const go_mod_path = sourcePath(b, options.go_dir, "go.mod");
    b.build_root.handle.access(b.graph.io, go_mod_path, .{}) catch |err| switch (err) {
        error.FileNotFound => update.addBytesToSource(b.fmt("module {s}\n\ngo {s}\n{s}", .{
            options.go_module,
            "1.24",
            if (backend == .purego) b.fmt("\nrequire {s} {s}\n", .{ build_options.purego_module, build_options.purego_version }) else "",
        }), go_mod_path),
        else => @panic("unable to inspect go.mod"),
    };
    if (backend == .purego) {
        const go_mod = b.build_root.handle.readFileAlloc(b.graph.io, go_mod_path, b.allocator, .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => @panic("unable to read go.mod for purego dependency validation"),
        };
        if (go_mod) |contents| {
            if (std.mem.indexOf(u8, contents, build_options.purego_module) == null)
                std.debug.panic("purego backend requires {0s} {1s}; run `go get {0s}@{1s}`", .{ build_options.purego_module, build_options.purego_version });
        }
    }
    if (backend == .purego) {
        // The purego doctor validates the deployed artifact, so it must run
        // against a freshly installed library and the module that loads it.
        // A cross-built artifact cannot be loaded here, so it is not offered:
        // the doctor reports that check as skipped rather than failing it.
        doctor.step.dependOn(&install_lib.step);
        if (isRunnableOnHost(options.target.result, b.graph.host.result))
            doctor.addArgs(&.{ "--library", installedLibraryPath(b, install_lib) });
        doctor.addArgs(&.{ "--go-mod", b.pathFromRoot(go_mod_path) });
    }
    update.step.dependOn(&install_lib.step);
    update.step.dependOn(&install_header.step);
    check.step.dependOn(&lib.step);
    if (abi_check) |run| run.step.dependOn(&lib.step);

    _ = options.target;
    _ = options.optimize;
    _ = options.prefix;

    return .{
        .update = update,
        .check = check,
        .abi_check = abi_check,
        .report = report,
        .doctor = doctor,
        .lib = lib,
        .install_library = install_lib,
        .library_filename = install_lib.dest_sub_path,
        .library_path = installedLibraryPath(b, install_lib),
        .semantic_json = semantic_json,
    };
}

/// Passes the run-time loading policy as delimited lists, matching the
/// generator's `--library-*` arguments.
fn addLibraryLoadingArgs(b: *std.Build, run: *std.Build.Step.Run, loading: LibraryLoading) void {
    if (loading.search_paths.len != 0)
        run.addArgs(&.{ "--library-search-paths", joinWith(b, loading.search_paths, ":") });
    if (loading.env_vars) |names| run.addArgs(&.{ "--library-env-vars", joinWith(b, names, ",") });
    if (loading.loader.isAutomatic()) run.addArg("--library-automatic");
    if (!loading.loader.exportsApi()) run.addArg("--library-internal-api");
}

fn joinWith(b: *std.Build, values: []const []const u8, separator: []const u8) []const u8 {
    return std.mem.join(b.allocator, separator, values) catch @panic("OOM");
}

/// Where the install step actually puts the native library.
///
/// The directory is not always `lib`: `std.Build.Step.InstallArtifact` resolves
/// a library artifact's destination as `if (artifact.isDll()) .bin else .lib`,
/// so a Windows DLL installs next to the executables while its import library
/// stays in `lib`. Reading the decision back off the step keeps zigo's idea of
/// the path from drifting from Zig's, which is what made `go-doctor` report a
/// freshly installed DLL as missing.
fn installedLibraryPath(b: *std.Build, install: *std.Build.Step.InstallArtifact) []const u8 {
    // `dest_dir` is only null when installation was disabled, which zigo never
    // does: `addInstallArtifact` is called with the default options.
    return b.getInstallPath(install.dest_dir.?, install.dest_sub_path);
}

/// Copies the generated Go tree into the package's Go directory and removes the
/// generated files a previous run left behind.
///
/// `UpdateSourceFiles` copies a named list of files, which this cannot be: how
/// many Go files a binding produces depends on what the binding declares, and
/// only the generator knows that. Pruning is part of the same job — a file left
/// over from a binding that no longer produces it is exactly what `zigo check`
/// reports as obsolete, so a publish that did not prune would leave the tree
/// failing its own check.
const PublishGeneratedGo = struct {
    step: std.Build.Step,
    generated: std.Build.LazyPath,
    /// The Go directory, relative to the package root.
    go_dir: []const u8,

    const generated_marker = "// Code generated by zigo. DO NOT EDIT.";

    fn create(b: *std.Build, generated: std.Build.LazyPath, go_dir: []const u8) *PublishGeneratedGo {
        const self = b.allocator.create(PublishGeneratedGo) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "PublishGeneratedGo",
                .owner = b,
                .makeFn = make,
            }),
            .generated = generated,
            .go_dir = go_dir,
        };
        generated.addStepDependencies(&self.step);
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const b = step.owner;
        const io = b.graph.io;
        const self: *PublishGeneratedGo = @fieldParentPtr("step", step);
        if (!step.inputs.populated()) try step.addWatchInput(self.generated);

        const generated_path = self.generated.getPath2(b, step);
        var generated_dir = std.Io.Dir.cwd().openDir(io, generated_path, .{ .iterate = true }) catch |err| {
            return step.fail("unable to open generated directory '{s}': {t}", .{ generated_path, err });
        };
        defer generated_dir.close(io);
        b.build_root.handle.createDirPath(io, self.go_dir) catch |err| {
            return step.fail("unable to make path '{f}{s}': {t}", .{ b.build_root, self.go_dir, err });
        };
        var go_dir = b.build_root.handle.openDir(io, self.go_dir, .{ .iterate = true }) catch |err| {
            return step.fail("unable to open Go directory '{f}{s}': {t}", .{ b.build_root, self.go_dir, err });
        };
        defer go_dir.close(io);

        var published: std.ArrayList([]const u8) = .empty;
        defer published.deinit(b.allocator);
        var any_miss = false;
        var walker = try go_walk.walk(generated_dir, b.allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".go")) continue;
            const sub_path = try b.allocator.dupe(u8, entry.path);
            try published.append(b.allocator, sub_path);
            if (std.fs.path.dirname(sub_path)) |dirname| {
                go_dir.createDirPath(io, dirname) catch |err| {
                    return step.fail("unable to make path '{f}{s}/{s}': {t}", .{ b.build_root, self.go_dir, dirname, err });
                };
            }
            const status = std.Io.Dir.updateFile(generated_dir, io, sub_path, go_dir, sub_path, .{}) catch |err| {
                return step.fail("unable to update file '{f}{s}/{s}': {t}", .{ b.build_root, self.go_dir, sub_path, err });
            };
            any_miss = any_miss or status == .stale;
        }

        var stale_walker = try go_walk.walk(go_dir, b.allocator);
        defer stale_walker.deinit();
        while (try stale_walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".go")) continue;
            for (published.items) |sub_path| {
                if (std.mem.eql(u8, sub_path, entry.path)) break;
            } else {
                // Only zigo's own output is removed; anything the user wrote in
                // the same directory carries no marker and is left alone.
                const contents = go_dir.readFileAlloc(io, entry.path, b.allocator, .limited(64 * 1024 * 1024)) catch continue;
                defer b.allocator.free(contents);
                if (!std.mem.startsWith(u8, contents, generated_marker)) continue;
                go_dir.deleteFile(io, entry.path) catch |err| {
                    return step.fail("unable to remove obsolete file '{f}{s}/{s}': {t}", .{ b.build_root, self.go_dir, entry.path, err });
                };
                any_miss = true;
            }
        }

        step.result_cached = !any_miss;
    }
};

fn isRunnableOnHost(target: std.Target, host: std.Target) bool {
    return target.cpu.arch == host.cpu.arch and target.os.tag == host.os.tag and target.abi == host.abi;
}

/// Colocation is not a separate option: naming the public package as the raw
/// package path is what colocates them.
fn resolveRawPackage(b: *std.Build, path: []const u8, go_package: []const u8) ResolvedRawPackage {
    if (std.mem.eql(u8, path, go_package)) return .{ .path = go_package, .name = go_package, .colocated = true };
    build_options.validateRawPackagePath(path) catch |err| switch (err) {
        error.InvalidPath => @panic("raw_package must be a non-empty relative slash-separated path"),
        error.InvalidComponent => @panic("raw_package must not contain empty, '.' or '..' components"),
        error.InvalidCharacter => @panic("raw_package components may contain only ASCII letters, digits, '_', '-' and '.'"),
    };
    const name = naming.snakeAlloc(b.allocator, std.fs.path.basename(path)) catch @panic("OOM");
    naming.validateGoPackageName(name) catch
        @panic("raw_package basename must normalize to a valid Go package name");
    return .{ .path = path, .name = name, .colocated = false };
}

fn sourcePath(b: *std.Build, directory: std.Build.LazyPath, child: []const u8) []const u8 {
    return switch (directory) {
        .src_path => |source| b.pathJoin(&.{ source.sub_path, child }),
        else => @panic("go_dir must be a source path"),
    };
}

fn cgoRelativePath(b: *std.Build, from: []const u8, to: []const u8) []const u8 {
    const relative = std.fs.path.relative(b.allocator, "", null, from, to) catch @panic("OOM");
    // `std.fs.path.relative` answers in the host separator, but this string is
    // baked into a generated `#cgo` flag. cgo expects forward slashes on every
    // host, and the committed bytes must not depend on where generation ran --
    // a Windows-generated `-I${SRCDIR}\..\..\zig-out\include` both differs
    // from the committed file and fails to resolve the header.
    std.mem.replaceScalar(u8, relative, std.fs.path.sep_windows, std.fs.path.sep_posix);
    return b.fmt("${{SRCDIR}}/{s}", .{relative});
}

fn joinFlags(b: *std.Build, flags: []const []const u8) []const u8 {
    return std.mem.join(b.allocator, " ", flags) catch @panic("OOM");
}

/// `-l` flags for the system libraries cgo has to name directly, plus a `-L`
/// for every search path on the module. Only `.force` libraries move to the
/// pkg-config line: `.yes` means "try pkg-config, otherwise `-lfoo`", and a
/// `#cgo pkg-config:` entry has no such fallback.
fn systemLibraryFlags(b: *std.Build, module: *std.Build.Module) []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    for (module.lib_paths.items) |path| {
        flags.append(b.allocator, b.fmt("-L{s}", .{path.getPath(b)})) catch @panic("OOM");
    }
    for (module.link_objects.items) |object| switch (object) {
        .system_lib => |library| {
            if (library.use_pkg_config == .force) continue;
            flags.append(b.allocator, b.fmt("-l{s}", .{library.name})) catch @panic("OOM");
        },
        else => {},
    };
    return joinFlags(b, flags.items);
}

/// pkg-config package names, space separated, for a `#cgo pkg-config:` line.
/// Only `.force` qualifies; see `systemLibraryFlags` for why.
fn pkgConfigLibraries(b: *std.Build, module: *std.Build.Module) []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (module.link_objects.items) |object| switch (object) {
        .system_lib => |library| {
            if (library.use_pkg_config != .force) continue;
            names.append(b.allocator, library.name) catch @panic("OOM");
        },
        else => {},
    };
    return joinFlags(b, names.items);
}

fn frameworkFlags(b: *std.Build, module: *std.Build.Module) []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    for (module.frameworks.keys(), module.frameworks.values()) |framework, framework_options| {
        flags.append(b.allocator, if (framework_options.weak) "-weak_framework" else "-framework") catch @panic("OOM");
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
    build_options: *std.Build.Module,
    dynamic_library: *std.Build.Module,
    semantic: *std.Build.Module,
    naming: *std.Build.Module,
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
    const build_options_module = b.createModule(.{
        .root_source_file = source_root.path(b, "build_options.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dynamic_library_module = b.createModule(.{
        .root_source_file = source_root.path(b, "dynamic_library.zig"),
        .target = target,
        .optimize = optimize,
    });
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
    const naming_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/naming.zig"),
        .target = target,
        .optimize = optimize,
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
        .imports = &.{
            .{ .name = "naming", .module = naming_module },
            .{ .name = "semantic", .module = semantic_module },
        },
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
            .{ .name = "naming", .module = naming_module },
            .{ .name = "abi", .module = abi_module },
            .{ .name = "diagnostic", .module = diagnostic_module },
            .{ .name = "errors_lock", .module = errors_lock_module },
        },
    });
    return .{
        .build_options = build_options_module,
        .dynamic_library = dynamic_library_module,
        .semantic = semantic_module,
        .naming = naming_module,
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
                .{ .name = "build_options", .module = modules.build_options },
                .{ .name = "dynamic_library", .module = modules.dynamic_library },
                .{ .name = "semantic", .module = modules.semantic },
                .{ .name = "naming", .module = modules.naming },
                .{ .name = "abi", .module = modules.abi },
                .{ .name = "diagnostic", .module = modules.diagnostic },
                .{ .name = "errors_lock", .module = modules.errors_lock },
                .{ .name = "abi_diff", .module = modules.abi_diff },
                .{ .name = "sync_check", .module = modules.sync_check },
            },
        }),
    });
}
