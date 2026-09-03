const zigo = @import("zigo");
const fixture = @import("pkg_config_fixture");

pub const bindings = zigo.define(.{
    .root = fixture,
    .functions = .{.{ .path = "root.answer" }},
});
