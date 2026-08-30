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

    const bindings = zigo.addGoBindings(b, .{
        .name = "opaque",
        .module = opaque_module,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/opaque",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
    });
    b.step("go", "Generate and build Go bindings").dependOn(&bindings.update.step);
    b.step("go-check", "Fail if generated bindings are stale").dependOn(&bindings.check.step);
    if (bindings.abi_check) |abi_check|
        b.step("abi-check", "Fail on a breaking ABI change").dependOn(&abi_check.step);
}
