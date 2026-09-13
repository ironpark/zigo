const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const callback = b.addModule("callback", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    callback.linkSystemLibrary("z", .{});
    const tests = b.addTest(.{ .root_module = callback });
    b.step("test", "Run the Zig callback tests").dependOn(&b.addRunArtifact(tests).step);

    // The public package sits at the module root and the raw bindings share
    // it: one Go package, no `internal/raw`.
    _ = zigo.addGoBindings(b, .{
        .name = "callback",
        .module = callback,
        .layout = .{
            .go_module = "example.com/zigo/callback",
            .go_package_path = ".",
            .raw_colocated = true,
        },
        .target = target,
        .optimize = optimize,
    });

    _ = zigo.addGoBindings(b, .{
        .name = "callback",
        .module = callback,
        .go_dir = b.path("go-purego"),
        .layout = .{ .go_module = "example.com/zigo/callback-purego", .go_package_path = "." },
        .target = target,
        .optimize = optimize,
        .link = .{ .purego = .{} },
        .standard_steps = .{ .variant = "purego" },
    });
}
