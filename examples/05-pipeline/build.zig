const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const pipeline = b.addModule("pipeline", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    pipeline.linkSystemLibrary("z", .{});

    const tests = b.addTest(.{ .root_module = pipeline });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the Zig pipeline tests").dependOn(&run_tests.step);

    const bindings = zigo.addGoBindings(b, .{
        .name = "pipeline",
        .module = pipeline,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/pipeline",
        .target = target,
        .optimize = optimize,
    });
    b.step("go", "Generate and build Go bindings").dependOn(&bindings.update.step);
    b.step("go-check", "Fail if generated bindings are stale").dependOn(&bindings.check.step);
    b.step("abi-check", "Fail on a breaking ABI change").dependOn(&bindings.abi_check.step);
}
