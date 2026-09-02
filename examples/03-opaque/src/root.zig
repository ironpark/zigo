const std = @import("std");

pub const CreateError = error{OutOfMemory};

var live_bytes: std.atomic.Value(usize) = .init(0);

pub const Context = struct {
    total: i64 = 0,

    pub fn create() CreateError!*Context {
        const value = std.heap.page_allocator.create(Context) catch return error.OutOfMemory;
        value.* = .{};
        _ = live_bytes.fetchAdd(@sizeOf(Context), .monotonic);
        return value;
    }

    pub fn add(self: *Context, value: i64) i64 {
        self.total += value;
        return self.total;
    }

    /// crash panics inside a method: what leaves a handle poisoned.
    pub fn crash(self: *Context) CreateError!void {
        _ = self;
        @panic("deliberate handle panic");
    }

    /// crashInfallible panics from a method that returns no error union.
    /// Its Go signature still carries an `error` -- the handle check has to
    /// be reportable -- so the panic reaches the caller through that.
    pub fn crashInfallible(self: *Context) i64 {
        _ = self;
        @panic("deliberate infallible panic");
    }

    pub fn deinit(self: *Context) void {
        std.heap.page_allocator.destroy(self);
        _ = live_bytes.fetchSub(@sizeOf(Context), .monotonic);
    }
};

/// A free function with no handle and no promoted integer has no `error` in
/// its Go signature, so a panic here has nowhere to be reported. Zig calls
/// that fatal, and so does zigo: the message goes to stderr and the process
/// aborts.
pub fn crashFatal() void {
    @panic("deliberate fatal panic");
}

pub fn liveBytes() usize {
    return live_bytes.load(.monotonic);
}

/// Echoes UTF-8 text without changing its bytes.
pub fn echo(text: []const u8) []const u8 {
    return text;
}

pub const fallback = struct {
    pub fn call(value: i64) i64 {
        return value * 2;
    }
}.call;

test "counting allocation returns to zero" {
    const context = try Context.create();
    try std.testing.expectEqual(@as(i64, 3), context.add(3));
    context.deinit();
    try std.testing.expectEqual(@as(usize, 0), liveBytes());
}
