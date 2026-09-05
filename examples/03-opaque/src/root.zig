const std = @import("std");

pub const CreateError = error{OutOfMemory};

var live_bytes: std.atomic.Value(usize) = .init(0);

pub const ContextView = struct {
    context: *Context,

    pub fn total(self: *ContextView) i64 {
        return self.context.total;
    }
};

pub const Context = struct {
    total: i64 = 0,
    view_value: ContextView = undefined,
    /// Where `next` is in its count-down from `total`.
    cursor: i64 = 0,

    pub fn create() CreateError!*Context {
        const value = std.heap.page_allocator.create(Context) catch return error.OutOfMemory;
        value.* = .{};
        value.view_value = .{ .context = value };
        _ = live_bytes.fetchAdd(@sizeOf(Context), .monotonic);
        return value;
    }

    pub fn add(self: *Context, value: i64) i64 {
        self.total += value;
        return self.total;
    }

    pub fn maybeTotal(self: *const Context, present: bool) ?i64 {
        return if (present) self.total else null;
    }

    pub fn setTotal(self: *Context, c: i64) void {
        self.total = c;
    }

    /// next counts from 1 up to the total, then reports the end with null.
    /// Bound with `.iterator`, so Go ranges over it as `All()`.
    pub fn next(self: *Context) ?i64 {
        if (self.cursor >= self.total) return null;
        self.cursor += 1;
        return self.cursor;
    }

    /// nextChecked is `next` with a failure path: a negative total is an
    /// error the sequence surfaces, rather than an empty sequence.
    pub fn nextChecked(self: *Context) error{NegativeTotal}!?i64 {
        if (self.total < 0) return error.NegativeTotal;
        return self.next();
    }

    pub fn rewind(self: *Context) void {
        self.cursor = 0;
    }

    /// addCopy receives a copy of the handle's value. Its mutation is visible
    /// to this call but cannot change the storage owned by the Go handle.
    pub fn addCopy(self: Context, value: i64) i64 {
        var copy = self;
        copy.total += value;
        return copy.total;
    }

    pub fn borrowView(self: *Context) *ContextView {
        return &self.view_value;
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

pub fn sumCopies(bias: i64, left: Context, right: Context) i64 {
    return bias + left.total + right.total;
}

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
