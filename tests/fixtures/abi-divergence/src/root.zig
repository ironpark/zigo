//! `c_long` is 8 bytes on Linux and macOS and 4 bytes on Windows, so the
//! layout reflection records on a POSIX host does not describe a Windows
//! target. The shim's comptime ABI guards must reject that instead of
//! shipping a struct whose C and Go mirrors disagree with the Zig one.
pub const Sizes = extern struct {
    span: c_long,
    tail: u32,
};

pub fn measure(sizes: Sizes) u32 {
    return sizes.tail +% @as(u32, @truncate(@as(u64, @bitCast(@as(i64, sizes.span)))));
}
