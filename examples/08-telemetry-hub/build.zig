const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const telemetry_hub = b.addModule("telemetry_hub", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = telemetry_hub });
    b.step("test", "Run broad telemetry hub tests").dependOn(&b.addRunArtifact(tests).step);

    _ = zigo.addGoBindings(b, .{
        .name = "telemetry_hub",
        .module = telemetry_hub,
        .source_root = b.path("src/root.zig"),
        .layout = .{ .go_module = "example.com/zigo/telemetry-hub", .raw_package = "internal/native" },
        .target = target,
        .optimize = optimize,
    });

    _ = zigo.addGoBindings(b, .{
        .name = "telemetry_hub",
        .module = telemetry_hub,
        .source_root = b.path("src/root.zig"),
        .go_dir = b.path("go-purego"),
        .layout = .{ .go_module = "example.com/zigo/telemetry-hub-purego", .raw_package = "internal/native" },
        .target = target,
        .optimize = optimize,
        // The configured install directory is used automatically when no
        // explicit search_paths are supplied. The public package exposes no
        // loader; deployment may select another copy through the environment.
        .link = .{ .purego = .{ .loader = .automatic_internal } },
        .standard_steps = .{ .variant = "purego" },
        // One more platform than the host, so the tree carries two shared
        // libraries under purego-layout/lib/<goos>_<goarch>/ and the loader
        // picks the running platform's directory. The second entry is chosen
        // to differ from whatever host builds this example.
        .targets = &.{b.resolveTargetQuery(if (target.result.os.tag == .linux)
            .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }
        else
            .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl })},
        .install = .{
            .library_dir = .{ .custom = "purego-layout/lib" },
            .header_dir = .{ .custom = "purego-layout/include" },
            .library_name = "telemetry_native",
            .header_name = "telemetry_native.h",
        },
    });
}
