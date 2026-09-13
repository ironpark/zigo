const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const http_client = b.addModule("HTTPClient", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = http_client });
    b.step("test", "Run the Zig CamelCase tests").dependOn(&b.addRunArtifact(tests).step);

    _ = zigo.addGoBindings(b, .{
        .name = "HTTPClient",
        .module = http_client,
        .layout = .{ .go_module = "example.com/zigo/http-client", .raw_colocated = true },
        .target = target,
        .optimize = optimize,
    });
}
