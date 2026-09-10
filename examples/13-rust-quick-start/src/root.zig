const std = @import("std");

/// Adds two signed 32-bit integers. The sum must fit in i32.
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

/// Sums a borrowed slice. The total is widened so a long slice of large
/// values cannot overflow the way the elements would.
pub fn sum(values: []const i32) i64 {
    var total: i64 = 0;
    for (values) |value| total += value;
    return total;
}

pub const MathError = error{DivideByZero};

/// Divides two integers, truncating toward zero.
pub fn divide(numerator: i32, denominator: i32) MathError!i32 {
    if (denominator == 0) return error.DivideByZero;
    return @divTrunc(numerator, denominator);
}

/// Bytes the tally allocations currently hold. The Rust tests read this to
/// prove that `Drop` reached the destructor rather than merely compiling.
var live_bytes: std.atomic.Value(usize) = .init(0);

pub fn liveBytes() usize {
    return live_bytes.load(.monotonic);
}

pub const TallyError = error{OutOfMemory};

/// A running total that lives in Zig. Rust owns one through `Drop`.
pub const Tally = struct {
    total: i64 = 0,
    /// Storage the reading borrows from, so the borrow is into the tally
    /// rather than into a temporary.
    reading_value: Reading = undefined,

    pub fn create() TallyError!*Tally {
        const value = std.heap.page_allocator.create(Tally) catch return error.OutOfMemory;
        value.* = .{};
        value.reading_value = .{ .tally = value };
        _ = live_bytes.fetchAdd(@sizeOf(Tally), .monotonic);
        return value;
    }

    /// Adds to the total and reports it. Mutates, so Rust receives `&mut self`.
    pub fn add(self: *Tally, value: i64) i64 {
        self.total += value;
        return self.total;
    }

    /// Reads the total from a copy of the handle's value. Rust receives
    /// `&self`, a distinction Go cannot express.
    pub fn peek(self: Tally) i64 {
        return self.total;
    }

    /// Fails when the total is negative, so Rust gets a `Result`.
    pub fn checkedHalf(self: *Tally) MathError!i64 {
        if (self.total == 0) return error.DivideByZero;
        return @divTrunc(self.total, 2);
    }

    /// Borrows a reading out of the tally. Rust ties the reading's lifetime to
    /// this borrow, so a reading cannot outlive the tally it came from.
    pub fn borrowReading(self: *Tally) *Reading {
        return &self.reading_value;
    }

    /// Renders the total into memory the caller owns. Rust takes ownership of
    /// the allocation instead of copying it.
    pub fn render(self: *Tally) TallyError![]const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "total={d}", .{self.total}) catch
            return error.OutOfMemory;
    }

    pub fn deinit(self: *Tally) void {
        std.heap.page_allocator.destroy(self);
        _ = live_bytes.fetchSub(@sizeOf(Tally), .monotonic);
    }
};

/// Releases what `Tally.render` handed over. A root-level function so the
/// binding can name it as this result's release target.
pub fn freeRendered(text: []const u8) void {
    std.heap.page_allocator.free(text);
}

/// A view into a `Tally`. It owns nothing.
pub const Reading = struct {
    tally: *Tally,

    pub fn total(self: *Reading) i64 {
        return self.tally.total;
    }
};

test "the shapes the Rust backend covers" {
    // Scalars, slices and error unions.
    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
    try std.testing.expectEqual(@as(i64, 6), sum(&.{ 1, 2, 3 }));
    try std.testing.expectEqual(@as(i64, 0), sum(&.{}));
    try std.testing.expectEqual(@as(i32, 3), try divide(7, 2));
    try std.testing.expectError(error.DivideByZero, divide(1, 0));

    // A handle, its borrowed view, and a caller-owned buffer.
    const tally = try Tally.create();
    try std.testing.expectEqual(@as(i64, 10), tally.add(10));
    try std.testing.expectEqual(@as(i64, 10), tally.peek());
    try std.testing.expectEqual(@as(i64, 5), try tally.checkedHalf());
    try std.testing.expectEqual(@as(i64, 10), tally.borrowReading().total());
    const rendered = try tally.render();
    defer freeRendered(rendered);
    try std.testing.expectEqualStrings("total=10", rendered);
    try std.testing.expect(liveBytes() != 0);
    tally.deinit();
    try std.testing.expectEqual(@as(usize, 0), liveBytes());
}
