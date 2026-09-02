const std = @import("std");

pub const CreateError = error{OutOfMemory};

var live_objects: std.atomic.Value(usize) = .init(0);

pub const Counter = struct {
    value: i64,

    pub fn create(initial: i64) CreateError!*Counter {
        const counter = std.heap.page_allocator.create(Counter) catch return error.OutOfMemory;
        counter.* = .{ .value = initial };
        _ = live_objects.fetchAdd(1, .monotonic);
        return counter;
    }

    pub fn get(self: *Counter) i64 {
        return self.value;
    }

    pub fn add(self: *Counter, delta: i64) i64 {
        self.value += delta;
        return self.value;
    }

    pub fn deinit(self: *Counter) void {
        std.heap.page_allocator.destroy(self);
        _ = live_objects.fetchSub(1, .monotonic);
    }
};

pub const Accumulator = struct {
    total_value: i64 = 0,

    pub fn create() CreateError!*Accumulator {
        const accumulator = std.heap.page_allocator.create(Accumulator) catch return error.OutOfMemory;
        accumulator.* = .{};
        _ = live_objects.fetchAdd(1, .monotonic);
        return accumulator;
    }

    /// Adds the current value of another exposed opaque type.
    pub fn absorb(self: *Accumulator, counter: *const Counter) i64 {
        self.total_value += counter.value;
        return self.total_value;
    }

    pub fn total(self: *Accumulator) i64 {
        return self.total_value;
    }

    pub fn deinit(self: *Accumulator) void {
        std.heap.page_allocator.destroy(self);
        _ = live_objects.fetchSub(1, .monotonic);
    }
};

pub fn liveObjects() usize {
    return live_objects.load(.monotonic);
}

/// Grouping an API under namespace structs instead of a flat root is ordinary
/// Zig, and a binding addresses it with the same dotted path the Zig caller
/// writes: `root.text.unicode.codepointWidth`.
pub const text = struct {
    pub const unicode = struct {
        /// Reports how many terminal cells a codepoint occupies.
        pub fn codepointWidth(cp: u21) u8 {
            return if (cp < 0x1100) 1 else 2;
        }
    };

    /// Reports how many cells a run of codepoints occupies.
    pub fn runWidth(first: u21, second: u21) u16 {
        return @as(u16, unicode.codepointWidth(first)) + unicode.codepointWidth(second);
    }
};

test "one opaque receiver accepts another exposed opaque type" {
    const counter = try Counter.create(40);
    defer counter.deinit();
    const accumulator = try Accumulator.create();
    defer accumulator.deinit();

    try std.testing.expectEqual(@as(i64, 40), accumulator.absorb(counter));
    try std.testing.expectEqual(@as(i64, 42), counter.add(2));
    try std.testing.expectEqual(@as(i64, 82), accumulator.absorb(counter));
    try std.testing.expectEqual(@as(i64, 82), accumulator.total());
    try std.testing.expectEqual(@as(usize, 2), liveObjects());
}

test "a nested namespace is reachable through its dotted path" {
    try std.testing.expectEqual(@as(u8, 2), text.unicode.codepointWidth(0x1100));
    try std.testing.expectEqual(@as(u16, 3), text.runWidth(0x1100, 'a'));
}

test "independent type lifecycles return the shared count to zero" {
    const counter = try Counter.create(1);
    try std.testing.expectEqual(@as(usize, 1), liveObjects());
    const accumulator = try Accumulator.create();
    try std.testing.expectEqual(@as(usize, 2), liveObjects());
    accumulator.deinit();
    counter.deinit();
    try std.testing.expectEqual(@as(usize, 0), liveObjects());
}
