const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const purego = b.option(bool, "purego", "Generate callback-free purego bindings") orelse false;
    const tagged_union = b.addModule("tagged_union", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = tagged_union });
    b.step("test", "Run the Zig tagged-union tests").dependOn(&b.addRunArtifact(tests).step);

    // A generator plugin: an ordinary Zig package that adds Go surface. This
    // one writes MarshalJSON/UnmarshalJSON for the value types that cross as
    // data, so a caller can put them on a wire without a hand-kept file.
    const json: zigo.PluginModule = .{
        .name = "zigo_json",
        .root_source_file = b.dependency("zigo_json", .{}).path("src/plugin.zig"),
    };

    const enumkit: zigo.PluginModule = .{
        .name = "zigo_enumkit",
        .root_source_file = b.dependency("zigo_enumkit", .{}).path("src/plugin.zig"),
    };

    _ = zigo.addGoBindings(b, .{
        .name = "tagged_union",
        .module = tagged_union,
        .go_dir = b.path(if (purego) "go-purego" else "go"),
        .layout = .{ .go_module = "example.com/zigo/tagged-union" },
        .target = target,
        .optimize = optimize,
        .link = if (purego) .{ .purego = .{} } else .cgo_static,
        .plugins = &.{ json, enumkit },
    });
}
