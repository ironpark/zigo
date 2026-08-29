pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "scalar example" {
    const std = @import("std");
    try std.testing.expectEqual(@as(i32, 10), add(3, 7));
}
