//! One project, two output languages, every option left at its default. The
//! build graph has to come up without a duplicate-step or duplicate-option
//! panic; `zig build -l` constructs the graph and lists what it registered.
const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const library = b.addModule("calculator", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    _ = zigo.addGoBindings(b, .{
        .name = "calculator",
        .module = library,
        .layout = .{ .go_module = "example.com/zigo/go-and-rust" },
        .target = target,
        .optimize = .Debug,
    });
    _ = zigo.addRustBindings(b, .{
        .name = "calculator",
        .module = library,
        .rust_dir = b.path("rust"),
        .target = target,
        .optimize = .Debug,
    });
}
