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

    const bindings = zigo.addGoBindings(b, .{
        .name = "callback",
        .module = callback,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/callback",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
    });
    _ = bindings.addStandardSteps(b, .{});

    const purego_bindings = zigo.addGoBindings(b, .{
        .name = "callback",
        .module = callback,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go-purego"),
        .go_module = "example.com/zigo/callback-purego",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .backend = .purego,
        .link_mode = .dynamic,
    });
    _ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
}
