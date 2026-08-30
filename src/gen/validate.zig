const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const naming = @import("naming.zig");

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
        if (function.has_comptime_params == true) return .{
            .severity = .@"error",
            .code = "ZIGO008",
            .message = "cannot expose a function with comptime parameters",
            .site = .{ .path = "semantic.json", .declaration = function.name },
            .hint = "bind a concrete specialization instead of the generic function",
        };
        for (function.params) |parameter| {
            if (unsupportedValueStruct(document, parameter.type) != null) return .{
                .severity = .@"error",
                .code = "ZIGO003",
                .message = "cannot pass a non-extern struct by value",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "declare it as `extern struct`, or expose it as opaque",
            };
            if (containsNonCFunctionPointer(parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO004",
                .message = "function pointer does not use the C calling convention",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "declare the callback with `callconv(.c)`",
            };
            if (parameter.type == .slice and containsPointer(parameter.type.slice.element.*)) return .{
                .severity = .@"error",
                .code = "ZIGO005",
                .message = "slice element type contains a pointer",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "pass scalar elements or opaque handle values instead of Go pointers",
            };
            if (parameter.retention == .retained and containsPointer(parameter.type) and !hasMatchingRelease(document, function)) return .{
                .severity = .@"error",
                .code = "ZIGO009",
                .message = "retained pointer has no matching release function",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "expose a release, clear, close, destroy, or deinit function for the retained value",
            };
        }
        if (unsupportedValueStruct(document, function.@"return") != null) return .{
            .severity = .@"error",
            .code = "ZIGO003",
            .message = "cannot pass a non-extern struct by value",
            .site = .{ .path = "semantic.json", .declaration = function.name },
            .hint = "declare it as `extern struct`, or expose it as opaque",
        };
        if (containsNonCFunctionPointer(function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO004",
            .message = "function pointer does not use the C calling convention",
            .site = .{ .path = "semantic.json", .declaration = function.name },
            .hint = "declare the callback with `callconv(.c)`",
        };
    }
    for (document.types) |declaration| {
        if (declaration.kind == .@"enum" and !declaration.exhaustive) return .{
            .severity = .@"error",
            .code = "ZIGO002",
            .message = "cannot expose a non-exhaustive enum",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "make the enum exhaustive before exposing it",
        };
        if (declaration.kind == .tagged_union) return .{
            .severity = .@"error",
            .code = "ZIGO006",
            .message = "tagged unions are not supported in IR v1",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "expose separate functions or an explicit extern struct representation",
        };
    }
    for (document.functions, 0..) |function, index| {
        const symbol = functionSymbolAlloc(std.heap.page_allocator, document.prefix, function) catch return null;
        defer std.heap.page_allocator.free(symbol);
        for (document.functions[0..index]) |previous| {
            const previous_symbol = functionSymbolAlloc(std.heap.page_allocator, document.prefix, previous) catch return null;
            defer std.heap.page_allocator.free(previous_symbol);
            if (std.mem.eql(u8, symbol, previous_symbol)) return .{
                .severity = .@"error",
                .code = "ZIGO007",
                .message = "generated C symbol collides with another declaration",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "rename one declaration or assign the APIs distinct receiver types",
            };
        }
    }
    return null;
}

fn containsNonCFunctionPointer(node: semantic.TypeNode) bool {
    return switch (node) {
        .callback => |callback| !callback.c_callconv,
        .slice => |value| containsNonCFunctionPointer(value.element.*),
        .optional => |value| containsNonCFunctionPointer(value.child.*),
        .error_union => |value| containsNonCFunctionPointer(value.payload.*),
        else => false,
    };
}

fn hasMatchingRelease(document: semantic.Semantic, retaining: semantic.SemanticFn) bool {
    if (retaining.receiver) |receiver| {
        for (document.constructors) |constructor| if (std.mem.eql(u8, constructor.type, receiver)) return true;
    }
    for (document.functions) |candidate| {
        if (!sameOwner(retaining, candidate)) continue;
        if (isReleaseName(candidate.name)) return true;
    }
    return false;
}

fn sameOwner(a: semantic.SemanticFn, b: semantic.SemanticFn) bool {
    const a_owner = a.receiver orelse a.namespace orelse "";
    const b_owner = b.receiver orelse b.namespace orelse "";
    return std.mem.eql(u8, a_owner, b_owner);
}

