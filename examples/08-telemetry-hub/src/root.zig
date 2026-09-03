const std = @import("std");

pub const CreateError = error{ OutOfMemory, InvalidName, InvalidCapacity };
pub const RenameError = error{ OutOfMemory, InvalidName };
pub const ConfigError = error{ NonFinite, InvalidRange };
pub const PushError = error{ Disabled, Full, NonFinite };
pub const ProcessError = error{ Empty, InvalidLimit, ObserverPanicked };
pub const QueryError = error{ Empty, InvalidRange };
pub const ReduceError = error{ Empty, Cancelled };

pub const Mode = enum(u32) {
    raw,
    scaled,
    absolute,
};

pub const OverflowPolicy = enum(u32) {
    reject,
    drop_oldest,
};

pub const Severity = enum(u32) {
    debug,
    info,
    warning,
    critical,
};

pub const Observer = *const fn (id: u64, value: f64, userdata: usize) callconv(.c) i32;

const Sample = struct {
    id: u64,
    value: f64,
    severity: Severity,
};

var live_hubs: std.atomic.Value(usize) = .init(0);

pub const TelemetryHub = struct {
    name_bytes: []u8,
    samples: std.ArrayList(Sample) = .empty,
    capacity_value: usize,
    mode_value: Mode,
    overflow_policy_value: OverflowPolicy,
    enabled_value: bool = true,
    threshold_value: f64 = -std.math.inf(f64),
    scale_factor_value: f64 = 1,
    offset_value: f64 = 0,
    observer: Observer,
    userdata: usize,
    next_id: u64 = 1,
    accepted_count: usize = 0,
    rejected_count: usize = 0,
    dropped_count: usize = 0,
    processed_count: usize = 0,
    filtered_count: usize = 0,

    pub fn create(
        input_name: []const u8,
        max_samples: usize,
        initial_mode: Mode,
        overflow_policy: OverflowPolicy,
        observer: Observer,
        userdata: usize,
    ) CreateError!*TelemetryHub {
        if (input_name.len == 0) return error.InvalidName;
        if (max_samples == 0) return error.InvalidCapacity;
        const allocator = std.heap.page_allocator;
        const name_bytes = allocator.dupe(u8, input_name) catch return error.OutOfMemory;
        errdefer allocator.free(name_bytes);
        const hub = allocator.create(TelemetryHub) catch return error.OutOfMemory;
        errdefer allocator.destroy(hub);
        hub.* = .{
            .name_bytes = name_bytes,
            .capacity_value = max_samples,
            .mode_value = initial_mode,
            .overflow_policy_value = overflow_policy,
            .observer = observer,
            .userdata = userdata,
        };
        hub.samples.ensureTotalCapacity(allocator, max_samples) catch return error.OutOfMemory;
        _ = live_hubs.fetchAdd(1, .monotonic);
        return hub;
    }

    pub fn rename(self: *TelemetryHub, new_name: []const u8) RenameError!void {
        if (new_name.len == 0) return error.InvalidName;
        const allocator = std.heap.page_allocator;
        const replacement = allocator.dupe(u8, new_name) catch return error.OutOfMemory;
        allocator.free(self.name_bytes);
        self.name_bytes = replacement;
    }

    pub fn name(self: *TelemetryHub) []const u8 {
        return self.name_bytes;
    }

    /// A deliberately long fold, polling a cancellation flag between rounds.
    /// The flag is Go's: a goroutine watching `ctx.Done()` raises it while
    /// this is running, and the only thing that has to be true for that to be
    /// safe is that this reads it atomically and never writes it.
    pub fn reduce(self: *TelemetryHub, rounds: u32, cancel: *const std.atomic.Value(u32)) ReduceError!f64 {
        if (self.samples.items.len == 0) return error.Empty;
        var total: f64 = 0;
        var round: u32 = 0;
        while (round < rounds) : (round += 1) {
            if (cancel.load(.monotonic) != 0) return error.Cancelled;
            for (self.samples.items) |sample| total += sample.value;
        }
        return total;
    }

    pub fn capacity(self: *TelemetryHub) usize {
        return self.capacity_value;
    }

    pub fn len(self: *TelemetryHub) usize {
        return self.samples.items.len;
    }

    pub fn isEmpty(self: *TelemetryHub) bool {
        return self.samples.items.len == 0;
    }

    pub fn isFull(self: *TelemetryHub) bool {
        return self.samples.items.len == self.capacity_value;
    }

    pub fn mode(self: *TelemetryHub) Mode {
        return self.mode_value;
    }

    pub fn setMode(self: *TelemetryHub, new_mode: Mode) Mode {
        const previous = self.mode_value;
        self.mode_value = new_mode;
        return previous;
    }

    pub fn overflowPolicy(self: *TelemetryHub) OverflowPolicy {
        return self.overflow_policy_value;
    }

    pub fn setOverflowPolicy(self: *TelemetryHub, new_policy: OverflowPolicy) OverflowPolicy {
        const previous = self.overflow_policy_value;
        self.overflow_policy_value = new_policy;
        return previous;
    }

    pub fn enabled(self: *TelemetryHub) bool {
        return self.enabled_value;
    }

    pub fn setEnabled(self: *TelemetryHub, new_enabled: bool) bool {
        const previous = self.enabled_value;
        self.enabled_value = new_enabled;
        return previous;
    }

    pub fn threshold(self: *TelemetryHub) f64 {
        return self.threshold_value;
    }

    pub fn setThreshold(self: *TelemetryHub, new_threshold: f64) ConfigError!void {
        if (std.math.isNan(new_threshold)) return error.NonFinite;
        self.threshold_value = new_threshold;
    }

    pub fn scaleFactor(self: *TelemetryHub) f64 {
        return self.scale_factor_value;
    }

    pub fn setScaleFactor(self: *TelemetryHub, new_factor: f64) ConfigError!void {
        if (!std.math.isFinite(new_factor)) return error.NonFinite;
        self.scale_factor_value = new_factor;
    }

    pub fn offset(self: *TelemetryHub) f64 {
        return self.offset_value;
    }

    pub fn setOffset(self: *TelemetryHub, new_offset: f64) ConfigError!void {
        if (!std.math.isFinite(new_offset)) return error.NonFinite;
        self.offset_value = new_offset;
    }

    pub fn push(self: *TelemetryHub, id: u64, value: f64) PushError!void {
        return self.pushWithSeverity(id, value, .info);
    }

    pub fn pushWithSeverity(self: *TelemetryHub, id: u64, value: f64, severity: Severity) PushError!void {
        if (!self.enabled_value) {
            self.rejected_count += 1;
            return error.Disabled;
        }
        if (!std.math.isFinite(value)) {
            self.rejected_count += 1;
            return error.NonFinite;
        }
        try self.makeRoom(1);
        self.samples.appendAssumeCapacity(.{ .id = id, .value = value, .severity = severity });
        self.accepted_count += 1;
    }

    pub fn pushBatch(self: *TelemetryHub, values: []const f64) PushError!void {
        if (!self.enabled_value) {
            self.rejected_count += values.len;
            return error.Disabled;
        }
        for (values) |value| if (!std.math.isFinite(value)) {
            self.rejected_count += values.len;
            return error.NonFinite;
        };
        if (self.overflow_policy_value == .reject and values.len > self.capacity_value - self.samples.items.len) {
            self.rejected_count += values.len;
            return error.Full;
        }
        for (values) |value| {
            try self.makeRoom(1);
            self.samples.appendAssumeCapacity(.{ .id = self.next_id, .value = value, .severity = .info });
            self.next_id +%= 1;
            self.accepted_count += 1;
        }
    }

    pub fn process(self: *TelemetryHub, limit: usize) ProcessError!usize {
        if (limit == 0) return error.InvalidLimit;
        if (self.samples.items.len == 0) return error.Empty;
        const count = @min(limit, self.samples.items.len);
        var consumed: usize = 0;
        while (consumed < count) {
            const sample = self.samples.items[0];
            const value = self.transformedValue(sample.value);
            if (value < self.threshold_value) {
                _ = self.samples.orderedRemove(0);
                self.filtered_count += 1;
                consumed += 1;
                continue;
            }
            if (self.observer(sample.id, value, self.userdata) == -3) return error.ObserverPanicked;
            _ = self.samples.orderedRemove(0);
            self.processed_count += 1;
            consumed += 1;
        }
        return consumed;
    }

    pub fn processAll(self: *TelemetryHub) ProcessError!usize {
        if (self.samples.items.len == 0) return error.Empty;
        return self.process(self.samples.items.len);
    }

    pub fn clear(self: *TelemetryHub) usize {
        const removed = self.samples.items.len;
        self.samples.clearRetainingCapacity();
        return removed;
    }

    pub fn resetStatistics(self: *TelemetryHub) void {
        self.accepted_count = 0;
        self.rejected_count = 0;
        self.dropped_count = 0;
        self.processed_count = 0;
        self.filtered_count = 0;
    }

    pub fn accepted(self: *TelemetryHub) usize {
        return self.accepted_count;
    }

    pub fn rejected(self: *TelemetryHub) usize {
        return self.rejected_count;
    }

    pub fn dropped(self: *TelemetryHub) usize {
        return self.dropped_count;
    }

    pub fn processed(self: *TelemetryHub) usize {
        return self.processed_count;
    }

    pub fn filtered(self: *TelemetryHub) usize {
        return self.filtered_count;
    }

    pub fn sum(self: *TelemetryHub) f64 {
        var result: f64 = 0;
        for (self.samples.items) |sample| result += sample.value;
        return result;
    }

    pub fn minimum(self: *TelemetryHub) QueryError!f64 {
        if (self.samples.items.len == 0) return error.Empty;
        var result = self.samples.items[0].value;
        for (self.samples.items[1..]) |sample| result = @min(result, sample.value);
        return result;
    }

    pub fn maximum(self: *TelemetryHub) QueryError!f64 {
        if (self.samples.items.len == 0) return error.Empty;
        var result = self.samples.items[0].value;
        for (self.samples.items[1..]) |sample| result = @max(result, sample.value);
        return result;
    }

    pub fn average(self: *TelemetryHub) QueryError!f64 {
        if (self.samples.items.len == 0) return error.Empty;
        return self.sum() / @as(f64, @floatFromInt(self.samples.items.len));
    }

    pub fn firstId(self: *TelemetryHub) QueryError!u64 {
        if (self.samples.items.len == 0) return error.Empty;
        return self.samples.items[0].id;
    }

    pub fn firstValue(self: *TelemetryHub) QueryError!f64 {
        if (self.samples.items.len == 0) return error.Empty;
        return self.samples.items[0].value;
    }

    pub fn lastId(self: *TelemetryHub) QueryError!u64 {
        if (self.samples.items.len == 0) return error.Empty;
        return self.samples.items[self.samples.items.len - 1].id;
    }

    pub fn lastValue(self: *TelemetryHub) QueryError!f64 {
        if (self.samples.items.len == 0) return error.Empty;
        return self.samples.items[self.samples.items.len - 1].value;
    }

    pub fn lastSeverity(self: *TelemetryHub) QueryError!Severity {
        if (self.samples.items.len == 0) return error.Empty;
        return self.samples.items[self.samples.items.len - 1].severity;
    }

    pub fn countAbove(self: *TelemetryHub, boundary: f64) ConfigError!usize {
        if (!std.math.isFinite(boundary)) return error.NonFinite;
        var count: usize = 0;
        for (self.samples.items) |sample| count += @intFromBool(sample.value > boundary);
        return count;
    }

    pub fn countBelow(self: *TelemetryHub, boundary: f64) ConfigError!usize {
        if (!std.math.isFinite(boundary)) return error.NonFinite;
        var count: usize = 0;
        for (self.samples.items) |sample| count += @intFromBool(sample.value < boundary);
        return count;
    }

    pub fn containsAbove(self: *TelemetryHub, boundary: f64) ConfigError!bool {
        return (try self.countAbove(boundary)) != 0;
    }

    pub fn containsBelow(self: *TelemetryHub, boundary: f64) ConfigError!bool {
        return (try self.countBelow(boundary)) != 0;
    }

    pub fn scaleValues(self: *TelemetryHub, factor: f64) ConfigError!void {
        if (!std.math.isFinite(factor)) return error.NonFinite;
        for (self.samples.items) |*sample| sample.value *= factor;
    }

    pub fn offsetValues(self: *TelemetryHub, delta: f64) ConfigError!void {
        if (!std.math.isFinite(delta)) return error.NonFinite;
        for (self.samples.items) |*sample| sample.value += delta;
    }

    pub fn clampValues(self: *TelemetryHub, lower: f64, upper: f64) ConfigError!void {
        if (!std.math.isFinite(lower) or !std.math.isFinite(upper)) return error.NonFinite;
        if (lower > upper) return error.InvalidRange;
        for (self.samples.items) |*sample| sample.value = @min(upper, @max(lower, sample.value));
    }

    pub fn absoluteValues(self: *TelemetryHub) void {
        for (self.samples.items) |*sample| sample.value = @abs(sample.value);
    }

    pub fn negateValues(self: *TelemetryHub) void {
        for (self.samples.items) |*sample| sample.value = -sample.value;
    }

    pub fn deinit(self: *TelemetryHub) void {
        const allocator = std.heap.page_allocator;
        self.samples.deinit(allocator);
        allocator.free(self.name_bytes);
        allocator.destroy(self);
        _ = live_hubs.fetchSub(1, .monotonic);
    }

    fn makeRoom(self: *TelemetryHub, needed: usize) PushError!void {
        if (self.samples.items.len + needed <= self.capacity_value) return;
        switch (self.overflow_policy_value) {
            .reject => {
                self.rejected_count += needed;
                return error.Full;
            },
            .drop_oldest => while (self.samples.items.len + needed > self.capacity_value) {
                _ = self.samples.orderedRemove(0);
                self.dropped_count += 1;
            },
        }
    }

    fn transformedValue(self: *TelemetryHub, value: f64) f64 {
        return switch (self.mode_value) {
            .raw => value,
            .scaled => value * self.scale_factor_value + self.offset_value,
            .absolute => @abs(value),
        };
    }
};

