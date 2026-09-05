//! The `std.Io` adapters the generated shim wraps around a Go `io.Writer` or
//! `io.Reader`. This file is the single source of truth for them: `emit/shim.zig`
//! embeds the region between the markers into every shim that needs it, and
//! the tests below compile and exercise that exact text. A contract this
//! fiddly -- drain order, splat, end of stream, not re-entering a panicked Go
//! frame -- is worth testing where it is written rather than only through a
//! generated binding.
const std = @import("std");

// zigo:adapters-begin
/// Bridges a Zig `*std.Io.Writer` onto the Go `io.Writer` behind `userdata`.
/// `buffer` is what makes the crossing rare: bytes accumulate there and only
/// reach Go when it fills, when the data is too big to be worth buffering, or
/// when the shim flushes on the way out.
const ZigoWriterAdapter = struct {
    interface: std.Io.Writer,
    callback: *const fn (ptr: [*]const u8, len: usize, userdata: usize) callconv(.c) i32,
    userdata: usize,
    /// Set once Go has reported a failure or panicked. Either way there is
    /// nothing left to say to it, and a panicked frame must not be re-entered.
    failed: bool = false,

    const vtable: std.Io.Writer.VTable = .{ .drain = drain, .flush = flush };

    fn init(
        buffer: []u8,
        callback: *const fn (ptr: [*]const u8, len: usize, userdata: usize) callconv(.c) i32,
        userdata: usize,
    ) ZigoWriterAdapter {
        return .{
            .interface = .{ .vtable = &vtable, .buffer = buffer },
            .callback = callback,
            .userdata = userdata,
        };
    }

    fn send(self: *ZigoWriterAdapter, bytes: []const u8) std.Io.Writer.Error!void {
        if (bytes.len == 0) return;
        if (self.failed) return error.WriteFailed;
        if (self.callback(bytes.ptr, bytes.len, self.userdata) != 0) {
            self.failed = true;
            return error.WriteFailed;
        }
    }

    /// Refills rather than forwards. A slice that still fits behind what is
    /// buffered is copied there instead of crossing on its own, which is what
    /// makes the crossings proportional to the payload rather than to the
    /// number of writes: a caller writing forty bytes at a time costs one
    /// crossing per buffer, not one per write. Only a slice at least as large
    /// as the whole buffer is handed over directly, because buffering it
    /// would cost a copy and save nothing.
    fn push(self: *ZigoWriterAdapter, w: *std.Io.Writer, bytes: []const u8) std.Io.Writer.Error!void {
        if (bytes.len == 0) return;
        if (bytes.len >= w.buffer.len) {
            try self.send(w.buffered());
            w.end = 0;
            return self.send(bytes);
        }
        if (w.end + bytes.len > w.buffer.len) {
            try self.send(w.buffered());
            w.end = 0;
        }
        @memcpy(w.buffer[w.end..][0..bytes.len], bytes);
        w.end += bytes.len;
    }

    /// `buffer[0..end]` is written before `data`, then every slice of `data`
    /// in order, then the last one `splat` more times. The returned count
    /// covers `data` only: the buffered bytes were logically written already.
    /// What "written" means here is "accepted", buffered or crossed, which is
    /// what lets the buffer do its job.
    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *ZigoWriterAdapter = @fieldParentPtr("interface", w);
        var written: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            try self.push(w, bytes);
            written += bytes.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| {
            try self.push(w, last);
            written += last.len;
        }
        return written;
    }

    /// Its own rather than `defaultFlush`, which drains until `end` is zero:
    /// a drain that buffers would never make that true.
    fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *ZigoWriterAdapter = @fieldParentPtr("interface", w);
        try self.send(w.buffered());
        w.end = 0;
    }
};

