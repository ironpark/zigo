const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const naming = @import("naming");

/// Every rejection reaches the user as a rendered diagnostic, so this only
/// reports whether the document had one. Callers that want the text call
/// `findIssue` themselves; the scratch arena here owns the strings that
/// diagnostic built.
pub fn semanticDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    if (try findIssue(scratch.allocator(), document) != null) return error.InvalidSemantic;
}

/// Every purego callback dispatcher returns one pointer-sized integer, which is
/// what Windows' `syscall.NewCallback` demands and what the native side reads
/// back as `int32_t` or ignores. A callback that returns anything else -- a
/// float, a wider integer -- has nowhere to put its result: the dispatcher would
/// drop it and the native caller would read whatever the register held.
/// Generation refuses instead of emitting that silence.
///
/// Float *parameters* are no longer a rejection class. They cross as their
/// IEEE-754 bit pattern through an integer of the same width, converted by the
/// shim on both ends, so `compileCallback` never sees a floating-point argument
/// on any platform.
pub fn puregoCallbackIssue(document: semantic.Semantic) ?diagnostic.Diagnostic {
    for (document.functions) |function| {
        for (function.params) |parameter| {
            if (parameter.type != .callback) continue;
            const result = parameter.type.callback.@"return".*;
            if (result == .void) continue;
            if (result == .int and result.int.signed and result.int.bits == 32) continue;
            return .{
                .severity = .@"error",
                .code = "ZIGO014",
                .message = "purego callback result must be void or a signed 32-bit integer",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "return `void` or `i32` from the callback, or report the value through userdata",
            };
        }
    }
    return null;
}

pub fn puregoCallbacks(document: semantic.Semantic) !void {
    if (puregoCallbackIssue(document) != null) return error.InvalidSemantic;
}

