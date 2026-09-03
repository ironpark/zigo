const std = @import("std");

pub const Leaf = struct {
    ok: bool,
    values: []const i32,
    labels: []const []const u8,
};

pub const Root = struct {
    count: usize,
    name: []const u8,
    child: *const Leaf,
    maybe: ?*const Leaf,
    children: []const Leaf,
};

const values = [_]i32{ 3, -5 };
const labels = [_][]const u8{ "one", "two" };
const leaf: Leaf = .{ .ok = true, .values = &values, .labels = &labels };
const children = [_]Leaf{leaf};
const root: Root = .{ .count = 1, .name = "root", .child = &leaf, .maybe = null, .children = &children };
const roots = [_]Root{root};

pub fn snapshot() Root {
    return root;
}

pub fn many() error{Invalid}![]const Root {
    return &roots;
}

pub fn fill(output: []Root) usize {
    if (output.len != 0) output[0] = root;
    return @min(output.len, 1);
}

pub fn fillChecked(output: []Root) error{Invalid}!usize {
    return fill(output);
}

pub fn release(buffer: []u8) void {
    std.heap.c_allocator.free(buffer);
}
