const zigo = @import("zigo");
const invalid = @import("invalid");

const api = zigo.scope(invalid);

pub const bindings = zigo.define(.{
    .root = invalid,
    .declarations = &.{
        api.function("lookupID", .{}),
        api.function("lookup_id", .{}),
    },
});
