const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const errors_module = b.addModule("errors", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = errors_module });
    b.step("test", "Run the Zig errors tests").dependOn(&b.addRunArtifact(tests).step);

    _ = zigo.addGoBindings(b, .{
        .name = "errors",
        .module = errors_module,
        // `errors` would shadow the standard package in every importer, so the public
        // package is `failures`; the raw package has to live under `internal/`.
        .layout = .{ .go_module = "example.com/zigo/errors", .go_package = "failures", .raw_package = "internal/ffi" },
        .target = target,
        .optimize = optimize,
    });
}
