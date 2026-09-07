//! Comptime helpers for building exact-path binding function entries.
const std = @import("std");
const declare = @import("declare.zig");

/// Select public functions declared directly on one container.
pub const FuncSelector = struct {
    /// Binding path of `Container`, such as `root`, `Context`, or
    /// `root.unicode`.
    base: []const u8 = "root",
    /// Select these exact declaration names in the listed order. When set,
    /// `prefix` and `exclude` must keep their defaults.
    names: []const []const u8 = &.{},
    /// Select declaration names beginning with this prefix. Empty selects all.
    prefix: []const u8 = "",
    /// Exact declaration names to leave out after applying `prefix`.
    exclude: []const []const u8 = &.{},
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
    comptime validateSelector(Container, selector);
    const count = comptime matchingFunctionCount(Container, selector);
    if (count == 0) @compileError("zigo.dsl.funcs selector matched no public functions");

    var entries: [count]declare.Function = undefined;
    var index: usize = 0;
    if (selector.names.len != 0) {
        inline for (selector.names) |name| {
            entries[index] = .{ .path = selector.base ++ "." ++ name };
            index += 1;
        }
    } else {
        inline for (comptime std.meta.declarations(Container)) |candidate| {
            const value = @field(Container, candidate.name);
            if (@typeInfo(@TypeOf(value)) != .@"fn") continue;
            if (!std.mem.startsWith(u8, candidate.name, selector.prefix)) continue;
            if (comptime isExcluded(candidate.name, selector.exclude)) continue;
            entries[index] = .{ .path = selector.base ++ "." ++ candidate.name };
            index += 1;
        }
    }
    return entries;
}

/// Flatten a tuple of individual entries and fixed-size arrays into one
/// fixed-size array, preserving left-to-right order. Entries must all be
/// either `zigo.Function` or all `zigo.Type`.
pub fn collect(comptime parts: anytype) [collectedCount(parts)]collectedElement(parts) {
    const Element = collectedElement(parts);
    const count = comptime collectedCount(parts);
    if (count == 0) @compileError("zigo.dsl.collect requires at least one entry");
    var entries: [count]Element = undefined;
    var index: usize = 0;
    inline for (parts) |part| {
        if (@TypeOf(part) == Element) {
            entries[index] = part;
            index += 1;
        } else {
            inline for (part) |entry| {
                entries[index] = entry;
                index += 1;
            }
        }
    }
    return entries;
}

/// Project function entries to their exact paths, for example when assigning
/// the same group to a Go sub-package.
pub fn pathsOf(comptime entries: anytype) [entries.len][]const u8 {
    const info = @typeInfo(@TypeOf(entries));
    if (info != .array or info.array.child != declare.Function)
        @compileError("zigo.dsl.pathsOf expects a fixed-size zigo.Function array");
    if (entries.len == 0) @compileError("zigo.dsl.pathsOf requires at least one function");
    var paths: [entries.len][]const u8 = undefined;
    inline for (entries, 0..) |entry, index| paths[index] = entry.path;
    return paths;
}

fn matchingFunctionCount(comptime Container: type, comptime selector: FuncSelector) usize {
    comptime validateSelector(Container, selector);
    if (selector.names.len != 0) return selector.names.len;
    var count: usize = 0;
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@typeInfo(@TypeOf(value)) == .@"fn" and
            std.mem.startsWith(u8, candidate.name, selector.prefix) and
            !isExcluded(candidate.name, selector.exclude)) count += 1;
    }
    return count;
}

fn validateSelector(comptime Container: type, comptime selector: FuncSelector) void {
    if (selector.base.len == 0)
        @compileError("zigo.dsl.funcs selector `.base` must not be empty");
    if (selector.base[0] == '.' or selector.base[selector.base.len - 1] == '.')
        @compileError("zigo.dsl.funcs selector `.base` must not start or end with `.`");
    if (selector.names.len != 0) {
        if (selector.prefix.len != 0)
            @compileError("zigo.dsl.funcs selector `.names` cannot be combined with `.prefix`");
        if (selector.exclude.len != 0)
            @compileError("zigo.dsl.funcs selector `.names` cannot be combined with `.exclude`");
        inline for (selector.names, 0..) |name, index| {
            var found = false;
            inline for (comptime std.meta.declarations(Container)) |candidate| {
                if (!std.mem.eql(u8, candidate.name, name)) continue;
                const value = @field(Container, candidate.name);
                found = @typeInfo(@TypeOf(value)) == .@"fn";
            }
            if (!found)
                @compileError("zigo.dsl.funcs exact name does not name a public function: " ++ name);
            inline for (selector.names[0..index]) |earlier| {
                if (std.mem.eql(u8, earlier, name))
                    @compileError("zigo.dsl.funcs lists an exact name more than once: " ++ name);
            }
        }
        return;
    }
    inline for (selector.exclude, 0..) |excluded, index| {
        var found = false;
        inline for (comptime std.meta.declarations(Container)) |candidate| {
            const value = @field(Container, candidate.name);
            if (@typeInfo(@TypeOf(value)) == .@"fn" and
                std.mem.eql(u8, candidate.name, excluded) and
                std.mem.startsWith(u8, candidate.name, selector.prefix)) found = true;
        }
        if (!found)
            @compileError("zigo.dsl.funcs exclusion does not name a selected public function: " ++ excluded);
        inline for (selector.exclude[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier, excluded))
                @compileError("zigo.dsl.funcs lists an exclusion more than once: " ++ excluded);
        }
    }
}

