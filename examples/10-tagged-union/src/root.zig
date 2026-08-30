const std = @import("std");

pub const CreateError = error{OutOfMemory};

pub const Mode = enum(u8) { idle, active, paused };

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

    pub fn create(initial: i64) CreateError!*Value {
        const value = std.heap.page_allocator.create(Value) catch return error.OutOfMemory;
        value.* = .{ .integer = initial };
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

    pub fn setChild(self: *Value, child: *const Child) void {
        self.* = .{ .child = child };
    }

    pub fn borrow(self: *Value) *const Value {
        return self;
    }

    pub fn deinit(self: *Value) void {
        std.heap.page_allocator.destroy(self);
    }
};

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
    value.setChild(child);
    try std.testing.expectEqual(@as(i32, 17), value.child.value);
    try std.testing.expect(value.borrow() == value);
}
