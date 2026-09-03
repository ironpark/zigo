const std = @import("std");
const semantic = @import("semantic");
const walk = @import("walk.zig");

pub const Status = enum { bound, excluded, unbound };

pub const Declaration = struct {
    path: []const u8,
    status: Status,
    reason: ?[]const u8 = null,
};

pub const Report = struct {
    package: []const u8,
    bound: usize,
    unbound: usize,
    excluded: usize,
    declarations: []const Declaration,
    unregistered_types: []const []const u8,

    pub fn render(self: Report, writer: *std.Io.Writer) !void {
        const total = self.bound + self.unbound;
        const percent = if (total == 0) 0 else self.bound * 100 / total;
        try writer.print("{s}: {d}/{d} public declarations bound ({d}%)\n", .{ self.package, self.bound, total, percent });
        for (self.declarations) |declaration| switch (declaration.status) {
            .bound => {},
            .excluded => try writer.print("  excluded: {s}\n", .{declaration.path}),
            .unbound => try writer.print("  unbound: {s}  (reason: {s})\n", .{ declaration.path, declaration.reason orelse "unsupported signature" }),
        };
        if (self.unregistered_types.len != 0) {
            try writer.writeAll("  unregistered types:\n");
            for (self.unregistered_types) |name| try writer.print("    {s}\n", .{name});
        }
    }

    pub fn json(self: Report, allocator: std.mem.Allocator) ![]u8 {
        return std.json.Stringify.valueAlloc(allocator, self, .{ .whitespace = .indent_2, .emit_null_optional_fields = false });
    }
};

pub fn classify(allocator: std.mem.Allocator, comptime binding: anytype, package: []const u8, document: semantic.Semantic) !Report {
    @setEvalBranchQuota(100_000);
    var declarations: std.ArrayList(Declaration) = .empty;
    var seen_functions: std.ArrayList([]const u8) = .empty;
    defer seen_functions.deinit(allocator);
    var public_types: std.ArrayList([]const u8) = .empty;
    defer public_types.deinit(allocator);
    var referenced_types: std.ArrayList([]const u8) = .empty;
    defer referenced_types.deinit(allocator);

    if (@hasField(@TypeOf(binding), "types")) inline for (binding.types) |entry| {
        if (comptime entry.repr != .callback) try collectContainer(
            allocator,
            &declarations,
            &seen_functions,
            &public_types,
            &referenced_types,
            binding,
            entry.type,
            comptime walk.typeEntryName(entry),
            comptime walk.typeEntryName(entry),
            comptime walk.discoveryEnabled(binding) and entry.repr != .enumeration,
        );
    };
    try collectContainer(allocator, &declarations, &seen_functions, &public_types, &referenced_types, binding, binding.root, null, "root", comptime walk.discoveryEnabled(binding));

    // Field accessors are generated functions even though there is no Zig
    // declaration to enumerate. Count each getter and setter exactly once.
    for (document.functions) |function| if (function.field_access != null) try declarations.append(allocator, .{
        .path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ function.receiver.?, function.name }),
        .status = .bound,
    });

    var unregistered: std.ArrayList([]const u8) = .empty;
    for (referenced_types.items) |full_name| {
        if (!contains(public_types.items, full_name) or registeredTypeName(binding, full_name)) continue;
        const name = walk.shortTypeName(full_name);
        if (!contains(unregistered.items, name)) try unregistered.append(allocator, name);
    }
    std.mem.sort([]const u8, unregistered.items, {}, lessThan);
    std.mem.sort(Declaration, declarations.items, {}, declarationLessThan);

    var bound: usize = 0;
    var unbound: usize = 0;
    var excluded: usize = 0;
    for (declarations.items) |item| switch (item.status) {
        .bound => bound += 1,
        .unbound => unbound += 1,
        .excluded => excluded += 1,
    };
    return .{
        .package = package,
        .bound = bound,
        .unbound = unbound,
        .excluded = excluded,
        .declarations = try declarations.toOwnedSlice(allocator),
        .unregistered_types = try unregistered.toOwnedSlice(allocator),
    };
}

