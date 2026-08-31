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
        // The library is found next to the executable when deployed, and in the
        // installed prefix when the tests run from the package directory. The
        // public package therefore exposes no loader at all.
        .library_loading = .{
            .search_paths = &.{ "${EXECUTABLE_DIR}", "${EXECUTABLE_DIR}/../lib", "../../zig-out/lib" },
            .loader = .automatic_internal,
        },
    });
    _ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
}
