const std = @import("std");

pub const CreateError = error{ OutOfMemory, InvalidName, InvalidCapacity };
pub const EnqueueError = error{Full};
pub const ProcessError = error{ Empty, InvalidLimit, ObserverPanicked };

pub const Policy = enum(u32) {
    reject,
    drop_oldest,
};

pub const Observer = *const fn (id: u64, value: i32, userdata: usize) callconv(.c) i32;

/// Counters read back in one call. `extern` fixes the layout, which is what
/// lets zigo mirror the struct into C; Go still sees an ordinary value.
pub const Stats = extern struct {
    len: u32,
    capacity: u32,
    dropped: u32,
    processed: u32,
    policy: Policy,
    saturated: bool,
};

/// Capacity and policy applied together, so the queue is never briefly
/// configured with one but not the other.
pub const Limits = extern struct {
    capacity: u32,
    policy: Policy,
};

const Event = struct {
    id: u64,
    value: i32,
};

var live_queues: std.atomic.Value(usize) = .init(0);

pub const EventQueue = struct {
    name_bytes: []u8,
    items: std.ArrayList(Event) = .empty,
    capacity_value: usize,
    policy_value: Policy,
    observer: Observer,
    userdata: usize,
    dropped_count: usize = 0,
    processed_count: usize = 0,

    pub fn create(
        input_name: []const u8,
        max_events: usize,
        queue_policy: Policy,
        observer: Observer,
        userdata: usize,
    ) CreateError!*EventQueue {
        if (input_name.len == 0) return error.InvalidName;
        if (max_events == 0) return error.InvalidCapacity;

        const allocator = std.heap.page_allocator;
        const name_bytes = allocator.dupe(u8, input_name) catch return error.OutOfMemory;
        errdefer allocator.free(name_bytes);
        const queue = allocator.create(EventQueue) catch return error.OutOfMemory;
        errdefer allocator.destroy(queue);
        queue.* = .{
            .name_bytes = name_bytes,
            .capacity_value = max_events,
            .policy_value = queue_policy,
            .observer = observer,
            .userdata = userdata,
        };
        queue.items.ensureTotalCapacity(allocator, max_events) catch return error.OutOfMemory;
        _ = live_queues.fetchAdd(1, .monotonic);
        return queue;
    }

    pub fn enqueue(self: *EventQueue, id: u64, value: i32) EnqueueError!void {
        if (self.items.items.len == self.capacity_value) switch (self.policy_value) {
            .reject => return error.Full,
            .drop_oldest => {
                _ = self.items.orderedRemove(0);
                self.dropped_count += 1;
            },
        };
        self.items.appendAssumeCapacity(.{ .id = id, .value = value });
    }

    pub fn process(self: *EventQueue, limit: usize) ProcessError!usize {
        if (limit == 0) return error.InvalidLimit;
        if (self.items.items.len == 0) return error.Empty;

        const count = @min(limit, self.items.items.len);
        var delivered: usize = 0;
        while (delivered < count) {
            const event = self.items.items[0];
            if (self.observer(event.id, event.value, self.userdata) == -3) return error.ObserverPanicked;
            _ = self.items.orderedRemove(0);
            self.processed_count += 1;
            delivered += 1;
        }
        return delivered;
    }

    pub fn name(self: *EventQueue) []const u8 {
        return self.name_bytes;
    }

    pub fn len(self: *EventQueue) usize {
        return self.items.items.len;
    }

    pub fn capacity(self: *EventQueue) usize {
        return self.capacity_value;
    }

    pub fn policy(self: *EventQueue) Policy {
        return self.policy_value;
    }

    pub fn dropped(self: *EventQueue) usize {
        return self.dropped_count;
    }

    pub fn processed(self: *EventQueue) usize {
        return self.processed_count;
    }

    pub fn stats(self: *EventQueue) Stats {
        return .{
            .len = @intCast(self.items.items.len),
            .capacity = @intCast(self.capacity_value),
            .dropped = @intCast(self.dropped_count),
            .processed = @intCast(self.processed_count),
            .policy = self.policy_value,
            .saturated = self.items.items.len >= self.capacity_value,
        };
    }

    pub fn applyLimits(self: *EventQueue, updated: Limits) CreateError!void {
        if (updated.capacity == 0) return error.InvalidCapacity;
        self.capacity_value = updated.capacity;
        self.policy_value = updated.policy;
        while (self.items.items.len > self.capacity_value) {
            _ = self.items.orderedRemove(0);
            self.dropped_count += 1;
        }
    }

    pub fn limits(self: *EventQueue) Limits {
        return .{ .capacity = @intCast(self.capacity_value), .policy = self.policy_value };
    }

    pub fn clear(self: *EventQueue) usize {
        const removed = self.items.items.len;
        self.items.clearRetainingCapacity();
        return removed;
    }

    pub fn deinit(self: *EventQueue) void {
        const allocator = std.heap.page_allocator;
        self.items.deinit(allocator);
        allocator.free(self.name_bytes);
        allocator.destroy(self);
        _ = live_queues.fetchSub(1, .monotonic);
    }
};

pub fn liveQueues() usize {
    return live_queues.load(.monotonic);
}

test "reject policy preserves queued events and reports capacity errors" {
    const observer = struct {
        fn call(_: u64, _: i32, _: usize) callconv(.c) i32 {
            return 0;
        }
    }.call;
    const queue = try EventQueue.create("중요 이벤트", 2, .reject, &observer, 0);
    defer queue.deinit();

    try queue.enqueue(10, 100);
    try queue.enqueue(11, 200);
    try std.testing.expectError(error.Full, queue.enqueue(12, 300));
    try std.testing.expectEqual(@as(usize, 2), queue.len());
    try std.testing.expectEqual(@as(usize, 1), try queue.process(1));
    try std.testing.expectEqual(@as(usize, 1), queue.len());
    try std.testing.expectEqual(@as(usize, 1), queue.processed());
}

test "drop-oldest policy and observer failure have explicit state transitions" {
    const observer = struct {
        fn call(id: u64, _: i32, _: usize) callconv(.c) i32 {
            return if (id == 2) -3 else 0;
        }
    }.call;
    const queue = try EventQueue.create("bounded", 2, .drop_oldest, &observer, 0);
    defer queue.deinit();

    try queue.enqueue(1, 10);
    try queue.enqueue(2, 20);
    try queue.enqueue(3, 30);
    try std.testing.expectEqual(@as(usize, 1), queue.dropped());
    try std.testing.expectError(error.ObserverPanicked, queue.process(2));
    try std.testing.expectEqual(@as(usize, 2), queue.len());
    try std.testing.expectEqual(@as(usize, 0), queue.processed());
    try std.testing.expectEqual(@as(usize, 2), queue.clear());
    try std.testing.expectError(error.Empty, queue.process(1));
    try std.testing.expectError(error.InvalidLimit, queue.process(0));
}

test "constructor validation never leaks a live queue" {
    const observer = struct {
        fn call(_: u64, _: i32, _: usize) callconv(.c) i32 {
            return 0;
        }
    }.call;
    try std.testing.expectError(error.InvalidName, EventQueue.create("", 1, .reject, &observer, 0));
    try std.testing.expectError(error.InvalidCapacity, EventQueue.create("queue", 0, .reject, &observer, 0));
    try std.testing.expectEqual(@as(usize, 0), liveQueues());
}
