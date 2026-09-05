//! The repository's own build steps: tests, contract checks, golden generator
//! cases, and the check, snapshot and smoke steps. Consumers never import this.
const std = @import("std");
const build_options = @import("../src/build_options.zig");
const modules = @import("modules.zig");
const steps = @import("steps.zig");

/// Everything `zig build` offers this repository beyond the generator itself:
/// the unit and snapshot tests, the contract tests, the golden generator
/// cases, and the `check`, `snapshot` and `shared-library-smoke` steps. A
/// consumer's build graph never reaches any of it.
pub fn addRepositorySteps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    test_filters: []const []const u8,
    zigo: *std.Build.Module,
    generator_modules: modules.GeneratorModules,
    generator: *std.Build.Step.Compile,
) void {
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
    const reflect_coverage_module = b.createModule(.{
        .root_source_file = b.path("src/reflect/coverage.zig"),
        .target = target,
        .optimize = optimize,
        // coverage.zig shares walk.zig's binding-declaration helpers, so it
        // inherits walk.zig's own imports too.
        .imports = &.{
            .{ .name = "naming", .module = generator_modules.naming },
            .{ .name = "semantic", .module = generator_modules.semantic },
        },
    });
    const build_options_module = b.createModule(.{
        .root_source_file = b.path("src/build_options.zig"),
        .target = target,
        .optimize = optimize,
    });
    const emit_module = b.createModule(.{
        .root_source_file = b.path("src/gen/emit/emit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "naming", .module = generator_modules.naming },
            .{ .name = "semantic", .module = generator_modules.semantic },
            .{ .name = "abi", .module = generator_modules.abi },
            .{ .name = "lower", .module = generator_modules.lower },
        },
    });
    const validate_module = b.createModule(.{
        .root_source_file = b.path("src/gen/validate/validate.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = generator_modules.abi },
            .{ .name = "lower", .module = generator_modules.lower },
            .{ .name = "naming", .module = generator_modules.naming },
            .{ .name = "diagnostic", .module = generator_modules.diagnostic },
            .{ .name = "semantic", .module = generator_modules.semantic },
        },
    });
    const stream_return_module = generator_modules.stream_return;
    const lower_module = generator_modules.lower;
    const report_module = b.createModule(.{
        .root_source_file = b.path("src/gen/report.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "naming", .module = generator_modules.naming },
            .{ .name = "abi", .module = generator_modules.abi },
            .{ .name = "lower", .module = generator_modules.lower },
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
    const semantic_tests = b.addTest(.{ .root_module = generator_modules.semantic, .filters = test_filters });
    const run_semantic_tests = b.addRunArtifact(semantic_tests);
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
    const stream_return_tests = b.addTest(.{ .root_module = stream_return_module, .filters = test_filters });
    const run_stream_return_tests = b.addRunArtifact(stream_return_tests);
    const report_tests = b.addTest(.{ .root_module = report_module, .filters = test_filters });
    const run_report_tests = b.addRunArtifact(report_tests);
    const doctor_tests = b.addTest(.{ .root_module = doctor_module, .filters = test_filters });
    const run_doctor_tests = b.addRunArtifact(doctor_tests);
    const coverage_tests = b.addTest(.{ .root_module = reflect_coverage_module, .filters = test_filters });
    const run_coverage_tests = b.addRunArtifact(coverage_tests);
    const dynamic_library_tests = b.addTest(.{ .root_module = generator_modules.dynamic_library, .filters = test_filters });
    const run_dynamic_library_tests = b.addRunArtifact(dynamic_library_tests);
    const test_step = b.step("test", "Run unit and snapshot harness tests");
    testTransitiveLinkInputCollection(b, target, optimize);
    const godoc_audit = b.addSystemCommand(&.{ "go", "run", "./tests/godoc_audit/main.go" });
    godoc_audit.addArgs(&.{
        "tests/generator_cases/atomic_value/expected",
        "tests/generator_cases/by_value_opaque/expected",
        "tests/generator_cases/callback_error/expected",
        "tests/generator_cases/callback_error_purego/expected",
        "tests/generator_cases/callback_failure_result/expected",
        "tests/generator_cases/callback_failure_result_purego/expected",
        "tests/generator_cases/cancel/expected",
        "tests/generator_cases/cancel_purego/expected",
        "tests/generator_cases/complex/expected",
        "tests/generator_cases/dependent_handle/expected",
        "tests/generator_cases/dependent_handle_purego/expected",
        "tests/generator_cases/injection/expected",
        "tests/generator_cases/narrow_int/expected",
        "tests/generator_cases/nested_namespace/expected",
        "tests/generator_cases/optional/expected",
        "tests/generator_cases/optional_purego/expected",
        "tests/generator_cases/optional_slice/expected",
        "tests/generator_cases/optional_slice_purego/expected",
        "tests/generator_cases/optional_return_checks/expected",
        "tests/generator_cases/optional_return_checks_purego/expected",
        "tests/generator_cases/open_enum/expected",
        "tests/generator_cases/open_enum_purego/expected",
        "tests/generator_cases/receiver_name_clash/expected",
        "tests/generator_cases/receiver_name_clash_purego/expected",
        "tests/generator_cases/root_constructor/expected",
        "tests/generator_cases/scalar/expected",
        "tests/generator_cases/sub_package_field_clash/expected",
        "tests/generator_cases/sub_packages/expected",
        "tests/generator_cases/sub_packages_purego/expected",
        "tests/generator_cases/union_snapshot/expected",
        "tests/generator_cases/value_struct/expected",
        "examples/01-scalar/go",
        "examples/02-errors/go",
        "examples/03-opaque/go",
        "examples/03-opaque/go-purego",
        "examples/04-callback/go",
        "examples/05-pipeline/go",
        "examples/06-camel-case/go",
        "examples/07-event-queue/go",
        "examples/08-telemetry-hub/go",
        "examples/09-type-relations/go",
        "examples/10-tagged-union/go",
        "examples/10-tagged-union/go-purego",
        "examples/11-io-streams/go",
        "examples/11-io-streams/go-purego",
        "examples/12-materialized/go",
        "examples/12-materialized/go-purego",
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
        "examples/11-io-streams",
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
    test_step.dependOn(&run_semantic_tests.step);
    test_step.dependOn(&run_errors_lock_tests.step);
    test_step.dependOn(&run_diagnostic_tests.step);
    test_step.dependOn(&run_sync_check_tests.step);
    test_step.dependOn(&run_cli_tests.step);
    test_step.dependOn(&run_build_options_tests.step);
    test_step.dependOn(&run_emit_tests.step);
    test_step.dependOn(&run_validate_tests.step);
    test_step.dependOn(&run_lower_tests.step);
    test_step.dependOn(&run_stream_return_tests.step);
    test_step.dependOn(&run_report_tests.step);
    test_step.dependOn(&run_doctor_tests.step);
    test_step.dependOn(&run_coverage_tests.step);
    test_step.dependOn(&run_dynamic_library_tests.step);
    addProcessContractTests(b, test_step, generator);
    addPkgConfigContractTests(b, test_step);

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
    check_step.dependOn(&semantic_tests.step);
    check_step.dependOn(&errors_lock_tests.step);
    check_step.dependOn(&diagnostic_tests.step);
    check_step.dependOn(&sync_check_tests.step);
    check_step.dependOn(&cli_tests.step);
    check_step.dependOn(&build_options_tests.step);
    check_step.dependOn(&emit_tests.step);
    check_step.dependOn(&validate_tests.step);
    check_step.dependOn(&lower_tests.step);
    check_step.dependOn(&stream_return_tests.step);
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
    invalid_semantic.expectStdErrMatch("error[ZIGO036]: C identifier `zg_lookup_id` collides between function `lookupID` and function `lookup_id`");
    test_step.dependOn(&invalid_semantic.step);

    // An unsupported type used to leave validation as a bare error, which the
    // CLI reported as a stack trace. It reaches the user as a diagnostic now.
    const unsupported_width = b.addRunArtifact(generator);
    unsupported_width.setName("CLI contract (unsupported integer width)");
    unsupported_width.addArgs(&.{ "generate", "--semantic" });
    unsupported_width.addFileArg(b.path("tests/fixtures/zigo018.json"));
    unsupported_width.addArg("--output");
    _ = unsupported_width.addOutputDirectoryArg("unsupported-width-output");
    unsupported_width.addArgs(&.{ "--package", "bad" });
    unsupported_width.expectExitCode(1);
    unsupported_width.expectStdErrMatch("error[ZIGO045]: narrow integer slice parameter `cps` needs temporary storage");
    unsupported_width.expectStdErrMatch("--> semantic.json (unicode.codepointWidths)");
    test_step.dependOn(&unsupported_width.step);

    // A function with a `source` location (from `names.zig`'s AST scan)
    // points a diagnostic at `bindings.zig:LINE:COL` instead of the
    // `semantic.json` fallback the case above uses.
    const located_diagnostic = b.addRunArtifact(generator);
    located_diagnostic.setName("CLI contract (diagnostic source location)");
    located_diagnostic.addArgs(&.{ "generate", "--semantic" });
    located_diagnostic.addFileArg(b.path("tests/fixtures/zigo025.json"));
    located_diagnostic.addArg("--output");
    _ = located_diagnostic.addOutputDirectoryArg("located-diagnostic-output");
    located_diagnostic.addArgs(&.{ "--package", "bad" });
    located_diagnostic.expectExitCode(1);
    located_diagnostic.expectStdErrMatch("error[ZIGO045]: narrow integer slice parameter `cps` needs temporary storage");
    located_diagnostic.expectStdErrMatch("--> src/bindings.zig:12:5 (unicode.codepointWidths)");
    test_step.dependOn(&located_diagnostic.step);

    // A name reflection derived from `@typeName` can be something Go cannot
    // parse. The diagnostic has to arrive before generation, not as a gofmt
    // failure over a file that should never have been written.
    const invalid_identifier = b.addRunArtifact(generator);
    invalid_identifier.setName("CLI contract (invalid Go identifier)");
    invalid_identifier.addArgs(&.{ "generate", "--semantic" });
    invalid_identifier.addFileArg(b.path("tests/fixtures/zigo021.json"));
    invalid_identifier.addArg("--output");
    _ = invalid_identifier.addOutputDirectoryArg("invalid-identifier-output");
    invalid_identifier.addArgs(&.{ "--package", "bad" });
    invalid_identifier.expectExitCode(1);
    invalid_identifier.expectStdErrMatch("error[ZIGO021]: registered type name `4])` from Zig type `vt.lib.Enum(");
    invalid_identifier.expectStdErrMatch("hint: register the type in `.types` with an explicit `.name`");
    test_step.dependOn(&invalid_identifier.step);

    // Public Go names drop the owning namespace, so two namespace functions
    // with the same last segment collide in Go even though their C symbols
    // (which do carry the namespace) do not, and ZIGO007 lets them through.
    const public_name_collision = b.addRunArtifact(generator);
    public_name_collision.setName("CLI contract (public name collision)");
    public_name_collision.addArgs(&.{ "generate", "--semantic" });
    public_name_collision.addFileArg(b.path("tests/fixtures/zigo024.json"));
    public_name_collision.addArg("--output");
    _ = public_name_collision.addOutputDirectoryArg("public-name-collision-output");
    public_name_collision.addArgs(&.{ "--package", "bad" });
    public_name_collision.expectExitCode(1);
    public_name_collision.expectStdErrMatch("error[ZIGO024]: public Go name `Open` collides between `File.open` and `Socket.open`");
    test_step.dependOn(&public_name_collision.step);

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

    // `abi-diff` lowers both documents, and lowering assumes a validated one:
    // an undeclared type reference used to reach `unreachable` inside `lower`
    // and abort with a stack trace instead of naming the offending file.
    const undeclared_abi = b.addRunArtifact(generator);
    undeclared_abi.setName("CLI contract (abi-diff with an undeclared type)");
    undeclared_abi.addArgs(&.{ "abi-diff", "--base" });
    undeclared_abi.addFileArg(b.path("tests/fixtures/cli/abi/undeclared_base.json"));
    undeclared_abi.addArg("--current");
    undeclared_abi.addFileArg(b.path("tests/fixtures/cli/abi/value_struct_base.json"));
    undeclared_abi.expectExitCode(1);
    undeclared_abi.expectStdErrMatch("error[ZIGO010]: semantic document contains an unresolved or incompatible declaration reference");
    undeclared_abi.expectStdErrMatch("undeclared_base.json (configure)");
    test_step.dependOn(&undeclared_abi.step);

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
    invalid_project.setName("invalid project contract (ZIGO036)");
    invalid_project.setCwd(b.path("tests/fixtures/invalid-project"));
    invalid_project.has_side_effects = true;
    invalid_project.expectExitCode(1);
    invalid_project.expectStdErrMatch("error[ZIGO036]: C identifier `zg_lookup_id` collides between function `lookupID` and function `lookup_id`");
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

fn addPkgConfigContractTests(b: *std.Build, test_step: *std.Build.Step) void {
    const fixture = "tests/fixtures/pkg-config/build.zig";
    const resolves_fallback = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "--build-file", fixture, "resolve" });
    resolves_fallback.setName("pkg-config resolves the lib-prefixed fallback");
    prependTestPath(b, resolves_fallback, "tests/fixtures/pkg-config/bin");
    resolves_fallback.expectExitCode(0);
    resolves_fallback.expectStdOutEqual("libavformat");
    test_step.dependOn(&resolves_fallback.step);

    const rejects_missing = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "--build-file", fixture, "resolve" });
    rejects_missing.setName("pkg-config rejects an unresolved forced library");
    prependTestPath(b, rejects_missing, "tests/fixtures/pkg-config/bin-none");
    rejects_missing.expectExitCode(1);
    rejects_missing.expectStdErrMatch("pkg-config could not resolve library 'avformat' declared by module 'src/dependency.zig'");
    test_step.dependOn(&rejects_missing.step);

    const unavailable = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "--build-file", fixture, "resolve" });
    unavailable.setName("missing pkg-config keeps the original name");
    unavailable.setEnvironmentVariable("PKG_CONFIG", b.pathFromRoot("tests/fixtures/pkg-config/does-not-exist"));
    unavailable.expectExitCode(0);
    unavailable.expectStdOutEqual("avformat");
    unavailable.expectStdErrMatch("pkg-config is unavailable; keeping original package name 'avformat'");
    test_step.dependOn(&unavailable.step);
}