/// The single place a semantic document is judged. A returned diagnostic may
/// point at strings allocated from `allocator` -- the declaration and location
/// text is built from the document -- so pass a scratch arena and drop it once
/// the diagnostic is rendered.
pub fn findIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    if (document.ir_version != 1) return .{
        .severity = .@"error",
        .code = "ZIGO020",
        .message = "semantic document uses an unsupported IR version",
        .site = .{ .path = "semantic.json", .declaration = "ir_version" },
        .hint = "regenerate semantic.json with a matching zigo version",
    };
    if (document.package.len == 0) return .{
        .severity = .@"error",
        .code = "ZIGO021",
        .message = "semantic document has an empty package name",
        .site = .{ .path = "semantic.json", .declaration = "package" },
        .hint = "give the binding a package name",
    };
    if (document.prefix.len == 0) return .{
        .severity = .@"error",
        .code = "ZIGO021",
        .message = "semantic document has an empty symbol prefix",
        .site = .{ .path = "semantic.json", .declaration = "prefix" },
        .hint = "give the binding a symbol prefix",
    };
    if (try identifierIssue(allocator, document)) |issue| return issue;
    for (document.functions) |function| {
        if (function.name.len == 0) return .{
            .severity = .@"error",
            .code = "ZIGO021",
            .message = "exposed function has an empty name",
            .site = .{ .path = "semantic.json", .declaration = "functions" },
            .hint = "expose a named declaration",
        };
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
            if (nestedValueStruct(parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO013",
                .message = "extern struct is only supported as a whole parameter or return value",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "pass the struct on its own or as a direct slice element; optional and callback signatures are not supported",
            };
            if (containsNonCFunctionPointer(parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO004",
                .message = "function pointer does not use the C calling convention",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "declare the callback with `callconv(.c)`",
            };
            if (parameter.type == .slice and containsPointer(parameter.type.slice.element.*) and
                !isStringSliceParameter(parameter)) return .{
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
        if (nestedValueStruct(function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO013",
            .message = "extern struct is only supported as a whole parameter or return value",
            .site = .{ .path = "semantic.json", .declaration = function.name },
            .hint = "pass the struct on its own or as a direct slice element; optional and callback signatures are not supported",
        };
        if (containsNonCFunctionPointer(function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO004",
            .message = "function pointer does not use the C calling convention",
            .site = .{ .path = "semantic.json", .declaration = function.name },
            .hint = "declare the callback with `callconv(.c)`",
        };
        // A returned slice crosses as `T*` plus a length, so its element has to
        // be a value the C ABI can name. The error-union payload uses the same
        // out parameters and answers to the same rule.
        if (sliceReturnElement(function)) |element| {
            if (containsPointer(element)) return .{
                .severity = .@"error",
                .code = "ZIGO005",
                .message = "slice element type contains a pointer",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "return scalar, enum, or extern-struct elements instead of Go pointers",
            };
        }
        // A caller-owned slice is handed over through `release` instead of a
        // handle destructor, so it answers to ZIGO016 rather than ZIGO015.
        if (function.ownership == .caller and isReleasableSliceReturn(function)) {
            if (releaseTargetIssue(document, function)) |issue| return issue;
        } else if (function.ownership == .caller and !ownedReturnIsWrappable(document, function)) return .{
            .severity = .@"error",
            .code = "ZIGO015",
            .message = "caller-owned return has no constructed handle to hand over",
            .site = .{ .path = "semantic.json", .declaration = function.name },
            .hint = "return a pointer to an opaque type that has both a constructor and a destructor, or drop `.returns = .caller`",
        };
        for (function.params) |parameter| {
            if (parameter.written == null) continue;
            if (parameter.direction != .out) return .{
                .severity = .@"error",
                .code = "ZIGO017",
                .message = "written hint declared on a parameter that is not an output slice",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "add `.direction = .out` to the parameter, or drop `.written`",
            };
            if (parameter.writtenHint() == .@"return" and !returnsCount(function.@"return")) return .{
                .severity = .@"error",
                .code = "ZIGO017",
                .message = "`.written = .return` needs a `usize` result to report the count",
                .site = .{ .path = "semantic.json", .declaration = function.name },
                .hint = "return `usize` or `!usize` from the function, or use the default `.written = .all`",
            };
        }
        if (function.release != null and !isReleasableSliceReturn(function)) return .{
            .severity = .@"error",
            .code = "ZIGO016",
            .message = "release function declared on a return that zigo does not free",
            .site = .{ .path = "semantic.json", .declaration = function.name },
            .hint = "use `.release` only together with `.returns = .caller` on a slice return",
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
            .hint = "use void, scalar, enum, opaque-pointer, or numeric-slice payloads",
        };
        if (declaration.kind == .value_struct and declaration.layout == .@"extern") {
            // A width zigo would promote elsewhere gets its own message here:
            // the field is mirrored into C byte for byte, with no shim in
            // between to convert it.
            for (declaration.fields) |field| {
                const node = field.type orelse continue;
                if (node != .int or integerSupported(node.int) or !promotableInteger(node.int)) continue;
                const spelling = try zigSpellingAlloc(allocator, node);
                return .{
                    .severity = .@"error",
                    .code = "ZIGO018",
                    .message = try std.fmt.allocPrint(allocator, "cannot promote integer width `{s}` in field `{s}`", .{ spelling, field.name }),
                    .site = .{ .path = "semantic.json", .declaration = declaration.name },
                    .hint = "an `extern struct` is mirrored into C field by field; use an 8, 16, 32, or 64-bit integer here",
                };
            }
            if (externStructProblem(document, declaration, 0)) |site| return .{
                .severity = .@"error",
                .code = "ZIGO012",
                .message = "extern struct cannot cross the C ABI",
                .site = .{ .path = "semantic.json", .declaration = site },
                .hint = "give every field a bool, integer, float, registered enum, or nested `extern struct` type; an empty struct has no C representation",
            };
        }
        if (declaration.kind == .tagged_union and declaration.accessStrategy() == .snapshot) {
            if (snapshotIneligibleVariant(document, declaration)) |variant| return .{
                .severity = .@"error",
                .code = "ZIGO011",
                .message = "tagged union variant cannot be mirrored into a value snapshot",
                .site = .{ .path = "semantic.json", .declaration = variant },
                .hint = "use `.access = .projection`, or give every variant a void, bool, integer, float, or enum payload and a name other than `tag`",
            };
        }
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
    if (try findGeneratedAccessorCollision(allocator, document)) |declaration| return .{
        .severity = .@"error",
        .code = "ZIGO007",
        .message = "generated tagged-union accessor collides with another declaration",
        .site = .{ .path = "semantic.json", .declaration = declaration },
        .hint = "rename the conflicting function, type, or union variant",
    };
    if (findIntegrityProblem(document)) |declaration| return .{
        .severity = .@"error",
        .code = "ZIGO010",
        .message = "semantic document contains an unresolved or incompatible declaration reference",
        .site = .{ .path = "semantic.json", .declaration = declaration },
        .hint = "regenerate semantic.json from matching bindings and source declarations",
    };
    // Types the C ABI cannot name are reported last so that the sharper
    // diagnostics above keep naming the declarations they always did.
    for (document.functions) |function| {
        for (function.params) |parameter| {
            if (try typeOffense(allocator, parameter.type, true)) |offense| {
                const root = try std.fmt.allocPrint(allocator, "parameter `{s}`", .{parameter.name});
                const location = try locationAlloc(allocator, offense.context, root);
                return try offenseDiagnostic(allocator, function, offense, location);
            }
        }
        if (try typeOffense(allocator, function.@"return", true)) |offense| {
            const location = try locationAlloc(allocator, offense.context, "the return value");
            return try offenseDiagnostic(allocator, function, offense, location);
        }
    }
    return null;
}

/// Names that reach Go verbatim -- a registered type's name -- have to be Go
/// identifiers already, because nothing stands between them and the `type`
/// declaration they become. Names zigo case-converts are judged on the
/// converted spelling instead, so a Zig field called `type` stays legal as the
/// Go field `Type`. Either way the check runs before generation, because a
/// name reflection derived from `@typeName` can be something like `4])` and
/// the only thing worse than rejecting it is writing it into a `.go` file.
fn identifierIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.types) |declaration| {
        if (try nameIssue(allocator, .{
            .label = "registered type name",
            .spelling = declaration.name,
            .declaration = if (declaration.name.len == 0) "types" else declaration.name,
            .zig_path = declaration.zig_path,
            .hint = "register the type in `.types` with an explicit `.name` that is a Go identifier",
        })) |issue| return issue;
        const member_label = switch (declaration.kind) {
            .@"enum" => "enum tag",
            .tagged_union => "union variant",
            .error_set => "error name",
            else => "field name",
        };
        for (declaration.fields) |field| {
            if (try nameIssue(allocator, .{
                .label = member_label,
                .spelling = field.name,
                .convert = true,
                .declaration = declaration.name,
                .zig_path = declaration.zig_path,
                .hint = "rename the declaration in Zig so its name converts to a Go identifier",
            })) |issue| return issue;
        }
    }
    for (document.functions) |function| {
        // An empty function name has its own diagnostic below, and it says
        // more than "this is not an identifier" would.
        if (function.name.len == 0) continue;
        if (try nameIssue(allocator, .{
            .label = "function name",
            .spelling = function.name,
            .convert = true,
            .declaration = function.name,
            .hint = "give the entry a `.name` that converts to a Go identifier",
        })) |issue| return issue;
    }
    return null;
}

const NameCheck = struct {
    label: []const u8,
    spelling: []const u8,
    /// True when zigo pascal-cases the name on its way into Go, which decides
    /// whether the written spelling or the converted one is judged.
    convert: bool = false,
    declaration: []const u8,
    zig_path: ?[]const u8 = null,
    hint: []const u8,
};

fn nameIssue(allocator: std.mem.Allocator, check: NameCheck) !?diagnostic.Diagnostic {
    // A document that validates must not leak: callers are only asked for a
    // scratch arena because a *rejection* builds strings, not an acceptance.
    const candidate = if (check.convert) try naming.pascalAlloc(allocator, check.spelling) else check.spelling;
    defer if (check.convert) allocator.free(candidate);
    if (naming.isGoIdentifier(candidate)) return null;
    const message = if (check.zig_path) |path|
        try std.fmt.allocPrint(allocator, "{s} `{s}` from Zig type `{s}` is not a valid Go identifier", .{ check.label, check.spelling, path })
    else
        try std.fmt.allocPrint(allocator, "{s} `{s}` is not a valid Go identifier", .{ check.label, check.spelling });
    return .{
        .severity = .@"error",
        .code = "ZIGO021",
        .message = message,
        .site = .{ .path = "semantic.json", .declaration = check.declaration },
        .hint = check.hint,
    };
}

/// The type the C ABI cannot name, plus how it was reached from the parameter
/// or return value that carries it. `context` is built on the way back out, so
/// a document that validates never allocates.
const Offense = struct {
    node: semantic.TypeNode,
    context: ?[]const u8 = null,
    reason: Reason = .unsupported,

    /// `narrow_position` is a width zigo does promote, found where it cannot:
    /// the two need different hints because only one of them is about the type.
    const Reason = enum { unsupported, narrow_position };
};

/// `promotable` is true only where the shim stands between Zig and C and can
/// convert a single value. Nested positions are mirrored byte for byte, so a
/// width C cannot name is still a rejection there.
fn typeOffense(allocator: std.mem.Allocator, node: semantic.TypeNode, promotable: bool) error{OutOfMemory}!?Offense {
    switch (node) {
        .void, .bool, .@"enum", .opaque_ptr, .value_struct => return null,
        .int => |value| {
            if (integerSupported(value)) return null;
            if (promotable and promotableInteger(value)) return null;
            return Offense{ .node = node, .reason = if (promotableInteger(value)) .narrow_position else .unsupported };
        },
        .float => |value| return if (floatSupported(value)) null else Offense{ .node = node },
        .slice => |value| return wrapOffense(allocator, try typeOffense(allocator, value.element.*, false), "the slice element"),
        .error_union => |value| return wrapOffense(allocator, try typeOffense(allocator, value.payload.*, promotable), "the error payload"),
        .callback => |value| {
            for (value.params, 0..) |parameter, index| {
                if (try typeOffense(allocator, parameter, false)) |found| {
                    const label = try std.fmt.allocPrint(allocator, "callback parameter {d}", .{index});
                    return wrapOffense(allocator, found, label);
                }
            }
            return wrapOffense(allocator, try typeOffense(allocator, value.@"return".*, false), "the callback return value");
        },
        else => return Offense{ .node = node },
    }
}

fn wrapOffense(allocator: std.mem.Allocator, found: ?Offense, label: []const u8) error{OutOfMemory}!?Offense {
    const offense = found orelse return null;
    const context = offense.context orelse return Offense{ .node = offense.node, .context = label, .reason = offense.reason };
    return Offense{
        .node = offense.node,
        .context = try std.fmt.allocPrint(allocator, "{s} of {s}", .{ context, label }),
        .reason = offense.reason,
    };
}

fn locationAlloc(allocator: std.mem.Allocator, context: ?[]const u8, root: []const u8) ![]const u8 {
    const inner = context orelse return root;
    return std.fmt.allocPrint(allocator, "{s} of {s}", .{ inner, root });
}

fn offenseDiagnostic(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    offense: Offense,
    location: []const u8,
) !diagnostic.Diagnostic {
    const node = offense.node;
    const spelling = try zigSpellingAlloc(allocator, node);
    const declaration = try functionDeclarationAlloc(allocator, function);
    return switch (node) {
        .int => if (offense.reason == .narrow_position) .{
            .severity = .@"error",
            .code = "ZIGO018",
            .message = try std.fmt.allocPrint(allocator, "cannot promote integer width `{s}` in {s}", .{ spelling, location }),
            .site = .{ .path = "semantic.json", .declaration = declaration },
            .hint = "zigo widens a narrow integer only as a whole parameter, return value, or error payload; use an 8, 16, 32, or 64-bit integer here",
        } else .{
            .severity = .@"error",
            .code = "ZIGO018",
            .message = try std.fmt.allocPrint(allocator, "unsupported integer width `{s}` in {s}", .{ spelling, location }),
            .site = .{ .path = "semantic.json", .declaration = declaration },
            .hint = "use an integer of 64 bits or fewer",
        },
        .float => .{
            .severity = .@"error",
            .code = "ZIGO018",
            .message = try std.fmt.allocPrint(allocator, "unsupported float width `{s}` in {s}", .{ spelling, location }),
            .site = .{ .path = "semantic.json", .declaration = declaration },
            .hint = "use `f32` or `f64`",
        },
        else => .{
            .severity = .@"error",
            .code = "ZIGO019",
            .message = try std.fmt.allocPrint(allocator, "unsupported type `{s}` in {s}", .{ spelling, location }),
            .site = .{ .path = "semantic.json", .declaration = declaration },
            .hint = "use a bool, integer, float, enum, opaque pointer, extern struct, slice, or callback type",
        },
    };
}

/// How a Zig author spells the offending type, so the message names what they
/// wrote rather than the IR tag that stands in for it.
fn zigSpellingAlloc(allocator: std.mem.Allocator, node: semantic.TypeNode) ![]const u8 {
    return switch (node) {
        .int => |value| if (value.is_usize)
            try allocator.dupe(u8, if (value.signed) "isize" else "usize")
        else
            try std.fmt.allocPrint(allocator, "{s}{d}", .{ if (value.signed) "i" else "u", value.bits }),
        .float => |value| try std.fmt.allocPrint(allocator, "f{d}", .{value.bits}),
        else => try allocator.dupe(u8, @tagName(node)),
    };
}

fn functionDeclarationAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]const u8 {
    const owner = function.receiver orelse function.namespace;
    return if (owner) |value|
        std.fmt.allocPrint(allocator, "{s}.{s}", .{ value, function.name })
    else
        allocator.dupe(u8, function.name);
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
            if (value.ref) |ref| if (!hasTypeKind(document, ref, .callback)) break :blk false;
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

/// What zigo can move across the C ABI as a single scalar. `bool` crosses as
/// uint8_t exactly as it does everywhere else; public Go restores it. Every
/// payload rule below is this set plus whatever else that position allows.
fn scalarPayloadSupported(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .bool => true,
        .int => |value| integerSupported(value),
        .float => |value| floatSupported(value),
        .@"enum" => |value| hasTypeKind(document, value.ref, .@"enum"),
        else => false,
    };
}

fn accessorPayloadSupported(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .void => true,
        .opaque_ptr => |value| hasHandleType(document, value.ref),
        .slice => |value| switch (value.element.*) {
            .int => |integer| integerSupported(integer),
            .float => |float| floatSupported(float),
            else => false,
        },
        else => scalarPayloadSupported(document, node),
    };
}

/// The first variant that cannot live in a zigo-owned snapshot struct, or null
/// when the union is eligible. Slices, opaque handles, nested aggregates,
/// optionals, error unions and callbacks all disqualify it: a snapshot must be
/// a flat copy of C-representable scalars.
fn snapshotIneligibleVariant(document: semantic.Semantic, declaration: semantic.TypeDecl) ?[]const u8 {
    for (declaration.fields) |field| {
        const payload = field.type orelse return field.name;
        if (!snapshotPayloadEligible(document, payload)) return field.name;
        // The snapshot struct spells the discriminant `tag`, so no variant may
        // claim that field name.
        if (std.ascii.eqlIgnoreCase(field.name, "tag")) return field.name;
    }
    return null;
}

fn snapshotPayloadEligible(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .void => true,
        else => scalarPayloadSupported(document, node),
    };
}

