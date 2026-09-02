//! Scalar arithmetic across the C ABI: the smallest binding zigo can generate.
//! This sentence reaches the generated Go package doc through the root module's `//!` block.
extern fn scalar_bridge_add(a: i32, b: i32) callconv(.c) i32;

pub fn add(a: i32, b: i32) i32 {
    return scalar_bridge_add(a, b);
}

test "scalar example" {
    const std = @import("std");
    try std.testing.expectEqual(@as(i32, 10), add(3, 7));
}
