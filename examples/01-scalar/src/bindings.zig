const zigo = @import("zigo");
const scalar = @import("scalar");

const api = zigo.scope(scalar);

pub const bindings = zigo.define(api, .{
    .declarations = &.{
        api.func("add", .{ .covers = &.{api.ref("subtract")} }),
    },
});
