const std = @import("std");

pub const CreateError = error{OutOfMemory};

var live_objects: std.atomic.Value(usize) = .init(0);

pub const Counter = struct {
    value: i64,

    pub fn create(initial: i64) CreateError!*Counter {
        const counter = std.heap.page_allocator.create(Counter) catch return error.OutOfMemory;
        counter.* = .{ .value = initial };
        _ = live_objects.fetchAdd(1, .monotonic);
        return counter;
    }

    pub fn get(self: *Counter) i64 {
        return self.value;
    }

    pub fn add(self: *Counter, delta: i64) i64 {
        self.value += delta;
        return self.value;
    }

    pub fn deinit(self: *Counter) void {
        std.heap.page_allocator.destroy(self);
        _ = live_objects.fetchSub(1, .monotonic);
    }
};

pub const Accumulator = struct {
    total_value: i64 = 0,

    pub fn create() CreateError!*Accumulator {
        const accumulator = std.heap.page_allocator.create(Accumulator) catch return error.OutOfMemory;
        accumulator.* = .{};
        _ = live_objects.fetchAdd(1, .monotonic);
        return accumulator;
    }

    /// Adds the current value of another exposed opaque type.
    pub fn absorb(self: *Accumulator, counter: *const Counter) i64 {
        self.total_value += counter.value;
        return self.total_value;
    }

    pub fn total(self: *Accumulator) i64 {
        return self.total_value;
    }

    pub fn deinit(self: *Accumulator) void {
        std.heap.page_allocator.destroy(self);
        _ = live_objects.fetchSub(1, .monotonic);
    }
};

/// A library that builds its enums from a table of names gives them a
/// `@typeName` that ends in the slice expression rather than in a name -- this
/// is the shape ghostty's `lib.Enum(...)` has. Nothing here is a Go identifier,
/// so the binding registers the type and supplies the name.
pub fn Enum(comptime names: []const []const u8) type {
    comptime var values: [names.len]u8 = undefined;
    inline for (&values, 0..) |*value, index| value.* = index;
    return @Enum(u8, .exhaustive, names, &values);
}

pub const CursorStyle = Enum(([_][]const u8{ "block", "bar", "underline" })[0..3]);
pub const CharsetSlot = Enum(([_][]const u8{ "block", "bar", "g2" })[0..3]);

pub fn configureStyles(slot: CharsetSlot, style: CursorStyle) bool {
    return slot == .block and style != .block;
}

/// Terminal input can carry erase modes newer than this library knows. The
/// catch-all keeps converting those bytes with `@enumFromInt` well-defined.
pub const EraseDisplay = enum(u8) {
    below,
    above,
    _,
};

pub fn defaultCursorStyle() CursorStyle {
    return .block;
}

/// Reports whether a cursor of this style blinks.
pub fn cursorStyleBlinks(style: CursorStyle) bool {
    return style != .block;
}

pub fn echoEraseDisplay(value: EraseDisplay) EraseDisplay {
    return value;
}

pub fn liveObjects() usize {
    return live_objects.load(.monotonic);
}

/// Grouping an API under namespace structs instead of a flat root is ordinary
/// Zig, and a binding addresses it with the same dotted path the Zig caller
/// writes: `root.text.unicode.codepointWidth`.
pub const text = struct {
    pub const unicode = struct {
        /// Reports how many terminal cells a codepoint occupies.
        pub fn codepointWidth(cp: u21) u8 {
            return if (cp < 0x1100) 1 else 2;
        }
    };

    /// Reports how many cells a run of codepoints occupies.
    pub fn runWidth(first: u21, second: u21) u16 {
        return @as(u16, unicode.codepointWidth(first)) + unicode.codepointWidth(second);
    }
};

/// An `extern struct` is a flat C record, so a whole one can travel behind a
/// nullable pointer even though a `?` inside it could not.
pub const Point = extern struct {
    x: i16,
    y: i16,
};

pub const ShiftError = error{Overflow};

/// A `?u32` on both sides: absent in, absent out.
pub fn doubleWidth(value: ?u32) ?u32 {
    return if (value) |width| width * 2 else null;
}

/// An optional bool has three states at the boundary, and Go sees all three.
pub fn invert(value: ?bool) ?bool {
    return if (value) |flag| !flag else null;
}

/// An optional enum resolves to the default style when it is absent.
pub fn styleOrDefault(style: ?CursorStyle) CursorStyle {
    return style orelse defaultCursorStyle();
}

/// An optional enum on the way out: only a blinking style is reported.
pub fn blinkingStyle(style: ?CursorStyle) ?CursorStyle {
    const resolved = style orelse return null;
    return if (cursorStyleBlinks(resolved)) resolved else null;
}

/// A whole `extern struct` in and out, presence carried alongside.
pub fn shiftPoint(origin: ?Point, delta: i16) ?Point {
    const point = origin orelse return null;
    return .{ .x = point.x + delta, .y = point.y + delta };
}

/// An optional payload inside an error union: the status code carries the
/// error and a separate flag carries presence, so all three outcomes are
/// distinguishable.
pub fn checkedShift(origin: ?Point, delta: i16) ShiftError!?Point {
    const point = origin orelse return null;
    if (delta > 1000) return error.Overflow;
    return .{ .x = point.x + delta, .y = point.y + delta };
}

