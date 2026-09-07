//! Comptime helpers for building exact-path binding function entries.
const std = @import("std");
const declare = @import("declare.zig");

/// Select public functions declared directly on one container.
pub const FuncSelector = struct {
    /// Binding path of `Container`, such as `root`, `Context`, or
    /// `root.unicode`.
    base: []const u8,
    /// Select declaration names beginning with this prefix. Empty selects all.
    prefix: []const u8 = "",
};

/// Build one function entry from an exact path. Call `.with(options)` on the
/// result when the entry needs metadata.
pub fn func(comptime path: []const u8) declare.Function {
    return .{ .path = path };
}

/// Expand matching public function declarations into exact-path entries.
/// No selector survives into the resulting binding declaration.
pub fn funcs(
    comptime Container: type,
    comptime selector: FuncSelector,
) [matchingFunctionCount(Container, selector)]declare.Function {
    comptime validateSelector(selector);
    const count = comptime matchingFunctionCount(Container, selector);
    if (count == 0) @compileError("zigo.dsl.funcs selector matched no public functions");

    var entries: [count]declare.Function = undefined;
    var index: usize = 0;
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@typeInfo(@TypeOf(value)) != .@"fn") continue;
        if (!std.mem.startsWith(u8, candidate.name, selector.prefix)) continue;
        entries[index] = .{ .path = selector.base ++ "." ++ candidate.name };
        index += 1;
    }
    return entries;
}

fn matchingFunctionCount(comptime Container: type, comptime selector: FuncSelector) usize {
    comptime validateSelector(selector);
    var count: usize = 0;
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@typeInfo(@TypeOf(value)) == .@"fn" and
            std.mem.startsWith(u8, candidate.name, selector.prefix)) count += 1;
    }
    return count;
}

fn validateSelector(comptime selector: FuncSelector) void {
    if (selector.base.len == 0)
        @compileError("zigo.dsl.funcs selector `.base` must not be empty");
    if (selector.base[0] == '.' or selector.base[selector.base.len - 1] == '.')
        @compileError("zigo.dsl.funcs selector `.base` must not start or end with `.`");
}

test "func accepts a path and with overlays typed options" {
    const plain = func("root.len");
    try std.testing.expectEqualStrings("root.len", plain.path);
    try std.testing.expectEqual(@as(?declare.Ownership, null), plain.returns.ownership);

    const detailed = func("root.take").with(.{
        .returns = .{ .ownership = .caller, .release = "root.free" },
    });
    try std.testing.expectEqual(declare.Ownership.caller, detailed.returns.ownership.?);
    try std.testing.expectEqualStrings("root.free", detailed.returns.release.?);
}

test "funcs expands a prefix in declaration order to exact paths" {
    const Api = struct {
        pub const Value = u32;

        pub fn queryFirst() void {}
        pub fn ignored() void {}
        pub fn querySecond() void {}
    };
    const selected = funcs(Api, .{ .base = "root", .prefix = "query" });
    const binding: declare.Binding = .{ .root = Api, .functions = &selected };
    try std.testing.expectEqual(@as(usize, 2), selected.len);
    try std.testing.expectEqual(@as(usize, 2), binding.functions.len);
    try std.testing.expectEqualStrings("root.queryFirst", selected[0].path);
    try std.testing.expectEqualStrings("root.querySecond", selected[1].path);
}

test "an empty prefix selects every public function and skips types" {
    const Api = struct {
        pub const Value = u32;
        pub fn first() void {}
        pub fn second() void {}
    };
    const selected = funcs(Api, .{ .base = "Context" });
    try std.testing.expectEqual(@as(usize, 2), selected.len);
    try std.testing.expectEqualStrings("Context.first", selected[0].path);
    try std.testing.expectEqualStrings("Context.second", selected[1].path);
}

test "selector matching detects an empty result" {
    const Api = struct {
        pub fn present() void {}
    };
    try std.testing.expectEqual(
        @as(usize, 0),
        comptime matchingFunctionCount(Api, .{ .base = "root", .prefix = "missing" }),
    );
}
