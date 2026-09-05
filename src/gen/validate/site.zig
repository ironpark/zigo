//! Where a diagnostic points: the site and declaration path of a function.
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
    return .{ .path = "semantic.json", .declaration = declaration };
}

pub fn functionSite(function: semantic.SemanticFn) diagnostic.Site {
    return functionSiteFor(function, function.name);
}

pub fn functionDeclarationAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]const u8 {
    const owner = function.receiver orelse function.namespace;
    return if (owner) |value|
        std.fmt.allocPrint(allocator, "{s}.{s}", .{ value, function.name })
    else
        allocator.dupe(u8, function.name);
}
