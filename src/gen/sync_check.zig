const std = @import("std");

pub const DifferenceKind = enum { missing, content };
pub const Difference = struct { kind: DifferenceKind, path: []const u8 };

pub const Result = struct {
    differences: std.ArrayList(Difference) = .empty,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        for (self.differences.items) |difference| allocator.free(difference.path);
        self.differences.deinit(allocator);
    }

    pub fn matches(self: Result) bool {
        return self.differences.items.len == 0;
    }

    pub fn render(self: Result, writer: *std.Io.Writer) !void {
        for (self.differences.items) |difference| {
            try writer.print("generated file {s}: {s}\n", .{ @tagName(difference.kind), difference.path });
        }
    }
};

/// Compare only generated Go files. Other source files in go_dir belong to the
/// consumer and are deliberately outside the check's scope.
pub fn compare(allocator: std.mem.Allocator, io: std.Io, generated: std.Io.Dir, go_dir: std.Io.Dir) !Result {
    var result: Result = .{};
    errdefer result.deinit(allocator);
    var walker = try generated.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".go")) continue;
        const actual = go_dir.readFileAlloc(io, entry.path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => {
                try append(allocator, &result, .missing, entry.path);
                continue;
            },
            else => return err,
        };
        defer allocator.free(actual);
        const expected = try generated.readFileAlloc(io, entry.path, allocator, .limited(64 * 1024 * 1024));
        defer allocator.free(expected);
        if (!std.mem.eql(u8, expected, actual)) try append(allocator, &result, .content, entry.path);
    }
    std.mem.sort(Difference, result.differences.items, {}, struct {
        fn lessThan(_: void, lhs: Difference, rhs: Difference) bool {
            return std.mem.lessThan(u8, lhs.path, rhs.path);
        }
    }.lessThan);
    return result;
}

fn append(allocator: std.mem.Allocator, result: *Result, kind: DifferenceKind, path: []const u8) !void {
    try result.differences.append(allocator, .{ .kind = kind, .path = try allocator.dupe(u8, path) });
}

test "source check reports a changed generated Go file" {
    var generated = std.testing.tmpDir(.{ .iterate = true });
    defer generated.cleanup();
    var source = std.testing.tmpDir(.{ .iterate = true });
    defer source.cleanup();
    try generated.dir.createDirPath(std.testing.io, "nested");
    try source.dir.createDirPath(std.testing.io, "nested");
    try generated.dir.writeFile(std.testing.io, .{ .sub_path = "nested/generated.go", .data = "current\n" });
    try source.dir.writeFile(std.testing.io, .{ .sub_path = "nested/generated.go", .data = "edited\n" });
    try source.dir.writeFile(std.testing.io, .{ .sub_path = "nested/user.go", .data = "package nested\n" });
    var result = try compare(std.testing.allocator, std.testing.io, generated.dir, source.dir);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), result.differences.items.len);
    try std.testing.expectEqualStrings("nested/generated.go", result.differences.items[0].path);
}
