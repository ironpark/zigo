const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const streams = b.addModule("streams", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    streams.link_libc = true;
    const tests = b.addTest(.{ .root_module = streams });
    b.step("test", "Run the Zig stream tests").dependOn(&b.addRunArtifact(tests).step);

    // A generator plugin: an ordinary Zig package that adds Go surface. This
    // one writes the `var _ io.ReadWriteCloser = (*Document)(nil)` assertion
    // next to the handle it belongs to.
    const satisfies: zigo.PluginModule = .{
        .name = "zigo_satisfies",
        .root_source_file = b.dependency("zigo_satisfies", .{}).path("src/plugin.zig"),
    };

    _ = zigo.addGoBindings(b, .{
        .name = "streams",
        .module = streams,
        .layout = .{ .go_module = "example.com/zigo/streams" },
        .target = target,
        .optimize = optimize,
        .plugins = &.{satisfies},
    });

    _ = zigo.addGoBindings(b, .{
        .name = "streams",
        .module = streams,
        .go_dir = b.path("go-purego"),
        .layout = .{ .go_module = "example.com/zigo/streams-purego" },
        .target = target,
        .optimize = optimize,
        .link = .{ .purego = .{} },
        .plugins = &.{satisfies},
        .standard_steps = .{ .variant = "purego" },
    });
}
