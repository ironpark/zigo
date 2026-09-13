const zigo = @import("zigo");
const library = @import("materialized");

const api = zigo.scope(library);
const LegacyLeaf = api.handle("LegacyLeaf", .{}).context();
const LegacyProbe = api.handle("LegacyProbe", .{}).context();

const Cursor = api.handle("Cursor", .{}).context();

const owned_tree = zigo.result.releasedBy(api.ref("release"));

// Owned result trees name their release function with a checked source reference.
pub const bindings = zigo.define(api, .{
    .allocator = .c_allocator,
    .declarations = &.{
        api.enumeration("Status", .{}),
        api.value("Point", .{}),
        api.materialized("Leaf", .{}),
        api.materialized("Probe", .{ .fields = &.{.{ .name = "raw", .semantic = .opaque_bytes }} }),
        LegacyLeaf.members(&.{
            LegacyLeaf.func("value", .{}),
        }),
        LegacyProbe.members(&.{
            LegacyProbe.func("create", .{}),
            LegacyProbe.func("id", .{}),
            LegacyProbe.func("active", .{}),
            LegacyProbe.func("child", .{ .returns = zigo.result.borrowed() }),
            LegacyProbe.func("deinit", .{}),
        }),
        Cursor.members(&.{
            Cursor.func("create", .{}),
            Cursor.func("next", .{ .returns = owned_tree }).use(zigo.features.iterator, .{}),
            Cursor.func("nextChecked", .{ .returns = owned_tree }).use(zigo.features.iterator, .{ .name = "Checked" }),
            Cursor.func("count", .{}),
            Cursor.func("deinit", .{}),
        }),
        api.func("optionalSnapshot", .{ .returns = owned_tree }),
        api.func("optionalBatch", .{ .returns = owned_tree }),
        api.func("optionalBatchChecked", .{ .returns = owned_tree }),
        api.func("releasedBuffers", .{}),
        api.func("snapshot", .{ .returns = owned_tree }),
        api.func("probeMany", .{ .returns = owned_tree }),
        api.func("fill", .{
            .returns = owned_tree,
            .params = &.{
                zigo.param.output(0, .result),
            },
        }),
        // Keep a foreign package before release to exercise stable release references.
        zigo.package(.{ .path = "metadata", .declarations = &.{api.func("wireVersion", .{})} }),
        api.func("release", .{}),
    },
});
