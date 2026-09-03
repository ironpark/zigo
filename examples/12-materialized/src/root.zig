const std = @import("std");

pub const Status = enum(u8) { ready, busy };

pub const Leaf = struct {
    value: i32,
    enabled: bool,
    label: []const u8,
    samples: []const f64,
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
};

const samples = [_]f64{ 1.25, -2.5, 9.75 };
const codes = [_]i16{ 3, -7, 21 };
const tags = [_][]const u8{ "alpha", "beta" };
const leaf = Leaf{ .value = 42, .enabled = true, .label = "leaf", .samples = &samples };
const children = [_]Leaf{
    leaf,
    .{ .value = -9, .enabled = false, .label = "second", .samples = &samples },
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
};
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

pub fn release(buffer: []u8) void {
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