/// The C mirror of an `extern struct` is a flat record of C-representable
/// members, so a field must be a scalar, a registered enum, or another
/// eligible `extern struct`. Returns the offending field, or the struct itself
/// when it has no fields to mirror.
fn externStructProblem(document: semantic.Semantic, declaration: semantic.TypeDecl, depth: usize) ?[]const u8 {
    // A well-formed document cannot nest structs cyclically, but a hand-written
    // one can; the bound keeps validation total rather than trusting the input.
    if (depth >= 16) return declaration.name;
    if (declaration.fields.len == 0) return declaration.name;
    for (declaration.fields) |field| {
        const node = field.type orelse return field.name;
        if (!externStructFieldEligible(document, node, depth)) return field.name;
    }
    return null;
}

fn externStructFieldEligible(document: semantic.Semantic, node: semantic.TypeNode, depth: usize) bool {
    return switch (node) {
        .value_struct => |value| for (document.types) |nested| {
            if (!std.mem.eql(u8, nested.name, value.ref)) continue;
            break nested.kind == .value_struct and nested.layout == .@"extern" and
                externStructProblem(document, nested, depth + 1) == null;
        } else false,
        else => scalarPayloadSupported(document, node),
    };
}

/// True when a value struct appears anywhere other than as a whole parameter,
/// return value, error-union payload, or direct slice element. Those positions
/// lower to a pointer to the struct (or a pointer-plus-length pair for slices);
/// optional and callback signatures still do not have an aggregate ABI shape.
fn nestedValueStruct(node: semantic.TypeNode) bool {
    return switch (node) {
        // A direct value-struct node is a supported aggregate position.
        .value_struct => false,
        // The slice lowering already carries the element as `T*`; only the
        // direct element is allowed. A slice of optional/slice/callback values
        // would still contain the struct in an unsupported nested position.
        .slice => |value| switch (value.element.*) {
            .value_struct => false,
            else => containsValueStruct(value.element.*),
        },
        .error_union => |value| nestedValueStruct(value.payload.*),
        else => containsValueStruct(node),
    };
}

