const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const coverage_json = b.option([]const u8, "coverage-json", "Write the go-coverage report as JSON at this path");
    const telemetry_hub = b.addModule("telemetry_hub", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = telemetry_hub });
    b.step("test", "Run broad telemetry hub tests").dependOn(&b.addRunArtifact(tests).step);

    const bindings = zigo.addGoBindings(b, .{
        .name = "telemetry_hub",
        .module = telemetry_hub,
        .bindings = b.path("src/bindings.zig"),
        .source_root = b.path("src/root.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/telemetry-hub",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .raw_package = "internal/native",
        .coverage_json = coverage_json,
    });
    _ = bindings.addStandardSteps(b, .{});

    const purego_bindings = zigo.addGoBindings(b, .{
        .name = "telemetry_hub",
        .module = telemetry_hub,
        .bindings = b.path("src/bindings.zig"),
        .source_root = b.path("src/root.zig"),
        .go_dir = b.path("go-purego"),
        .go_module = "example.com/zigo/telemetry-hub-purego",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .raw_package = "internal/native",
        .link = .purego,
        .install = .{
            .library_dir = .{ .custom = "purego-layout/lib" },
            .header_dir = .{ .custom = "purego-layout/include" },
            .library_name = "telemetry_native",
            .header_name = "telemetry_native.h",
        },
        // The configured install directory is used automatically when no
        // explicit search_paths are supplied. The public package exposes no
        // loader; deployment may select another copy through the environment.
        .library_loading = .{
            .loader = .automatic_internal,
        },
    });
    _ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
}
