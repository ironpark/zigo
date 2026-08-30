const std = @import("std");

pub const CreateError = error{OutOfMemory};

pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();
        items: std.ArrayList(T) = .empty,

        pub fn create() CreateError!*Self {
            const value = std.heap.page_allocator.create(Self) catch return error.OutOfMemory;
            value.* = .{};
            return value;
        }

        pub fn push(self: *Self, value: T) void {
            self.items.append(std.heap.page_allocator, value) catch return;
        }

        pub fn len(self: *Self) usize {
            return self.items.items.len;
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(std.heap.page_allocator);
            std.heap.page_allocator.destroy(self);
        }
    };
}

pub const FloatBuffer = Buffer(f32);
pub const IntBuffer = Buffer(i32);

pub const Observer = *const fn (value: i32, userdata: usize) callconv(.c) i32;

pub const CallbackContext = struct {
    callback: Observer,
    userdata: usize,

    pub fn create(callback: Observer, userdata: usize) CreateError!*CallbackContext {
        const value = std.heap.page_allocator.create(CallbackContext) catch return error.OutOfMemory;
        value.* = .{ .callback = callback, .userdata = userdata };
        return value;
    }

    pub fn run(self: *CallbackContext, value: i32) i32 {
        return self.callback(value, self.userdata);
    }

    pub fn deinit(self: *CallbackContext) void {
        std.heap.page_allocator.destroy(self);
    }
};

test "generic specializations and callback context" {
    const float_buffer = try FloatBuffer.create();
    defer float_buffer.deinit();
    float_buffer.push(1.5);
    try std.testing.expectEqual(@as(usize, 1), float_buffer.len());

    const callback = struct {
        fn call(value: i32, _: usize) callconv(.c) i32 {
            return value + 1;
        }
    }.call;
    const context = try CallbackContext.create(&callback, 0);
    defer context.deinit();
    try std.testing.expectEqual(@as(i32, 8), context.run(7));
}
