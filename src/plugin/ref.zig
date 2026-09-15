//! Reference-typed plugin options: an option field that names a registered
//! type, a bound function or a declared interface instead of spelling it as
//! free text. The authoring side writes `api.typeRef("Context")`, the wire
//! form is one string, and the generator resolves that string back to the
//! declaration it came from.
//!
//! The string is the *native* path -- what the reflector writes as
//! `TypeDecl.zig_path`, and the Zig call path a function is reached by -- and
//! never a Go name. A binding that registers `Item` as `Widget`, or a plugin
//! whose `name_type` renames it again, changes what Go sees and nothing here.
const std = @import("std");
const semantic = @import("semantic");

/// A reference to a registered type. `path` is `@typeName` of the Zig type,
/// which is exactly what the reflector records as `TypeDecl.zig_path`.
pub const Type = struct {
    path: []const u8,

    pub fn jsonStringify(self: Type, jw: anytype) !void {
        try jw.write(self.path);
    }
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Type {
        return .{ .path = try std.json.innerParse([]const u8, allocator, source, options) };
    }
    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, _: std.json.ParseOptions) std.json.ParseFromValueError!Type {
        return .{ .path = try parsePath(allocator, source) };
    }
};

/// A reference to a bound function. `path` is `<container>.<name>` with the
/// container spelled as `@typeName`, or the bare name for a function declared
/// at the binding root.
pub const Function = struct {
    path: []const u8,

    pub fn jsonStringify(self: Function, jw: anytype) !void {
        try jw.write(self.path);
    }
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Function {
        return .{ .path = try std.json.innerParse([]const u8, allocator, source, options) };
    }
    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, _: std.json.ParseOptions) std.json.ParseFromValueError!Function {
        return .{ .path = try parsePath(allocator, source) };
    }
};

/// A reference to an interface the binding declared. An interface has no Zig
/// declaration behind it, so its name is its identity.
pub const Interface = struct {
    name: []const u8,

    pub fn jsonStringify(self: Interface, jw: anytype) !void {
        try jw.write(self.name);
    }
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Interface {
        return .{ .name = try std.json.innerParse([]const u8, allocator, source, options) };
    }
    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, _: std.json.ParseOptions) std.json.ParseFromValueError!Interface {
        return .{ .name = try parsePath(allocator, source) };
    }
};

fn parsePath(allocator: std.mem.Allocator, source: std.json.Value) std.json.ParseFromValueError![]const u8 {
    return switch (source) {
        .string => |text| try allocator.dupe(u8, text),
        else => error.UnexpectedToken,
    };
}

/// Whether `T` is one of the three reference types.
pub fn isRef(comptime T: type) bool {
    return T == Type or T == Function or T == Interface;
}

/// Two type declarations of one Zig type are told apart by a `#<name>`
/// suffix; the part before it is the path a reference carries.
fn zigPathBase(path: []const u8) []const u8 {
    return path[0 .. std.mem.indexOfScalar(u8, path, '#') orelse path.len];
}

fn lastSegment(path: []const u8) []const u8 {
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[index + 1 ..];
}

/// The declaration `reference` names, or null when the document has none.
pub fn findType(types: []const semantic.TypeDecl, reference: Type) ?*const semantic.TypeDecl {
    for (types) |*declaration| {
        const path = declaration.zig_path orelse continue;
        if (std.mem.eql(u8, zigPathBase(path), reference.path)) return declaration;
    }
    return null;
}

/// The function `reference` names. The container half of the path is resolved
/// through the type table first, so a registered type renamed for Go is still
/// found by the Zig type it was registered from.
pub fn findFunction(types: []const semantic.TypeDecl, functions: []const semantic.SemanticFn, reference: Function) ?*const semantic.SemanticFn {
    const split = std.mem.lastIndexOfScalar(u8, reference.path, '.');
    const container = if (split) |index| reference.path[0..index] else "";
    const name = if (split) |index| reference.path[index + 1 ..] else reference.path;
    const owner: ?[]const u8 = if (container.len == 0) null else blk: {
        if (findType(types, .{ .path = container })) |declaration| break :blk declaration.native_name orelse declaration.name;
        break :blk lastSegment(container);
    };
    for (functions) |*function| {
        // A rename records the pre-rename call path, so a function that has
        // one is identified by it alone.
        if (function.zig_path) |path| {
            if (pathEquals(path, owner, name)) return function;
            continue;
        }
        if (!std.mem.eql(u8, function.name, name)) continue;
        const declared = function.receiver orelse function.namespace;
        if (owner == null and declared == null) return function;
        if (owner != null and declared != null and std.mem.eql(u8, owner.?, declared.?)) return function;
    }
    return null;
}

pub fn findInterface(interfaces: []const semantic.Interface, reference: Interface) ?*const semantic.Interface {
    for (interfaces) |*declared| {
        if (std.mem.eql(u8, declared.name, reference.name)) return declared;
    }
    return null;
}

fn pathEquals(path: []const u8, owner: ?[]const u8, name: []const u8) bool {
    const prefix = owner orelse return std.mem.eql(u8, path, name);
    if (path.len != prefix.len + 1 + name.len) return false;
    if (!std.mem.startsWith(u8, path, prefix) or path[prefix.len] != '.') return false;
    return std.mem.eql(u8, path[prefix.len + 1 ..], name);
}

/// One reference an option value carries that the document cannot resolve.
pub const Unresolved = struct {
    kind: enum { type, function, interface },
    path: []const u8,
};

