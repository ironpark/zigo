const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const coverage_json = b.option([]const u8, "coverage-json", "Write the go-coverage report as JSON at this path");
    const streams = b.addModule("streams", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    streams.link_libc = true;
    const tests = b.addTest(.{ .root_module = streams });
    b.step("test", "Run the Zig stream tests").dependOn(&b.addRunArtifact(tests).step);

    const bindings = zigo.addGoBindings(b, .{
        .name = "streams",
        .module = streams,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/streams",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .coverage_json = coverage_json,
    });
    _ = bindings.addStandardSteps(b, .{});

    const purego_bindings = zigo.addGoBindings(b, .{
        .name = "streams",
        .module = streams,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go-purego"),
        .go_module = "example.com/zigo/streams-purego",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .link = .purego,
    });
    _ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
}
