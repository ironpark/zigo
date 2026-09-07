const zigo = @import("zigo");
const Lib = struct {
    pub const Item = opaque {
        pub fn read(_: *@This(), _: u32) void {}
    };
    pub const Callback = *const fn () void;
    pub fn f(_: u32) void {}
    pub fn release(_: []u8) void {}
    pub fn take() []u8 {
        unreachable;
    }
};
const api = zigo.scope(Lib);
comptime {
    _ = zigo.define(.{ .root = Lib, .declarations = &.{ api.handle("Item", .{}), api.handle("Item", .{}) } });
}
