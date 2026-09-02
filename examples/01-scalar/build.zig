const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dynamic = b.option(bool, "dynamic", "Build a runtime-loadable shared binding library") orelse false;
    const scalar = b.addModule("scalar", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const support = b.addLibrary(.{
        .name = "scalar_support",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    support.root_module.addCSourceFile(.{
        .file = b.path("src/support.c"),
        .flags = &.{"-fno-sanitize=undefined"},
    });
    scalar.linkLibrary(support);
    const tests = b.addTest(.{ .root_module = scalar });
    b.step("test", "Run the Zig scalar tests").dependOn(&b.addRunArtifact(tests).step);

    const bindings = zigo.addGoBindings(b, .{
        .name = "scalar",
        .module = scalar,
        .bindings = b.path("src/bindings.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/zigo/scalar",
        .target = target,
        .optimize = optimize,
        .link = if (dynamic) .cgo_dynamic else .cgo_static,
        .abi_base = "HEAD",
        .raw_package = "scalar",
    });
    _ = bindings.addStandardSteps(b, .{});
}
