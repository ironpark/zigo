const zigo = @import("zigo");
const library = @import("materialized");

const api = zigo.scope(library);
const legacy_leaf = api.in("LegacyLeaf");
const legacy_probe = api.in("LegacyProbe");

const owned_tree = zigo.result.releasedBy(api.ref("release"));

// Owned result trees name their release function with a checked source reference.
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .c_allocator,
    .declarations = &.{
        api.enumeration("Status", .{}),
        api.value("Point", .{}),
        api.materialized("Leaf", .{}),
        api.materialized("Probe", .{ .fields = &.{.{ .name = "raw", .semantic = .opaque_bytes }} }),
        api.handle("LegacyLeaf", .{}).members(&.{
            legacy_leaf.function("value", .{}),
        }),
        api.handle("LegacyProbe", .{}).members(&.{
            legacy_probe.function("create", .{}),
            legacy_probe.function("id", .{}),
            legacy_probe.function("active", .{}),
            legacy_probe.function("child", .{ .returns = zigo.result.borrowed() }),
            legacy_probe.function("deinit", .{}),
        }),
        api.function("snapshot", .{ .returns = owned_tree }),
        api.function("probeMany", .{ .returns = owned_tree }),
        api.function("fill", .{
            .returns = owned_tree,
            .params = &.{
                zigo.param.output(0, .result),
            },
        }),
        api.function("release", .{}),
    },
});
