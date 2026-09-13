const std = @import("std");
const shim = @import("expected/shim.zig");

// The generated export is what proves the shape: the Zig function returns a
// slice of the caller's buffer, and what crosses the boundary is its length.
extern fn zg_print_attributes_impl(buffer_ptr: [*c]u8, buffer_len: usize, out_result: *usize) i32;
extern fn zg_copy_digits_impl(buffer_ptr: [*c]u8, buffer_len: usize, count: usize) usize;

test "a fallible fill reports the length of the slice it returned" {
    var buffer: [16]u8 = undefined;
    var written: usize = 0;
    try std.testing.expectEqual(@as(i32, 0), zg_print_attributes_impl(&buffer, buffer.len, &written));
    try std.testing.expectEqual(@as(usize, 5), written);
    try std.testing.expectEqualStrings("1;31m", buffer[0..written]);
}

test "the error path reports the code and leaves the count alone" {
    var buffer: [2]u8 = undefined;
    var written: usize = 12345;
    try std.testing.expectEqual(@as(i32, 1), zg_print_attributes_impl(&buffer, buffer.len, &written));
    try std.testing.expectEqual(@as(usize, 12345), written);
}

test "an infallible fill returns the length directly" {
    var buffer: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 3), zg_copy_digits_impl(&buffer, buffer.len, 3));
    try std.testing.expectEqualStrings("012", buffer[0..3]);
    // The buffer is the ceiling; a larger request is clamped to it.
    try std.testing.expectEqual(@as(usize, 8), zg_copy_digits_impl(&buffer, buffer.len, 40));
}

comptime {
    _ = shim;
}