fn collectContainer(
    allocator: std.mem.Allocator,
    declarations: *std.ArrayList(Declaration),
    seen_functions: *std.ArrayList([]const u8),
    public_types: *std.ArrayList([]const u8),
    referenced_types: *std.ArrayList([]const u8),
    comptime binding: anytype,
    comptime Container: type,
    comptime owner: ?[]const u8,
    comptime path_prefix: []const u8,
    comptime discovered: bool,
) !void {
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@TypeOf(value) == type and comptime walk.isContainer(value)) {
            if (!contains(public_types.items, @typeName(value))) try public_types.append(allocator, @typeName(value));
        }
        if (@typeInfo(@TypeOf(value)) != .@"fn") continue;
        const identity = @typeName(Container) ++ "." ++ candidate.name;
        if (!contains(seen_functions.items, identity)) {
            try seen_functions.append(allocator, identity);
            const path = path_prefix ++ "." ++ candidate.name;
            const status: Status = if (comptime walk.selectorContains(binding, "exclude", path))
                .excluded
            else if (discovered or comptime functionListed(binding, path))
                .bound
            else
                .unbound;
            try collectFunctionTypes(allocator, referenced_types, @TypeOf(value));
            try declarations.append(allocator, .{
                .path = displayPath(owner, candidate.name),
                .status = status,
                .reason = if (status == .unbound) comptime signatureReason(binding, @TypeOf(value)) else null,
            });
        }
    }
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@TypeOf(value) != type or comptime !walk.isNestedContainer(Container, value)) continue;
        try collectContainer(
            allocator,
            declarations,
            seen_functions,
            public_types,
            referenced_types,
            binding,
            value,
            comptime if (owner) |parent| parent ++ "." ++ candidate.name else candidate.name,
            path_prefix ++ "." ++ candidate.name,
            comptime discovered and walk.discoveryRecursive(binding),
        );
    }
}

fn displayPath(comptime owner: ?[]const u8, comptime name: []const u8) []const u8 {
    return if (owner) |value| value ++ "." ++ name else name;
}

fn collectFunctionTypes(allocator: std.mem.Allocator, types: *std.ArrayList([]const u8), comptime F: type) !void {
    const info = @typeInfo(F).@"fn";
    inline for (info.params) |parameter| if (parameter.type) |T| try collectType(allocator, types, T);
    if (info.return_type) |T| try collectType(allocator, types, T);
}

fn collectType(allocator: std.mem.Allocator, types: *std.ArrayList([]const u8), comptime T: type) !void {
    switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union" => if (!isBuiltinSpecial(T) and !contains(types.items, @typeName(T))) try types.append(allocator, @typeName(T)),
        .pointer => |info| if (@typeInfo(info.child) == .@"fn") try collectFunctionTypes(allocator, types, info.child) else try collectType(allocator, types, info.child),
        .optional => |info| try collectType(allocator, types, info.child),
        .error_union => |info| try collectType(allocator, types, info.payload),
        .@"fn" => try collectFunctionTypes(allocator, types, T),
        else => {},
    }
}

/// Best-effort coverage reason. It mirrors the broad rejection classes in
/// validate.typeOffense and the sharper ZIGO signature diagnostics; anything
/// it cannot prove falls back to "unsupported signature" at render time.
fn signatureReason(comptime binding: anytype, comptime F: type) ?[]const u8 {
    const info = @typeInfo(F).@"fn";
    if (info.is_generic) return "comptime parameters";
    inline for (info.params) |parameter| {
        if (parameter.is_generic or parameter.type == null) return "comptime parameters";
        const T = parameter.type.?;
        if (T == std.mem.Allocator and !@hasField(@TypeOf(binding), "allocator")) return "allocator param, no metadata";
        if (T == std.Io and !@hasField(@TypeOf(binding), "io")) return "io param, no metadata";
        if (T == *std.Io.Writer) return "writer param, no metadata";
        if (T == *std.Io.Reader) return "reader param, no metadata";
        if (comptime typeReason(binding, T, true)) |reason| return reason;
    }
    if (info.return_type) |T| {
        if (@typeInfo(T) == .error_union and @typeInfo(T).error_union.error_set == anyerror) return "anyerror return";
        if (comptime typeReason(binding, T, true)) |reason| return reason;
    }
    return "not listed";
}

