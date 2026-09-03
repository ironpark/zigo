//! Scalar arithmetic across the C ABI: the smallest binding zigo can generate.
//! This sentence reaches the generated Go package doc through the root module's `//!` block.
const bridge = @import("scalar_bridge");

pub fn add(a: i32, b: i32) i32 {
    return bridge.scalar_bridge_add(a, b);
}

/// Deliberately left out of the binding so `go-coverage` demonstrates the gap.
pub fn subtract(a: i32, b: i32) i32 {
    return a - b;
}

test "scalar example" {
    const std = @import("std");
    try std.testing.expectEqual(@as(i32, 10), add(3, 7));
}
