const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const naming = @import("naming.zig");

pub fn semanticDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !void {
    if (document.ir_version != 1) return error.UnsupportedIrVersion;
    if (document.package.len == 0 or document.prefix.len == 0) return error.InvalidName;
    if (try findIssue(allocator, document) != null) return error.InvalidSemantic;
    for (document.functions) |function| {
        if (function.name.len == 0) return error.InvalidName;
        for (function.params) |parameter| try supported(parameter.type);
        try supported(function.@"return");
    }
}

pub fn findIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
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
            if (containsTaggedUnionValue(document, parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO006",
                .message = "cannot pass a tagged union by value",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "register it with `.repr = .tagged_union` and expose pointers to the union",
            };
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
        if (containsTaggedUnionValue(document, function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO006",
            .message = "cannot return a tagged union by value",
            .site = .{ .path = "semantic.json", .declaration = function.name },
            .hint = "register it with `.repr = .tagged_union` and expose pointers to the union",
        };
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
        if (declaration.kind == .tagged_union and !taggedUnionAccessorsSupported(document, declaration)) return .{
            .severity = .@"error",
            .code = "ZIGO006",
            .message = "tagged union contains a payload that cannot use generated accessors",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "use void, scalar, enum, opaque-pointer, or scalar-slice payloads",
        };
    }
    for (document.functions, 0..) |function, index| {
        const symbol = try functionSymbolAlloc(allocator, document.prefix, function);
        defer allocator.free(symbol);
        for (document.functions[0..index]) |previous| {
            const previous_symbol = try functionSymbolAlloc(allocator, document.prefix, previous);
            defer allocator.free(previous_symbol);
            if (std.mem.eql(u8, symbol, previous_symbol)) return .{
                .severity = .@"error",
                .code = "ZIGO007",
                .message = "generated C symbol collides with another declaration",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "rename one declaration or assign the APIs distinct receiver types",
            };
        }
    }
    if (findIntegrityProblem(document)) |declaration| return .{
        .severity = .@"error",
        .code = "ZIGO010",
        .message = "semantic document contains an unresolved or incompatible declaration reference",
        .site = .{ .path = "semantic.json", .declaration = declaration },
        .hint = "regenerate semantic.json from matching bindings and source declarations",
    };
    return null;
}

fn findIntegrityProblem(document: semantic.Semantic) ?[]const u8 {
    for (document.types, 0..) |declaration, index| {
        for (document.types[0..index]) |previous| {
            if (std.mem.eql(u8, declaration.name, previous.name)) return declaration.name;
        }
        if (declaration.kind == .@"enum") {
            const tag = declaration.tag_type orelse return declaration.name;
            if (tag != .int or tag.int.bits == 0 or tag.int.bits > 64) return declaration.name;
        }
        for (declaration.fields) |field| {
            if (field.type) |node| if (!referencesValid(document, node)) return declaration.name;
        }
    }
    for (document.functions) |function| {
        if (function.receiver) |receiver| {
            if (!hasHandleType(document, receiver)) return function.name;
        }
        for (function.params) |parameter| {
            if (!referencesValid(document, parameter.type)) return function.name;
        }
        if (!referencesValid(document, function.@"return")) return function.name;
    }
    for (document.constructors, 0..) |constructor, index| {
        if (!hasHandleType(document, constructor.type)) return constructor.type;
        for (document.constructors[0..index]) |previous| {
            if (std.mem.eql(u8, constructor.type, previous.type)) return constructor.type;
        }
        if (!hasConstructorInit(document, constructor)) return constructor.init;
        if (!hasConstructorDeinit(document, constructor)) return constructor.deinit;
    }
    return null;
}

fn referencesValid(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .@"enum" => |value| hasTypeKind(document, value.ref, .@"enum"),
        .opaque_ptr => |value| hasHandleType(document, value.ref),
        .value_struct => |value| hasTypeKind(document, value.ref, .value_struct),
        .slice => |value| referencesValid(document, value.element.*),
        .optional => |value| referencesValid(document, value.child.*),
        .error_union => |value| referencesValid(document, value.payload.*),
        .callback => |value| blk: {
            for (value.params) |parameter| if (!referencesValid(document, parameter)) break :blk false;
            break :blk referencesValid(document, value.@"return".*);
        },
        else => true,
    };
}

