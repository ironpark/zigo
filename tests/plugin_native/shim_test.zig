//! The plugin's Zig really compiles into the shim, and the symbol the shim
//! exported really calls it. The golden pins the source the generator writes;
//! this is what proves that source is a shim `zig build` accepts, with the
//! plugin module wired in the way `build.zig` wires it for a consumer.
const std = @import("std");
comptime {
    _ = @import("shim");
}
extern fn zg_add_impl(a: i32, b: i32) callconv(.c) i32;
extern fn zg_wraptest_answer_impl() callconv(.c) u32;
export fn zg_panic_bridge(message: [*]const u8, length: usize) callconv(.c) noreturn {
    @panic(message[0..length]);
}
test "the shim exports the plugin's symbol beside the bound library's" {
    try std.testing.expectEqual(@as(i32, 5), zg_add_impl(2, 3));
    try std.testing.expectEqual(@as(u32, 42), zg_wraptest_answer_impl());
}
