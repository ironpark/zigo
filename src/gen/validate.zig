const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");

pub fn semanticDocument(document: semantic.Semantic) !void {
    if (document.ir_version != 1) return error.UnsupportedIrVersion;
    if (document.package.len == 0 or document.prefix.len == 0) return error.InvalidName;
    if (findIssue(document) != null) return error.InvalidSemantic;
    for (document.functions) |function| {
        if (function.name.len == 0) return error.InvalidName;
        for (function.params) |parameter| try supported(parameter.type);
        try supported(function.@"return");
    }
}

pub fn findIssue(document: semantic.Semantic) ?diagnostic.Diagnostic {
    for (document.functions) |function| {
        if (function.@"return" == .error_union and function.@"return".error_union.anyerror) return .{
            .severity = .@"error",
            .code = "ZIGO001",
            .message = "cannot expose an anyerror return with stable ABI codes",
            .site = .{ .path = "semantic.json", .declaration = function.name },
            .hint = "use an explicit error set in the Zig function signature",
        };
        for (function.params) |parameter| {
            if (parameter.type == .slice and containsPointer(parameter.type.slice.element.*)) return .{
                .severity = .@"error",
                .code = "ZIGO005",
                .message = "slice element type contains a pointer",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "pass scalar elements or opaque handle values instead of Go pointers",
            };
        }
    }
    for (document.types) |declaration| {
        if (declaration.kind == .@"enum" and !declaration.exhaustive) return .{
            .severity = .@"error",
            .code = "ZIGO002",
            .message = "cannot expose a non-exhaustive enum",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "make the enum exhaustive before exposing it",
        };
    }
    return null;
}

fn supported(node: semantic.TypeNode) !void {
    switch (node) {
        .void, .bool, .@"enum" => {},
        .int => |value| if (value.bits == 0 or value.bits > 64) return error.UnsupportedIntegerWidth,
        .float => |value| if (value.bits != 32 and value.bits != 64) return error.UnsupportedFloatWidth,
        .slice => |value| try supported(value.element.*),
        .error_union => |value| try supported(value.payload.*),
        else => return error.UnsupportedType,
    }
}

fn containsPointer(node: semantic.TypeNode) bool {
    return switch (node) {
        .opaque_ptr, .slice, .callback => true,
        .optional => |value| containsPointer(value.child.*),
        else => false,
    };
}

test "ZIGO001 ZIGO002 and ZIGO005 diagnostics are stable snapshots" {
    var void_node: semantic.TypeNode = .{ .void = {} };
    var pointer_node: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Thing" } };
    const cases = [_]struct { document: semantic.Semantic, snapshot: []const u8 }{
        .{ .document = .{
            .functions = &.{.{
                .name = "unstable",
                .params = &.{},
                .@"return" = .{ .error_union = .{ .anyerror = true, .error_set = &.{}, .payload = &void_node } },
                .symbol = "zg_unstable",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO001]: cannot expose an anyerror return with stable ABI codes\n  --> semantic.json (unstable)\n  hint: use an explicit error set in the Zig function signature\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .exhaustive = false, .kind = .@"enum", .name = "Open" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO002]: cannot expose a non-exhaustive enum\n  --> semantic.json (Open)\n  hint: make the enum exhaustive before exposing it\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "pointers",
                .params = &.{.{ .name = "values", .type = .{ .slice = .{ .@"const" = true, .element = &pointer_node } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_pointers",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO005]: slice element type contains a pointer\n  --> semantic.json (pointers)\n  hint: pass scalar elements or opaque handle values instead of Go pointers\n" },
    };
    for (cases) |case| {
        const issue = findIssue(case.document) orelse return error.MissingDiagnostic;
        const rendered = try issue.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings(case.snapshot, rendered);
    }
}