/// A `?[]const u8` parameter: the slice's own pointer carries absence, so an
/// absent text and an empty one are different arguments.
pub fn describeText(label: ?[]const u8) u8 {
    const value = label orelse return 0;
    return if (value.len == 0) 1 else 2;
}

/// A `?[]const i32` parameter, summed when present.
pub fn sumOrZero(values: ?[]const i32) i64 {
    const slice = values orelse return -1;
    var total: i64 = 0;
    for (slice) |value| total += value;
    return total;
}

const digit_table = [_]i32{ 0, 1, 2, 3, 4 };

/// A `?[]const i32` return over static storage: absent above the table, and
/// an empty-but-present slice at zero.
pub fn leadingDigits(count: u32) ?[]const i32 {
    if (count > digit_table.len) return null;
    return digit_table[0..count];
}

/// A `?[]const u8` return, which Go sees as `(string, bool)`.
pub fn styleName(style: ?CursorStyle) ?[]const u8 {
    return switch (style orelse return null) {
        .block => "block",
        .bar => "bar",
        .underline => "underline",
    };
}

test "an optional slice keeps absence apart from emptiness" {
    try std.testing.expectEqual(@as(u8, 0), describeText(null));
    try std.testing.expectEqual(@as(u8, 1), describeText(""));
    try std.testing.expectEqual(@as(u8, 2), describeText("hi"));
    try std.testing.expectEqual(@as(i64, -1), sumOrZero(null));
    try std.testing.expectEqual(@as(i64, 0), sumOrZero(&.{}));
    try std.testing.expectEqual(@as(i64, 6), sumOrZero(&.{ 1, 2, 3 }));
    try std.testing.expectEqual(@as(usize, 0), leadingDigits(0).?.len);
    try std.testing.expectEqual(@as(usize, 3), leadingDigits(3).?.len);
    try std.testing.expectEqual(@as(?[]const i32, null), leadingDigits(99));
    try std.testing.expectEqualStrings("bar", styleName(.bar).?);
    try std.testing.expectEqual(@as(?[]const u8, null), styleName(null));
}

test "an optional crosses as a value or as its absence" {
    try std.testing.expectEqual(@as(?u32, 84), doubleWidth(42));
    try std.testing.expectEqual(@as(?u32, null), doubleWidth(null));
    try std.testing.expectEqual(@as(?bool, false), invert(true));
    try std.testing.expectEqual(@as(?bool, null), invert(null));
    try std.testing.expectEqual(CursorStyle.block, styleOrDefault(null));
    try std.testing.expectEqual(CursorStyle.bar, styleOrDefault(.bar));
    try std.testing.expectEqual(@as(?CursorStyle, .bar), blinkingStyle(.bar));
    try std.testing.expectEqual(@as(?CursorStyle, null), blinkingStyle(.block));
    try std.testing.expectEqual(@as(?CursorStyle, null), blinkingStyle(null));
}

test "an optional extern struct keeps presence separate from its value" {
    try std.testing.expectEqual(Point{ .x = 3, .y = 4 }, shiftPoint(.{ .x = 1, .y = 2 }, 2).?);
    try std.testing.expectEqual(@as(?Point, null), shiftPoint(null, 2));
    try std.testing.expectEqual(Point{ .x = 2, .y = 3 }, (try checkedShift(.{ .x = 1, .y = 2 }, 1)).?);
    try std.testing.expectEqual(@as(?Point, null), try checkedShift(null, 1));
    try std.testing.expectError(error.Overflow, checkedShift(.{ .x = 1, .y = 2 }, 2000));
}

test "one opaque receiver accepts another exposed opaque type" {
    const counter = try Counter.create(40);
    defer counter.deinit();
    const accumulator = try Accumulator.create();
    defer accumulator.deinit();

    try std.testing.expectEqual(@as(i64, 40), accumulator.absorb(counter));
    try std.testing.expectEqual(@as(i64, 42), counter.add(2));
    try std.testing.expectEqual(@as(i64, 82), accumulator.absorb(counter));
    try std.testing.expectEqual(@as(i64, 82), accumulator.total());
    try std.testing.expectEqual(@as(usize, 2), liveObjects());
}

test "a generated enum still behaves like an ordinary Zig enum" {
    try std.testing.expectEqual(CursorStyle.block, defaultCursorStyle());
    try std.testing.expect(cursorStyleBlinks(.bar));
    try std.testing.expect(!cursorStyleBlinks(.block));
    try std.testing.expect(configureStyles(.block, .bar));
}

test "a non-exhaustive enum accepts unnamed values" {
    const unknown: EraseDisplay = @enumFromInt(42);
    try std.testing.expectEqual(@as(u8, 42), @intFromEnum(echoEraseDisplay(unknown)));
}

test "a nested namespace is reachable through its dotted path" {
    try std.testing.expectEqual(@as(u8, 2), text.unicode.codepointWidth(0x1100));
    try std.testing.expectEqual(@as(u16, 3), text.runWidth(0x1100, 'a'));
}

test "independent type lifecycles return the shared count to zero" {
    const counter = try Counter.create(1);
    try std.testing.expectEqual(@as(usize, 1), liveObjects());
    const accumulator = try Accumulator.create();
    try std.testing.expectEqual(@as(usize, 2), liveObjects());
    accumulator.deinit();
    counter.deinit();
    try std.testing.expectEqual(@as(usize, 0), liveObjects());
}
