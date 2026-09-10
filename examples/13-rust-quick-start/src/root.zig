/// Adds two signed 32-bit integers. The sum must fit in i32.
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

/// Sums a borrowed slice. The total is widened so a long slice of large
/// values cannot overflow the way the elements would.
pub fn sum(values: []const i32) i64 {
    var total: i64 = 0;
    for (values) |value| total += value;
    return total;
}

pub const MathError = error{DivideByZero};

/// Divides two integers, truncating toward zero.
pub fn divide(numerator: i32, denominator: i32) MathError!i32 {
    if (denominator == 0) return error.DivideByZero;
    return @divTrunc(numerator, denominator);
}

test "the three shapes the minimal Rust backend covers" {
    const std = @import("std");
    // A scalar.
    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
    // A slice.
    try std.testing.expectEqual(@as(i64, 6), sum(&.{ 1, 2, 3 }));
    try std.testing.expectEqual(@as(i64, 0), sum(&.{}));
    // An error union.
    try std.testing.expectEqual(@as(i32, 3), try divide(7, 2));
    try std.testing.expectError(error.DivideByZero, divide(1, 0));
}
