//! Where a diagnostic points: the site and declaration path of a function or
//! a type. Every `semantic.json` fallback a diagnostic can carry is spelled
//! here and nowhere else, so a rule module never writes the path itself.
const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");

/// The `Site` a function- or parameter-level diagnostic points at: the
/// function's own AST location when `names.zig` recorded one, else the
/// `semantic.json` fallback every diagnostic used before source locations
/// existed. `declaration` stays whatever the caller already had -- usually
/// `function.name` or a dotted owner path -- so this only ever changes
/// `path`/`line`/`column`.
pub fn functionSiteFor(function: semantic.SemanticFn, declaration: []const u8) diagnostic.Site {
    if (function.source) |source| return .{
        .path = source.path,
        .declaration = declaration,
        .line = source.line,
        .column = source.column,
    };
    return documentSite(declaration);
}

pub fn functionSite(function: semantic.SemanticFn) diagnostic.Site {
    return functionSiteFor(function, function.name);
}

/// The `Site` one parameter's diagnostic points at: the parameter's own name
/// token when `names.zig` recorded one, else its function's location. A
/// parameter carries no path of its own -- it is always its function's -- so
/// the function is what supplies it, and the parameter still names itself
/// either way, exactly as `functionSiteFor` lets a member name itself.
pub fn paramSite(function: semantic.SemanticFn, index: usize) diagnostic.Site {
    if (index >= function.params.len) return functionSite(function);
    const parameter = function.params[index];
    const source = function.source orelse return functionSiteFor(function, parameter.name);
    const location = parameter.source orelse return functionSiteFor(function, parameter.name);
    return .{
        .path = source.path,
        .declaration = parameter.name,
        .line = location.line,
        .column = location.column,
    };
}

/// The `Site` a result-level diagnostic points at. A result has no token of
/// its own in the source scan, so it is the function's site throughout.
pub fn resultSite(function: semantic.SemanticFn) diagnostic.Site {
    return functionSite(function);
}

/// The `Site` one member's diagnostic points at: the container's own source
/// location, named by `<Type>.<field>`. The scan records no per-member token,
/// so only the declaration name narrows from the type to the field.
pub fn fieldSite(declaration: semantic.TypeDecl, allocator: std.mem.Allocator, index: usize) !diagnostic.Site {
    if (index >= declaration.fields.len) return typeSite(declaration);
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ declaration.name, declaration.fields[index].name });
    return typeSiteFor(declaration, name);
}

/// The `Site` one enum tag's diagnostic points at. Tags and fields are the
/// same IR node, so this is `fieldSite` under the name a tag reads as.
pub fn tagSite(declaration: semantic.TypeDecl, allocator: std.mem.Allocator, index: usize) !diagnostic.Site {
    return fieldSite(declaration, allocator, index);
}

/// The `Site` a type-level diagnostic points at: the container's own source
/// location when `names.zig` recorded one, else the type's entry in
/// `semantic.json`. `declaration` is what the diagnostic names -- usually the
/// type name, or a dotted member path -- and only `path`/`line`/`column`
/// depend on whether the location is known.
pub fn typeSiteFor(declaration: semantic.TypeDecl, name: []const u8) diagnostic.Site {
    if (declaration.source) |source| return .{
        .path = source.path,
        .declaration = name,
        .line = source.line,
        .column = source.column,
    };
    return documentSite(name);
}

pub fn typeSite(declaration: semantic.TypeDecl) diagnostic.Site {
    return typeSiteFor(declaration, declaration.name);
}

/// The `Site` of a declaration that has no source location of its own -- an
/// interface, a session, or a type the source scan could not place -- which is
/// its entry in the reflected document.
pub fn documentSite(declaration: []const u8) diagnostic.Site {
    return .{ .path = "semantic.json", .declaration = declaration };
}

pub fn functionDeclarationAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]const u8 {
    const owner = function.receiver orelse function.namespace;
    return if (owner) |value|
        std.fmt.allocPrint(allocator, "{s}.{s}", .{ value, function.name })
    else
        allocator.dupe(u8, function.name);
}

test "type sites use the recorded source location and fall back to the document" {
    const located: semantic.TypeDecl = .{ .kind = .@"opaque", .name = "Document", .source = .{ .path = "src/root.zig", .line = 4, .column = 11 } };
    const site = typeSite(located);
    try std.testing.expectEqualStrings("src/root.zig", site.path);
    try std.testing.expectEqualStrings("Document", site.declaration);
    try std.testing.expectEqual(@as(?u32, 4), site.line);
    const unplaced = typeSiteFor(.{ .kind = .@"enum", .name = "Mode" }, "Mode.idle");
    try std.testing.expectEqualStrings("semantic.json", unplaced.path);
    try std.testing.expectEqualStrings("Mode.idle", unplaced.declaration);
    try std.testing.expect(unplaced.line == null);
}

test "parameter sites narrow to the parameter token and fall back to the function" {
    const located: semantic.SemanticFn = .{
        .name = "feed",
        .params = &.{
            .{ .name = "chunk", .type = .{ .bool = {} }, .source = .{ .line = 9, .column = 17 } },
            .{ .name = "count", .type = .{ .bool = {} } },
        },
        .@"return" = .{ .void = {} },
        .source = .{ .path = "src/root.zig", .line = 9, .column = 1 },
        .symbol = "zg_feed",
    };
    const parameter = paramSite(located, 0);
    try std.testing.expectEqualStrings("src/root.zig", parameter.path);
    try std.testing.expectEqualStrings("chunk", parameter.declaration);
    try std.testing.expectEqual(@as(?u32, 9), parameter.line);
    try std.testing.expectEqual(@as(?u32, 17), parameter.column);
    // A parameter the scan never placed still names itself, under the
    // function's own location; an index past the end is the function.
    const unplaced = paramSite(located, 1);
    try std.testing.expectEqualStrings("count", unplaced.declaration);
    try std.testing.expectEqual(@as(?u32, 9), unplaced.line);
    try std.testing.expectEqualStrings("feed", paramSite(located, 7).declaration);
    try std.testing.expectEqualStrings("feed", resultSite(located).declaration);
}

test "field and tag sites name the member under the container's location" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const declaration: semantic.TypeDecl = .{
        .fields = &.{.{ .name = "x", .type = .{ .bool = {} } }},
        .kind = .value_struct,
        .name = "Point",
        .source = .{ .path = "src/root.zig", .line = 3, .column = 5 },
    };
    const field = try fieldSite(declaration, allocator, 0);
    try std.testing.expectEqualStrings("src/root.zig", field.path);
    try std.testing.expectEqualStrings("Point.x", field.declaration);
    try std.testing.expectEqual(@as(?u32, 3), field.line);
    const tag = try tagSite(declaration, allocator, 0);
    try std.testing.expectEqualStrings("Point.x", tag.declaration);
    // An index past the end is the container itself rather than a bad read.
    try std.testing.expectEqualStrings("Point", (try fieldSite(declaration, allocator, 4)).declaration);
}
