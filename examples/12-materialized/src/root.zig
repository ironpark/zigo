const std = @import("std");

pub const Status = enum(u8) { ready, busy };

pub const Point = extern struct { x: i32, y: i32 };

pub const Leaf = struct {
    value: i32,
    enabled: bool,
    label: []const u8,
    samples: []const f64,
    alias: ?[]const u8,
};

pub const Probe = struct {
    id: u64,
    active: bool,
    status: Status,
    name: []const u8,
    codes: []const i16,
    tags: []const []const u8,
    embedded: Leaf,
    child: *const Leaf,
    maybe: ?*const Leaf,
    children: []const Leaf,
    weight: ?f64,
    note: ?[]const u8,
    origin: Point,
    matrix: []const []const i32,
    raw: []const u8,
    flags: [3]bool,
    spare: ?Leaf,
};

const samples = [_]f64{ 1.25, -2.5, 9.75 };
const codes = [_]i16{ 3, -7, 21 };
const tags = [_][]const u8{ "alpha", "beta" };
const leaf = Leaf{ .value = 42, .enabled = true, .label = "leaf", .samples = &samples, .alias = "L" };
const children = [_]Leaf{
    leaf,
    .{ .value = -9, .enabled = false, .label = "second", .samples = &samples, .alias = null },
};
const probe = Probe{
    .id = 0xfeed_beef,
    .active = true,
    .status = .ready,
    .name = "materialized",
    .codes = &codes,
    .tags = &tags,
    .embedded = leaf,
    .child = &leaf,
    .maybe = null,
    .children = &children,
    .weight = 0.5,
    .note = null,
    .origin = .{ .x = -3, .y = 9 },
    .matrix = &matrix,
    .raw = &.{ 0, 255, 7 },
    .flags = .{ true, false, true },
    .spare = leaf,
};
const row_a = [_]i32{ 1, 2 };
const row_b = [_]i32{3};
const matrix = [_][]const i32{ &row_a, &row_b };
const corpus = [_]Probe{probe} ** 128;

pub fn snapshot() Probe {
    return probe;
}

pub fn probeMany() error{Invalid}![]const Probe {
    return &corpus;
}

pub fn fill(output: []Probe) usize {
    const count = @min(output.len, corpus.len);
    @memcpy(output[0..count], corpus[0..count]);
    return count;
}

var released_buffers: u32 = 0;

pub fn releasedBuffers() u32 {
    return released_buffers;
}

pub fn release(buffer: []u8) void {
    released_buffers += 1;
    std.heap.c_allocator.free(buffer);
}

pub const LegacyLeaf = struct {
    item: *const Leaf,

    pub fn value(self: *const LegacyLeaf) i32 {
        return self.item.value;
    }
};

pub const LegacyProbe = struct {
    item: *const Probe,
    leaf_view: LegacyLeaf,

    pub fn create(index: usize) error{Invalid}!*LegacyProbe {
        if (index >= corpus.len) return error.Invalid;
        const result = std.heap.c_allocator.create(LegacyProbe) catch return error.Invalid;
        result.* = .{ .item = &corpus[index], .leaf_view = .{ .item = corpus[index].child } };
        return result;
    }

    pub fn id(self: *const LegacyProbe) u64 {
        return self.item.id;
    }

    pub fn active(self: *const LegacyProbe) bool {
        return self.item.active;
    }

    pub fn child(self: *const LegacyProbe) *const LegacyLeaf {
        return &self.leaf_view;
    }

    pub fn deinit(self: *LegacyProbe) void {
        std.heap.c_allocator.destroy(self);
    }
};

test "materialized sources expose the same tree in every position" {
    try std.testing.expectEqual(@as(u64, 0xfeed_beef), snapshot().id);
    try std.testing.expectEqual(@as(usize, 128), (try probeMany()).len);
    var output: [2]Probe = undefined;
    try std.testing.expectEqual(@as(usize, 2), fill(&output));
    try std.testing.expectEqualStrings("second", output[0].children[1].label);
}

/// Reports the materialized wire format used by this example.
pub fn wireVersion() u32 {
    return 1;
}

/// A bounded source used to demonstrate optional materialized iteration.
pub const Cursor = struct {
    position: u32 = 0,
    limit: u32,
    fail_at: u32,

    pub fn create(limit: u32, fail_at: u32) error{OutOfMemory}!*Cursor {
        const self = try std.heap.c_allocator.create(Cursor);
        self.* = .{ .limit = limit, .fail_at = fail_at };
        return self;
    }

    pub fn next(self: *Cursor) ?Probe {
        if (self.position == self.limit) return null;
        self.position += 1;
        return probe;
    }

    pub fn nextChecked(self: *Cursor) error{Invalid}!?Probe {
        if (self.position == self.fail_at) return error.Invalid;
        return self.next();
    }

    pub fn count(self: *const Cursor) u32 {
        return self.position;
    }

    pub fn deinit(self: *Cursor) void {
        std.heap.c_allocator.destroy(self);
    }
};

pub fn optionalSnapshot(present: bool) ?Probe {
    return if (present) probe else null;
}

pub fn optionalBatch(present: bool, empty: bool) ?[]const Probe {
    return if (!present) null else if (empty) corpus[0..0] else &corpus;
}

pub fn optionalBatchChecked(present: bool, empty: bool, fail: bool) error{Invalid}!?[]const Probe {
    if (fail) return error.Invalid;
    return optionalBatch(present, empty);
}
