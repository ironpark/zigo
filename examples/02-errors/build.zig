const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const errors_module = b.addModule("errors", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = errors_module });
    b.step("test", "Run the Zig errors tests").dependOn(&b.addRunArtifact(tests).step);

    const bindings = zigo.addGoBindings(b, .{
        .name = "errors",
        .module = errors_module,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/errors",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .raw_package = .{ .path = "support/ffi" },
    });
    _ = bindings.addStandardSteps(b, .{});
}
