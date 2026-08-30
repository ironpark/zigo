const std = @import("std");

pub const CreateError = error{OutOfMemory};

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

pub fn liveValues() usize {
    return live_values.load(.monotonic);
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
