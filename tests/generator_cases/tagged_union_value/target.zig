const std = @import("std");

pub const Mode = enum(u8) { instant, smooth };
pub const RGB = packed struct(u24) { r: u8, g: u8, b: u8 };
pub const Region = extern struct { x: i16, enabled: bool };

pub const ScrollViewportTag = enum(u8) { top, delta, page, ratio, animated, mode, rgb, region, unknown };

pub const ScrollViewport = union(ScrollViewportTag) {
    top,
    delta: isize,
    page: usize,
    ratio: f64,
    animated: bool,
    mode: Mode,
    rgb: RGB,
    region: Region,
    unknown: *const anyopaque,
};

pub fn apply(behavior: ScrollViewport) i64 {
    return switch (behavior) {
        .top => 0,
        .delta => |value| value,
        else => -1,
    };
}

pub fn current() ScrollViewport {
    return .{ .page = 3 };
}

/// The shape the error union adds: a union result from a call that can fail.
pub fn parse(text: []const u8) error{Invalid}!ScrollViewport {
    if (std.mem.eql(u8, text, "top")) return .top;
    if (std.mem.eql(u8, text, "smooth")) return .{ .mode = .smooth };
    if (std.mem.eql(u8, text, "opaque")) return .{ .unknown = &opaque_value };
    return error.Invalid;
}

const opaque_value: u8 = 0;
