const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const event_queue = b.addModule("event_queue", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = event_queue });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the Zig event queue tests").dependOn(&run_tests.step);

    const bindings = zigo.addGoBindings(b, .{
        .name = "event_queue",
        .module = event_queue,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/event-queue",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .raw_package = .{ .path = "bridge/cgo" },
        .auto_cleanup = true,
    });
    b.step("go", "Generate and build Go bindings").dependOn(&bindings.update.step);
    b.step("go-check", "Fail if generated bindings are stale").dependOn(&bindings.check.step);
    if (bindings.abi_check) |abi_check|
        b.step("abi-check", "Fail on a breaking ABI change").dependOn(&abi_check.step);
}
