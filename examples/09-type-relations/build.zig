const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const type_relations = b.addModule("type_relations", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = type_relations });
    b.step("test", "Run the Zig multi-type tests").dependOn(&b.addRunArtifact(tests).step);

    _ = zigo.addGoBindings(b, .{
        .name = "type_relations",
        .module = type_relations,
        .layout = .{ .go_module = "example.com/zigo/type-relations" },
        .target = target,
        .optimize = optimize,
    });
}
