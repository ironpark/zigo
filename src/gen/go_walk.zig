const std = @import("std");

/// Build outputs that live inside the package but never hold published
/// bindings. A `go_dir` pointing at the build root (the colocated layout) puts
/// the generator's own cached copies under `.zig-cache`; walking into them made
/// prune delete cached output first and then, on the next cache hit, the real
/// committed `*_gen.go` files. Both the prune walk and `zigo check` therefore
/// treat these names as invisible at any depth.
pub const skipped_dir_names = [_][]const u8{ ".zig-cache", "zig-out" };

pub fn isSkippedDir(name: []const u8) bool {
    for (skipped_dir_names) |skipped| {
        if (std.mem.eql(u8, name, skipped)) return true;
    }
    return false;
}

/// A `std.Io.Dir.Walker` that does not descend into `skipped_dir_names`.
///
/// Skipped directories are still reported as entries, exactly like the standard
/// walker reports directories, so callers that filter on `entry.kind` need no
/// change beyond swapping the constructor.
pub const Walker = struct {
    inner: std.Io.Dir.SelectiveWalker,

    pub const Entry = std.Io.Dir.Walker.Entry;

    pub fn next(self: *Walker, io: std.Io) !?Entry {
        const entry = try self.inner.next(io) orelse return null;
        if (entry.kind == .directory and !isSkippedDir(entry.basename))
            try self.inner.enter(io, entry);
        return entry;
    }

    pub fn deinit(self: *Walker) void {
        self.inner.deinit();
    }
};

pub fn walk(dir: std.Io.Dir, allocator: std.mem.Allocator) !Walker {
    return .{ .inner = try dir.walkSelectively(allocator) };
}

test "walk skips build cache directories at any depth" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "nested/.zig-cache/o/deadbeef");
    try tmp.dir.createDirPath(std.testing.io, "zig-out/lib");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "nested/keep_gen.go", .data = "keep\n" });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "nested/.zig-cache/o/deadbeef/cached_gen.go",
        .data = "cached\n",
    });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "zig-out/lib/out_gen.go", .data = "out\n" });

    var found: std.ArrayList([]const u8) = .empty;
    defer {
        for (found.items) |item| std.testing.allocator.free(item);
        found.deinit(std.testing.allocator);
    }
    var walker = try walk(tmp.dir, std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(std.testing.io)) |entry| {
        if (entry.kind != .file) continue;
        try found.append(std.testing.allocator, try std.testing.allocator.dupe(u8, entry.path));
    }
    try std.testing.expectEqual(@as(usize, 1), found.items.len);
    try std.testing.expectEqualStrings("nested/keep_gen.go", found.items[0]);
}
