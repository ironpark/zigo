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
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generator = addGenerator(b, b.path("src/main.zig"), target, optimize);
    b.installArtifact(generator);

    const semantic_module = b.createModule(.{
        .root_source_file = b.path("src/gen/ir/semantic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const abi_module = b.createModule(.{
        .root_source_file = b.path("src/gen/ir/abi.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = semantic_module }},
    });
    const reflect_walk_module = b.createModule(.{
        .root_source_file = b.path("src/reflect/walk.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = semantic_module }},
    });
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigo", .module = zigo },
            .{ .name = "diagnostic", .module = b.createModule(.{
                .root_source_file = b.path("src/gen/diagnostic.zig"),
                .target = target,
                .optimize = optimize,
            }) },
            .{ .name = "semantic", .module = semantic_module },
            .{ .name = "errors_lock", .module = b.createModule(.{
                .root_source_file = b.path("src/gen/ir/errors_lock.zig"),
                .target = target,
                .optimize = optimize,
            }) },
            .{ .name = "abi", .module = abi_module },
            .{ .name = "reflect_walk", .module = reflect_walk_module },
        },
    }) });
    const run_tests = b.addRunArtifact(tests);
    const generator_test_semantic = b.createModule(.{
        .root_source_file = b.path("src/gen/ir/semantic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generator_test_abi = b.createModule(.{
        .root_source_file = b.path("src/gen/ir/abi.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = generator_test_semantic }},
    });
    const generator_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/gen/generator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "semantic", .module = generator_test_semantic },
            .{ .name = "abi", .module = generator_test_abi },
            .{ .name = "diagnostic", .module = b.createModule(.{
                .root_source_file = b.path("src/gen/diagnostic.zig"),
                .target = target,
                .optimize = optimize,
            }) },
            .{ .name = "errors_lock", .module = b.createModule(.{
                .root_source_file = b.path("src/gen/ir/errors_lock.zig"),
                .target = target,
                .optimize = optimize,
            }) },
        },
    }) });
    const run_generator_tests = b.addRunArtifact(generator_tests);
    const test_step = b.step("test", "Run unit and snapshot harness tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_generator_tests.step);

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

/// Adds the Go-binding pipeline to a consuming build graph.
pub fn addGoBindings(b: *std.Build, options: Options) GoBindings {
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
    const semantic_json = semantic_run.captureStdOut(.{ .basename = "semantic.json", .trim_whitespace = .none });

    const raw_source_dir = options.go_dir.path(b, "internal/raw").getPath(b);
    const include_dir = cgoRelativePath(b, raw_source_dir, b.pathJoin(&.{ b.install_path, "include" }));
    const library_dir = cgoRelativePath(b, raw_source_dir, b.pathJoin(&.{ b.install_path, "lib" }));
    const generate = b.addRunArtifact(generator);
    generate.addFileArg(semantic_json);
    const generated_dir = generate.addOutputDirectoryArg("bindings");
    generate.addArgs(&.{ options.name, options.prefix, options.go_module, include_dir, library_dir });
    const errors_lock_path = "zigo/errors.lock.json";
    const has_errors_lock = blk: {
        b.build_root.handle.access(b.graph.io, errors_lock_path, .{}) catch |err| switch (err) {
            error.FileNotFound => break :blk false,
            else => @panic("unable to inspect errors.lock.json"),
        };
        break :blk true;
    };
    if (has_errors_lock) generate.addFileArg(b.path(errors_lock_path));

    const check = b.addRunArtifact(generator);
    check.addArg("--check-stub");
    const abi_check = b.addRunArtifact(generator);
    abi_check.addArgs(&.{ "--abi-check-stub", options.abi_base });

    const shim_module = b.createModule(.{
        .root_source_file = generated_dir.path(b, "shim.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{.{ .name = "zigo_target", .module = options.module }},
    });
    const lib = b.addLibrary(.{
        .name = b.fmt("{s}_zigo", .{options.name}),
        .linkage = switch (options.link_mode) {
            .static => .static,
            .dynamic => .dynamic,
        },
        .root_module = shim_module,
    });
    const install_lib = b.addInstallArtifact(lib, .{});
    const header_name = b.fmt("zigo_{s}.h", .{options.name});
    const install_header = b.addInstallHeaderFile(generated_dir.path(b, header_name), header_name);
    const update = b.addUpdateSourceFiles();
    update.addCopyFileToSource(generated_dir.path(b, "internal/raw/cgo.go"), sourcePath(b, options.go_dir, "internal/raw/cgo.go"));
    update.addCopyFileToSource(generated_dir.path(b, b.fmt("{s}/generated.go", .{options.name})), sourcePath(b, options.go_dir, b.fmt("{s}/generated.go", .{options.name})));
    update.addCopyFileToSource(generated_dir.path(b, "errors.lock.json"), errors_lock_path);
    const go_mod_path = sourcePath(b, options.go_dir, "go.mod");
    b.build_root.handle.access(b.graph.io, go_mod_path, .{}) catch |err| switch (err) {
        error.FileNotFound => update.addBytesToSource(b.fmt("module {s}\n\ngo 1.23\n", .{options.go_module}), go_mod_path),
        else => @panic("unable to inspect go.mod"),
    };
    update.step.dependOn(&install_lib.step);
    update.step.dependOn(&install_header.step);
    check.step.dependOn(&lib.step);
    abi_check.step.dependOn(&lib.step);

    _ = options.target;
    _ = options.optimize;
    _ = options.prefix;
    _ = options.cgo_flags;
    _ = layout_json;

    return .{ .update = update, .check = check, .abi_check = abi_check, .lib = lib, .semantic_json = semantic_json };
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

fn addGenerator(
    b: *std.Build,
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const semantic_module = b.createModule(.{
        .root_source_file = root_source_file.dirname().path(b, "gen/ir/semantic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const abi_module = b.createModule(.{
        .root_source_file = root_source_file.dirname().path(b, "gen/ir/abi.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = semantic_module }},
    });
    const diagnostic_module = b.createModule(.{
        .root_source_file = root_source_file.dirname().path(b, "gen/diagnostic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const errors_lock_module = b.createModule(.{
        .root_source_file = root_source_file.dirname().path(b, "gen/ir/errors_lock.zig"),
        .target = target,
        .optimize = optimize,
    });
    return b.addExecutable(.{
        .name = "zigo-gen",
        .root_module = b.createModule(.{
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "semantic", .module = semantic_module },
                .{ .name = "abi", .module = abi_module },
                .{ .name = "diagnostic", .module = diagnostic_module },
                .{ .name = "errors_lock", .module = errors_lock_module },
            },
        }),
    });
}
