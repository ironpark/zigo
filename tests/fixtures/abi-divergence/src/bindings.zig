const zigo = @import("zigo");
const divergence = @import("divergence");

pub const bindings = zigo.define(.{
    .root = divergence,
    .functions = .{
        .{ .path = "root.measure", .params = .{"sizes"} },
    },
});