fn containsValueStruct(node: semantic.TypeNode) bool {
    return switch (node) {
        .value_struct => true,
        .slice => |value| containsValueStruct(value.element.*),
        .optional => |value| containsValueStruct(value.child.*),
        .error_union => |value| containsValueStruct(value.payload.*),
        .callback => |value| blk: {
            for (value.params) |parameter| if (containsValueStruct(parameter)) break :blk true;
            break :blk containsValueStruct(value.@"return".*);
        },
        else => false,
    };
}

/// The widths C can name directly. Every position that mirrors bytes into C --
/// an `extern struct` field, a slice element, a callback signature -- answers
/// to this one, because those have no shim between the two spellings.
fn integerSupported(value: semantic.Int) bool {
    if (value.is_usize) return value.bits != 0 and value.bits <= 64;
    return value.bits == 8 or value.bits == 16 or value.bits == 32 or value.bits == 64;
}

/// A whole parameter, return value, or error payload passes through the shim,
/// which range-checks the value and casts it, so any width Zig can spell up to
/// 64 bits crosses in the next C integer that exists.
fn promotableInteger(value: semantic.Int) bool {
    return !value.is_usize and value.bits >= 1 and value.bits <= 64;
}

fn floatSupported(value: semantic.Float) bool {
    return value.bits == 32 or value.bits == 64;
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

/// Whether a `.returns = .caller` result can become an owned Go handle. Only a
/// pointer to a type the binding constructs has a `newX` helper to wrap it and a
/// destructor for the cleanup to call; anything else would emit a raw pointer
/// against a typed signature, which does not compile.
fn ownedReturnIsWrappable(document: semantic.Semantic, function: semantic.SemanticFn) bool {
    const payload = if (function.@"return" == .error_union) function.@"return".error_union.payload.* else function.@"return";
    if (payload != .opaque_ptr) return false;
    for (document.constructors) |constructor| {
        if (std.mem.eql(u8, constructor.type, payload.opaque_ptr.ref)) return true;
    }
    return false;
}

/// A slice return is the one non-handle result zigo can hand over: generated Go
/// copies it and then calls the declared release function. A fallible slice
/// return hands over the same buffer, so `![]T` qualifies on the same terms.
/// The count a `.written = .return` parameter reads back from. An error union
/// reports it through its payload; the error path writes zero instead.
fn returnsCount(node: semantic.TypeNode) bool {
    const payload = if (node == .error_union) node.error_union.payload.* else node;
    return payload == .int and payload.int.is_usize;
}

fn isReleasableSliceReturn(function: semantic.SemanticFn) bool {
    return sliceReturnElement(function) != null;
}

/// The release target must exist and take exactly the returned slice, otherwise
/// the generated free call would pass a pointer the library cannot interpret.
fn releaseTargetIssue(document: semantic.Semantic, function: semantic.SemanticFn) ?diagnostic.Diagnostic {
    const missing: diagnostic.Diagnostic = .{
        .severity = .@"error",
        .code = "ZIGO016",
        .message = "caller-owned slice return has no matching release function",
        .site = .{ .path = "semantic.json", .declaration = function.name },
        .hint = "add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type",
    };
    const name = function.release orelse return missing;
    for (document.functions) |candidate| {
        if (!std.mem.eql(u8, candidate.name, name)) continue;
        if (candidate.@"return" != .void or candidate.params.len != 1) return missing;
        const parameter = candidate.params[0];
        if (parameter.direction != .in or parameter.type != .slice) return missing;
        if (!typeNodeEqual(parameter.type.slice.element.*, sliceReturnElement(function).?)) return missing;
        return null;
    }
    return missing;
}

/// The element of a slice a function returns through `out_result_ptr` and
/// `out_result_len`, or null when it returns something else. `![]T` shares the
/// shape with `[]T`; a sentinel byte pointer keeps its own C-string lowering.
fn sliceReturnElement(function: semantic.SemanticFn) ?semantic.TypeNode {
    if (function.return_semantic == .c_string) return null;
    return switch (function.@"return") {
        .slice => |value| value.element.*,
        .error_union => |value| if (value.payload.* == .slice) value.payload.slice.element.* else null,
        else => null,
    };
}

fn typeNodeEqual(lhs: semantic.TypeNode, rhs: semantic.TypeNode) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .void, .bool => true,
        .int => |value| value.bits == rhs.int.bits and value.signed == rhs.int.signed and value.is_usize == rhs.int.is_usize,
        .float => |value| value.bits == rhs.float.bits,
        .@"enum" => |value| std.mem.eql(u8, value.ref, rhs.@"enum".ref),
        .value_struct => |value| std.mem.eql(u8, value.ref, rhs.value_struct.ref),
        else => false,
    };
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
    return naming.functionSymbolAlloc(allocator, prefix, function.receiver orelse function.namespace, function.name);
}

