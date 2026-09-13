//! A zigo generator plugin, packaged the way any other one is: a module named
//! `plugin` whose root file declares `pub const plugin`.
//!
//! The generator itself never reads this file: `addGoBindings` compiles
//! `src/plugin.zig` against its own `plugin`, `abi`, `semantic` and
//! `diagnostic` modules, so the plugin and the generator that runs it speak
//! about one set of types rather than two identical-looking copies. What this
//! build offers is `zig build test`: the plugin's own unit tests, compiled
//! against the same contract modules zigo publishes.
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
    b.step("test", "Run the plugin's unit tests").dependOn(&b.addRunArtifact(tests).step);
}
