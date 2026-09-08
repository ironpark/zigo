//! Ownership and formatting metadata shared by generation, publish and check.
const std = @import("std");
pub const filename = ".zigo-outputs.json";
pub const File = struct {
    path: []const u8,
    kind: enum { go, artifact, native },
    pub fn publishable(self: File) bool {
        return self.kind != .native;
    }
};
pub const Document = struct {
    version: u32 = 1,
    files: []const File,
    pub fn contains(self: Document, path: []const u8) bool {
        for (self.files) |file| if (file.publishable() and std.mem.eql(u8, file.path, path)) return true;
        return false;
    }
};
pub fn read(allocator: std.mem.Allocator, io: std.Io, directory: std.Io.Dir) !?std.json.Parsed(Document) {
    const bytes = directory.readFileAlloc(io, filename, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(bytes);
    const parsed = std.json.parseFromSlice(Document, allocator, bytes, .{ .allocate = .alloc_always }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return error.InvalidOutputManifest,
    };
    errdefer parsed.deinit();
    if (parsed.value.version != 1) return error.InvalidOutputManifest;
    for (parsed.value.files, 0..) |file, index| {
        if (!validPath(file.path)) return error.InvalidOutputManifest;
        for (parsed.value.files[0..index]) |previous| if (std.ascii.eqlIgnoreCase(previous.path, file.path)) return error.InvalidOutputManifest;
    }
    return parsed;
}
fn validPath(path: []const u8) bool {
    if (path.len == 0 or std.mem.indexOfAny(u8, path, "\\:\x00") != null or std.ascii.eqlIgnoreCase(path, filename)) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}
