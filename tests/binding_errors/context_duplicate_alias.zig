const zigo = @import("zigo");
const Lib = struct {
    pub const A = opaque {
        pub fn read(_: *@This()) void {}
    };
    pub const B = opaque {};
    pub const AliasA = A;
    pub const Callback = *const fn (usize) callconv(.c) void;
    pub fn rootFn() void {}
};
const api = zigo.scope(Lib);

comptime {
    const A = api.handle("A", .{}).context();
    const Alias = api.handle("AliasA", .{}).context();
    _ = zigo.define(.{ .root = Lib, .declarations = &.{ A.define(&.{}), Alias.define(&.{}) } });
}