fn isReleaseName(name: []const u8) bool {
    return std.mem.eql(u8, name, "release") or std.mem.eql(u8, name, "clear") or
        std.mem.eql(u8, name, "close") or std.mem.eql(u8, name, "destroy") or
        std.mem.eql(u8, name, "deinit");
}

fn functionSymbolAlloc(allocator: std.mem.Allocator, prefix: []const u8, function: semantic.SemanticFn) ![]u8 {
    const function_name = try naming.snakeAlloc(allocator, function.name);
    defer allocator.free(function_name);
    if (function.receiver orelse function.namespace) |owner| {
        const owner_name = try naming.snakeAlloc(allocator, owner);
        defer allocator.free(owner_name);
        return std.fmt.allocPrint(allocator, "{s}_{s}_{s}", .{ prefix, owner_name, function_name });
    }
    return std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, function_name });
}

fn supported(node: semantic.TypeNode) !void {
    switch (node) {
        .void, .bool, .@"enum", .opaque_ptr, .value_struct => {},
        .int => |value| if (value.bits == 0 or value.bits > 64) return error.UnsupportedIntegerWidth,
        .float => |value| if (value.bits != 32 and value.bits != 64) return error.UnsupportedFloatWidth,
        .slice => |value| try supported(value.element.*),
        .error_union => |value| try supported(value.payload.*),
        .callback => |value| {
            for (value.params) |parameter| try supported(parameter);
            try supported(value.@"return".*);
        },
        else => return error.UnsupportedType,
    }
}

fn unsupportedValueStruct(document: semantic.Semantic, node: semantic.TypeNode) ?[]const u8 {
    return switch (node) {
        .value_struct => |value| blk: {
            for (document.types) |declaration| {
                if (declaration.kind == .value_struct and std.mem.eql(u8, declaration.name, value.ref)) {
                    break :blk if (declaration.layout == null) declaration.name else null;
                }
            }
            break :blk value.ref;
        },
        .slice => |value| unsupportedValueStruct(document, value.element.*),
        .optional => |value| unsupportedValueStruct(document, value.child.*),
        .error_union => |value| unsupportedValueStruct(document, value.payload.*),
        else => null,
    };
}

fn containsPointer(node: semantic.TypeNode) bool {
    return switch (node) {
        .opaque_ptr, .slice, .callback => true,
        .optional => |value| containsPointer(value.child.*),
        else => false,
    };
}

test "implemented diagnostic snapshots are stable" {
    var void_node: semantic.TypeNode = .{ .void = {} };
    var pointer_node: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Thing" } };
    var callback_return: semantic.TypeNode = .{ .void = {} };
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
                .name = "configure",
                .params = &.{.{ .name = "config", .type = .{ .value_struct = .{ .ref = "Config" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_configure",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .value_struct, .name = "Config" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO003]: cannot pass a non-extern struct by value\n  --> semantic.json (configure)\n  hint: declare it as `extern struct`, or expose it as opaque\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "setCallback",
                .params = &.{.{ .name = "callback", .type = .{ .callback = .{ .c_callconv = false, .has_userdata = false, .params = &.{}, .@"return" = &callback_return } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_set_callback",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO004]: function pointer does not use the C calling convention\n  --> semantic.json (setCallback)\n  hint: declare the callback with `callconv(.c)`\n" },
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
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .tagged_union, .name = "Value" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO006]: tagged unions are not supported in IR v1\n  --> semantic.json (Value)\n  hint: expose separate functions or an explicit extern struct representation\n" },
        .{ .document = .{
            .functions = &.{
                .{ .name = "lookupID", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
                .{ .name = "lookup_id", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
            },
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO007]: generated C symbol collides with another declaration\n  --> semantic.json (lookup_id)\n  hint: rename one declaration or assign the APIs distinct receiver types\n" },
        .{ .document = .{
            .functions = &.{.{
                .has_comptime_params = true,
                .name = "generic",
                .params = &.{},
                .@"return" = .{ .void = {} },
                .symbol = "zg_generic",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO008]: cannot expose a function with comptime parameters\n  --> semantic.json (generic)\n  hint: bind a concrete specialization instead of the generic function\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "remember",
                .params = &.{.{ .name = "thing", .retention = .retained, .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Thing" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_remember",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Thing" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO009]: retained pointer has no matching release function\n  --> semantic.json (remember)\n  hint: expose a release, clear, close, destroy, or deinit function for the retained value\n" },
    };
    for (cases) |case| {
        const issue = findIssue(case.document) orelse return error.MissingDiagnostic;
        const rendered = try issue.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings(case.snapshot, rendered);
    }
}
