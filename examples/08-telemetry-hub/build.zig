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
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/telemetry-hub",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .raw_package = .{ .path = "internal/native" },
    });
    b.step("go", "Generate the broad Go API").dependOn(&bindings.update.step);
    b.step("go-check", "Fail if the broad generated API is stale").dependOn(&bindings.check.step);
    if (bindings.abi_check) |abi_check|
        b.step("abi-check", "Fail on a breaking broad API change").dependOn(&abi_check.step);
}
