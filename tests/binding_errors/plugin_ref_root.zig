const zigo = @import("zigo");
const Lib = struct {
    pub const Item = opaque {};
};
const Other = struct {
    pub const Thing = opaque {};
};
const api = zigo.scope(Lib);
const other = zigo.scope(Other);
const P: zigo.Plugin = .{
    .name = "TEST",
    .TypeOptions = struct { target: ?zigo.plugin.ref.Type = null },
    .subjects = &.{.handle},
};
comptime {
    _ = api.handle("Item", .{}).use(P, .{ .target = other.typeRef("Thing") });
}