fn containsTaggedUnionValue(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .value_struct => |value| hasTypeKind(document, value.ref, .tagged_union),
        .slice => |value| containsTaggedUnionValue(document, value.element.*),
        .optional => |value| containsTaggedUnionValue(document, value.child.*),
        .error_union => |value| containsTaggedUnionValue(document, value.payload.*),
        .callback => |value| blk: {
            for (value.params) |parameter| if (containsTaggedUnionValue(document, parameter)) break :blk true;
            break :blk containsTaggedUnionValue(document, value.@"return".*);
        },
        else => false,
    };
}

fn taggedUnionAccessorsSupported(document: semantic.Semantic, declaration: semantic.TypeDecl) bool {
    const tag = declaration.tag_type orelse return false;
    if (tag != .@"enum" or !hasTypeKind(document, tag.@"enum".ref, .@"enum")) return false;
    if (declaration.fields.len == 0) return false;
    for (declaration.fields) |field| {
        const payload = field.type orelse return false;
        if (!accessorPayloadSupported(document, payload)) return false;
    }
    return true;
}

fn accessorPayloadSupported(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .void, .bool, .int, .float => true,
        .@"enum" => |value| hasTypeKind(document, value.ref, .@"enum"),
        .opaque_ptr => |value| hasHandleType(document, value.ref),
        .slice => |value| switch (value.element.*) {
            .bool, .int, .float => true,
            .@"enum" => |entry| hasTypeKind(document, entry.ref, .@"enum"),
            else => false,
        },
        else => false,
    };
}

fn hasTypeKind(document: semantic.Semantic, name: []const u8, kind: semantic.TypeKind) bool {
    for (document.types) |declaration| {
        if (std.mem.eql(u8, declaration.name, name)) return declaration.kind == kind;
    }
    return false;
}

fn hasHandleType(document: semantic.Semantic, name: []const u8) bool {
    return hasTypeKind(document, name, .@"opaque") or hasTypeKind(document, name, .tagged_union);
}

fn hasConstructorInit(document: semantic.Semantic, constructor: semantic.Constructor) bool {
    for (document.functions) |function| {
        if (!std.mem.eql(u8, function.name, constructor.init) or function.receiver != null or
            !std.mem.eql(u8, function.namespace orelse "", constructor.type)) continue;
        if (function.ownership != .caller or function.@"return" != .error_union) return false;
        const payload = function.@"return".error_union.payload.*;
        if (payload != .opaque_ptr) return false;
        return !payload.opaque_ptr.nullable and std.mem.eql(u8, payload.opaque_ptr.ref, constructor.type);
    }
    return false;
}

fn hasConstructorDeinit(document: semantic.Semantic, constructor: semantic.Constructor) bool {
    for (document.functions) |function| {
        if (!std.mem.eql(u8, function.name, constructor.deinit) or
            !std.mem.eql(u8, function.receiver orelse "", constructor.type)) continue;
        return function.params.len == 0 and function.@"return" == .void;
    }
    return false;
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
            .functions = &.{.{
                .name = "consume",
                .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_consume",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .tagged_union, .name = "Value" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO006]: cannot pass a tagged union by value\n  --> semantic.json (consume)\n  hint: register it with `.repr = .tagged_union` and expose pointers to the union\n" },
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
        const issue = (try findIssue(std.testing.allocator, case.document)) orelse return error.MissingDiagnostic;
        const rendered = try issue.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings(case.snapshot, rendered);
    }
}

test "tagged union handles accept supported accessor payloads and constructors" {
    var handle_payload: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Value" } };
    const document: semantic.Semantic = .{
        .constructors = &.{.{ .deinit = "deinit", .init = "create", .type = "Value" }},
        .functions = &.{
            .{
                .name = "create",
                .namespace = "Value",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &handle_payload } },
                .symbol = "zg_value_create",
            },
            .{ .name = "deinit", .params = &.{}, .receiver = "Value", .@"return" = .{ .void = {} }, .symbol = "zg_value_deinit" },
        },
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "integer", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
                },
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{
                    .{ .name = "none", .value = 0 },
                    .{ .name = "integer", .value = 1 },
                },
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    try semanticDocument(std.testing.allocator, document);
}

