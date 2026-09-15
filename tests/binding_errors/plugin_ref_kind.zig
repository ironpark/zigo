const zigo = @import("zigo");
const Lib = struct {
    pub const Item = opaque {};
};
const api = zigo.scope(Lib);
const P: zigo.Plugin = .{
    .name = "TEST",
    .TypeOptions = struct { satisfies: []const zigo.plugin.ref.Interface = &.{} },
    .subjects = &.{.handle},
};
comptime {
    // An interface reference names an interface; a type declaration is a
    // reference of another kind.
    _ = api.handle("Item", .{}).use(P, .{ .satisfies = &.{.{ .entry = api.handle("Item", .{}) }} });
}
