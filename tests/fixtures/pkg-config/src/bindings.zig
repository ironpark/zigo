const zigo = @import("zigo");
const fixture = @import("pkg_config_fixture");

const api = zigo.scope(fixture);

pub const bindings = zigo.define(api, .{
    .declarations = &.{
        api.func("answer", .{}),
    },
});
