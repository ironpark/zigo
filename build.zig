const std = @import("std");

pub const CgoFlags = struct {
    cflags: []const []const u8 = &.{},
    ldflags: []const []const u8 = &.{},
};

pub const LinkMode = enum { static, dynamic };

pub const Options = struct {
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
    abi_base: []const u8 = "HEAD",
};

pub const GoBindings = struct {
    update: *std.Build.Step.UpdateSourceFiles,
    check: *std.Build.Step.Run,
    abi_check: *std.Build.Step.Run,
    lib: *std.Build.Step.Compile,
    semantic_json: std.Build.LazyPath,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zigo = b.addModule("zigo", .{
        .root_source_file = packagePath("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generator = addGenerator(b, packagePath("src/main.zig"), target, optimize);
    b.installArtifact(generator);

    const semantic_module = b.createModule(.{
        .root_source_file = packagePath("src/gen/ir/semantic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const abi_module = b.createModule(.{
        .root_source_file = packagePath("src/gen/ir/abi.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = semantic_module }},
    });
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = packagePath("tests/test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigo", .module = zigo },
            .{ .name = "diagnostic", .module = b.createModule(.{
                .root_source_file = packagePath("src/gen/diagnostic.zig"),
                .target = target,
                .optimize = optimize,
            }) },
            .{ .name = "semantic", .module = semantic_module },
            .{ .name = "errors_lock", .module = b.createModule(.{
                .root_source_file = packagePath("src/gen/ir/errors_lock.zig"),
                .target = target,
                .optimize = optimize,
            }) },
            .{ .name = "abi", .module = abi_module },
        },
    }) });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit and snapshot harness tests");
    test_step.dependOn(&run_tests.step);

    const snapshot_exe = b.addExecutable(.{
        .name = "zigo-snapshot",
        .root_module = b.createModule(.{
            .root_source_file = packagePath("tests/snapshot_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_snapshot = b.addRunArtifact(snapshot_exe);
    if (b.args) |args| run_snapshot.addArgs(args);
    const snapshot_step = b.step("snapshot", "Compare or update a snapshot directory tree");
    snapshot_step.dependOn(&run_snapshot.step);
}

/// Adds the Go-binding pipeline to a consuming build graph.
pub fn addGoBindings(b: *std.Build, options: Options) GoBindings {
    const zigo_dependency = b.dependencyFromBuildZig(@This(), .{});
    const generator = addGenerator(b, zigo_dependency.path("src/main.zig"), b.graph.host, .Debug);
    const semantic_run = b.addRunArtifact(generator);
    semantic_run.addArg("--semantic-stub");
    const semantic_json = semantic_run.captureStdOut(.{ .basename = "semantic.json", .trim_whitespace = .none });

    const check = b.addRunArtifact(generator);
    check.addArg("--check-stub");
    const abi_check = b.addRunArtifact(generator);
    abi_check.addArgs(&.{ "--abi-check-stub", options.abi_base });

    const lib = b.addLibrary(.{
        .name = b.fmt("{s}_zigo", .{options.name}),
        .linkage = switch (options.link_mode) {
            .static => .static,
            .dynamic => .dynamic,
        },
        .root_module = options.module,
    });
    const update = b.addUpdateSourceFiles();
    update.step.dependOn(&semantic_run.step);
    update.step.dependOn(&lib.step);
    check.step.dependOn(&lib.step);
    abi_check.step.dependOn(&lib.step);

    _ = options.bindings;
    _ = options.go_dir;
    _ = options.go_module;
    _ = options.target;
    _ = options.optimize;
    _ = options.prefix;
    _ = options.cgo_flags;

    return .{ .update = update, .check = check, .abi_check = abi_check, .lib = lib, .semantic_json = semantic_json };
}

fn addGenerator(
    b: *std.Build,
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "zigo-gen",
        .root_module = b.createModule(.{
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
        }),
    });
}

fn packagePath(comptime sub_path: []const u8) std.Build.LazyPath {
    const package_root = comptime std.fs.path.dirname(@src().file) orelse ".";
    return .{ .cwd_relative = package_root ++ "/" ++ sub_path };
}
