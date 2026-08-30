const std = @import("std");

pub const DifferenceKind = enum { missing, unexpected, content };
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

    pub fn renderTo(self: Result, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.differences.items) |difference| {
            try writer.print("snapshot {s}: {s}\n", .{ @tagName(difference.kind), difference.path });
        }
    }

    pub fn render(self: Result) void {
        var buffer: [64]u8 = undefined;
        const stderr = std.debug.lockStderr(&buffer);
        defer std.debug.unlockStderr();
        self.renderTo(&stderr.file_writer.interface) catch {};
    }
};

pub fn compare(allocator: std.mem.Allocator, io: std.Io, expected: std.Io.Dir, actual: std.Io.Dir) !Result {
    var result: Result = .{};
    errdefer result.deinit(allocator);
    try compareOneWay(allocator, io, expected, actual, false, &result);
    try compareOneWay(allocator, io, actual, expected, true, &result);
    std.mem.sort(Difference, result.differences.items, {}, lessThan);
    return result;
}

pub fn updateGolden(allocator: std.mem.Allocator, io: std.Io, golden: std.Io.Dir, actual: std.Io.Dir) !void {
    var stale_paths: std.ArrayList([]u8) = .empty;
    defer {
        for (stale_paths.items) |path| allocator.free(path);
        stale_paths.deinit(allocator);
    }

    var golden_walker = try golden.walk(allocator);
    defer golden_walker.deinit();
    while (try golden_walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        actual.access(io, entry.path, .{}) catch |err| switch (err) {
            error.FileNotFound => try stale_paths.append(allocator, try allocator.dupe(u8, entry.path)),
            else => return err,
        };
    }
    for (stale_paths.items) |path| try golden.deleteFile(io, path);

    var actual_walker = try actual.walk(allocator);
    defer actual_walker.deinit();
    while (try actual_walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const contents = try actual.readFileAlloc(io, entry.path, allocator, .limited(64 * 1024 * 1024));
        defer allocator.free(contents);
        if (std.fs.path.dirname(entry.path)) |dirname| try golden.createDirPath(io, dirname);
        try golden.writeFile(io, .{ .sub_path = entry.path, .data = contents });
    }
}

fn compareOneWay(allocator: std.mem.Allocator, io: std.Io, source: std.Io.Dir, destination: std.Io.Dir, report_unexpected: bool, result: *Result) !void {
    var walker = try source.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const destination_bytes = destination.readFileAlloc(io, entry.path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => {
                try appendDifference(allocator, result, if (report_unexpected) .unexpected else .missing, entry.path);
                continue;
            },
            else => return err,
        };
        defer allocator.free(destination_bytes);
        if (!report_unexpected) {
            const source_bytes = try source.readFileAlloc(io, entry.path, allocator, .limited(64 * 1024 * 1024));
            defer allocator.free(source_bytes);
            if (!std.mem.eql(u8, source_bytes, destination_bytes)) try appendDifference(allocator, result, .content, entry.path);
        }
    }
}

fn appendDifference(allocator: std.mem.Allocator, result: *Result, kind: DifferenceKind, path: []const u8) !void {
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    try result.differences.append(allocator, .{ .kind = kind, .path = owned_path });
}

fn lessThan(_: void, lhs: Difference, rhs: Difference) bool {
    const order = std.mem.order(u8, lhs.path, rhs.path);
    if (order != .eq) return order == .lt;
    return @intFromEnum(lhs.kind) < @intFromEnum(rhs.kind);
}

test "reports a corrupted golden tree by file name" {
    var expected = std.testing.tmpDir(.{ .iterate = true });
    defer expected.cleanup();
    var actual = std.testing.tmpDir(.{ .iterate = true });
    defer actual.cleanup();
    try expected.dir.createDirPath(std.testing.io, "nested");
    try actual.dir.createDirPath(std.testing.io, "nested");
    try expected.dir.writeFile(std.testing.io, .{ .sub_path = "nested/nested_gen.go", .data = "golden\n" });
    try actual.dir.writeFile(std.testing.io, .{ .sub_path = "nested/nested_gen.go", .data = "corrupted\n" });
    var result = try compare(std.testing.allocator, std.testing.io, expected.dir, actual.dir);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!result.matches());
    try std.testing.expectEqual(@as(usize, 1), result.differences.items.len);
    try std.testing.expectEqual(DifferenceKind.content, result.differences.items[0].kind);
    try std.testing.expectEqualStrings("nested/nested_gen.go", result.differences.items[0].path);

    var rendered: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer rendered.deinit();
    try result.renderTo(&rendered.writer);
    try std.testing.expectEqualStrings("snapshot content: nested/nested_gen.go\n", rendered.written());
}

test "update mode makes the golden tree match actual output" {
    var golden = std.testing.tmpDir(.{ .iterate = true });
    defer golden.cleanup();
    var actual = std.testing.tmpDir(.{ .iterate = true });
    defer actual.cleanup();
    try golden.dir.writeFile(std.testing.io, .{ .sub_path = "stale.txt", .data = "remove me" });
    try actual.dir.createDirPath(std.testing.io, "nested");
    try actual.dir.writeFile(std.testing.io, .{ .sub_path = "nested/nested_gen.go", .data = "current\n" });

    try updateGolden(std.testing.allocator, std.testing.io, golden.dir, actual.dir);
    var result = try compare(std.testing.allocator, std.testing.io, golden.dir, actual.dir);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.matches());
}

test "snapshot comparison cleans up every partial allocation failure" {
    var expected = std.testing.tmpDir(.{ .iterate = true });
    defer expected.cleanup();
    var actual = std.testing.tmpDir(.{ .iterate = true });
    defer actual.cleanup();
    try expected.dir.writeFile(std.testing.io, .{ .sub_path = "value.txt", .data = "expected\n" });
    try actual.dir.writeFile(std.testing.io, .{ .sub_path = "value.txt", .data = "actual\n" });
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expectContentDifference, .{ expected.dir, actual.dir });
}

fn expectContentDifference(allocator: std.mem.Allocator, expected: std.Io.Dir, actual: std.Io.Dir) !void {
    var result = try compare(allocator, std.testing.io, expected, actual);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.differences.items.len);
}
