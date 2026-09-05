//! The generator executable and the module graph behind it, shared by this
//! repository's build and by `addGoBindings` in a consumer's build.
const std = @import("std");
const build_options = @import("../src/build_options.zig");
const naming = @import("../src/gen/naming.zig");

pub fn addGenerator(
    b: *std.Build,
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const modules = createGeneratorModules(b, root_source_file.dirname(), target, optimize);
    return addGeneratorWithModules(b, root_source_file, target, optimize, modules);
}

pub const GeneratorModules = struct {
    build_options: *std.Build.Module,
    dynamic_library: *std.Build.Module,
    semantic: *std.Build.Module,
    naming: *std.Build.Module,
    abi: *std.Build.Module,
    diagnostic: *std.Build.Module,
    errors_lock: *std.Build.Module,
    abi_diff: *std.Build.Module,
    lower: *std.Build.Module,
    stream_return: *std.Build.Module,
    sync_check: *std.Build.Module,
    generator: *std.Build.Module,
};

pub fn createGeneratorModules(
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
    const naming_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/naming.zig"),
        .target = target,
        .optimize = optimize,
    });
    const semantic_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/ir/semantic.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "naming", .module = naming_module }},
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
    const gen_stream_return_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/stream_return.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "semantic", .module = semantic_module }},
    });
    const gen_lower_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/lower.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "naming", .module = naming_module },
            .{ .name = "abi", .module = abi_module },
            .{ .name = "semantic", .module = semantic_module },
        },
    });
    const abi_diff_module = b.createModule(.{
        .root_source_file = source_root.path(b, "gen/abi_diff.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "naming", .module = naming_module },
            .{ .name = "abi", .module = abi_module },
            .{ .name = "lower", .module = gen_lower_module },
            .{ .name = "stream_return", .module = gen_stream_return_module },
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
            .{ .name = "lower", .module = gen_lower_module },
            .{ .name = "stream_return", .module = gen_stream_return_module },
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
        .lower = gen_lower_module,
        .stream_return = gen_stream_return_module,
        .sync_check = sync_check_module,
        .generator = generator_module,
    };
}

pub fn addGeneratorWithModules(
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
                .{ .name = "lower", .module = modules.lower },
                .{ .name = "stream_return", .module = modules.stream_return },
                .{ .name = "sync_check", .module = modules.sync_check },
            },
        }),
    });
}