/// Bridges a Zig `*std.Io.Reader` onto the Go `io.Reader` behind `userdata`.
/// Go fills the destination directly, so a read costs one crossing and no copy.
const ZigoReaderAdapter = struct {
    interface: std.Io.Reader,
    callback: *const fn (ptr: [*]u8, capacity: usize, userdata: usize) callconv(.c) i32,
    userdata: usize,
    failed: bool = false,

    const vtable: std.Io.Reader.VTable = .{ .stream = stream };

    fn init(
        buffer: []u8,
        callback: *const fn (ptr: [*]u8, capacity: usize, userdata: usize) callconv(.c) i32,
        userdata: usize,
    ) ZigoReaderAdapter {
        return .{
            .interface = .{ .vtable = &vtable, .buffer = buffer, .seek = 0, .end = 0 },
            .callback = callback,
            .userdata = userdata,
        };
    }

    fn stream(r: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *ZigoReaderAdapter = @fieldParentPtr("interface", r);
        if (self.failed) return error.ReadFailed;
        const destination = limit.slice(try w.writableSliceGreedy(1));
        if (destination.len == 0) return 0;
        // The trampoline reports its count in an `i32`, so a wider destination
        // is offered one `i32` worth of it at a time.
        const capacity = @min(destination.len, @as(usize, std.math.maxInt(i32)));
        const count = self.callback(destination.ptr, capacity, self.userdata);
        if (count < 0) {
            self.failed = true;
            return error.ReadFailed;
        }
        if (count == 0) return error.EndOfStream;
        w.advance(@intCast(count));
        return @intCast(count);
    }
};

// zigo:adapters-end

/// Stands in for the Go side: the trampoline is a C function pointer with no
/// room for state, so the tests reach their recording through `userdata`
/// exactly as the generated trampoline reaches its `CallbackState`.
const Sink = struct {
    calls: std.ArrayList([]u8) = .empty,
    /// Nonzero makes the next crossing report failure, as a Go `Write` that
    /// returned an error does.
    fail_after: ?usize = null,
    /// Bytes the reader hands back, consumed from the front.
    source: []const u8 = "",
    read_calls: usize = 0,
    /// Set when a crossing happened after one already failed, which is the
    /// thing the adapter must never do.
    reentered: bool = false,

    fn deinit(self: *Sink, allocator: std.mem.Allocator) void {
        for (self.calls.items) |call| allocator.free(call);
        self.calls.deinit(allocator);
    }

    fn write(ptr: [*]const u8, len: usize, userdata: usize) callconv(.c) i32 {
        const self: *Sink = @ptrFromInt(userdata);
        if (self.fail_after) |limit| {
            if (self.calls.items.len >= limit) {
                if (self.calls.items.len > limit) self.reentered = true;
                self.calls.append(std.testing.allocator, std.testing.allocator.dupe(u8, "") catch return -1) catch return -1;
                return -1;
            }
        }
        const copy = std.testing.allocator.dupe(u8, ptr[0..len]) catch return -1;
        self.calls.append(std.testing.allocator, copy) catch return -1;
        return 0;
    }

    fn read(ptr: [*]u8, capacity: usize, userdata: usize) callconv(.c) i32 {
        const self: *Sink = @ptrFromInt(userdata);
        self.read_calls += 1;
        const count = @min(capacity, self.source.len);
        @memcpy(ptr[0..count], self.source[0..count]);
        self.source = self.source[count..];
        return @intCast(count);
    }

    fn readFailing(_: [*]u8, _: usize, userdata: usize) callconv(.c) i32 {
        const self: *Sink = @ptrFromInt(userdata);
        if (self.read_calls != 0) self.reentered = true;
        self.read_calls += 1;
        return -1;
    }
};

test "drain buffers what fits and repeats the splat slice" {
    var sink: Sink = .{};
    defer sink.deinit(std.testing.allocator);
    var buffer: [8]u8 = undefined;
    var adapter: ZigoWriterAdapter = .init(&buffer, Sink.write, @intFromPtr(&sink));

    try adapter.interface.writeAll("ab");
    // Still buffered: nothing small enough to fit has crossed yet.
    try std.testing.expectEqual(@as(usize, 0), sink.calls.items.len);
    _ = try ZigoWriterAdapter.drain(&adapter.interface, &.{ "cd", "ef" }, 3);
    try adapter.interface.flush();

    // Order, and the splat repeated three times rather than once plus three.
    // A buffer of 8 holds "ab" + "cd" + "ef", so the fourth "ef" is what
    // forces the first crossing.
    try std.testing.expectEqualStrings("abcdefef", sink.calls.items[0]);
    try std.testing.expectEqualStrings("ef", sink.calls.items[1]);
    try std.testing.expectEqual(@as(usize, 2), sink.calls.items.len);
}

