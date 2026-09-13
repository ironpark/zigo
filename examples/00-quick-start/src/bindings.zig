const zigo = @import("zigo");
const library = @import("calculator");

const api = zigo.scope(library);

pub const bindings = zigo.define(api, .{
    .declarations = &.{
        api.func("add", .{}),
    },
});
