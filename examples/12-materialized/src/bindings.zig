const zigo = @import("zigo");
const library = @import("materialized");

const api = zigo.scope(library);
const LegacyLeaf = api.handle("LegacyLeaf", .{}).context();
const LegacyProbe = api.handle("LegacyProbe", .{}).context();

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
        LegacyLeaf.define(&.{
            LegacyLeaf.function("value", .{}),
        }),
        LegacyProbe.define(&.{
            LegacyProbe.function("create", .{}),
            LegacyProbe.function("id", .{}),
            LegacyProbe.function("active", .{}),
            LegacyProbe.function("child", .{ .returns = zigo.result.borrowed() }),
            LegacyProbe.function("deinit", .{}),
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
