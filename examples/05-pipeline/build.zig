const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const coverage_json = b.option([]const u8, "coverage-json", "Write the go-coverage report as JSON at this path");
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
        .source_root = b.path("src/root.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/pipeline",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .coverage_json = coverage_json,
    });
    _ = bindings.addStandardSteps(b, .{});
}
