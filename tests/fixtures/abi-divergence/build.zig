const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const module = b.addModule("divergence", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    const bindings = zigo.addGoBindings(b, .{
        .name = "divergence",
        .module = module,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/divergence",
        .target = target,
        .optimize = .Debug,
        .link = .purego,
    });
    // The guards live in the shim, so compiling the library is what proves
    // them: generation itself never sees the target's own layout.
    b.step("lib", "Build the native library for the requested target")
        .dependOn(&bindings.install_library.step);
}