fn findGeneratedAccessorCollision(allocator: std.mem.Allocator, document: semantic.Semantic) !?[]const u8 {
    const Generated = struct { symbol: []const u8 };
    var generated: std.ArrayList(Generated) = .empty;
    defer {
        for (generated.items) |entry| allocator.free(entry.symbol);
        generated.deinit(allocator);
    }
    for (document.types) |declaration| {
        if (declaration.kind != .tagged_union) continue;
        var projection_index: usize = 0;
        while (projection_index <= declaration.fields.len) : (projection_index += 1) {
            const projection = if (projection_index == 0) "tag" else declaration.fields[projection_index - 1].name;
            if (projection_index != 0 and declaration.fields[projection_index - 1].type.? == .void) continue;
            const symbol = try naming.projectionSymbolAlloc(allocator, document.prefix, declaration.name, projection);
            errdefer allocator.free(symbol);
            for (document.functions) |function| {
                const function_symbol = try functionSymbolAlloc(allocator, document.prefix, function);
                defer allocator.free(function_symbol);
                if (std.mem.eql(u8, symbol, function_symbol)) {
                    allocator.free(symbol);
                    return function.name;
                }
            }
            for (generated.items) |previous| {
                if (std.mem.eql(u8, symbol, previous.symbol)) {
                    allocator.free(symbol);
                    return declaration.name;
                }
            }
            try generated.append(allocator, .{ .symbol = symbol });
        }
        for (document.functions) |function| {
            if (!std.mem.eql(u8, function.receiver orelse "", declaration.name)) continue;
            const method = try naming.pascalAlloc(allocator, function.name);
            defer allocator.free(method);
            if (std.mem.eql(u8, method, "Tag")) return function.name;
            for (declaration.fields) |field| {
                if (field.type.? == .void) continue;
                const field_name = try naming.pascalAlloc(allocator, field.name);
                defer allocator.free(field_name);
                const accessor = try std.fmt.allocPrint(allocator, "As{s}", .{field_name});
                defer allocator.free(accessor);
                if (std.mem.eql(u8, method, accessor)) return function.name;
            }
        }
    }
    return null;
}

