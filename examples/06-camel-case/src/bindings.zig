const zigo = @import("zigo");
const http_client = @import("HTTPClient");

pub const bindings = zigo.define(.{
    .functions = .{.{ .name = "statusCode", .@"fn" = http_client.statusCode }},
});
