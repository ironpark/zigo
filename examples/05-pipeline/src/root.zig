const std = @import("std");

pub const AllocationError = error{OutOfMemory};
pub const CreateError = error{ OutOfMemory, InvalidName };
pub const ProcessError = error{ EmptyInput, Disabled, CallbackPanicked };

pub const Mode = enum(u32) {
    sum,
    weighted,
};

pub const Transform = *const fn (value: i32, userdata: usize) callconv(.c) i32;

var live_bytes: std.atomic.Value(usize) = .init(0);

pub const Pipeline = struct {
    name_bytes: []u8,
    mode_value: Mode,
    enabled: bool = true,
    callback: Transform,
    userdata: usize,
    processed_count: usize = 0,
    running_total: i64 = 0,

    pub fn create(
        input_name: []const u8,
        pipeline_mode: Mode,
        callback: Transform,
        userdata: usize,
    ) CreateError!*Pipeline {
        if (input_name.len == 0) return error.InvalidName;

        const allocator = std.heap.page_allocator;
        const owned_name = allocator.dupe(u8, input_name) catch return error.OutOfMemory;
        errdefer allocator.free(owned_name);

        const pipeline = allocator.create(Pipeline) catch return error.OutOfMemory;
        pipeline.* = .{
            .name_bytes = owned_name,
            .mode_value = pipeline_mode,
            .callback = callback,
            .userdata = userdata,
        };
        _ = live_bytes.fetchAdd(@sizeOf(Pipeline) + owned_name.len, .monotonic);
        return pipeline;
    }

    pub fn process(self: *Pipeline, values: []const i32) ProcessError!i64 {
        if (!self.enabled) return error.Disabled;
        if (values.len == 0) return error.EmptyInput;

        var batch_total: i64 = 0;
        for (values, 0..) |value, index| {
            const transformed = self.callback(value, self.userdata);
            if (transformed == -3) return error.CallbackPanicked;
            const weight: i64 = switch (self.mode_value) {
                .sum => 1,
                .weighted => @intCast(index + 1),
            };
            batch_total += @as(i64, transformed) * weight;
        }

        self.processed_count += values.len;
        self.running_total += batch_total;
        return batch_total;
    }

    pub fn name(self: *Pipeline) []const u8 {
        return self.name_bytes;
    }

    pub fn mode(self: *Pipeline) Mode {
        return self.mode_value;
    }

    pub fn setEnabled(self: *Pipeline, enabled: bool) bool {
        const previous = self.enabled;
        self.enabled = enabled;
        return previous;
    }

    pub fn processed(self: *Pipeline) usize {
        return self.processed_count;
    }

    pub fn total(self: *Pipeline) i64 {
        return self.running_total;
    }

    pub fn deinit(self: *Pipeline) void {
        const allocator = std.heap.page_allocator;
        const owned_bytes = @sizeOf(Pipeline) + self.name_bytes.len;
        allocator.free(self.name_bytes);
        allocator.destroy(self);
        _ = live_bytes.fetchSub(owned_bytes, .monotonic);
    }
};

pub fn Batch(comptime T: type) type {
    return struct {
        const Self = @This();
        items: std.ArrayList(T) = .empty,

        pub fn create() AllocationError!*Self {
            const batch = std.heap.page_allocator.create(Self) catch return error.OutOfMemory;
            batch.* = .{};
            return batch;
        }

        pub fn push(self: *Self, value: T) AllocationError!void {
            self.items.append(std.heap.page_allocator, value) catch return error.OutOfMemory;
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

pub const IntBatch = Batch(i32);
pub const FloatBatch = Batch(f64);

pub fn liveBytes() usize {
    return live_bytes.load(.monotonic);
}

extern fn compressBound(source_len: usize) callconv(.c) usize;

pub fn compressionBound(source_len: usize) usize {
    return compressBound(source_len);
}

test "pipeline combines callbacks, slices, state, and typed errors" {
    const transform = struct {
        fn call(value: i32, userdata: usize) callconv(.c) i32 {
            return value + @as(i32, @intCast(userdata));
        }
    }.call;

    {
        const pipeline = try Pipeline.create("복합 파이프라인", .weighted, &transform, 10);
        defer pipeline.deinit();

        try std.testing.expectEqualStrings("복합 파이프라인", pipeline.name());
        try std.testing.expectEqual(Mode.weighted, pipeline.mode());
        try std.testing.expectEqual(@as(i64, 74), try pipeline.process(&.{ 1, 2, 3 }));
        try std.testing.expectEqual(@as(usize, 3), pipeline.processed());
        try std.testing.expectEqual(@as(i64, 74), pipeline.total());
        try std.testing.expect(pipeline.setEnabled(false));
        try std.testing.expectError(error.Disabled, pipeline.process(&.{1}));
        try std.testing.expect(!pipeline.setEnabled(true));
        try std.testing.expectError(error.EmptyInput, pipeline.process(&.{}));
    }
    try std.testing.expectEqual(@as(usize, 0), liveBytes());
    try std.testing.expectError(error.InvalidName, Pipeline.create("", .sum, &transform, 0));
}

test "named generic batches remain independent" {
    const ints = try IntBatch.create();
    defer ints.deinit();
    try ints.push(7);
    try ints.push(9);
    try std.testing.expectEqual(@as(usize, 2), ints.len());

    const floats = try FloatBatch.create();
    defer floats.deinit();
    try floats.push(1.5);
    try std.testing.expectEqual(@as(usize, 1), floats.len());
}

test "system library call is linked into the module" {
    try std.testing.expect(compressionBound(1024) > 1024);
}
