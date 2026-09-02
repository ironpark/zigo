//! Scalar arithmetic across the C ABI: the smallest binding zigo can generate.
//! This sentence reaches the generated Go package doc through the `//!` block.
const zigo = @import("zigo");
const scalar = @import("scalar");

pub const bindings = zigo.define(.{
    .root = scalar,
    .functions = .{.{ .path = "root.add" }},
});
