const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const library = b.addModule("calculator", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = library });
    b.step("test", "Run the Zig tests").dependOn(&b.addRunArtifact(tests).step);

    // A generator plugin with a native half. `buildinfo` ships a Zig source
    // that the generated shim compiles beside the bound library, and exports
    // one C symbol out of it; the Go package gets `BuildInfo()` on top.
    // `native_sources` repeats what the plugin's own `native.sources`
    // declares, because only `build.zig` can turn a path into a module.
    const buildinfo: zigo.PluginModule = .{
        .name = "zigo_buildinfo",
        .root_source_file = b.dependency("zigo_buildinfo", .{}).path("src/plugin.zig"),
        .native_sources = &.{.{ .module = "buildinfo_native", .path = "native.zig" }},
    };

    _ = zigo.addGoBindings(b, .{
        .name = "calculator",
        .module = library,
        .layout = .{ .go_module = "example.com/zigo/quick-start" },
        .target = target,
        .optimize = optimize,
        .plugins = &.{buildinfo},
    });
}
