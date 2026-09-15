//! The Zig `BUILDINFO` contributes to the native library.
//!
//! It is compiled by the generated shim, against nothing but `std`, and
//! exports nothing of its own: the shim writes the `export` wrapper for the
//! symbol the plugin declares. What it can see that no generated code can is
//! `@import("builtin")` as resolved for the native library itself -- the Zig
//! that built it, the optimize mode it was built in, and the target it was
//! built for.
const std = @import("std");
const builtin = @import("builtin");

/// `zig <version>; <optimize mode>; <arch>-<os>-<abi>`, built at comptime and
/// stored in the binary, so the pointer the symbol hands back is valid for
/// the life of the process -- which is what the plugin contract requires of a
/// `c_string` return.
const info = std.fmt.comptimePrint("zig {s}; {s}; {s}-{s}-{s}", .{
    builtin.zig_version_string,
    @tagName(builtin.mode),
    @tagName(builtin.target.cpu.arch),
    @tagName(builtin.target.os.tag),
    @tagName(builtin.target.abi),
});

/// What the plugin's `build_info` symbol hands back.
pub fn buildInfo() [*:0]const u8 {
    return info;
}

test "the string names the Zig that compiled this file" {
    const text = std.mem.span(buildInfo());
    try std.testing.expect(std.mem.startsWith(u8, text, "zig "));
    try std.testing.expect(std.mem.indexOf(u8, text, builtin.zig_version_string) != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "; "));
}
