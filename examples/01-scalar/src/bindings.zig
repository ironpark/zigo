//! Binding declarations are populated when the reflector DSL lands in Phase 2.
const zigo = @import("zigo");
const scalar = @import("scalar");

pub const bindings = zigo.define(.{
    .root = scalar,
    .functions = .{.{ .path = "root.add" }},
});
