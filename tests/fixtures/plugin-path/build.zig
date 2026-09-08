const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const module = b.addModule("fixture", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    const bindings = zigo.addGoBindings(b, .{
        .name = "fixture",
        .module = module,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/plugin-path",
        .target = target,
        .optimize = .Debug,
        .plugins = &.{.{
            .name = "wrappers",
            .root_source_file = b.dependency("zigo", .{}).path("tests/plugins/wrappers.zig"),
        }},
    });
    b.step("report", "Reflect an external plugin using publicFilePathAlloc").dependOn(&bindings.report.step);
}
