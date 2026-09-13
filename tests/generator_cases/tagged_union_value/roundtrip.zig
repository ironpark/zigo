const std = @import("std");
const shim = @import("expected/shim.zig");

const Snapshot = extern struct {
    tag: u8,
    delta: isize,
    page: usize,
    ratio: f64,
    animated: u8,
    mode: u8,
    rgb: u32,
    region_x: i16,
    region_enabled: u8,
};

extern fn zg_parse_impl(text_ptr: [*c]const u8, text_len: usize, out_result: *Snapshot) i32;

test "a fallible union result reports its variant on success" {
    var out: Snapshot = undefined;
    try std.testing.expectEqual(@as(i32, 0), zg_parse_impl("smooth", 6, &out));
    try std.testing.expectEqual(@as(u8, 5), out.tag);
    try std.testing.expectEqual(@as(u8, @intFromEnum(@import("zigo_target").Mode.smooth)), out.mode);
}

test "the Zig error and the omitted variant stay distinguishable" {
    var out: Snapshot = undefined;
    // The error set the function declared.
    try std.testing.expectEqual(@as(i32, 1), zg_parse_impl("nonsense", 8, &out));
    // The variant the binding left out, which is not one of those errors.
    try std.testing.expectEqual(@as(i32, -3), zg_parse_impl("opaque", 6, &out));
}

comptime {
    _ = shim;
}
