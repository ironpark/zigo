const zigo = @import("zigo");
const invalid = @import("invalid");

const api = zigo.scope(invalid);

pub const bindings = zigo.define(api, .{
    .declarations = &.{
        api.func("lookupID", .{}),
        api.func("lookup_id", .{}),
    },
});
