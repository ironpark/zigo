const zigo = @import("zigo");
const Lib = struct {
    pub const Callback = *const fn (u32, [*]const u8, usize, usize) callconv(.c) void;
};
const api = zigo.scope(Lib);
comptime {
    _ = zigo.define(.{ .root = Lib, .declarations = &.{api.callback("Callback", .{ .params = &.{ .{ .index = 0 }, .{ .index = 0 } } })} });
}