fn unsupportedValueStruct(document: semantic.Semantic, node: semantic.TypeNode) ?[]const u8 {
    return switch (node) {
        .value_struct => |value| blk: {
            for (document.types) |declaration| {
                if (declaration.kind == .value_struct and std.mem.eql(u8, declaration.name, value.ref)) {
                    // Only `extern` has a C layout. `packed` backing is out of
                    // scope and is rejected with the same diagnostic.
                    break :blk if (declaration.layout != .@"extern") declaration.name else null;
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

/// A string slice is the only pointer-bearing slice that may cross the Go
/// boundary. It is flattened into bytes plus lengths before the native call;
/// every other pointer-bearing element keeps the ZIGO005 rejection.
fn isStringSliceParameter(parameter: semantic.Parameter) bool {
    if (parameter.direction != .in or parameter.type != .slice or !parameter.type.slice.@"const") return false;
    const element = parameter.type.slice.element.*;
    if (element != .slice or !element.slice.@"const" or !isByte(element.slice.element.*)) return false;
    if (element.slice.sentinel) |sentinel| return sentinel == 0;
    return parameter.semantic == .utf8_string;
}

fn isByte(node: semantic.TypeNode) bool {
    return node == .int and !node.int.signed and node.int.bits == 8;
}

test "implemented diagnostic snapshots are stable" {
    var void_node: semantic.TypeNode = .{ .void = {} };
    var pointer_node: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Thing" } };
    var pointer_slice_node: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &pointer_node } };
    var callback_return: semantic.TypeNode = .{ .void = {} };
    var sample_element: semantic.TypeNode = .{ .int = .{ .bits = 16, .signed = true } };
    const config_element: semantic.TypeNode = .{ .value_struct = .{ .ref = "Config" } };
    var callback_params = [_]semantic.TypeNode{config_element};
    const struct_callback: semantic.TypeNode = .{ .callback = .{ .params = &callback_params, .@"return" = &callback_return, .has_userdata = false } };
    var byte_element: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var byte_slice_node: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte_element } };
    var word_element: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const word_slice_node: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &word_element } };
    const count_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    var wide_element: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    const wide_slice_node: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &wide_element } };
    var wide_callback_params = [_]semantic.TypeNode{.{ .int = .{ .bits = 21, .signed = false } }};
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
                .name = "takePointers",
                .params = &.{},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &pointer_node } },
                .symbol = "zg_take_pointers",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO005]: slice element type contains a pointer\n  --> semantic.json (takePointers)\n  hint: return scalar, enum, or extern-struct elements instead of Go pointers\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "takePointersChecked",
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &pointer_slice_node } },
                .symbol = "zg_take_pointers_checked",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO005]: slice element type contains a pointer\n  --> semantic.json (takePointersChecked)\n  hint: return scalar, enum, or extern-struct elements instead of Go pointers\n" },
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
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{
                .{
                    .fields = &.{
                        .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                        .{ .name = "samples", .type = .{ .slice = .{ .@"const" = true, .element = &sample_element } }, .value = 1 },
                    },
                    .kind = .tagged_union,
                    .name = "Signal",
                    .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
                    .access = .snapshot,
                },
                .{
                    .fields = &.{ .{ .name = "none", .value = 0 }, .{ .name = "samples", .value = 1 } },
                    .kind = .@"enum",
                    .name = "SignalTag",
                    .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
                },
            },
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO011]: tagged union variant cannot be mirrored into a value snapshot\n  --> semantic.json (samples)\n  hint: use `.access = .projection`, or give every variant a void, bool, integer, float, or enum payload and a name other than `tag`\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{
                    .{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                    .{ .name = "label", .type = .{ .slice = .{ .@"const" = true, .element = &sample_element } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Config",
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO012]: extern struct cannot cross the C ABI\n  --> semantic.json (label)\n  hint: give every field a bool, integer, float, registered enum, or nested `extern struct` type; an empty struct has no C representation\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "visitAll",
                .params = &.{.{ .name = "visitor", .type = struct_callback }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Config",
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO013]: extern struct is only supported as a whole parameter or return value\n  --> semantic.json (visitAll)\n  hint: pass the struct on its own or as a direct slice element; optional and callback signatures are not supported\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "takeName",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &byte_element } },
                .symbol = "zg_take_name",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO016]: caller-owned slice return has no matching release function\n  --> semantic.json (takeName)\n  hint: add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type\n" },
        .{ .document = .{
            .functions = &.{
                .{
                    .name = "takeBytes",
                    .ownership = .caller,
                    .params = &.{},
                    .release = "freeWords",
                    .@"return" = .{ .slice = .{ .@"const" = true, .element = &byte_element } },
                    .symbol = "zg_take_bytes",
                },
                .{
                    .name = "freeWords",
                    .params = &.{.{ .name = "words", .type = .{ .slice = .{ .@"const" = false, .element = &word_element } } }},
                    .@"return" = .{ .void = {} },
                    .symbol = "zg_free_words",
                },
            },
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO016]: caller-owned slice return has no matching release function\n  --> semantic.json (takeBytes)\n  hint: add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "takeNameChecked",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &byte_slice_node } },
                .symbol = "zg_take_name_checked",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO016]: caller-owned slice return has no matching release function\n  --> semantic.json (takeNameChecked)\n  hint: add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type\n" },
        .{ .document = .{
            .functions = &.{
                .{
                    .name = "takeBytesChecked",
                    .ownership = .caller,
                    .params = &.{},
                    .release = "freeWords",
                    .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &byte_slice_node } },
                    .symbol = "zg_take_bytes_checked",
                },
                .{
                    .name = "freeWords",
                    .params = &.{.{ .name = "words", .type = .{ .slice = .{ .@"const" = false, .element = &word_element } } }},
                    .@"return" = .{ .void = {} },
                    .symbol = "zg_free_words",
                },
            },
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO016]: caller-owned slice return has no matching release function\n  --> semantic.json (takeBytesChecked)\n  hint: add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "openThing",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Thing" } },
                .symbol = "zg_open_thing",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Thing" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO015]: caller-owned return has no constructed handle to hand over\n  --> semantic.json (openThing)\n  hint: return a pointer to an opaque type that has both a constructor and a destructor, or drop `.returns = .caller`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "readInto",
                .params = &.{.{ .name = "source", .type = word_slice_node, .written = .@"return" }},
                .@"return" = count_node,
                .symbol = "zg_read_into",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO017]: written hint declared on a parameter that is not an output slice\n  --> semantic.json (readInto)\n  hint: add `.direction = .out` to the parameter, or drop `.written`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "fillInto",
                .params = &.{.{ .direction = .out, .name = "dst", .type = word_slice_node, .written = .@"return" }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_fill_into",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO017]: `.written = .return` needs a `usize` result to report the count\n  --> semantic.json (fillInto)\n  hint: return `usize` or `!usize` from the function, or use the default `.written = .all`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "codepointWidth",
                .namespace = "unicode",
                .params = &.{.{ .name = "cp", .type = .{ .int = .{ .bits = 128, .signed = false } } }},
                .@"return" = .{ .int = .{ .bits = 8, .signed = true } },
                .symbol = "zg_unicode_codepoint_width",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO018]: unsupported integer width `u128` in parameter `cp`\n  --> semantic.json (unicode.codepointWidth)\n  hint: use an integer of 64 bits or fewer\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "widths",
                .params = &.{.{ .name = "cps", .type = wide_slice_node }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_widths",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO018]: cannot promote integer width `u21` in the slice element of parameter `cps`\n  --> semantic.json (widths)\n  hint: zigo widens a narrow integer only as a whole parameter, return value, or error payload; use an 8, 16, 32, or 64-bit integer here\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "onCodepoint",
                .params = &.{.{ .name = "callback", .type = .{ .callback = .{ .has_userdata = false, .params = &wide_callback_params, .@"return" = &callback_return } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_on_codepoint",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO018]: cannot promote integer width `u21` in callback parameter 0 of parameter `callback`\n  --> semantic.json (onCodepoint)\n  hint: zigo widens a narrow integer only as a whole parameter, return value, or error payload; use an 8, 16, 32, or 64-bit integer here\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "codepoint", .type = .{ .int = .{ .bits = 21, .signed = false } } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Cell",
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO018]: cannot promote integer width `u21` in field `codepoint`\n  --> semantic.json (Cell)\n  hint: an `extern struct` is mirrored into C field by field; use an 8, 16, 32, or 64-bit integer here\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "extended",
                .params = &.{},
                .@"return" = .{ .float = .{ .bits = 80 } },
                .symbol = "zg_extended",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO018]: unsupported float width `f80` in the return value\n  --> semantic.json (extended)\n  hint: use `f32` or `f64`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "maybe",
                .params = &.{.{ .name = "value", .type = .{ .optional = .{ .child = &word_element } } }},
                .@"return" = .{ .void = {} },
                .receiver = "Thing",
                .symbol = "zg_thing_maybe",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Thing" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO019]: unsupported type `optional` in parameter `value`\n  --> semantic.json (Thing.maybe)\n  hint: use a bool, integer, float, enum, opaque pointer, extern struct, slice, or callback type\n" },
        .{ .document = .{
            .ir_version = 2,
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO020]: semantic document uses an unsupported IR version\n  --> semantic.json (ir_version)\n  hint: regenerate semantic.json with a matching zigo version\n" },
        .{ .document = .{
            .package = "",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: semantic document has an empty package name\n  --> semantic.json (package)\n  hint: give the binding a package name\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: semantic document has an empty symbol prefix\n  --> semantic.json (prefix)\n  hint: give the binding a symbol prefix\n" },
        .{ .document = .{
            .functions = &.{.{ .name = "", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_" }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: exposed function has an empty name\n  --> semantic.json (functions)\n  hint: expose a named declaration\n" },
        // `@typeName` of a comptime-generated enum ends in the slice
        // expression that built it, and the last dotted segment of that is
        // not a name at all.
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{ .{ .name = "block", .value = 0 }, .{ .name = "bar", .value = 1 } },
                .kind = .@"enum",
                .name = "4])",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
                .zig_path = "vt.lib.Enum([_][]const u8{ \"block\", \"bar\" }[0..4])",
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: registered type name `4])` from Zig type `vt.lib.Enum([_][]const u8{ \"block\", \"bar\" }[0..4])` is not a valid Go identifier\n  --> semantic.json (4]))\n  hint: register the type in `.types` with an explicit `.name` that is a Go identifier\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "range" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: registered type name `range` is not a valid Go identifier\n  --> semantic.json (range)\n  hint: register the type in `.types` with an explicit `.name` that is a Go identifier\n" },
    };
    // A located diagnostic names the declaration and the parameter it found,
    // so its strings come from the arena the caller is expected to pass.
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    for (cases) |case| {
        const issue = (try findIssue(scratch.allocator(), case.document)) orelse return error.MissingDiagnostic;
        const rendered = try issue.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings(case.snapshot, rendered);
    }
}

test "names zigo case-converts are judged on the Go spelling, not the Zig one" {
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "range",
            .params = &.{},
            .@"return" = .{ .void = {} },
            .symbol = "zg_range",
        }},
        .package = "keywords",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{ .{ .name = "type", .value = 0 }, .{ .name = "go_to", .value = 1 } },
            .kind = .@"enum",
            .name = "Kind",
            .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
        }},
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    // `range` becomes `Range`, `type` becomes `Type`: Go keywords in Zig
    // spelling never reach Go, so rejecting them here would reject working
    // bindings.
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(scratch.allocator(), document));
}

