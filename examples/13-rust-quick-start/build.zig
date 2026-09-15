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

    // A generator plugin. `enumkit` fills both render slots, so the same
    // entry that adds `ModeValues()` to a Go binding set adds
    // `Rounding::values()` to this crate.
    const enumkit: zigo.PluginModule = .{
        .name = "zigo_enumkit",
        .root_source_file = b.dependency("zigo_enumkit", .{}).path("src/plugin.zig"),
    };

    _ = zigo.addRustBindings(b, .{
        .name = "calculator",
        .module = library,
        .rust_dir = b.path("rust"),
        .target = target,
        .optimize = optimize,
        .plugins = &.{enumkit},
    });
}
