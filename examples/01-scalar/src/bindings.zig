const zigo = @import("zigo");
const scalar = @import("scalar");

pub const bindings = zigo.define(.{
    .root = scalar,
    .functions = .{.{ .path = "root.add" }},
});