fn typeReason(comptime binding: anytype, comptime T: type, comptime whole: bool) ?[]const u8 {
    return switch (@typeInfo(T)) {
        .void, .bool => null,
        .int => |info| if (whole or info.bits == 8 or info.bits == 16 or info.bits == 32 or info.bits == 64) null else "no C representation",
        .float => |info| if (info.bits == 32 or info.bits == 64) null else "no C representation",
        .@"enum" => null,
        .@"struct" => |info| if (info.layout == .@"extern" or info.layout == .@"packed") null else "no C representation",
        .@"union" => |info| if (info.tag_type == null) "no C representation" else null,
        .pointer => |info| switch (info.size) {
            .slice => typeReason(binding, info.child, false),
            .one => if (@typeInfo(info.child) == .@"fn") callbackReason(binding, info.child) else if (isBuiltinSpecial(info.child) or registeredType(binding, info.child)) null else "unregistered type",
            .many => if (info.child == u8 and info.is_const and info.sentinel() != null) null else "no C representation",
            else => "no C representation",
        },
        .optional => |info| typeReason(binding, info.child, whole),
        .error_union => |info| typeReason(binding, info.payload, whole),
        .@"fn" => callbackReason(binding, T),
        else => "unsupported signature",
    };
}

fn callbackReason(comptime binding: anytype, comptime F: type) ?[]const u8 {
    const info = @typeInfo(F).@"fn";
    if (!std.meta.eql(info.calling_convention, std.builtin.CallingConvention.c)) return "non-C callback";
    inline for (info.params) |parameter| {
        const T = parameter.type orelse return "comptime parameters";
        if (comptime typeReason(binding, T, false)) |reason| return reason;
    }
    if (info.return_type) |T| return typeReason(binding, T, false);
    return null;
}

fn functionListed(comptime binding: anytype, comptime path: []const u8) bool {
    if (!@hasField(@TypeOf(binding), "functions")) return false;
    inline for (binding.functions) |entry| if (walk.functionEntryContainsPath(entry, path)) return true;
    return false;
}

fn registeredType(comptime binding: anytype, comptime T: type) bool {
    if (!@hasField(@TypeOf(binding), "types")) return false;
    inline for (binding.types) |entry| if (entry.type == T) return true;
    return false;
}

fn registeredTypeName(comptime binding: anytype, full_name: []const u8) bool {
    if (!@hasField(@TypeOf(binding), "types")) return false;
    inline for (binding.types) |entry| if (std.mem.eql(u8, @typeName(entry.type), full_name)) return true;
    return false;
}

fn isBuiltinSpecial(comptime T: type) bool {
    return T == std.Io.Writer or T == std.Io.Reader or T == std.mem.Allocator or T == std.Io or T == std.atomic.Value(u32);
}

fn contains(values: []const []const u8, wanted: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, wanted)) return true;
    return false;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn declarationLessThan(_: void, a: Declaration, b: Declaration) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

test "classifier distinguishes selected excluded and unsupported functions" {
    const Api = struct {
        pub const Nested = struct {
            pub const Hidden = struct { value: u32 };
            pub fn omitted(value: i32) i32 {
                return value;
            }
            pub fn unsupported(value: *Hidden) void {
                _ = value;
            }
        };
        pub fn selected(value: i32) i32 {
            return value;
        }
        pub fn ignored() void {}
    };
    const binding = .{ .root = Api, .discover = .public, .exclude = .{"root.ignored"} };
    const report = try classify(std.testing.allocator, binding, "sample", .{
        .package = "sample",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .functions = &.{},
        .types = &.{},
    });
    defer std.testing.allocator.free(report.declarations);
    defer std.testing.allocator.free(report.unregistered_types);
    try std.testing.expectEqual(@as(usize, 1), report.bound);
    try std.testing.expectEqual(@as(usize, 2), report.unbound);
    try std.testing.expectEqual(@as(usize, 1), report.excluded);
    try std.testing.expectEqualStrings("not listed", report.declarations[0].reason.?);
    try std.testing.expectEqualStrings("unregistered type", report.declarations[1].reason.?);
    try std.testing.expectEqualStrings("Hidden", report.unregistered_types[0]);
}
