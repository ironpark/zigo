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
        .raw_package = "bridge/cgo",
        .go_package_doc = "Package event_queue queues events natively and hands the results to Go.\n\nThe doc body comes from the `go_package_doc` build option rather than from a\n`//!` block in the bindings file.",
    });
    _ = bindings.addStandardSteps(b, .{});

    const purego_bindings = zigo.addGoBindings(b, .{
        .name = "event_queue",
        .module = event_queue,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go-purego"),
        .go_module = "example.com/zigo/event-queue-purego",
        .target = target,
        .optimize = optimize,
        .abi_base = "HEAD",
        .raw_package = "internal/native",
        .go_package_doc = "Package event_queue queues events natively and hands the results to Go.\n\nThe doc body comes from the `go_package_doc` build option rather than from a\n`//!` block in the bindings file.",

        .link = .purego,
    });
    _ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
}
