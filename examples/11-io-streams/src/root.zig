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

/// The other direction: an object that *hands out* a `std.Io.Writer` instead
/// of taking one. The pointer belongs to the sink, so it never crosses to Go;
/// the binding generates `Write` and `Flush` on the handle, and each of them
/// calls `writer()` again.
pub const Sink = struct {
    inner: std.Io.Writer.Allocating,

    pub fn create() error{OutOfMemory}!*Sink {
        const value = try std.heap.c_allocator.create(Sink);
        value.* = .{ .inner = .init(std.heap.c_allocator) };
        return value;
    }

    pub fn deinit(self: *Sink) void {
        self.inner.deinit();
        std.heap.c_allocator.destroy(self);
    }

    /// Re-fetched by every generated operation rather than stored anywhere.
    pub fn writer(self: *Sink) *std.Io.Writer {
        return &self.inner.writer;
    }

    pub fn count(self: *Sink) usize {
        return self.inner.written().len;
    }
};

/// The reading mirror of `Sink`: it owns the bytes and hands out a reader over
/// them, so Go gets a `Read` that satisfies `io.Reader`.
pub const Source = struct {
    bytes: []u8,
    inner: std.Io.Reader,

    pub fn create(bytes: []const u8) error{OutOfMemory}!*Source {
        const value = try std.heap.c_allocator.create(Source);
        errdefer std.heap.c_allocator.destroy(value);
        const copy = try std.heap.c_allocator.dupe(u8, bytes);
        value.* = .{ .bytes = copy, .inner = .fixed(copy) };
        return value;
    }

    pub fn deinit(self: *Source) void {
        std.heap.c_allocator.free(self.bytes);
        std.heap.c_allocator.destroy(self);
    }

    pub fn reader(self: *Source) *std.Io.Reader {
        return &self.inner;
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
    // Keep progress explicit instead of asking the reader to reserve writable
    // space in another adapter. This also bounds temporary storage for files
    // larger than either adapter's staging buffer.
    var buffer: [4096]u8 = undefined;
    var total: usize = 0;
    while (true) {
        const count = r.readSliceShort(&buffer) catch return error.ReadFailed;
        if (count == 0) return total;
        w.writeAll(buffer[0..count]) catch return error.ReadFailed;
        total += count;
    }
}

/// Sums Unicode scalar storage after the binding narrows each promoted Go
/// element into the `u21` representation used by Zig text code.
pub fn sumCodepoints(values: []const u21) u32 {
    var total: u32 = 0;
    for (values) |value| total += value;
    return total;
}

/// Writes narrow elements through a caller-owned output slice.
pub fn fillCodepoints(output: []u21) void {
    const sample = [_]u21{ 'A', 0x1f642, 0x10ffff };
    for (output, 0..) |*value, index| value.* = sample[index % sample.len];
}

/// Returns caller-owned narrow storage; generated Go widens it before calling
/// `freeCodepoints` with the original allocation.
pub fn takeCodepoints() []const u21 {
    const result = std.heap.c_allocator.alloc(u21, 3) catch @panic("out of memory");
    result[0] = 'Z';
    result[1] = 0x1f642;
    result[2] = 0x10ffff;
    return result;
}

pub fn freeCodepoints(values: []const u21) void {
    std.heap.c_allocator.free(values);
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

test "a sink and a source hand their streams out" {
    const sink = try Sink.create();
    defer sink.deinit();
    try sink.writer().writeAll("hello");
    try sink.writer().flush();
    try std.testing.expectEqual(@as(usize, 5), sink.count());

    const source = try Source.create("hello");
    defer source.deinit();
    var buffer: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 5), try source.reader().readSliceShort(&buffer));
    try std.testing.expectEqualStrings("hello", buffer[0..5]);
}

test "narrow codepoint slices round-trip" {
    try std.testing.expectEqual(@as(u32, 'A' + 0x1f642), sumCodepoints(&.{ 'A', 0x1f642 }));
    var output: [3]u21 = undefined;
    fillCodepoints(&output);
    try std.testing.expectEqualSlices(u21, &.{ 'A', 0x1f642, 0x10ffff }, &output);
    const owned = takeCodepoints();
    defer freeCodepoints(owned);
    try std.testing.expectEqualSlices(u21, &.{ 'Z', 0x1f642, 0x10ffff }, owned);
}
