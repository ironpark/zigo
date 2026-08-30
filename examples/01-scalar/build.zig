const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const scalar = b.addModule("scalar", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = scalar });
    b.step("test", "Run the Zig scalar tests").dependOn(&b.addRunArtifact(tests).step);

    const bindings = zigo.addGoBindings(b, .{
        .name = "scalar",
        .module = scalar,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/scalar",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .raw_package = .colocated,
    });
    _ = bindings.addStandardSteps(b, .{});
}
