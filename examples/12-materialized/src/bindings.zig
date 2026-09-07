const zigo = @import("zigo");
const library = @import("materialized");

pub const bindings = zigo.define(.{
    .allocator = .c_allocator,
    .root = library,
    .types = &.{
        .{ .enumeration = .{ .type = library.Status } },
        .{ .value = .{ .type = library.Point } },
        .{ .materialized = .{ .type = library.Leaf } },
        .{ .materialized = .{ .type = library.Probe, .fields = &.{.{ .name = "raw", .semantic = .opaque_bytes }} } },
        .{ .handle = .{ .type = library.LegacyLeaf } },
        .{ .handle = .{ .type = library.LegacyProbe } },
    },
    .functions = &.{
        .{ .path = "root.snapshot", .returns = .{ .ownership = .caller, .release = "root.release" } },
        .{ .path = "root.probeMany", .returns = .{ .ownership = .caller, .release = "root.release" } },
        .{
            .path = "root.fill",
            .params = &.{.{ .name = "output", .direction = .out, .written = .result }},
            .returns = .{ .ownership = .caller, .release = "root.release" },
        },
        .{ .path = "root.release", .params = &.{.{ .name = "buffer" }} },
        .{ .path = "LegacyProbe.create", .params = &.{.{ .name = "index" }} },
        .{ .path = "LegacyProbe.id" },
        .{ .path = "LegacyProbe.active" },
        .{ .path = "LegacyProbe.child", .returns = .{ .ownership = .borrowed } },
        .{ .path = "LegacyProbe.deinit" },
        .{ .path = "LegacyLeaf.value" },
    },
});
