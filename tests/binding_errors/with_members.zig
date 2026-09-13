const zigo = @import("zigo");
const Lib = struct {
    pub const A = opaque {};
    pub fn make(_: *A) void {}
};
const api = zigo.scope(Lib);
comptime {
    _ = api.handle("A", .{}).with(.{ .members = &.{api.func("make", .{})} });
}
