//! A library that reads and writes through `std.Io` streams rather than
//! through buffers it owns. Everything here takes a `*std.Io.Writer` or a
//! `*std.Io.Reader` and never learns where the bytes came from or went.
const std = @import("std");

pub const DumpError = error{WriteFailed};
pub const LoadError = error{ ReadFailed, TooLarge };

/// A document is a list of lines. Nothing about it knows about streaming; the
/// streaming is in how it is written out and read back.
pub const Document = struct {
    lines: std.ArrayList([]u8) = .empty,

    pub fn create() error{OutOfMemory}!*Document {
        const value = try std.heap.c_allocator.create(Document);
        value.* = .{};
        return value;
    }

    pub fn deinit(self: *Document) void {
        for (self.lines.items) |line| std.heap.c_allocator.free(line);
        self.lines.deinit(std.heap.c_allocator);
        std.heap.c_allocator.destroy(self);
    }

    pub fn append(self: *Document, line: []const u8) error{OutOfMemory}!void {
        const copy = try std.heap.c_allocator.dupe(u8, line);
        errdefer std.heap.c_allocator.free(copy);
        try self.lines.append(std.heap.c_allocator, copy);
    }

    pub fn count(self: *Document) usize {
        return self.lines.items.len;
    }

    /// Writes every line out, newline separated. The output is far larger than
    /// the shim's staging buffer for a document of any size, which is the
    /// point: the buffer is what keeps the crossings proportional to the
    /// payload rather than to the number of `writeAll` calls.
    pub fn dump(self: *Document, w: *std.Io.Writer) DumpError!void {
        for (self.lines.items) |line| {
            try w.writeAll(line);
            try w.writeByte('\n');
        }
    }

    /// Reads newline-terminated lines until the stream ends, and reports how
    /// many bytes it consumed. A trailing fragment with no newline is not a
    /// line: `dump` always terminates, so a stream this can read always does.
    pub fn load(self: *Document, r: *std.Io.Reader) LoadError!usize {
        var total: usize = 0;
        while (true) {
            const line = r.takeDelimiterExclusive('\n') catch |err| switch (err) {
                error.EndOfStream => break,
                error.StreamTooLong => return error.TooLarge,
                error.ReadFailed => return error.ReadFailed,
            };
            // The line is handed over without its delimiter, and the delimiter
            // is left in the stream; the copy has to happen before it moves.
            self.append(line) catch return error.TooLarge;
            r.toss(1);
            total += line.len + 1;
        }
        return total;
    }
};

/// A free function taking a stream, so the example covers the shape that has
/// no receiver and no error union of its own.
pub fn banner(w: *std.Io.Writer, width: u32) DumpError!void {
    var remaining = width;
    while (remaining != 0) : (remaining -= 1) try w.writeByte('=');
    try w.writeByte('\n');
}

/// Copies a reader into a writer, so one call exercises both directions at
/// once and the byte count comes back through the return value.
pub fn tee(r: *std.Io.Reader, w: *std.Io.Writer) LoadError!usize {
    return r.streamRemaining(w) catch |err| switch (err) {
        error.ReadFailed => error.ReadFailed,
        error.WriteFailed => error.ReadFailed,
    };
}

test "a document round-trips through a fixed buffer" {
    const document = try Document.create();
    defer document.deinit();
    try document.append("alpha");
    try document.append("beta");

    var storage: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&storage);
    try document.dump(&writer);
    try std.testing.expectEqualStrings("alpha\nbeta\n", writer.buffered());

    const restored = try Document.create();
    defer restored.deinit();
    var reader: std.Io.Reader = .fixed(writer.buffered());
    try std.testing.expectEqual(@as(usize, 11), try restored.load(&reader));
    try std.testing.expectEqual(@as(usize, 2), restored.count());
}
