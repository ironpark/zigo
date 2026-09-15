//! The shipped `buildinfo` plugin's Zig really compiles into the shim, and
//! the symbol the shim exported really hands back the string it built.
//!
//! The golden pins the source the generator writes; this is what proves that
//! source is a shim `zig build` accepts -- including the one signature a
//! plugin symbol may have that is not a plain scalar, `[*:0]const u8`.
const std = @import("std");
comptime {
    _ = @import("shim");
}
extern fn zg_add_impl(a: i32, b: i32) callconv(.c) i32;
extern fn zg_buildinfo_build_info_impl() callconv(.c) [*:0]const u8;
export fn zg_panic_bridge(message: [*]const u8, length: usize) callconv(.c) noreturn {
    @panic(message[0..length]);
}
test "the shim exports the plugin's C string beside the bound library's symbol" {
    try std.testing.expectEqual(@as(i32, 5), zg_add_impl(2, 3));
    const text = std.mem.span(zg_buildinfo_build_info_impl());
    try std.testing.expect(std.mem.startsWith(u8, text, "zig "));
    try std.testing.expect(std.mem.indexOf(u8, text, @import("builtin").zig_version_string) != null);
}