test "a narrow integer is accepted where the shim can promote it" {
    var payload: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "codepointWidth",
                .namespace = "unicode",
                .params = &.{.{ .name = "cp", .type = .{ .int = .{ .bits = 21, .signed = false } } }},
                .@"return" = .{ .int = .{ .bits = 24, .signed = true } },
                .symbol = "zg_unicode_codepoint_width",
            },
            .{
                .name = "decode",
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &payload } },
                .symbol = "zg_decode",
            },
        },
        .package = "narrow",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(scratch.allocator(), document));
}

test "a written hint is accepted on an out slice of a counting function" {
    var element: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var count: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    const slice: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &element } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "fill",
                .params = &.{.{ .direction = .out, .name = "dst", .type = slice, .written = .@"return" }},
                .@"return" = count,
                .symbol = "zg_fill",
            },
            .{
                .name = "fillChecked",
                .params = &.{.{ .direction = .out, .name = "dst", .type = slice, .written = .@"return" }},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &count } },
                .symbol = "zg_fill_checked",
            },
            .{
                .name = "fillAll",
                .params = &.{.{ .direction = .out, .name = "dst", .type = slice }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_fill_all",
            },
        },
        .package = "written",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(std.testing.allocator, document));
}

test "scalar extern struct slices are valid while optional structs stay rejected" {
    var element: semantic.TypeNode = .{ .value_struct = .{ .ref = "Point" } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "consume",
                .params = &.{.{ .name = "values", .type = .{ .slice = .{ .@"const" = true, .element = &element } } }},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &element } },
                .symbol = "zg_consume",
            },
        },
        .package = "good",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{
                .{ .name = "x", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                .{ .name = "y", .type = .{ .float = .{ .bits = 64 } } },
            },
            .kind = .value_struct,
            .layout = .@"extern",
            .name = "Point",
        }},
        .zig_version = "0.16.0",
    };
    try semanticDocument(std.testing.allocator, document);

    const optional: semantic.TypeNode = .{ .optional = .{ .child = &element } };
    const invalid: semantic.Semantic = .{
        .functions = &.{.{
            .name = "optional",
            .params = &.{.{ .name = "value", .type = optional }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_optional",
        }},
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "x", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
            .kind = .value_struct,
            .layout = .@"extern",
            .name = "Point",
        }},
        .zig_version = "0.16.0",
    };
    const issue = (try findIssue(std.testing.allocator, invalid)).?;
    try std.testing.expectEqualStrings("ZIGO013", issue.code);
    try std.testing.expect(std.mem.containsAtLeast(u8, issue.hint, 1, "direct slice element"));
}

