/// Adds two signed 32-bit integers. The sum must fit in i32.
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add" {
    const std = @import("std");
    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
}
