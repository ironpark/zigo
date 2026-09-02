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

/// Sample buffers handed to the caller and not yet released. The Go tests read
/// it to prove the generated binding calls the release function exactly once.
var live_samples: std.atomic.Value(usize) = .init(0);

/// The same idea for `extractLimits`, whose result the Go side reinterprets
/// rather than copying a second time.
var live_limits: std.atomic.Value(usize) = .init(0);

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

    /// clone copies the queued events, name and limits into an independent
    /// queue that the caller owns and must close. The copy takes its own
    /// observer instead of sharing the original's, so closing either queue
    /// never strands the other's callback.
    pub fn clone(self: *EventQueue, observer: Observer, userdata: usize) CreateError!*EventQueue {
        const copy = try EventQueue.create(self.name_bytes, self.capacity_value, self.policy_value, observer, userdata);
        errdefer copy.deinit();
        copy.items.appendSlice(std.heap.page_allocator, self.items.items) catch return error.OutOfMemory;
        copy.dropped_count = self.dropped_count;
        copy.processed_count = self.processed_count;
        return copy;
    }

    /// mergeFrom appends another queue's events to this one under the current
    /// policy and reports how many were taken. A null source is not an error:
    /// it merges nothing, which is what makes the parameter optional.
    pub fn mergeFrom(self: *EventQueue, source: ?*const EventQueue) EnqueueError!usize {
        const other = source orelse return 0;
        var taken: usize = 0;
        for (other.items.items) |event| {
            try self.enqueue(event.id, event.value);
            taken += 1;
        }
        return taken;
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

    /// Sentinel byte pointers use the C string lowering and surface as Go
    /// strings without a separate length parameter.
    pub fn echoCString(text: [*:0]const u8) [*:0]const u8 {
        return text;
    }

    pub fn sampleCString() [*:0]const u8 {
        return "sentinel event queue";
    }

    pub fn extractPaths(paths: []const []const u8) usize {
        var total: usize = 0;
        for (paths) |path| total += path.len;
        return total;
    }

    pub fn extractSentinelSlices(paths: []const [:0]const u8) usize {
        var total: usize = 0;
        for (paths) |path| total += path.len;
        return total;
    }

    pub fn extractSentinelPointers(paths: []const [*:0]const u8) usize {
        var total: usize = 0;
        for (paths) |path| total += std.mem.len(path);
        return total;
    }

    /// A numeric slice return intentionally points at native storage. The Go
    /// binding must copy it before returning so a caller cannot alias it.
    pub fn sampleValues(_: *EventQueue) []const f32 {
        return &.{ 0.25, 1.5, 3.75 };
    }

    /// sampleValuesChecked returns the same samples as `sampleValues`, but an
    /// empty queue has nothing to sample and fails instead. The generated
    /// binding must report that error without reading the slice output
    /// parameters the shim never wrote.
    pub fn sampleValuesChecked(self: *EventQueue) ProcessError![]const f32 {
        if (self.items.items.len == 0) return error.Empty;
        return &.{ 0.25, 1.5, 3.75 };
    }

    /// Hands the caller a freshly allocated buffer. Ownership moves with the
    /// return value, so the generated binding must copy it and then call
    /// `freeSamples` before handing the slice to Go.
    pub fn extractSamples(self: *EventQueue) []f32 {
        const allocator = std.heap.page_allocator;
        const samples = allocator.alloc(f32, self.items.items.len + 1) catch return &.{};
        samples[0] = @floatFromInt(self.items.items.len);
        for (self.items.items, 1..) |event, index| samples[index] = @floatFromInt(event.value);
        _ = live_samples.fetchAdd(1, .monotonic);
        return samples;
    }

    /// extractSamplesChecked hands over a buffer exactly like `extractSamples`,
    /// but an empty queue fails before allocating anything. Nothing is handed
    /// over on that path, so the generated binding must not call `freeSamples`.
    pub fn extractSamplesChecked(self: *EventQueue) ProcessError![]f32 {
        if (self.items.items.len == 0) return error.Empty;
        return self.extractSamples();
    }

    /// The same samples as `extractSamples`, written into a buffer the caller
    /// already has. Nothing is allocated and nothing has to be released: the
    /// result says how many entries were filled, and everything past that is
    /// still whatever the caller left there.
    pub fn extractSamplesInto(self: *EventQueue, dst: []f32) usize {
        const wanted = self.items.items.len + 1;
        if (dst.len < wanted) return 0;
        dst[0] = @floatFromInt(self.items.items.len);
        for (self.items.items, 1..) |event, index| dst[index] = @floatFromInt(event.value);
        return wanted;
    }

    /// One `Limits` row per queued event, up to what the buffer holds. `Limits`
    /// has no bool field, so both backends hand the buffer's address straight
    /// to the native call and neither direction copies.
    pub fn limitsInto(self: *EventQueue, dst: []Limits) usize {
        const written = @min(dst.len, self.items.items.len);
        for (dst[0..written]) |*entry| entry.* = self.limits();
        return written;
    }

    /// Caller-owned limit rows. `Limits` has no bool field, so the generated
    /// binding copies the buffer once, releases it, and reinterprets that copy
    /// as `[]Limits` instead of converting every row again.
    pub fn extractLimits(self: *EventQueue) []Limits {
        const allocator = std.heap.page_allocator;
        const rows = allocator.alloc(Limits, self.items.items.len) catch return &.{};
        const current = self.limits();
        for (rows, 0..) |*row, index| row.* = .{
            .capacity = current.capacity + @as(u32, @intCast(index)),
            .policy = current.policy,
        };
        _ = live_limits.fetchAdd(1, .monotonic);
        return rows;
    }

    /// Releases a buffer produced by `extractLimits`.
    pub fn freeLimits(_: *EventQueue, rows: []Limits) void {
        if (rows.len == 0) return;
        std.heap.page_allocator.free(rows);
        _ = live_limits.fetchSub(1, .monotonic);
    }

    /// Releases a buffer produced by `extractSamples`.
    pub fn freeSamples(_: *EventQueue, samples: []f32) void {
        if (samples.len == 0) return;
        std.heap.page_allocator.free(samples);
        _ = live_samples.fetchSub(1, .monotonic);
    }

    /// Accepts a batch of value snapshots so both backends exercise their
    /// struct-slice input conversion path.
    pub fn acceptStats(_: *EventQueue, values: []const Stats) usize {
        return values.len;
    }

    /// Fills one value snapshot per queued event. The return value is the
    /// number of output entries written, while the explicit out metadata keeps
    /// the slice capacity visible in the C ABI.
    pub fn estimate(self: *EventQueue, output: []Stats) ProcessError!usize {
        if (output.len < self.items.items.len) return error.InvalidLimit;
        const summary = self.stats();
        for (output[0..self.items.items.len]) |*entry| entry.* = summary;
        return self.items.items.len;
    }

    /// Returns value snapshots from native storage; the generated Go binding
    /// must copy each struct before exposing the slice.
    pub fn sampleStats(self: *EventQueue) []const Stats {
        const summary = self.stats();
        return &.{ summary, summary };
    }

    /// Borrowed limit rows from native storage. The raw layer still copies
    /// them out of native memory; only the public layer's second copy is gone.
    pub fn sampleLimits(self: *EventQueue) []const Limits {
        const current = self.limits();
        return &.{ current, .{ .capacity = current.capacity + 1, .policy = current.policy } };
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

/// Sample buffers still owned by the library. A correct binding returns this to
/// zero after every `extractSamples` call.
pub fn liveSamples() usize {
    return live_samples.load(.monotonic);
}

pub fn liveLimits() usize {
    return live_limits.load(.monotonic);
}

pub fn liveQueues() usize {
    return live_queues.load(.monotonic);
}

test "merging from a null source is a no-op" {
    const observer = struct {
        fn call(_: u64, _: i32, _: usize) callconv(.c) i32 {
            return 0;
        }
    }.call;
    const target = try EventQueue.create("target", 4, .reject, &observer, 0);
    defer target.deinit();
    const source = try EventQueue.create("source", 4, .reject, &observer, 0);
    defer source.deinit();
    try source.enqueue(1, 10);
    try source.enqueue(2, 20);

    try std.testing.expectEqual(@as(usize, 0), try target.mergeFrom(null));
    try std.testing.expectEqual(@as(usize, 0), target.len());
    try std.testing.expectEqual(@as(usize, 2), try target.mergeFrom(source));
    try std.testing.expectEqual(@as(usize, 2), target.len());
}

test "a cloned queue owns its own events" {
    const observer = struct {
        fn call(_: u64, _: i32, _: usize) callconv(.c) i32 {
            return 0;
        }
    }.call;
    const queue = try EventQueue.create("source", 2, .reject, &observer, 0);
    defer queue.deinit();
    try queue.enqueue(1, 10);

    const copy = try queue.clone(&observer, 7);
    defer copy.deinit();
    try std.testing.expectEqualStrings("source", copy.name());
    try std.testing.expectEqual(@as(usize, 1), copy.len());
    try std.testing.expectEqual(@as(usize, 2), liveQueues());

    try copy.enqueue(2, 20);
    try std.testing.expectEqual(@as(usize, 2), copy.len());
    try std.testing.expectEqual(@as(usize, 1), queue.len());
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
