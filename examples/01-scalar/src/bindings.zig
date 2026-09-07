const zigo = @import("zigo");
const scalar = @import("scalar");

const api = zigo.scope(scalar);

pub const bindings = zigo.define(.{
    .root = scalar,
    .declarations = &.{
        api.func("add", .{ .covers = &.{api.ref("subtract")} }),
    },
});
