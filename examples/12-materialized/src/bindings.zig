const zigo = @import("zigo");
const library = @import("materialized");

pub const bindings = zigo.define(.{
    .allocator = .c_allocator,
    .root = library,
    .types = .{
        .{ .type = library.Status, .repr = .enumeration },
        .{ .type = library.Leaf, .repr = .materialized },
        .{ .type = library.Probe, .repr = .materialized },
        .{ .type = library.LegacyLeaf, .repr = .@"opaque" },
        .{ .type = library.LegacyProbe, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .path = "root.snapshot", .returns = .caller, .release = "root.release" },
        .{ .path = "root.probeMany", .returns = .caller, .release = "root.release" },
        .{
            .path = "root.fill",
            .params = .{"output"},
            .param_meta = .{ .output = .{ .direction = .out, .written = .@"return" } },
            .returns = .caller,
            .release = "root.release",
        },
        .{ .path = "root.release", .params = .{"buffer"} },
        .{ .path = "LegacyProbe.create", .params = .{"index"} },
        .{ .path = "LegacyProbe.id" },
        .{ .path = "LegacyProbe.active" },
        .{ .path = "LegacyProbe.child", .returns = .borrowed },
        .{ .path = "LegacyProbe.deinit" },
        .{ .path = "LegacyLeaf.value" },
    },
});
