//! A zigo generator plugin, packaged the way any other one is: a module named
//! `plugin` whose root file declares `pub const plugin`.
//!
//! This one ships a second file. `src/native.zig` is not part of the plugin
//! module at all -- the generated shim compiles it, against nothing but `std`
//! -- so the build below only tests it, while the consuming build names it
//! through `PluginModule.native_sources`.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zigo = b.dependency("zigo", .{ .target = target, .optimize = optimize });
    const module = b.addModule("plugin", .{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "plugin", .module = zigo.module("plugin") },
            .{ .name = "abi", .module = zigo.module("abi") },
            .{ .name = "semantic", .module = zigo.module("semantic") },
            .{ .name = "diagnostic", .module = zigo.module("diagnostic") },
        },
    });
    const tests = b.addTest(.{ .root_module = module });
    const native = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/native.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const step = b.step("test", "Run the plugin's unit tests");
    step.dependOn(&b.addRunArtifact(tests).step);
    step.dependOn(&b.addRunArtifact(native).step);
}