test "utf8 string slices are the pointer-bearing slice exception" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var string_element: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    const strings: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &string_element } };
    const valid: semantic.Semantic = .{
        .functions = &.{.{
            .name = "extract",
            .params = &.{.{ .name = "paths", .semantic = .utf8_string, .type = strings }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_extract",
        }},
        .package = "good",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try semanticDocument(std.testing.allocator, valid);

    string_element.slice.sentinel = 1;
    const issue = (try findIssue(std.testing.allocator, valid)).?;
    try std.testing.expectEqualStrings("ZIGO005", issue.code);
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

test "tagged union accessor payload rejects unrepresentable scalar widths" {
    var i24_node: semantic.TypeNode = .{ .int = .{ .bits = 24, .signed = true } };
    const cases = [_]semantic.TypeNode{
        .{ .int = .{ .bits = 128, .signed = false } },
        .{ .float = .{ .bits = 16 } },
        .{ .slice = .{ .@"const" = true, .element = &i24_node } },
    };
    for (cases) |payload| {
        const document: semantic.Semantic = .{
            .package = "variant",
            .prefix = "zg",
            .types = &.{
                .{
                    .fields = &.{.{ .name = "value", .type = payload, .value = 0 }},
                    .kind = .tagged_union,
                    .name = "Value",
                    .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
                },
                .{ .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            },
            .zig_version = "0.16.0",
        };
        const issue = (try findIssue(std.testing.allocator, document)).?;
        try std.testing.expectEqualStrings("ZIGO006", issue.code);
        try std.testing.expectEqualStrings("Value", issue.site.declaration);
    }
}

test "tagged union generated accessor collisions are rejected" {
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "projectTag",
            .params = &.{},
            .receiver = "Value",
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "none", .type = .{ .void = {} }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{ .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    const issue = (try findIssue(std.testing.allocator, document)).?;
    try std.testing.expectEqualStrings("ZIGO007", issue.code);
    try std.testing.expectEqualStrings("projectTag", issue.site.declaration);
}

test "normalized tagged union type and variant collisions are rejected" {
    const cases = [_]semantic.Semantic{
        .{
            .package = "variant",
            .prefix = "zg",
            .types = &.{
                .{ .fields = &.{.{ .name = "none", .type = .{ .void = {} }, .value = 0 }}, .kind = .tagged_union, .name = "HTTPValue", .tag_type = .{ .@"enum" = .{ .ref = "HTTPValueTag" } } },
                .{ .fields = &.{.{ .name = "none", .type = .{ .void = {} }, .value = 0 }}, .kind = .tagged_union, .name = "http_value", .tag_type = .{ .@"enum" = .{ .ref = "OtherTag" } } },
                .{ .kind = .@"enum", .name = "HTTPValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
                .{ .kind = .@"enum", .name = "OtherTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            },
            .zig_version = "0.16.0",
        },
        .{
            .package = "variant",
            .prefix = "zg",
            .types = &.{
                .{
                    .fields = &.{
                        .{ .name = "httpCode", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 0 },
                        .{ .name = "http_code", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
                    },
                    .kind = .tagged_union,
                    .name = "Value",
                    .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
                },
                .{ .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            },
            .zig_version = "0.16.0",
        },
    };
    for (cases) |document| {
        const issue = (try findIssue(std.testing.allocator, document)).?;
        try std.testing.expectEqualStrings("ZIGO007", issue.code);
    }
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
                .{
                    .fields = &.{.{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
                    .kind = .value_struct,
                    .name = "Thing",
                    .layout = .@"extern",
                },
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

test "a variant named tag collides with the snapshot discriminant member" {
    const document: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "tag", .type = .{ .int = .{ .bits = 32, .signed = false } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Signal",
                .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
                .access = .snapshot,
            },
            .{ .fields = &.{.{ .name = "tag", .value = 0 }}, .kind = .@"enum", .name = "SignalTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    const issue = (try findIssue(std.testing.allocator, document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO011", issue.code);
    try std.testing.expectEqualStrings("tag", issue.site.declaration);
}

test "value snapshot eligibility accepts void bool scalar and enum payloads" {
    const eligible: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "idle", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "ticks", .type = .{ .int = .{ .bits = 32, .signed = false } }, .value = 1 },
                    .{ .name = "level", .type = .{ .float = .{ .bits = 32 } }, .value = 2 },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } }, .value = 3 },
                    .{ .name = "active", .type = .{ .bool = {} }, .value = 4 },
                },
                .kind = .tagged_union,
                .name = "Signal",
                .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
                .access = .snapshot,
            },
            .{
                .fields = &.{
                    .{ .name = "idle", .value = 0 },
                    .{ .name = "ticks", .value = 1 },
                    .{ .name = "level", .value = 2 },
                    .{ .name = "mode", .value = 3 },
                    .{ .name = "active", .value = 4 },
                },
                .kind = .@"enum",
                .name = "SignalTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{ .fields = &.{.{ .name = "idle", .value = 0 }}, .kind = .@"enum", .name = "Mode", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(std.testing.allocator, eligible));
    try semanticDocument(std.testing.allocator, eligible);
}

test "an opaque handle payload keeps a union out of the value snapshot representation" {
    var child: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Child" } };
    _ = &child;
    const document: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "child", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Child" } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Signal",
                .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
                .access = .snapshot,
            },
            .{ .fields = &.{.{ .name = "child", .value = 0 }}, .kind = .@"enum", .name = "SignalTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            .{ .kind = .@"opaque", .name = "Child" },
        },
        .zig_version = "0.16.0",
    };
    const issue = (try findIssue(std.testing.allocator, document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO011", issue.code);
    try std.testing.expectEqualStrings("child", issue.site.declaration);

    // The same union stays valid under the default projection representation.
    var projection_types = document.types[0];
    projection_types.access = null;
    var types = [_]semantic.TypeDecl{ projection_types, document.types[1], document.types[2] };
    var projection_document = document;
    projection_document.types = &types;
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(std.testing.allocator, projection_document));
}

test "an extern struct of scalars enums and nested structs passes validation" {
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "configure",
                .params = &.{.{ .name = "config", .type = .{ .value_struct = .{ .ref = "Config" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            },
            .{
                .name = "defaultConfig",
                .params = &.{},
                .@"return" = .{ .value_struct = .{ .ref = "Config" } },
                .symbol = "ignored",
            },
        },
        .package = "config",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                    .{ .name = "ratio", .type = .{ .float = .{ .bits = 64 } } },
                    .{ .name = "enabled", .type = .{ .bool = {} } },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } } },
                    .{ .name = "origin", .type = .{ .value_struct = .{ .ref = "Point" } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Config",
            },
            .{
                .fields = &.{
                    .{ .name = "x", .type = .{ .int = .{ .bits = 16, .signed = true } } },
                    .{ .name = "y", .type = .{ .int = .{ .bits = 16, .signed = true } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Point",
            },
            .{ .fields = &.{.{ .name = "idle", .value = 0 }}, .kind = .@"enum", .name = "Mode", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(std.testing.allocator, document));
    try semanticDocument(std.testing.allocator, document);
}

test "a packed struct and an opaque-pointer field stay out of the extern struct path" {
    const packed_document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "configure",
            .params = &.{.{ .name = "config", .type = .{ .value_struct = .{ .ref = "Flags" } } }},
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "enabled", .type = .{ .bool = {} } }},
            .kind = .value_struct,
            .layout = .@"packed",
            .name = "Flags",
        }},
        .zig_version = "0.16.0",
    };
    const packed_issue = (try findIssue(std.testing.allocator, packed_document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO003", packed_issue.code);

    const pointer_document: semantic.Semantic = .{
        .package = "bad",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "owner", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Thing" } } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Config",
            },
            .{ .kind = .@"opaque", .name = "Thing" },
        },
        .zig_version = "0.16.0",
    };
    const pointer_issue = (try findIssue(std.testing.allocator, pointer_document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO012", pointer_issue.code);
    try std.testing.expectEqualStrings("owner", pointer_issue.site.declaration);
}

test "a purego callback result outside the uintptr ABI is rejected" {
    var int32_return: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var float_return: semantic.TypeNode = .{ .float = .{ .bits = 64 } };
    const usize_param: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    const float_callback: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &.{ .{ .float = .{ .bits = 64 } }, usize_param },
        .@"return" = &int32_return,
    } };
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "observe",
            .params = &.{.{ .name = "sink", .type = float_callback }},
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "hub",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    // A float parameter travels as its bit pattern now, so neither validator
    // has anything to say about it.
    try std.testing.expect((try findIssue(std.testing.allocator, document)) == null);
    try std.testing.expect(puregoCallbackIssue(document) == null);

    const float_result_callback: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &.{ .{ .int = .{ .bits = 64, .signed = false } }, usize_param },
        .@"return" = &float_return,
    } };
    var float_result = document;
    float_result.functions = &.{.{
        .name = "observe",
        .params = &.{.{ .name = "sink", .type = float_result_callback }},
        .@"return" = .{ .void = {} },
        .symbol = "ignored",
    }};
    const issue = puregoCallbackIssue(float_result) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO014", issue.code);
    try std.testing.expectEqualStrings("observe", issue.site.declaration);
    // The result shape is a purego-backend rule, not a platform one, so the
    // general validator stays silent about it.
    try std.testing.expect((try findIssue(std.testing.allocator, float_result)) == null);
}