test "the drain result counts data bytes and never the buffered ones" {
    var sink: Sink = .{};
    defer sink.deinit(std.testing.allocator);
    var buffer: [8]u8 = undefined;
    var adapter: ZigoWriterAdapter = .init(&buffer, Sink.write, @intFromPtr(&sink));
    try adapter.interface.writeAll("xyz");
    const written = try ZigoWriterAdapter.drain(&adapter.interface, &.{"1234"}, 2);
    // Eight bytes of `data` were accepted; the three that were already
    // buffered are not part of the count.
    try std.testing.expectEqual(@as(usize, 8), written);
}

test "a payload larger than the buffer costs one crossing per buffer" {
    var sink: Sink = .{};
    defer sink.deinit(std.testing.allocator);
    var buffer: [16]u8 = undefined;
    var adapter: ZigoWriterAdapter = .init(&buffer, Sink.write, @intFromPtr(&sink));
    const payload = "0123456789" ** 10;
    try adapter.interface.writeAll(payload);
    try adapter.interface.flush();

    var total: usize = 0;
    for (sink.calls.items) |call| total += call.len;
    try std.testing.expectEqual(payload.len, total);
    const ceiling = (payload.len + buffer.len - 1) / buffer.len;
    try std.testing.expect(sink.calls.items.len <= ceiling);
}

test "a failed crossing fails the writer and is never retried" {
    var sink: Sink = .{ .fail_after = 0 };
    defer sink.deinit(std.testing.allocator);
    var buffer: [4]u8 = undefined;
    var adapter: ZigoWriterAdapter = .init(&buffer, Sink.write, @intFromPtr(&sink));
    try std.testing.expectError(error.WriteFailed, adapter.interface.writeAll("abcdefghij"));
    try std.testing.expect(adapter.failed);
    const crossings = sink.calls.items.len;
    // The flush the shim runs on the way out must not reach Go again, whether
    // it finds bytes still buffered or not.
    adapter.interface.flush() catch {};
    try std.testing.expectEqual(crossings, sink.calls.items.len);
    try std.testing.expect(!sink.reentered);
    // And a caller whose next write has to cross gets the failure instead.
    try std.testing.expectError(error.WriteFailed, adapter.interface.writeAll("more bytes than the buffer holds"));
    try std.testing.expectEqual(crossings, sink.calls.items.len);
}

test "the reader streams what Go hands over and reports end of stream at zero" {
    var sink: Sink = .{ .source = "hello world" };
    defer sink.deinit(std.testing.allocator);
    var buffer: [4]u8 = undefined;
    var adapter: ZigoReaderAdapter = .init(&buffer, Sink.read, @intFromPtr(&sink));

    var collected: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer collected.deinit();
    const streamed = adapter.interface.streamRemaining(&collected.writer) catch |err| switch (err) {
        error.ReadFailed => return err,
        else => return err,
    };
    try std.testing.expectEqual(@as(usize, 11), streamed);
    try std.testing.expectEqualStrings("hello world", collected.written());
}

test "a failed read fails the reader and is never retried" {
    var sink: Sink = .{};
    defer sink.deinit(std.testing.allocator);
    var buffer: [8]u8 = undefined;
    var adapter: ZigoReaderAdapter = .init(&buffer, Sink.readFailing, @intFromPtr(&sink));
    var collected: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer collected.deinit();

    try std.testing.expectError(error.ReadFailed, adapter.interface.streamRemaining(&collected.writer));
    try std.testing.expectError(error.ReadFailed, adapter.interface.streamRemaining(&collected.writer));
    try std.testing.expect(!sink.reentered);
    try std.testing.expectEqual(@as(usize, 1), sink.read_calls);
}
