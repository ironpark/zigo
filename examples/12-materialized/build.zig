const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const materialized = b.addModule("materialized", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    materialized.link_libc = true;
    const tests = b.addTest(.{ .root_module = materialized });
    b.step("test", "Run the Zig materialized-tree tests").dependOn(&b.addRunArtifact(tests).step);

    _ = zigo.addGoBindings(b, .{
        .name = "materialized",
        .module = materialized,
        .layout = .{ .go_module = "example.com/zigo/materialized" },
        .target = target,
        .optimize = optimize,
    });

    _ = zigo.addGoBindings(b, .{
        .name = "materialized",
        .module = materialized,
        .go_dir = b.path("go-purego"),
        .layout = .{ .go_module = "example.com/zigo/materialized-purego" },
        .target = target,
        .optimize = optimize,
        .link = .{ .purego = .{} },
        .standard_steps = .{ .variant = "purego" },
    });
}