fn prependTestPath(b: *std.Build, run: *std.Build.Step.Run, directory: []const u8) void {
    const current = b.graph.environ_map.get("PATH") orelse "";
    run.setEnvironmentVariable("PATH", b.fmt("{s}{c}{s}", .{ b.pathFromRoot(directory), std.fs.path.delimiter, current }));
}

/// Build-graph regression test: a dependency reached through both sides of a
/// diamond contributes each cgo flag once.
fn testTransitiveLinkInputCollection(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const dependency = b.createModule(.{ .target = target, .optimize = optimize });
    dependency.addLibraryPath(b.path("tests/fixtures/transitive-link-inputs/lib"));
    dependency.linkSystemLibrary("zigo_transitive_test", .{});
    dependency.linkFramework("ZigoTransitiveTest", .{});

    const left = b.createModule(.{ .target = target, .optimize = optimize });
    left.addImport("dependency", dependency);
    const right = b.createModule(.{ .target = target, .optimize = optimize });
    right.addImport("dependency", dependency);
    const root = b.createModule(.{ .target = target, .optimize = optimize });
    root.addImport("left", left);
    root.addImport("right", right);

    var inputs: steps.LinkInputCollector = .{};
    inputs.collect(b, root);
    const system_flags = steps.systemLibraryFlags(b, &inputs);
    const framework_flags = steps.frameworkFlags(b, &inputs);
    std.debug.assert(std.mem.count(u8, system_flags, "-L") == 1);
    std.debug.assert(std.mem.count(u8, system_flags, "-lzigo_transitive_test") == 1);
    std.debug.assert(std.mem.count(u8, framework_flags, "-framework ZigoTransitiveTest") == 1);
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
        // A directory argument only puts its resolved path in the manifest,
        // so editing a case's `semantic.json`, `options.json` or an expected
        // file left the step cached while the runner would have produced a
        // different tree. Every file the runner reads is declared by name.
        const files = caseFiles(b, directory, name);
        for (files) |file| run.addFileInput(cases.path(b, file));
        test_step.dependOn(&run.step);
        addGoldenArtifactChecks(b, test_step, cases.path(b, name), name, files);
    }
}

