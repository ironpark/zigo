const zigo = @import("zigo");
const Lib = struct {
    pub const Mode = enum(u8) { idle };
};
const api = zigo.scope(Lib);
const P: zigo.Plugin = .{ .name = "TEST", .subjects = &.{.enumeration}, .TagOptions = struct {} };
comptime {
    _ = api.enumeration("Mode", .{ .fields = &.{(zigo.EnumField{ .name = "idle" }).use(P, .{})} });
}
