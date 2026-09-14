const zigo = @import("zigo");
const Lib = struct {
    pub fn f(_: u32) void {}
};
const api = zigo.scope(Lib);
const P: zigo.Plugin = .{ .name = "TEST", .subjects = &.{.function}, .ResultOptions = struct {} };
comptime {
    _ = api.func("f", .{ .returns = zigo.result.owned().use(P, .{}) });
}
