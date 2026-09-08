const std = @import("std");
comptime {
    _ = @import("shim");
}
extern fn zg_combine_impl(right: u64, left: u64) callconv(.c) u64;
extern fn zg_derived_impl(left: u64, right: u64) callconv(.c) u64;
extern fn zg_state_impl(value: u8) callconv(.c) u8;
export fn zg_panic_bridge(message: [*]const u8, length: usize) callconv(.c) noreturn {
    @panic(message[0..length]);
}
test "transformed shim calls original Zig functions with the original argument meaning" {
    try std.testing.expectEqual(@as(u64, 207), zg_combine_impl(7, 2));
    try std.testing.expectEqual(@as(u64, 207), zg_derived_impl(2, 7));
    try std.testing.expectEqual(@as(u8, 0), zg_state_impl(0));
}
