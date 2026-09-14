const zigo = @import("zigo");
const Lib = struct {
    pub const Point = extern struct { x: i32 };
};
const api = zigo.scope(Lib);
const P: zigo.Plugin = .{ .name = "TEST", .subjects = &.{.value}, .FieldOptions = struct {} };
comptime {
    _ = api.value("Point", .{ .fields = &.{(zigo.ValueField{ .name = "x" }).use(P, .{})} });
}
