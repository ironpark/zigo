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

    // A built-in plugin is configured like an added one: by name, with no
    // module of its own. MUST adds a `Must*` mirror of every fallible method.
    const must: zigo.PluginModule = .{
        .name = "MUST",
        .config = zigo.configJson(b, .{ .enabled = true }),
    };
    const package_doc = "Package event_queue queues events natively and hands the results to Go.\n\nThe doc body comes from the `go_package_doc` build option rather than from a\n`//!` block in the bindings file.";

    _ = zigo.addGoBindings(b, .{
        .name = "event_queue",
        .module = event_queue,
        .layout = .{ .go_module = "example.com/zigo/event-queue", .raw_package = "internal/cgo" },
        .target = target,
        .optimize = optimize,
        .go_package_doc = package_doc,
        .plugins = &.{must},
    });

    _ = zigo.addGoBindings(b, .{
        .name = "event_queue",
        .module = event_queue,
        .go_dir = b.path("go-purego"),
        .layout = .{ .go_module = "example.com/zigo/event-queue-purego", .raw_package = "internal/native" },
        .target = target,
        .optimize = optimize,
        .go_package_doc = package_doc,
        .plugins = &.{must},
        .link = .{ .purego = .{} },
        .standard_steps = .{ .variant = "purego" },
    });
}
