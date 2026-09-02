const std = @import("std");

pub const CreateError = error{OutOfMemory};
pub const MathError = error{DivideByZero};

pub const Mode = enum(u8) { idle, active, paused };

var mutable_samples = [_]i16{ 21, 34, 55 };
var live_values: std.atomic.Value(usize) = .init(0);

pub const Child = struct {
    value: i32,

    pub fn create(value: i32) CreateError!*Child {
        const child = std.heap.page_allocator.create(Child) catch return error.OutOfMemory;
        child.* = .{ .value = value };
        return child;
    }

    pub fn get(self: *Child) i32 {
        return self.value;
    }

    pub fn deinit(self: *Child) void {
        std.heap.page_allocator.destroy(self);
    }
};

pub const Value = union(enum(u8)) {
    none,
    integer: i64,
    flag: bool,
    mode: Mode,
    samples: []const i16,
    child: *const Child,
    mutableSamples: []i16,

    pub fn create(initial: i64) CreateError!*Value {
        const value = std.heap.page_allocator.create(Value) catch return error.OutOfMemory;
        value.* = .{ .integer = initial };
        _ = live_values.fetchAdd(1, .monotonic);
        return value;
    }

    pub fn setNone(self: *Value) void {
        self.* = .none;
    }

    pub fn setFlag(self: *Value, flag: bool) void {
        self.* = .{ .flag = flag };
    }

    pub fn setMode(self: *Value, mode: Mode) void {
        self.* = .{ .mode = mode };
    }

    pub fn usePresetSamples(self: *Value) void {
        self.* = .{ .samples = &.{ 3, 5, 8, 13 } };
    }

    pub fn useEmptySamples(self: *Value) void {
        self.* = .{ .samples = &.{} };
    }

    pub fn useMutableSamples(self: *Value) void {
        self.* = .{ .mutableSamples = mutable_samples[0..] };
    }

    pub fn setChild(self: *Value, child: *const Child) void {
        self.* = .{ .child = child };
    }

    pub fn borrow(self: *Value) *const Value {
        return self;
    }

    pub fn deinit(self: *Value) void {
        _ = live_values.fetchSub(1, .monotonic);
        std.heap.page_allocator.destroy(self);
    }
};

/// Every variant payload is a scalar or an enum, so this union opts into the
/// value snapshot representation: Go reads the tag and the payload together.
pub const Signal = union(enum(u8)) {
    idle,
    ticks: u32,
    level: f64,
    offset: i16,
    mode: Mode,
    active: bool,

    pub fn create(initial: u32) CreateError!*Signal {
        const signal = std.heap.page_allocator.create(Signal) catch return error.OutOfMemory;
        signal.* = .{ .ticks = initial };
        return signal;
    }

    pub fn setIdle(self: *Signal) void {
        self.* = .idle;
    }

    pub fn setTicks(self: *Signal, ticks: u32) void {
        self.* = .{ .ticks = ticks };
    }

    pub fn setLevel(self: *Signal, level: f64) void {
        self.* = .{ .level = level };
    }

    pub fn setOffset(self: *Signal, offset: i16) void {
        self.* = .{ .offset = offset };
    }

    pub fn setMode(self: *Signal, mode: Mode) void {
        self.* = .{ .mode = mode };
    }

    pub fn setActive(self: *Signal, active: bool) void {
        self.* = .{ .active = active };
    }

    pub fn deinit(self: *Signal) void {
        std.heap.page_allocator.destroy(self);
    }
};

/// A value-only tagged union. zigo flattens it to a tag and one scalar slot
/// per payload instead of exposing it as a pointer handle.
pub const ScrollViewport = union(enum(u8)) {
    top,
    bottom,
    delta: isize,
    page: usize,
};

pub fn scrollAmount(behavior: ScrollViewport) isize {
    return switch (behavior) {
        .top => 1,
        .bottom => 2,
        .delta => |value| value,
        .page => |value| @intCast(value),
    };
}

pub fn liveValues() usize {
    return live_values.load(.monotonic);
}

pub fn divide(numerator: f64, denominator: f64) MathError!f64 {
    if (denominator == 0) return error.DivideByZero;
    return numerator / denominator;
}

pub fn sum(values: []const f64) f64 {
    var total: f64 = 0;
    for (values) |value| total += value;
    return total;
}

pub fn panicError() error{Never}!void {
    @panic("purego panic translation");
}

test "tagged union changes variants without exposing its layout" {
    const child = try Child.create(17);
    defer child.deinit();
    const value = try Value.create(42);
    defer value.deinit();

    try std.testing.expectEqual(@as(i64, 42), value.integer);
    value.setFlag(true);
    try std.testing.expect(value.flag);
    value.setMode(.paused);
    try std.testing.expectEqual(Mode.paused, value.mode);
    value.usePresetSamples();
    try std.testing.expectEqualSlices(i16, &.{ 3, 5, 8, 13 }, value.samples);
    value.useEmptySamples();
    try std.testing.expectEqual(@as(usize, 0), value.samples.len);
    value.useMutableSamples();
    try std.testing.expectEqualSlices(i16, &.{ 21, 34, 55 }, value.mutableSamples);
    value.setChild(child);
    try std.testing.expectEqual(@as(i32, 17), value.child.value);
    try std.testing.expect(value.borrow() == value);
}

test "value lifecycle accounting returns to zero" {
    const value = try Value.create(1);
    try std.testing.expectEqual(@as(usize, 1), liveValues());
    value.deinit();
    try std.testing.expectEqual(@as(usize, 0), liveValues());
}

test "the value snapshot union changes variants like any other tagged union" {
    const signal = try Signal.create(7);
    defer signal.deinit();

    try std.testing.expectEqual(@as(u32, 7), signal.ticks);
    signal.setLevel(1.5);
    try std.testing.expectEqual(@as(f64, 1.5), signal.level);
    signal.setOffset(-3);
    try std.testing.expectEqual(@as(i16, -3), signal.offset);
    signal.setMode(.active);
    try std.testing.expectEqual(Mode.active, signal.mode);
    signal.setActive(true);
    try std.testing.expect(signal.active);
    signal.setIdle();
    try std.testing.expectEqual(std.meta.activeTag(signal.*), .idle);
}

test "scalar payload tagged unions pass by value" {
    try std.testing.expectEqual(@as(isize, 1), scrollAmount(.top));
    try std.testing.expectEqual(@as(isize, 2), scrollAmount(.bottom));
    try std.testing.expectEqual(@as(isize, -4), scrollAmount(.{ .delta = -4 }));
    try std.testing.expectEqual(@as(isize, 3), scrollAmount(.{ .page = 3 }));
}
