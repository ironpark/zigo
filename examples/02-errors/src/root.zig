pub const MathError = error{DivideByZero};
pub const Format = enum(u32) { pcm, flac };

pub fn divide(numerator: f64, denominator: f64) MathError!f64 {
    if (denominator == 0) return error.DivideByZero;
    return numerator / denominator;
}

pub fn sum(values: []const f64) f64 {
    var total: f64 = 0;
    for (values) |value| total += value;
    return total;
}

pub fn normalizeFormat(value: Format) Format {
    return value;
}

test "errors and slices example" {
    const std = @import("std");
    try std.testing.expectError(error.DivideByZero, divide(1, 0));
    try std.testing.expectEqual(@as(f64, 6), sum(&.{ 1, 2, 3 }));
    try std.testing.expectEqual(Format.flac, normalizeFormat(.flac));
}
