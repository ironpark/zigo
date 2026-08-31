const zigo = @import("zigo");
const http_client = @import("HTTPClient");

pub const bindings = zigo.define(.{
    .root = http_client,
    .functions = .{.{ .path = "root.statusCode" }},
});
