const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opaque_module = b.addModule("opaque", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = opaque_module });
    b.step("test", "Run the Zig opaque tests").dependOn(&b.addRunArtifact(tests).step);

    _ = zigo.addGoBindings(b, .{
        .name = "opaque",
        .module = opaque_module,
        .layout = .{ .go_module = "example.com/zigo/opaque" },
        .target = target,
        .optimize = optimize,
    });

    // The same declaration reached without cgo: a second binding set that
    // differs only in how Go finds the library, registered as `go-purego*`.
    _ = zigo.addGoBindings(b, .{
        .name = "opaque",
        .module = opaque_module,
        .go_dir = b.path("go-purego"),
        .layout = .{ .go_module = "example.com/zigo/opaque-purego" },
        .target = target,
        .optimize = optimize,
        .link = .{ .purego = .{} },
        .standard_steps = .{ .variant = "purego" },
    });
}
