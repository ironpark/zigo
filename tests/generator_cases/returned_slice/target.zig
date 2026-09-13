const std = @import("std");

/// The ghostty shape: the caller lends a buffer, the function writes into it
/// and returns the prefix it filled.
pub fn printAttributes(buffer: []u8) error{NoSpaceLeft}![]const u8 {
    const text = "1;31m";
    if (buffer.len < text.len) return error.NoSpaceLeft;
    @memcpy(buffer[0..text.len], text);
    return buffer[0..text.len];
}

/// The same shape without an error set.
pub fn copyDigits(buffer: []u8, count: usize) []const u8 {
    const written = @min(buffer.len, count);
    for (buffer[0..written], 0..) |*slot, index| slot.* = '0' + @as(u8, @intCast(index % 10));
    return buffer[0..written];
}