/// Every file under one case directory, as paths relative to
/// `tests/generator_cases`, sorted so the manifest does not depend on the
/// order the file system happens to hand them back in.
fn caseFiles(b: *std.Build, cases: std.Io.Dir, name: []const u8) []const []const u8 {
    var case = cases.openDir(b.graph.io, name, .{ .iterate = true }) catch |err|
        std.debug.panic("unable to open generator case '{s}': {}", .{ name, err });
    defer case.close(b.graph.io);

    var files: std.ArrayList([]const u8) = .empty;
    var walker = case.walk(b.allocator) catch @panic("OOM");
    defer walker.deinit();
    while (walker.next(b.graph.io) catch |err|
        std.debug.panic("unable to enumerate generator case '{s}': {}", .{ name, err })) |entry|
    {
        if (entry.kind != .file) continue;
        files.append(b.allocator, b.pathJoin(&.{ name, entry.path })) catch @panic("OOM");
    }
    std.mem.sort([]const u8, files.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);
    return files.toOwnedSlice(b.allocator) catch @panic("OOM");
}

/// Compiles the committed golden native artifacts. The tree comparison alone
/// only proves the bytes are stable, so a `panic.c` that does not compile can be
/// pinned as the expectation; this catches that before an example does.
fn addGoldenArtifactChecks(
    b: *std.Build,
    test_step: *std.Build.Step,
    case: std.Build.LazyPath,
    name: []const u8,
    files: []const []const u8,
) void {
    const cases = b.path("tests/generator_cases");
    const expected = case.path(b, "expected");
    const compile_panic = b.addSystemCommand(&.{ b.graph.zig_exe, "cc", "-c" });
    compile_panic.setName(b.fmt("golden panic.c compiles ({s})", .{name}));
    // The include directory is a bare path argument in the manifest, so the
    // headers `panic.c` includes are declared as inputs on their own.
    compile_panic.addPrefixedDirectoryArg("-I", expected);
    const header_prefix = b.pathJoin(&.{ name, "expected" });
    for (files) |file| {
        if (!std.mem.startsWith(u8, file, header_prefix)) continue;
        if (!std.mem.endsWith(u8, file, ".h")) continue;
        compile_panic.addFileInput(cases.path(b, file));
    }
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

    // A case that ships a `roundtrip.zig` runs it against the golden shim.
    if (hasCaseFile(files, name, "roundtrip.zig")) {
        // The target's release path frees through `std.heap.c_allocator`, as
        // the generated shim does, so the test links libc explicitly: macOS
        // links it implicitly and hides the omission, Linux does not.
        const roundtrip = b.addSystemCommand(&.{ b.graph.zig_exe, "test", "-lc", "--dep", "zigo_target" });
        roundtrip.setName(b.fmt("{s} walker round trip", .{name}));
        roundtrip.addPrefixedFileArg("-Mroot=", case.path(b, "roundtrip.zig"));
        roundtrip.addPrefixedFileArg("-Mzigo_target=", case.path(b, "target.zig"));
        roundtrip.addFileInput(expected.path(b, "shim.zig"));
        roundtrip.expectExitCode(0);
        test_step.dependOn(&roundtrip.step);
    }
}

fn hasCaseFile(files: []const []const u8, case_name: []const u8, file_name: []const u8) bool {
    for (files) |file| {
        if (file.len != case_name.len + 1 + file_name.len) continue;
        if (std.mem.startsWith(u8, file, case_name) and file[case_name.len] == '/' and std.mem.endsWith(u8, file, file_name)) return true;
    }
    return false;
}

fn matchesAnyFilter(name: []const u8, filters: []const []const u8) bool {
    if (filters.len == 0) return true;
    for (filters) |filter| if (std.mem.find(u8, name, filter) != null) return true;
    return false;
}