fn isExcluded(comptime name: []const u8, comptime exclusions: []const []const u8) bool {
    inline for (exclusions) |excluded| {
        if (std.mem.eql(u8, name, excluded)) return true;
    }
    return false;
}

fn collectedElement(comptime parts: anytype) type {
    const info = @typeInfo(@TypeOf(parts));
    if (info != .@"struct" or !info.@"struct".is_tuple)
        @compileError("zigo.dsl.collect expects a tuple of entries and fixed-size arrays");
    if (info.@"struct".fields.len == 0)
        @compileError("zigo.dsl.collect requires at least one entry or array");

    const first = parts[0];
    const First = @TypeOf(first);
    const Element = switch (@typeInfo(First)) {
        .array => |array| array.child,
        else => First,
    };
    if (Element != declare.Function and Element != declare.Type)
        @compileError("zigo.dsl.collect accepts only zigo.Function or zigo.Type entries and arrays");
    return Element;
}

fn collectedCount(comptime parts: anytype) usize {
    const Element = collectedElement(parts);
    var count: usize = 0;
    inline for (parts) |part| {
        const T = @TypeOf(part);
        if (T == Element) {
            count += 1;
            continue;
        }
        switch (@typeInfo(T)) {
            .array => |array| {
                if (array.child != Element)
                    @compileError("zigo.dsl.collect cannot mix zigo.Function and zigo.Type entries");
                count += array.len;
            },
            else => @compileError("zigo.dsl.collect cannot mix zigo.Function and zigo.Type entries"),
        }
    }
    return count;
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

test "function ownership shortcuts preserve other metadata" {
    const owned = func("root.open").with(.{ .name = "OpenStore" }).callerOwned();
    try std.testing.expectEqualStrings("OpenStore", owned.name.?);
    try std.testing.expectEqual(declare.Ownership.caller, owned.returns.ownership.?);

    const released = func("root.take").releasedBy("root.free");
    try std.testing.expectEqual(declare.Ownership.caller, released.returns.ownership.?);
    try std.testing.expectEqualStrings("root.free", released.returns.release.?);

    const view = func("Context.view").borrowed();
    try std.testing.expectEqual(declare.Ownership.borrowed, view.returns.ownership.?);
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

test "funcs exact names preserve caller order" {
    const Api = struct {
        pub const Value = u32;
        pub fn first() void {}
        pub fn second() void {}
        pub fn third() void {}
    };
    const selected = funcs(Api, .{
        .base = "Api",
        .names = &.{ "third", "first" },
    });
    try std.testing.expectEqual(@as(usize, 2), selected.len);
    try std.testing.expectEqualStrings("Api.third", selected[0].path);
    try std.testing.expectEqualStrings("Api.first", selected[1].path);
}

test "an empty prefix selects every public function and skips types" {
    const Api = struct {
        pub const Value = u32;
        pub fn first() void {}
        pub fn second() void {}
    };
    const selected = funcs(Api, .{ .exclude = &.{"second"} });
    try std.testing.expectEqual(@as(usize, 1), selected.len);
    try std.testing.expectEqualStrings("root.first", selected[0].path);
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

test "collect flattens generated arrays and individual functions in order" {
    const Api = struct {
        pub fn queryFirst() void {}
        pub fn querySecond() void {}
    };
    const queries = funcs(Api, .{ .prefix = "query" });
    const entries = collect(.{
        func("root.before"),
        queries,
        func("root.after").releasedBy("root.free"),
    });
    try std.testing.expectEqual(@as(usize, 4), entries.len);
    try std.testing.expectEqualStrings("root.before", entries[0].path);
    try std.testing.expectEqualStrings("root.queryFirst", entries[1].path);
    try std.testing.expectEqualStrings("root.querySecond", entries[2].path);
    try std.testing.expectEqualStrings("root.after", entries[3].path);
}

test "collect infers registered type entries" {
    const First = struct {};
    const Second = enum { value };
    const handles = [_]declare.Type{.{ .handle = .{ .type = First } }};
    const entries = collect(.{
        handles,
        declare.Type{ .enumeration = .{ .type = Second } },
    });
    try std.testing.expectEqual(@as(usize, 2), entries.len);
    try std.testing.expect(entries[0] == .handle);
    try std.testing.expect(entries[1] == .enumeration);
}

test "pathsOf derives package paths without repeating strings" {
    const Api = struct {
        pub fn encodeKey() void {}
        pub fn encodeMouse() void {}
    };
    const functions = funcs(Api, .{ .names = &.{ "encodeMouse", "encodeKey" } });
    const paths = pathsOf(functions);
    try std.testing.expectEqual(@as(usize, 2), paths.len);
    try std.testing.expectEqualStrings("root.encodeMouse", paths[0]);
    try std.testing.expectEqualStrings("root.encodeKey", paths[1]);
}
