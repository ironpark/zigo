const zigo = @import("zigo");
const http_client = @import("HTTPClient");

const api = zigo.scope(http_client);

pub const bindings = zigo.define(.{
    .root = http_client,
    .declarations = &.{
        api.func("statusCode", .{}),
    },
});
