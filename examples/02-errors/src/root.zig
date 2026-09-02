pub const MathError = error{DivideByZero};
pub const TextError = error{NotPrintable};
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

/// A Unicode codepoint is `u21` in Zig, which C cannot name. zigo carries it
/// in a `uint32_t` and the shim range-checks the value on the way in, so a Go
/// caller that passes something wider gets a native panic rather than a
/// truncated codepoint.
pub fn codepointWidth(cp: u21) TextError!u21 {
    if (cp < 0x20) return error.NotPrintable;
    return if (cp < 0x1100) 1 else 2;
}

test "errors and slices example" {
    const std = @import("std");
    try std.testing.expectError(error.DivideByZero, divide(1, 0));
    try std.testing.expectEqual(@as(f64, 6), sum(&.{ 1, 2, 3 }));
    try std.testing.expectEqual(Format.flac, normalizeFormat(.flac));
    try std.testing.expectEqual(@as(u21, 2), try codepointWidth(0x1100));
    try std.testing.expectError(error.NotPrintable, codepointWidth(0));
}