test "tagged union accessor payload rejects slices containing handles" {
    var handle: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Thing" } };
    const document: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "things", .type = .{ .slice = .{ .@"const" = true, .element = &handle } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{ .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            .{ .kind = .@"opaque", .name = "Thing" },
        },
        .zig_version = "0.16.0",
    };
    const issue = (try findIssue(std.testing.allocator, document)).?;
    try std.testing.expectEqualStrings("ZIGO006", issue.code);
    try std.testing.expectEqualStrings("Value", issue.site.declaration);
}

test "symbol collision validation propagates every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expectSymbolCollision, .{});
}

test "referential integrity failures are reported before lowering" {
    var callback_return: semantic.TypeNode = .{ .@"enum" = .{ .ref = "MissingMode" } };
    var optional_child: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "WrongKind" } };
    var constructor_payload: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Context" } };
    const valid_constructor_functions = [_]semantic.SemanticFn{
        .{
            .name = "create",
            .namespace = "Context",
            .ownership = .caller,
            .params = &.{},
            .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &constructor_payload } },
            .symbol = "ignored",
        },
        .{
            .name = "deinit",
            .params = &.{},
            .receiver = "Context",
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        },
    };
    const cases = [_]struct {
        document: semantic.Semantic,
        declaration: []const u8,
    }{
        .{ .document = .{
            .functions = &.{.{
                .name = "normalize",
                .params = &.{},
                .@"return" = .{ .@"enum" = .{ .ref = "MissingMode" } },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .declaration = "normalize" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"enum", .name = "Mode" }},
            .zig_version = "0.16.0",
        }, .declaration = "Mode" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{
                .{ .kind = .@"opaque", .name = "Thing" },
                .{ .kind = .value_struct, .name = "Thing", .layout = .@"extern" },
            },
            .zig_version = "0.16.0",
        }, .declaration = "Thing" },
        .{ .document = .{
            .functions = &.{.{
                .name = "visit",
                .params = &.{.{ .name = "callback", .type = .{ .callback = .{
                    .has_userdata = false,
                    .params = &.{},
                    .@"return" = &callback_return,
                } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .declaration = "visit" },
        .{ .document = .{
            .functions = &.{.{
                .name = "use",
                .params = &.{.{ .name = "thing", .type = .{ .optional = .{ .child = &optional_child } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"enum", .name = "WrongKind", .tag_type = .{ .int = .{ .bits = 32, .signed = false } } }},
            .zig_version = "0.16.0",
        }, .declaration = "use" },
        .{ .document = .{
            .constructors = &.{.{ .type = "Context", .init = "missing", .deinit = "deinit" }},
            .functions = &valid_constructor_functions,
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Context" }},
            .zig_version = "0.16.0",
        }, .declaration = "missing" },
        .{ .document = .{
            .constructors = &.{
                .{ .type = "Context", .init = "create", .deinit = "deinit" },
                .{ .type = "Context", .init = "create", .deinit = "deinit" },
            },
            .functions = &valid_constructor_functions,
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Context" }},
            .zig_version = "0.16.0",
        }, .declaration = "Context" },
    };
    for (cases) |case| {
        const issue = (try findIssue(std.testing.allocator, case.document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO010", issue.code);
        try std.testing.expectEqualStrings(case.declaration, issue.site.declaration);
        try std.testing.expectError(error.InvalidSemantic, semanticDocument(std.testing.allocator, case.document));
    }
}

test "well-formed constructor references pass integrity validation" {
    var payload: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Context" } };
    const document: semantic.Semantic = .{
        .constructors = &.{.{ .type = "Context", .init = "create", .deinit = "deinit" }},
        .functions = &.{
            .{
                .name = "create",
                .namespace = "Context",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &payload } },
                .symbol = "ignored",
            },
            .{
                .name = "deinit",
                .params = &.{},
                .receiver = "Context",
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            },
        },
        .package = "good",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Context" }},
        .zig_version = "0.16.0",
    };
    try std.testing.expect((try findIssue(std.testing.allocator, document)) == null);
    try semanticDocument(std.testing.allocator, document);
}

fn expectSymbolCollision(allocator: std.mem.Allocator) !void {
    const document: semantic.Semantic = .{
        .functions = &.{
            .{ .name = "lookupID", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
            .{ .name = "lookup_id", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
        },
        .package = "bad",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const issue = (try findIssue(allocator, document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO007", issue.code);
}