/// The first unresolved reference anywhere in `value`, whatever shape the
/// plugin gave its options: a reference field, an optional one, a slice of
/// them, or any of those nested in a plain struct.
pub fn unresolvedIn(comptime T: type, value: T, document: semantic.Semantic) ?Unresolved {
    if (comptime T == Type) {
        return if (findType(document.types, value) == null) .{ .kind = .type, .path = value.path } else null;
    }
    if (comptime T == Function) {
        return if (findFunction(document.types, document.functions, value) == null) .{ .kind = .function, .path = value.path } else null;
    }
    if (comptime T == Interface) {
        return if (findInterface(document.interfaces orelse &.{}, value) == null) .{ .kind = .interface, .path = value.name } else null;
    }
    switch (@typeInfo(T)) {
        .optional => |optional| {
            const inner = value orelse return null;
            return unresolvedIn(optional.child, inner, document);
        },
        .pointer => |pointer| {
            if (pointer.size != .slice or pointer.child == u8) return null;
            for (value) |item| if (unresolvedIn(pointer.child, item, document)) |missing| return missing;
            return null;
        },
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                if (unresolvedIn(field.type, @field(value, field.name), document)) |missing| return missing;
            }
            return null;
        },
        else => return null,
    }
}

/// Whether `T` mentions a reference type at all, so a caller can skip the
/// walk for the options of a plugin that declared none.
pub fn mentionsRef(comptime T: type) bool {
    if (isRef(T)) return true;
    return switch (@typeInfo(T)) {
        .optional => |optional| mentionsRef(optional.child),
        .pointer => |pointer| pointer.size == .slice and pointer.child != u8 and mentionsRef(pointer.child),
        .@"struct" => |info| blk: {
            inline for (info.fields) |field| if (mentionsRef(field.type)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

test "a reference is one string on the wire, in both directions" {
    const Options = struct {
        target: ?Type = null,
        helper: ?Function = null,
        satisfies: []const Interface = &.{},
    };
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, Options{
        .target = .{ .path = "mylib.Context" },
        .satisfies = &.{.{ .name = "Readable" }},
    }, .{});
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"target\":\"mylib.Context\",\"helper\":null,\"satisfies\":[\"Readable\"]}", text);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try std.json.parseFromSliceLeaky(Options, arena.allocator(), text, .{});
    try std.testing.expectEqualStrings("mylib.Context", parsed.target.?.path);
    try std.testing.expectEqualStrings("Readable", parsed.satisfies[0].name);
    try std.testing.expect(parsed.helper == null);
}

test "references resolve through native paths, not Go names" {
    const types = [_]semantic.TypeDecl{
        .{ .name = "Widget", .kind = .@"opaque", .zig_path = "mylib.Item" },
        .{ .name = "HTTPState", .native_name = "State", .kind = .@"opaque", .zig_path = "mylib.State" },
    };
    const functions = [_]semantic.SemanticFn{
        .{ .name = "read", .receiver = "Widget", .symbol = "zg_widget_read", .params = &.{}, .@"return" = .{ .void = {} } },
        .{ .name = "open", .symbol = "zg_open", .params = &.{}, .@"return" = .{ .void = {} } },
        .{ .name = "close", .receiver = "HTTPState", .zig_path = "State.close", .symbol = "zg_state_close", .params = &.{}, .@"return" = .{ .void = {} } },
    };
    try std.testing.expectEqualStrings("Widget", findType(&types, .{ .path = "mylib.Item" }).?.name);
    try std.testing.expect(findType(&types, .{ .path = "mylib.Missing" }) == null);
    try std.testing.expectEqualStrings("read", findFunction(&types, &functions, .{ .path = "mylib.Item.read" }).?.name);
    try std.testing.expectEqualStrings("open", findFunction(&types, &functions, .{ .path = "open" }).?.name);
    // The receiver was renamed by a plugin; the recorded call path still
    // spells the native owner, and that is what the reference matches.
    try std.testing.expectEqualStrings("close", findFunction(&types, &functions, .{ .path = "mylib.State.close" }).?.name);
    try std.testing.expect(findFunction(&types, &functions, .{ .path = "mylib.Item.write" }) == null);
}

test "the walk finds a reference wherever the option type put it" {
    const Nested = struct { inner: ?Type = null };
    const Options = struct {
        label: []const u8 = "",
        target: ?Type = null,
        satisfies: []const Interface = &.{},
        nested: Nested = .{},
    };
    const document: semantic.Semantic = .{
        .package = "mylib",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .types = &.{.{ .name = "Context", .kind = .@"opaque", .zig_path = "mylib.Context" }},
        .interfaces = &.{.{ .name = "Readable", .methods = &.{}, .types = &.{} }},
    };
    try std.testing.expect(unresolvedIn(Options, .{ .target = .{ .path = "mylib.Context" } }, document) == null);
    try std.testing.expectEqualStrings("mylib.Gone", unresolvedIn(Options, .{ .target = .{ .path = "mylib.Gone" } }, document).?.path);
    try std.testing.expectEqualStrings("Writable", unresolvedIn(Options, .{ .satisfies = &.{.{ .name = "Writable" }} }, document).?.path);
    try std.testing.expectEqualStrings("mylib.Gone", unresolvedIn(Options, .{ .nested = .{ .inner = .{ .path = "mylib.Gone" } } }, document).?.path);
    try std.testing.expect(mentionsRef(Options));
    try std.testing.expect(!mentionsRef(struct { label: []const u8 = "" }));
}
