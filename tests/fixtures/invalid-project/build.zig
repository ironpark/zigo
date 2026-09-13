const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const module = b.addModule("invalid", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    const bindings = zigo.addGoBindings(b, .{
        .name = "invalid",
        .module = module,
        .layout = .{ .go_module = "example.com/zigo/invalid" },
        .target = target,
        .optimize = .Debug,
        .abi_base = null,
        // This fixture names its own `go` step.
        .standard_steps = null,
    });
    std.debug.assert(bindings.abi_check == null);
    b.step("go", "Expected diagnostic failure").dependOn(&bindings.update.step);
}
