const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const dependency = b.createModule(.{
        .root_source_file = b.path("src/dependency.zig"),
        .target = target,
    });
    dependency.linkSystemLibrary("avformat", .{ .use_pkg_config = .force });
    const module = b.addModule("pkg_config_fixture", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{.{ .name = "dependency", .module = dependency }},
    });
    const bindings = zigo.addGoBindings(b, .{
        .name = "pkg_config_fixture",
        .module = module,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/pkg-config-fixture",
        .target = target,
        .optimize = .Debug,
    });

    const resolved = b.addSystemCommand(&.{"cat"});
    resolved.addFileArg(bindings.resolved_pkg_config.?);
    b.step("resolve", "Print resolved pkg-config libraries").dependOn(&resolved.step);
}
