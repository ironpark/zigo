const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const purego = b.option(bool, "purego", "Generate callback-free purego bindings") orelse false;
    const coverage_json = b.option([]const u8, "coverage-json", "Write the go-coverage report as JSON at this path");
    const tagged_union = b.addModule("tagged_union", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = tagged_union });
    b.step("test", "Run the Zig tagged-union tests").dependOn(&b.addRunArtifact(tests).step);

    const bindings = zigo.addGoBindings(b, .{
        .name = "tagged_union",
        .module = tagged_union,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path(if (purego) "go-purego" else "go"),
        .go_module = "example.com/zigo/tagged-union",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .link = if (purego) .purego else .cgo_static,
        .coverage_json = coverage_json,
    });
    _ = bindings.addStandardSteps(b, .{});
}
