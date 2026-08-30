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
    const bindings = zigo.addGoBindings(b, .{
        .name = "errors",
        .module = errors_module,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/errors",
        .target = target,
        .optimize = optimize,
        .raw_package = .{ .path = "support/ffi" },
    });
    b.step("go", "Generate and build Go bindings").dependOn(&bindings.update.step);
    b.step("go-check", "Fail if generated bindings are stale").dependOn(&bindings.check.step);
    b.step("abi-check", "Fail on a breaking ABI change").dependOn(&bindings.abi_check.step);
}