pub fn liveHubs() usize {
    return live_hubs.load(.monotonic);
}

test "broad configuration ingestion query and transform surface" {
    const observer = struct {
        fn call(_: u64, _: f64, _: usize) callconv(.c) i32 {
            return 0;
        }
    }.call;
    const hub = try TelemetryHub.create("telemetry", 4, .raw, .reject, &observer, 0);
    defer hub.deinit();

    try hub.pushWithSeverity(10, -2, .warning);
    try hub.pushBatch(&.{ 4, 8 });
    try std.testing.expectEqual(@as(usize, 3), hub.len());
    try std.testing.expectApproxEqAbs(@as(f64, 10), hub.sum(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, -2), try hub.minimum(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 8), try hub.maximum(), 0.0001);
    try std.testing.expectEqual(@as(usize, 2), try hub.countAbove(0));
    try std.testing.expect(try hub.containsBelow(0));
    hub.absoluteValues();
    try hub.scaleValues(2);
    try hub.offsetValues(1);
    try hub.clampValues(0, 10);
    try std.testing.expectApproxEqAbs(@as(f64, 5), try hub.firstValue(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 10), try hub.lastValue(), 0.0001);
    try std.testing.expectEqual(Severity.info, try hub.lastSeverity());
}

test "broad processing configuration and lifecycle surface" {
    const observer = struct {
        fn call(_: u64, value: f64, userdata: usize) callconv(.c) i32 {
            return if (value == @as(f64, @floatFromInt(userdata))) -3 else 0;
        }
    }.call;
    const hub = try TelemetryHub.create("processing", 2, .scaled, .drop_oldest, &observer, 99);
    defer hub.deinit();
    try hub.setScaleFactor(2);
    try hub.setOffset(1);
    try hub.setThreshold(0);
    try hub.push(1, -2);
    try hub.push(2, 49);
    try hub.push(3, 3);
    try std.testing.expectEqual(@as(usize, 1), hub.dropped());
    try std.testing.expectError(error.ObserverPanicked, hub.processAll());
    try std.testing.expectEqual(@as(usize, 2), hub.len());
    _ = hub.setMode(.absolute);
    try std.testing.expectEqual(@as(usize, 2), try hub.processAll());
    try std.testing.expect(hub.isEmpty());
    try std.testing.expectEqual(@as(usize, 2), hub.processed());
}

test "broad failures preserve ownership and transactional reject batches" {
    const observer = struct {
        fn call(_: u64, _: f64, _: usize) callconv(.c) i32 {
            return 0;
        }
    }.call;
    const hub = try TelemetryHub.create("safe", 2, .raw, .reject, &observer, 0);
    try hub.push(1, 1);
    try std.testing.expectError(error.Full, hub.pushBatch(&.{ 2, 3 }));
    try std.testing.expectEqual(@as(usize, 1), hub.len());
    try std.testing.expectError(error.InvalidName, hub.rename(""));
    try std.testing.expectEqualStrings("safe", hub.name());
    try std.testing.expectError(error.InvalidRange, hub.clampValues(2, 1));
    hub.deinit();
    try std.testing.expectEqual(@as(usize, 0), liveHubs());
}
