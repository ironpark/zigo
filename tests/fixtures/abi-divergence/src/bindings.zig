const zigo = @import("zigo");
const divergence = @import("divergence");

const api = zigo.scope(divergence);

pub const bindings = zigo.define(.{
    .root = divergence,
    .declarations = &.{
        api.function("measure", .{ .params = &.{.{ .index = 0, .go_name = "sizes" }} }),
    },
});
