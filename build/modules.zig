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
    plugins: []const std.Build.LazyPath,
) *std.Build.Step.Compile {
    const modules = createGeneratorModules(b, root_source_file.dirname(), target, optimize, plugins);
    return addGeneratorWithModules(b, root_source_file, target, optimize, modules);
}

pub const GeneratorModules = struct {
    build_options: *std.Build.Module,
    dynamic_library: *std.Build.Module,
    semantic: *std.Build.Module,
    naming: *std.Build.Module,
    abi: *std.Build.Module,
    diagnostic: *std.Build.Module,
    plugin: *std.Build.Module,
    plugin_registry: *std.Build.Module,
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
    plugins: []const std.Build.LazyPath,
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
    // The plugin contract is its own module: a plugin package compiles
    // against it alone, so it cannot depend on generator internals and the
    // generator cannot depend on a plugin's.
    const plugin_module = b.createModule(.{
        .root_source_file = source_root.path(b, "plugin.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "naming", .module = naming_module },
            .{ .name = "abi", .module = abi_module },
            .{ .name = "semantic", .module = semantic_module },
            .{ .name = "diagnostic", .module = diagnostic_module },
        },
    });
    // A plugin is taken as a source path, not as a module: the generator
    // compiles it against its own `plugin`, `abi` and `semantic`, and two
    // modules built from the same files are different types in Zig. A shared
    // module would have the plugin and the generator running it talk about
    // two `Plugin`s that only look alike.
    const plugin_modules = b.allocator.alloc(*std.Build.Module, plugins.len) catch @panic("OOM");
    for (plugins, plugin_modules) |root, *module| {
        module.* = b.createModule(.{
            .root_source_file = root,
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "plugin", .module = plugin_module },
                .{ .name = "abi", .module = abi_module },
                .{ .name = "semantic", .module = semantic_module },
                .{ .name = "diagnostic", .module = diagnostic_module },
                .{ .name = "naming", .module = naming_module },
            },
        });
    }
    const plugin_registry_module = createPluginRegistry(b, target, optimize, plugin_module, plugin_modules);
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
            .{ .name = "plugin", .module = plugin_module },
            .{ .name = "plugin_registry", .module = plugin_registry_module },
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
        .plugin = plugin_module,
        .plugin_registry = plugin_registry_module,
        .errors_lock = errors_lock_module,
        .abi_diff = abi_diff_module,
        .lower = gen_lower_module,
        .stream_return = gen_stream_return_module,
        .sync_check = sync_check_module,
        .generator = generator_module,
    };
}

/// The `plugin_registry` module the generator's in-tree registry imports: a
/// generated file naming the plugin modules the consuming build listed. It is
/// created even when there are none, so `registry.zig` has one spelling either
/// way and a build that lists no plugin costs one empty file.
fn createPluginRegistry(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    plugin_module: *std.Build.Module,
    plugins: []const *std.Build.Module,
) *std.Build.Module {
    var source: std.ArrayList(u8) = .empty;
    source.appendSlice(b.allocator,
        \\//! Generated by zigo's build integration: the plugins the consuming
        \\//! build passed to `addGoBindings(.plugins)`, in the order it listed
        \\//! them. Each module's root file declares `pub const plugin`.
        \\const plugin = @import("plugin");
        \\
        \\pub const plugins: []const plugin.Plugin = &.{
        \\
    ) catch @panic("OOM");
    for (plugins, 0..) |_, index| {
        source.appendSlice(b.allocator, b.fmt("    @import(\"p{d}\").plugin,\n", .{index})) catch @panic("OOM");
    }
    source.appendSlice(b.allocator, "};\n") catch @panic("OOM");
    const written = b.addWriteFiles().add("plugin_registry.zig", source.items);
    const module = b.createModule(.{
        .root_source_file = written,
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "plugin", .module = plugin_module }},
    });
    for (plugins, 0..) |entry, index| {
        module.addImport(b.fmt("p{d}", .{index}), entry);
    }
    return module;
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
                .{ .name = "plugin", .module = modules.plugin },
                .{ .name = "plugin_registry", .module = modules.plugin_registry },
                .{ .name = "stream_return", .module = modules.stream_return },
                .{ .name = "sync_check", .module = modules.sync_check },
            },
        }),
    });
}
