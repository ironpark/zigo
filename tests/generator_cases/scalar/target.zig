const std = @import("std");

/// The bound module declares its own log policy. `std.log` reads the
/// compilation root's, which for a zigo build is the generated shim, so this
/// only reaches the logger if the shim passes it through.
pub const std_options: std.Options = .{ .log_level = .debug, .logFn = record };

pub var last_level: ?std.log.Level = null;
pub var last_message: [128]u8 = undefined;
pub var last_length: usize = 0;

fn record(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    last_level = level;
    last_length = (std.fmt.bufPrint(&last_message, format, args) catch return).len;
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
