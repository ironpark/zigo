const zigo = @import("zigo");
const Lib = struct {
    pub fn f(_: u32) void {}
};
const api = zigo.scope(Lib);
const P: zigo.Plugin = .{ .name = "TEST", .subjects = &.{.function}, .ParamOptions = struct {} };
comptime {
    _ = api.func("f", .{ .params = &.{zigo.param.input(0).use(P, .{})} });
}
