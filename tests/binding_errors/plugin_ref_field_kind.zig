const zigo = @import("zigo");
const Lib = struct {
    pub const Point = extern struct { x: i32 };
};
const api = zigo.scope(Lib);
const P: zigo.Plugin = .{
    .name = "TEST",
    .FieldOptions = struct { satisfies: []const zigo.plugin.ref.Interface = &.{} },
    .subjects = &.{ .value, .field },
};
comptime {
    // A field reference is checked the way a declaration's is: an interface
    // reference names an interface, and a type declaration is another kind.
    _ = api.value("Point", .{ .fields = &.{
        (zigo.ValueField{ .name = "x" }).use(P, .{ .satisfies = &.{.{ .entry = api.value("Point", .{}) }} }),
    } });
}
