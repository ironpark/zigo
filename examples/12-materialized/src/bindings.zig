const zigo = @import("zigo");
const library = @import("materialized");

const api = zigo.scope(library);

// Owned result trees name their release function with a checked source reference.
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .c_allocator,
    .declarations = &.{
        api.enumeration("Status", .{}),
        api.value("Point", .{}),
        api.materialized("Leaf", .{}),
        api.materialized("Probe", .{ .fields = &.{.{ .name = "raw", .semantic = .opaque_bytes }} }),
        api.handle("LegacyLeaf", .{}),
        api.handle("LegacyProbe", .{}),
        api.function("snapshot", .{ .returns = .{ .lifetime = .{ .owned = .{ .release = api.ref("release") } } } }),
        api.function("probeMany", .{ .returns = .{ .lifetime = .{ .owned = .{ .release = api.ref("release") } } } }),
        api.function("fill", .{ .returns = .{ .lifetime = .{ .owned = .{ .release = api.ref("release") } } }, .params = &.{
            .{ .index = 0, .go_name = "output", .contract = .{ .buffer = .{ .output = .{ .written = .result } } } },
        } }),
        api.function("release", .{ .params = &.{.{ .index = 0, .go_name = "buffer" }} }),
        api.in("LegacyProbe").function("create", .{ .params = &.{.{ .index = 0, .go_name = "index" }} }),
        api.in("LegacyProbe").function("id", .{}),
        api.in("LegacyProbe").function("active", .{}),
        api.in("LegacyProbe").function("child", .{ .returns = .{ .lifetime = .{ .borrowed = .receiver } } }),
        api.in("LegacyProbe").function("deinit", .{}),
        api.in("LegacyLeaf").function("value", .{}),
    },
});
