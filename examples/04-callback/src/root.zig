const std = @import("std");

pub const CreateError = error{OutOfMemory};

pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();
        items: std.ArrayList(T) = .empty,

        pub fn create() CreateError!*Self {
            const value = std.heap.page_allocator.create(Self) catch return error.OutOfMemory;
            value.* = .{};
            return value;
        }

        pub fn push(self: *Self, value: T) void {
            self.items.append(std.heap.page_allocator, value) catch return;
        }

        pub fn len(self: *Self) usize {
            return self.items.items.len;
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(std.heap.page_allocator);
            std.heap.page_allocator.destroy(self);
        }
    };
}

pub const FloatBuffer = Buffer(f32);
pub const IntBuffer = Buffer(i32);

pub const Observer = *const fn (value: i32, userdata: usize) callconv(.c) i32;
pub const VoidObserver = *const fn (value: i32, userdata: usize) callconv(.c) void;

pub fn apply(value: i32, callback: Observer, userdata: usize) i32 {
    return callback(value, userdata);
}

/// Calls callback until limit is reached or cancel is raised. The callback's
/// return value is deliberately ignored so the generated failure path must
/// trip cancel rather than relying on an in-band sentinel to stop this loop.
pub fn applyUntilCancelled(limit: u32, callback: Observer, userdata: usize, cancel: *const std.atomic.Value(u32)) error{Canceled}!u32 {
    var runs: u32 = 0;
    while (runs < limit and cancel.load(.seq_cst) == 0) : (runs += 1) {
        _ = callback(@intCast(runs), userdata);
    }
    if (cancel.load(.seq_cst) != 0) return error.Canceled;
    return runs;
}

pub fn notify(value: i32, callback: VoidObserver, userdata: usize) void {
    callback(value, userdata);
}

/// A predicate takes and returns `bool`. The shim converts between the `u8`
/// the wire carries and the `bool` this signature declares.
pub const Predicate = *const fn (value: i32, strict: bool, userdata: usize) callconv(.c) bool;

/// True when predicate accepts value. `strict` is passed through untouched so
/// the round trip of a `bool` parameter is observable from Go.
pub fn filter(value: i32, strict: bool, predicate: Predicate, userdata: usize) bool {
    return predicate(value, strict, userdata);
}

/// A visitor receives one codepoint. It returns nothing because purego only
/// carries `void` or `i32` callback results.
pub const Visitor = *const fn (cp: u32, userdata: usize) callconv(.c) void;

/// Calls visitor for every codepoint of text and returns the last one, or 0
/// for empty text. Malformed bytes are visited as U+FFFD.
pub fn visitCodepoints(text: []const u8, visitor: Visitor, userdata: usize) u32 {
    var last: u32 = 0;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        visitor(cp, userdata);
        last = cp;
    }
    return last;
}

/// A logger receives a NUL-terminated level name and the message as a
/// pointer/length pair. Both reach Go as `string` copies the callback may keep.
pub const Logger = *const fn (level: [*:0]const u8, message: [*]const u8, message_len: usize, userdata: usize) callconv(.c) void;

/// Logs message at the info level, then at the debug level, through logger.
pub fn logMessage(message: []const u8, logger: Logger, userdata: usize) void {
    logger("info", message.ptr, message.len, userdata);
    logger("debug", message.ptr, message.len, userdata);
}

/// A sink receives a chunk of bytes. The binding marks the pair `.opaque_bytes`,
/// so Go sees `[]byte` rather than `string`.
pub const ByteSink = *const fn (data: [*]const u8, len: usize, userdata: usize) callconv(.c) void;

/// Splits data into chunks of at most chunk_len bytes and hands each to sink.
pub fn emitChunks(data: []const u8, chunk_len: usize, sink: ByteSink, userdata: usize) usize {
    var count: usize = 0;
    var rest = data;
    while (rest.len != 0) : (count += 1) {
        const take = @min(chunk_len, rest.len);
        sink(rest.ptr, take, userdata);
        rest = rest[take..];
    }
    return count;
}

/// A reducer takes its context first, the way many C libraries declare their
/// callbacks. The binding points `.userdata = .first` at it and the shim thunk
/// reorders the arguments into the order Go dispatches in.
pub const Reducer = *const fn (ctx: usize, acc: i32, value: i32) callconv(.c) i32;

/// Folds values through reducer, starting from zero.
pub fn reduce(ctx: usize, values: []const i32, reducer: Reducer) i32 {
    var acc: i32 = 0;
    for (values) |value| acc = reducer(ctx, acc, value);
    return acc;
}

pub const CallbackContext = struct {
    const Stats = struct { runs: std.atomic.Value(u32) = .init(0) };

    callback: Observer,
    userdata: usize,
    stats: Stats = .{},

    pub fn create(callback: Observer, userdata: usize) CreateError!*CallbackContext {
        const value = std.heap.page_allocator.create(CallbackContext) catch return error.OutOfMemory;
        value.* = .{ .callback = callback, .userdata = userdata };
        return value;
    }

    pub fn run(self: *CallbackContext, value: i32) i32 {
        _ = self.stats.runs.fetchAdd(1, .seq_cst);
        return self.callback(value, self.userdata);
    }

    pub fn deinit(self: *CallbackContext) void {
        std.heap.page_allocator.destroy(self);
    }
};

pub fn panicNow() CreateError!void {
    @panic("deliberate boundary panic");
}

extern fn compressBound(source_len: usize) callconv(.c) usize;

pub fn compressionBound(source_len: usize) usize {
    return compressBound(source_len);
}

pub fn incrementShared(counter: *std.atomic.Value(u64), delta: u64) u64 {
    return counter.fetchAdd(delta, .seq_cst) + delta;
}

pub fn readShared(value: *const std.atomic.Value(i32)) i32 {
    return value.load(.seq_cst);
}

test "generic specializations and callback context" {
    const float_buffer = try FloatBuffer.create();
    defer float_buffer.deinit();
    float_buffer.push(1.5);
    try std.testing.expectEqual(@as(usize, 1), float_buffer.len());

    const callback = struct {
        fn call(value: i32, _: usize) callconv(.c) i32 {
            return value + 1;
        }
    }.call;
    const context = try CallbackContext.create(&callback, 0);
    defer context.deinit();
    try std.testing.expectEqual(@as(i32, 8), context.run(7));
    try std.testing.expectEqual(@as(i32, 9), apply(8, &callback, 0));

    var cancel: std.atomic.Value(u32) = .init(0);
    try std.testing.expectEqual(@as(u32, 3), applyUntilCancelled(3, &callback, 0, &cancel));

    const predicate = struct {
        fn call(value: i32, strict: bool, _: usize) callconv(.c) bool {
            return if (strict) value > 0 else value >= 0;
        }
    }.call;
    try std.testing.expect(!filter(0, true, &predicate, 0));
    try std.testing.expect(filter(0, false, &predicate, 0));

    const reducer = struct {
        fn call(_: usize, acc: i32, value: i32) callconv(.c) i32 {
            return acc + value;
        }
    }.call;
    try std.testing.expectEqual(@as(i32, 6), reduce(0, &.{ 1, 2, 3 }, &reducer));

    var notified: i32 = 0;
    const void_callback = struct {
        fn call(value: i32, userdata: usize) callconv(.c) void {
            const output: *i32 = @ptrFromInt(userdata);
            output.* = value;
        }
    }.call;
    notify(10, &void_callback, @intFromPtr(&notified));
    try std.testing.expectEqual(@as(i32, 10), notified);
}
