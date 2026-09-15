const zigo = @import("zigo");
const Lib = struct {
    pub const Point = extern struct { x: i32 };
};
const Other = struct {
    pub const Thing = opaque {};
};
const api = zigo.scope(Lib);
const other = zigo.scope(Other);
const P: zigo.Plugin = .{
    .name = "TEST",
    .FieldOptions = struct { target: ?zigo.plugin.ref.Type = null },
    .subjects = &.{ .value, .field },
};
comptime {
    // A field literal is written before the type declaration that names the
    // binding, so the root check happens once the binding is resolved.
    _ = zigo.define(api, .{ .declarations = &.{
        api.value("Point", .{ .fields = &.{
            (zigo.ValueField{ .name = "x" }).use(P, .{ .target = other.typeRef("Thing") }),
        } }),
    } });
}
