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
