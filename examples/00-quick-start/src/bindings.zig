const zigo = @import("zigo");
const library = @import("calculator");

pub const bindings = zigo.define(.{
    .root = library,
    .functions = .{.{ .path = "root.add" }},
});
