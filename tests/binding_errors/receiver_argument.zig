const zigo = @import("zigo");
const Lib = struct {
    pub const A = opaque {};
    pub const B = opaque {};
    pub fn make(_: *A) *B {
        unreachable;
    }
};
const api = zigo.scope(Lib);
comptime {
    _ = zigo.define(.{ .root = Lib, .declarations = &.{
        api.handle("A", .{}), api.handle("B", .{}).members(&.{api.function("make", .{ .role = .{ .constructor = .{ .type = api.typeRef("B"), .receiver = .member } } })}),
    } });
}
