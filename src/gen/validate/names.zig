//! Go identifiers and the collisions between generated names.
const std = @import("std");
const diagnostic = @import("diagnostic");
const lower = @import("lower");
const semantic = @import("semantic");
const targets = @import("targets");
const naming = @import("naming");
const site = @import("site.zig");
const validate = @import("validate.zig");

pub fn generatedAccessorCollisionIssue(allocator: std.mem.Allocator, document: semantic.Semantic, target: targets.Target) !?diagnostic.Diagnostic {
    if (try findGeneratedAccessorCollision(allocator, document, target)) |declaration| return .{
        .severity = .@"error",
        .code = "ZIGO007",
        .message = "generated tagged-union accessor collides with another declaration",
        .site = .{ .path = "semantic.json", .declaration = declaration },
        .hint = "rename the conflicting function, type, or union variant",
    };
    return null;
}

// The C symbol check above catches collisions that would fail the linker.
// It cannot catch this class: generation drops the owning namespace from
// a receiverless function's public name (only a method's receiver scopes
// it), so two functions in different namespaces -- or a namespace
// function and a registered type -- can still resolve to the same public
// Go identifier and fail `go build` with a duplicate declaration instead
// of a zigo diagnostic.
pub fn publicNameCollisionIssue(allocator: std.mem.Allocator, document: semantic.Semantic, target: targets.Target) !?diagnostic.Diagnostic {
    for (document.types) |declaration| {
        for (document.functions) |function| {
            if (function.receiver != null) continue;
            if (!semantic.optionalStringEqual(declaration.package, function.package)) continue;
            const function_name = try target.publicFunctionNameAlloc(allocator, document, function);
            defer allocator.free(function_name);
            if (!std.mem.eql(u8, function_name, declaration.name)) continue;
            // Kept alive: `site.declaration` below points directly at it.
            const function_path = try site.functionDeclarationAlloc(allocator, function);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}` collides between type `{s}` and function `{s}`",
                    .{ function_name, declaration.zig_path orelse declaration.name, function_path },
                ),
                .site = site.functionSiteFor(function, function_path),
                .hint = "rename the function, or register the type with a `.name` that resolves to a different Go identifier",
                .note = try typeRenameNoteAlloc(allocator, declaration),
            };
        }
    }
    for (document.functions, 0..) |function, index| {
        if (lower.constructorForDeinit(document.constructors, function) != null) continue;
        const bucket = function.receiver orelse "";
        const name = try target.publicFunctionNameAlloc(allocator, document, function);
        defer allocator.free(name);
        for (document.functions[0..index]) |previous| {
            if (lower.constructorForDeinit(document.constructors, previous) != null) continue;
            const previous_bucket = previous.receiver orelse "";
            if (!std.mem.eql(u8, bucket, previous_bucket)) continue;
            if (!semantic.optionalStringEqual(function.package, previous.package)) continue;
            const previous_name = try target.publicFunctionNameAlloc(allocator, document, previous);
            defer allocator.free(previous_name);
            if (!std.mem.eql(u8, name, previous_name)) continue;
            // Kept alive: `site.declaration` below points directly at it.
            const function_path = try site.functionDeclarationAlloc(allocator, function);
            const previous_path = try site.functionDeclarationAlloc(allocator, previous);
            defer allocator.free(previous_path);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}` collides between `{s}` and `{s}`",
                    .{ name, previous_path, function_path },
                ),
                .site = site.functionSiteFor(function, function_path),
                .hint = "rename one declaration, or give it a `.name` that resolves to a different Go identifier",
                .note = if (semantic.constructorForInit(document.constructors, function) != null)
                    try functionOrConstructorRenameNoteAlloc(allocator, document, function, target)
                else if (semantic.constructorForInit(document.constructors, previous) != null)
                    try functionOrConstructorRenameNoteAlloc(allocator, document, previous, target)
                else
                    try functionRenameNoteAlloc(allocator, function, target),
            };
        }
    }
    // An iterator wrapper is one more method on its receiver, so it must not
    // share a name with a bound method or another wrapper of that type.
    for (document.functions, 0..) |function, index| {
        const iterator = function.goIterator() orelse continue;
        const receiver = function.receiver orelse continue;
        for (document.functions, 0..) |other, other_index| {
            if (!std.mem.eql(u8, other.receiver orelse "", receiver)) continue;
            if (!semantic.optionalStringEqual(function.package, other.package)) continue;
            const other_name = try target.publicFunctionNameAlloc(allocator, document, other);
            defer allocator.free(other_name);
            const clashes_method = std.mem.eql(u8, iterator.name, other_name);
            const clashes_wrapper = other_index < index and other.goIterator() != null and std.mem.eql(u8, iterator.name, other.goIterator().?.name);
            if (!clashes_method and !clashes_wrapper) continue;
            const function_path = try site.functionDeclarationAlloc(allocator, function);
            const other_path = try site.functionDeclarationAlloc(allocator, other);
            defer allocator.free(other_path);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}.{s}` collides between the iterator wrapper of `{s}` and `{s}`",
                    .{ receiver, iterator.name, function_path, other_path },
                ),
                .site = site.functionSiteFor(function, function_path),
                .hint = "give the wrapper another `.iterator = .{ .name = ... }`, or rename the other declaration",
            };
        }
    }
    // An `.implements` wrapper is one more method on its receiver, named by
    // the interface, so a receiver carries each interface once and no bound
    // method may already own that name.
    for (document.functions, 0..) |function, index| {
        const implements = function.goImplements() orelse continue;
        const receiver = function.receiver orelse continue;
        const wrapper = implements.methodName();
        for (document.functions, 0..) |other, other_index| {
            if (!std.mem.eql(u8, other.receiver orelse "", receiver)) continue;
            if (!semantic.optionalStringEqual(function.package, other.package)) continue;
            const other_name = try target.publicFunctionNameAlloc(allocator, document, other);
            defer allocator.free(other_name);
            const clashes_method = std.mem.eql(u8, wrapper, other_name);
            const clashes_iterator = other.goIterator() != null and std.mem.eql(u8, wrapper, other.goIterator().?.name);
            const clashes_wrapper = other_index < index and other.goImplements() != null and std.mem.eql(u8, wrapper, other.goImplements().?.methodName());
            if (!clashes_method and !clashes_iterator and !clashes_wrapper) continue;
            const function_path = try site.functionDeclarationAlloc(allocator, function);
            const other_path = try site.functionDeclarationAlloc(allocator, other);
            defer allocator.free(other_path);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}.{s}` collides between the {s} wrapper of `{s}` and `{s}`",
                    .{ receiver, wrapper, implements.interfaceName(), function_path, other_path },
                ),
                .site = site.functionSiteFor(function, function_path),
                .hint = "a handle satisfies each interface through one method; drop one `.implements`, or rename the other declaration",
            };
        }
    }
    // A method bound onto a registered enum shares a namespace with the
    // methods zigo generates on that enum, and Go has no way to tell two
    // `String()` declarations apart.
    for (document.functions) |function| {
        if (!function.receiverIsValue()) continue;
        const declaration = semantic.typeDecl(document.types, function.receiver.?) orelse continue;
        if (declaration.kind != .@"enum") continue;
        const name = try target.publicFunctionNameAlloc(allocator, document, function);
        defer allocator.free(name);
        const generated: []const []const u8 = if (declaration.text orelse false)
            &.{ "String", "MarshalText", "UnmarshalText" }
        else
            &.{"String"};
        for (generated) |reserved| {
            if (!std.mem.eql(u8, name, reserved)) continue;
            const function_path = try site.functionDeclarationAlloc(allocator, function);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}.{s}` collides with the method zigo generates on enum `{s}`",
                    .{ declaration.name, reserved, declaration.name },
                ),
                .site = site.functionSiteFor(function, function_path),
                .hint = "give the method a `.name` that is not one zigo generates (`String`, and `MarshalText`/`UnmarshalText` with `.text = true`)",
            };
        }
    }
    for (document.types) |declaration| {
        if (declaration.kind != .@"enum") continue;
        for (declaration.fields, 0..) |field, index| {
            const field_name = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(field_name);
            for (declaration.fields[0..index]) |previous| {
                const previous_name = try naming.pascalAlloc(allocator, previous.name);
                defer allocator.free(previous_name);
                if (!std.mem.eql(u8, field_name, previous_name)) continue;
                return .{
                    .severity = .@"error",
                    .code = "ZIGO024",
                    .message = try std.fmt.allocPrint(
                        allocator,
                        "public Go name `{s}{s}` collides between enum tags `{s}` and `{s}`",
                        .{ declaration.name, field_name, previous.name, field.name },
                    ),
                    .site = .{ .path = "semantic.json", .declaration = declaration.name },
                    .hint = "rename one of the enum tags so they no longer share a Go identifier",
                    .note = try memberCollisionNoteAlloc(allocator, field.name, target),
                };
            }
        }
    }
    if (try optionsCollisionIssue(allocator, document, target)) |issue| return issue;
    return null;
}

/// Names that reach Go verbatim -- a registered type's name -- have to be Go
/// identifiers already, because nothing stands between them and the `type`
/// declaration they become. Names zigo case-converts are judged on the
/// converted spelling instead, so a Zig field called `type` stays legal as the
/// Go field `Type`. Either way the check runs before generation, because a
/// name reflection derived from `@typeName` can be something like `4])` and
/// the only thing worse than rejecting it is writing it into a `.go` file.
pub fn identifierIssue(allocator: std.mem.Allocator, document: semantic.Semantic, target: targets.Target) !?diagnostic.Diagnostic {
    for (document.types) |declaration| {
        if (try nameIssueForTarget(allocator, target, .{
            .label = "registered type name",
            .spelling = declaration.name,
            .declaration = if (declaration.name.len == 0) "types" else declaration.name,
            .zig_path = declaration.zig_path,
            .hint = "register the type in `.types` with an explicit `.name` that is a Go identifier",
        })) |issue| {
            var result = issue;
            result.note = try invalidTypeNameNoteAlloc(allocator, declaration, target);
            return result;
        }
        const member_label = switch (declaration.kind) {
            .@"enum" => "enum tag",
            .tagged_union => "union variant",
            .error_set => "error name",
            else => "field name",
        };
        for (declaration.fields) |field| {
            if (try nameIssueForTarget(allocator, target, .{
                .label = member_label,
                .spelling = field.name,
                .convert = true,
                // Enum constants are emitted as <Type><Pascal(tag)>; a tag
                // may therefore start with a digit while the full name does
                // not. Other converted members are emitted on their type and
                // still have to stand as identifiers themselves.
                .prefix = if (declaration.kind == .@"enum") declaration.name else null,
                .declaration = declaration.name,
                .zig_path = declaration.zig_path,
                .hint = "rename the declaration in Zig so its name converts to a Go identifier",
            })) |issue| {
                var result = issue;
                result.note = try invalidMemberNameNoteAlloc(allocator, member_label, field.name, target);
                return result;
            }
        }
    }
    for (document.functions) |function| {
        // An empty function name has its own diagnostic below, and it says
        // more than "this is not an identifier" would.
        if (function.name.len == 0) continue;
        if (try nameIssueForTarget(allocator, target, .{
            .label = "function name",
            .spelling = function.goName() orelse function.name,
            .convert = function.goName() == null,
            .declaration = function.name,
            .source = function.source,
            .hint = "give the entry a `.name` that converts to a Go identifier",
        })) |issue| {
            var result = issue;
            result.note = try functionOrConstructorRenameNoteAlloc(allocator, document, function, target);
            return result;
        }
        // A parameter name reaches the C header verbatim, where `uint8_t
        // double` is a syntax error the Go escaping above never sees. The
        // header is public, so the name is rejected rather than mangled.
        for (function.params) |parameter| {
            if (parameter.injected != null) continue;
            if (!naming.isCKeyword(parameter.name)) continue;
            const function_path = try site.functionDeclarationAlloc(allocator, function);
            var location = site.functionSiteFor(function, function_path);
            if (parameter.source) |source| {
                location.line = source.line;
                location.column = source.column;
            }
            return .{
                .severity = .@"error",
                .code = "ZIGO021",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "parameter name `{s}` of `{s}` is a C keyword and cannot be declared in the generated header",
                    .{ parameter.name, function_path },
                ),
                .site = location,
                .hint = "rename the parameter in `.params` (or in the Zig signature) so the C declaration compiles",
            };
        }
    }
    return null;
}

/// The C header has one ordinary identifier namespace shared by typedefs,
/// exported functions, and macros. Check the exact names lowering will emit
/// for both backends before generation writes an uncompilable header.
pub fn cIdentifierIssue(allocator: std.mem.Allocator, document: semantic.Semantic, target: targets.Target) !?diagnostic.Diagnostic {
    if (try cIdentifierBackendIssue(allocator, document, false, target)) |issue| return issue;
    return cIdentifierBackendIssue(allocator, document, true, target);
}

fn cIdentifierBackendIssue(allocator: std.mem.Allocator, document: semantic.Semantic, purego: bool, target: targets.Target) !?diagnostic.Diagnostic {
    var scratch_arena = std.heap.ArenaAllocator.init(allocator);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    // Keyed by the emitted C name so a collision costs one lookup rather than a
    // scan of every identifier collected so far.
    var identifiers: std.StringHashMapUnmanaged(CIdentifierOrigin) = .empty;

    for (document.types) |declaration| {
        const emits_handle = declaration.kind == .@"opaque" or (declaration.kind == .tagged_union and
            !document.isValueOnlyTaggedUnion(declaration.name));
        const emits_struct = (declaration.kind == .value_struct and document.valueStructUsed(declaration.name)) or declaration.kind == .materialized;
        if (emits_handle or declaration.kind == .@"enum" or emits_struct) {
            const name = try naming.cTypeNameAlloc(scratch, document.prefix, declaration.name);
            const label = try std.fmt.allocPrint(scratch, "type `{s}`", .{declaration.name});
            const note = try typeRenameNoteAlloc(scratch, declaration);
            if (try addCIdentifier(allocator, scratch, &identifiers, name, .{ .label = label, .note = .{ .type = note } })) |issue| return issue;
        }
        if (declaration.kind == .@"enum") for (declaration.fields) |field| {
            const type_name = try naming.cTypeNameAlloc(scratch, document.prefix, declaration.name);
            const member = try naming.snakeAlloc(scratch, field.name);
            const combined = try std.fmt.allocPrint(scratch, "{s}_{s}", .{ type_name, member });
            const name = try std.ascii.allocUpperString(scratch, combined);
            const label = try std.fmt.allocPrint(scratch, "enum constant `{s}.{s}`", .{ declaration.name, field.name });
            const note = try typeRenameNoteAlloc(scratch, declaration);
            if (try addCIdentifier(allocator, scratch, &identifiers, name, .{ .label = label, .note = .{ .type = note } })) |issue| return issue;
        };
    }
    for (document.functions) |function| {
        const base = try functionSymbolAlloc(scratch, document.prefix, function);
        const name = if (purego and semantic.functionHasCallback(function))
            try std.fmt.allocPrint(scratch, "{s}_purego_v2", .{base})
        else
            base;
        const label = try std.fmt.allocPrint(scratch, "function `{s}`", .{try site.functionDeclarationAlloc(scratch, function)});
        // A constructor's symbol is named after the type it builds, so a
        // collision on it is answered by renaming that type.
        const note: CIdentifierOrigin.Note = if (semantic.constructorForInit(document.constructors, function)) |constructor|
            .{ .type = try typeNameRenameNoteAlloc(scratch, constructor.type, .@"opaque") }
        else
            .{ .function = try functionRenameNoteAlloc(scratch, function, target) };
        if (try addCIdentifier(allocator, scratch, &identifiers, name, .{ .label = label, .note = note })) |issue| return issue;
    }
    for (document.types) |declaration| {
        if (declaration.kind != .tagged_union) continue;
        if (!document.isValueOnlyTaggedUnion(declaration.name)) {
            const tag = try naming.projectionSymbolAlloc(scratch, document.prefix, declaration.name, "tag");
            const tag_label = try std.fmt.allocPrint(scratch, "tag projection `{s}`", .{declaration.name});
            const type_note = try typeRenameNoteAlloc(scratch, declaration);
            if (try addCIdentifier(allocator, scratch, &identifiers, tag, .{ .label = tag_label, .note = .{ .type = type_note } })) |issue| return issue;
            for (declaration.fields) |field| {
                if (field.type.? == .void) continue;
                const name = try naming.projectionSymbolAlloc(scratch, document.prefix, declaration.name, field.name);
                const label = try std.fmt.allocPrint(scratch, "payload projection `{s}.{s}`", .{ declaration.name, field.name });
                if (try addCIdentifier(allocator, scratch, &identifiers, name, .{ .label = label, .note = .{ .type = type_note } })) |issue| return issue;
            }
        }
        if (declaration.accessStrategy() == .snapshot) {
            const owner = try naming.snakeAlloc(scratch, declaration.name);
            const symbol = try std.fmt.allocPrint(scratch, "{s}_{s}_snapshot", .{ document.prefix, owner });
            const symbol_label = try std.fmt.allocPrint(scratch, "snapshot function `{s}`", .{declaration.name});
            const type_note = try typeRenameNoteAlloc(scratch, declaration);
            if (try addCIdentifier(allocator, scratch, &identifiers, symbol, .{ .label = symbol_label, .note = .{ .type = type_note } })) |issue| return issue;
            const type_name = try std.fmt.allocPrint(scratch, "{s}_t", .{symbol});
            const type_label = try std.fmt.allocPrint(scratch, "snapshot type `{s}`", .{declaration.name});
            if (try addCIdentifier(allocator, scratch, &identifiers, type_name, .{ .label = type_label, .note = .{ .type = type_note } })) |issue| return issue;
        }
    }
    const last_error = try std.fmt.allocPrint(scratch, "{s}_last_error_message", .{document.prefix});
    return addCIdentifier(allocator, scratch, &identifiers, last_error, .{ .label = "generated last-error function" });
}

const CIdentifierOrigin = struct {
    label: []const u8,
    note: Note = .none,

    /// Where the rename hint attached to an identifier comes from. The
    /// declaration that owns the name decides it once; a type note outranks a
    /// function one, because renaming the type is what moves the identifier.
    /// Either payload may still be absent: a declaration that was never
    /// renamed has nothing to point at.
    const Note = union(enum) {
        none,
        function: ?[]const u8,
        type: ?[]const u8,

        fn text(self: Note) ?[]const u8 {
            return switch (self) {
                .none => null,
                .function, .type => |value| value,
            };
        }
    };
};

fn addCIdentifier(
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    identifiers: *std.StringHashMapUnmanaged(CIdentifierOrigin),
    name: []const u8,
    declaration: CIdentifierOrigin,
) !?diagnostic.Diagnostic {
    const entry = try identifiers.getOrPut(scratch, name);
    if (entry.found_existing) {
        const previous = entry.value_ptr.*;
        const selected_note = if (previous.note == .type)
            previous.note.text()
        else
            declaration.note.text() orelse previous.note.text();
        return .{
            .severity = .@"error",
            .code = "ZIGO036",
            .message = try std.fmt.allocPrint(
                allocator,
                "C identifier `{s}` collides between {s} and {s}",
                .{ name, previous.label, declaration.label },
            ),
            .site = .{ .path = "semantic.json", .declaration = try allocator.dupe(u8, declaration.label) },
            .hint = "give one declaration a distinct `.name`, or choose a different binding `.prefix`",
            .note = if (selected_note) |note| try allocator.dupe(u8, note) else null,
        };
    }
    entry.value_ptr.* = declaration;
    return null;
}

const NameCheck = struct {
    label: []const u8,
    spelling: []const u8,
    /// True when zigo pascal-cases the name on its way into Go, which decides
    /// whether the written spelling or the converted one is judged.
    convert: bool = false,
    /// Prefix included in the actual emitted identifier after conversion.
    prefix: ?[]const u8 = null,
    declaration: []const u8,
    zig_path: ?[]const u8 = null,
    /// Set only when the check is a function name; a type or field name check
    /// has no `SemanticFn` to source a location from, so it keeps pointing at
    /// `semantic.json`.
    source: ?semantic.SourceLocation = null,
    hint: []const u8,
};

fn nameIssueForTarget(allocator: std.mem.Allocator, target: targets.Target, check: NameCheck) !?diagnostic.Diagnostic {
    // A document that validates must not leak: callers are only asked for a
    // scratch arena because a *rejection* builds strings, not an acceptance.
    var converted: ?[]u8 = null;
    defer if (converted) |value| allocator.free(value);
    var candidate = check.spelling;
    if (check.convert) {
        const suffix = try naming.pascalAlloc(allocator, check.spelling);
        if (check.prefix) |prefix| {
            defer allocator.free(suffix);
            converted = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, suffix });
        } else converted = suffix;
        candidate = converted.?;
        // An empty conversion would emit no member spelling at all (and, for
        // an enum, collide with the type name), even when a prefix is valid.
        if (suffix.len != 0 and target.isIdentifier(candidate)) return null;
    } else if (target.isIdentifier(candidate)) return null;
    const message = if (check.zig_path) |path|
        try std.fmt.allocPrint(allocator, "{s} `{s}` from Zig type `{s}` is not a valid Go identifier", .{ check.label, check.spelling, path })
    else
        try std.fmt.allocPrint(allocator, "{s} `{s}` is not a valid Go identifier", .{ check.label, check.spelling });
    const location: diagnostic.Site = if (check.source) |source| .{
        .path = source.path,
        .declaration = check.declaration,
        .line = source.line,
        .column = source.column,
    } else .{ .path = "semantic.json", .declaration = check.declaration };
    return .{
        .severity = .@"error",
        .code = "ZIGO021",
        .message = message,
        .site = location,
        .hint = check.hint,
    };
}

fn typeRenameNoteAlloc(allocator: std.mem.Allocator, declaration: semantic.TypeDecl) ![]u8 {
    return typeNameRenameNoteAlloc(allocator, declaration.name, declaration.kind);
}

pub fn retentionNoteAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]u8 {
    const path = try site.functionDeclarationAlloc(allocator, function);
    defer allocator.free(path);
    return std.fmt.allocPrint(allocator, "consider exposing `pub fn release() void` alongside `{s}`", .{path});
}

fn typeNameRenameNoteAlloc(allocator: std.mem.Allocator, name: []const u8, kind: semantic.TypeKind) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "consider .name = \"{s}{s}\" on type {s}",
        .{ name, if (kind == .@"enum") "Kind" else "Type", name },
    );
}

fn functionRenameNoteAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn, target: targets.Target) ![]u8 {
    const converted = try naming.pascalAlloc(allocator, function.name);
    defer allocator.free(converted);
    const public_name = try validGoNameAlloc(allocator, converted, "Function", target);
    defer allocator.free(public_name);
    const path = try site.functionDeclarationAlloc(allocator, function);
    defer allocator.free(path);
    return std.fmt.allocPrint(allocator, "consider .name = \"{s}Binding\" on function {s}", .{ public_name, path });
}

fn functionOrConstructorRenameNoteAlloc(allocator: std.mem.Allocator, document: semantic.Semantic, function: semantic.SemanticFn, target: targets.Target) ![]u8 {
    if (semantic.constructorForInit(document.constructors, function)) |constructor| {
        for (document.types) |declaration| {
            if (std.mem.eql(u8, declaration.name, constructor.type)) return typeRenameNoteAlloc(allocator, declaration);
        }
        return typeNameRenameNoteAlloc(allocator, constructor.type, .@"opaque");
    }
    return functionRenameNoteAlloc(allocator, function, target);
}

fn invalidTypeNameNoteAlloc(allocator: std.mem.Allocator, declaration: semantic.TypeDecl, target: targets.Target) ![]u8 {
    const converted = try naming.pascalAlloc(allocator, declaration.name);
    defer allocator.free(converted);
    const suggestion = try validGoNameAlloc(allocator, converted, if (declaration.kind == .@"enum") "Enum" else "Type", target);
    defer allocator.free(suggestion);
    return std.fmt.allocPrint(
        allocator,
        "consider .name = \"{s}\" on type {s}",
        .{ suggestion, declaration.zig_path orelse declaration.name },
    );
}

fn invalidMemberNameNoteAlloc(allocator: std.mem.Allocator, label: []const u8, name: []const u8, target: targets.Target) ![]u8 {
    const converted = try naming.camelAlloc(allocator, name);
    defer allocator.free(converted);
    const suggestion = try validGoNameAlloc(allocator, converted, "value", target);
    defer allocator.free(suggestion);
    return std.fmt.allocPrint(allocator, "consider renaming {s} `{s}` to `{s}`", .{ label, name, suggestion });
}

fn memberCollisionNoteAlloc(allocator: std.mem.Allocator, name: []const u8, target: targets.Target) ![]u8 {
    const converted = try naming.camelAlloc(allocator, name);
    defer allocator.free(converted);
    const base = try validGoNameAlloc(allocator, converted, "value", target);
    defer allocator.free(base);
    return std.fmt.allocPrint(allocator, "consider renaming enum tag `{s}` to `{s}Value`", .{ name, base });
}

fn validGoNameAlloc(allocator: std.mem.Allocator, candidate: []const u8, fallback: []const u8, target: targets.Target) ![]u8 {
    var first: ?u8 = null;
    for (candidate) |character| {
        if (std.ascii.isAlphanumeric(character) or character == '_') {
            first = character;
            break;
        }
    }
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    if (first == null or std.ascii.isDigit(first.?)) try result.appendSlice(allocator, fallback);
    for (candidate) |character| {
        if (std.ascii.isAlphanumeric(character) or character == '_') try result.append(allocator, character);
    }
    if (result.items.len == 0) try result.appendSlice(allocator, fallback);
    if (!target.isIdentifier(result.items)) try result.appendSlice(allocator, "Value");
    return result.toOwnedSlice(allocator);
}

fn functionSymbolAlloc(allocator: std.mem.Allocator, prefix: []const u8, function: semantic.SemanticFn) ![]u8 {
    return semantic.functionSymbolAlloc(allocator, prefix, function);
}

fn findGeneratedAccessorCollision(allocator: std.mem.Allocator, document: semantic.Semantic, target: targets.Target) !?[]const u8 {
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
            const method = try target.publicFunctionNameAlloc(allocator, document, function);
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

test "an implements wrapper collides with a same-named method or a second implements" {
    const handle: semantic.TypeDecl = .{ .kind = .@"opaque", .name = "Stream" };
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const bytes_in: semantic.Parameter = .{ .name = "bytes", .type = .{ .slice = .{ .@"const" = true, .element = &byte } } };
    const feed: semantic.SemanticFn = .{ .go = .{ .implements = .writer }, .name = "feed", .params = &.{bytes_in}, .receiver = "Stream", .@"return" = .{ .void = {} }, .symbol = "zg_stream_feed" };
    var write = feed;
    write.setGoImplements(null);
    write.name = "write";
    write.symbol = "zg_stream_write";
    var push = feed;
    push.name = "push";
    push.symbol = "zg_stream_push";
    for ([_][]const semantic.SemanticFn{ &.{ feed, write }, &.{ feed, push } }) |functions| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{ .functions = functions, .package = "vt", .prefix = "zg", .types = &.{handle}, .zig_version = "0.16.0" };
        const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO024", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "Stream.Write") != null);
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
            .fields = &.{ .{ .name = "type", .value = 0 }, .{ .name = "go_to", .value = 1 }, .{ .name = "80_cols", .value = 2 } },
            .kind = .@"enum",
            .name = "Kind",
            .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
        }},
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    // `range` becomes `Range`, `type` becomes `KindType`, and `80_cols`
    // becomes `Kind80Cols`: Zig spellings that are invalid alone need not be
    // rejected when their emitted Go identifiers are valid.
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(scratch.allocator(), document));
}

test "a parameter named after a C keyword is rejected before it reaches the header" {
    const byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "scale",
            .params = &.{ .{ .name = "value", .type = byte }, .{ .name = "double", .type = byte, .name_source = .sidecar } },
            .@"return" = .{ .void = {} },
            .symbol = "zg_scale",
        }},
        .package = "keywords",
        .prefix = "zg",
        .types = &.{},
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO021", issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "`double`") != null);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "C keyword") != null);
    // An injected parameter has no C declaration, so its name is free.
    const injected: semantic.Semantic = .{
        .allocator = "std.heap.c_allocator",
        .functions = &.{.{
            .name = "scale",
            .params = &.{ .{ .injected = .allocator, .name = "int", .type = .{ .void = {} } }, .{ .name = "value", .type = byte } },
            .@"return" = .{ .void = {} },
            .symbol = "zg_scale",
        }},
        .package = "keywords",
        .prefix = "zg",
        .types = &.{},
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(scratch.allocator(), injected));
}

test "a written symbol is checked as the C identifier it is" {
    // `.symbol` on `Key.fromASCII` spells `zg_key_from_ascii` by hand;
    // a root function whose derived symbol is the same collides with it.
    const document: semantic.Semantic = .{
        .functions = &.{
            .{ .name = "keyFromASCII", .namespace = "Key", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_key_from_ascii", .custom_symbol = true },
            .{ .name = "keyFromAscii", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_key_from_ascii" },
        },
        .package = "keys",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try validate.findIssue(scratch.allocator(), document)).?;
    try std.testing.expectEqualStrings("ZIGO036", issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "zg_key_from_ascii") != null);
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
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try validate.findIssue(scratch.allocator(), document)).?;
    try std.testing.expectEqualStrings("ZIGO036", issue.code);
    try std.testing.expectEqualStrings("tag projection `Value`", issue.site.declaration);
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
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    for (cases) |document| {
        const issue = (try validate.findIssue(scratch.allocator(), document)).?;
        try std.testing.expectEqualStrings("ZIGO036", issue.code);
    }
}

test "symbol collision validation propagates every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expectSymbolCollision, .{});
}

test "a public name hint resolves a collision between two namespaced functions" {
    // Same shape that ZIGO024's fixture rejects (`File.open`, `Socket.open`
    // both resolving to `Open`), except `Socket`'s function carries a `.name`
    // hint. A binding's `.name` override lands directly in `function.name` by
    // the time semantic.json exists, so `openSocket` here stands in for what
    // `.name = "openSocket"` on the Zig declaration would produce.
    const document: semantic.Semantic = .{
        .functions = &.{
            .{ .name = "open", .namespace = "File", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_file_open" },
            .{ .name = "openSocket", .namespace = "Socket", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_socket_open_socket" },
        },
        .package = "good",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expect((try validate.findIssue(std.testing.allocator, document)) == null);
    try validate.semanticDocument(std.testing.allocator, document);
}

test "a registered type name collides with a namespaced function's public name" {
    const document: semantic.Semantic = .{
        .functions = &.{.{ .name = "open", .namespace = "socket", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_socket_open" }},
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Open" }},
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO024", issue.code);
}

test "two enum tags that pascal-case to the same identifier collide" {
    const document: semantic.Semantic = .{
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{ .{ .name = "foo_bar", .value = 0 }, .{ .name = "fooBar", .value = 1 } },
            .kind = .@"enum",
            .name = "Kind",
            .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
        }},
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO036", issue.code);
}

test "a constructor pair does not collide with itself across two different types" {
    // Both `Counter` and `Timer` register `create`/`deinit` as their
    // constructor pair. Without constructor-aware name resolution the
    // collision check would see two receiverless `create` functions in the
    // global bucket and reject a document generation already accepts, since
    // each actually reaches Go as a distinct `New<Type>`.
    var counter_payload: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Counter" } };
    var timer_payload: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Timer" } };
    const document: semantic.Semantic = .{
        .constructors = &.{
            .{ .type = "Counter", .init = "create", .deinit = "deinit" },
            .{ .type = "Timer", .init = "create", .deinit = "deinit" },
        },
        .functions = &.{
            .{
                .name = "create",
                .namespace = "Counter",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &counter_payload } },
                .symbol = "zg_counter_create",
            },
            .{ .name = "deinit", .params = &.{}, .receiver = "Counter", .@"return" = .{ .void = {} }, .symbol = "zg_counter_deinit" },
            .{
                .name = "create",
                .namespace = "Timer",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &timer_payload } },
                .symbol = "zg_timer_create",
            },
            .{ .name = "deinit", .params = &.{}, .receiver = "Timer", .@"return" = .{ .void = {} }, .symbol = "zg_timer_deinit" },
        },
        .package = "good",
        .prefix = "zg",
        .types = &.{ .{ .kind = .@"opaque", .name = "Counter" }, .{ .kind = .@"opaque", .name = "Timer" } },
        .zig_version = "0.16.0",
    };
    try std.testing.expect((try validate.findIssue(std.testing.allocator, document)) == null);
    try validate.semanticDocument(std.testing.allocator, document);
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
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO036", issue.code);
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
    const issue = (try validate.findIssue(std.testing.allocator, document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO011", issue.code);
    try std.testing.expectEqualStrings("tag", issue.site.declaration);
}

test "an enum method cannot take a name zigo generates on that enum" {
    const tag: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const plain: semantic.TypeDecl = .{ .kind = .@"enum", .name = "Key", .fields = &.{.{ .name = "a", .value = 0 }}, .tag_type = tag };
    const textual: semantic.TypeDecl = .{ .kind = .@"enum", .name = "Key", .fields = &.{.{ .name = "a", .value = 0 }}, .tag_type = tag, .text = true };
    const method: semantic.SemanticFn = .{
        .name = "string",
        .params = &.{},
        .receiver = "Key",
        .receiver_kind = .value,
        .@"return" = .{ .void = {} },
        .symbol = "zg_key_string",
    };
    var marshal = method;
    marshal.name = "marshalText";
    marshal.symbol = "zg_key_marshal_text";

    const cases = [_]struct { function: semantic.SemanticFn, declaration: semantic.TypeDecl, collides: bool }{
        .{ .function = method, .declaration = plain, .collides = true },
        .{ .function = marshal, .declaration = textual, .collides = true },
        // Without `.text` there is no `MarshalText` to collide with.
        .{ .function = marshal, .declaration = plain, .collides = false },
    };
    for (cases) |case| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{case.function},
            .package = "input",
            .prefix = "zg",
            .types = &.{case.declaration},
            .zig_version = "0.16.0",
        };
        const issue = try publicNameCollisionIssue(scratch.allocator(), document, targets.default);
        if (!case.collides) {
            try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), issue);
            continue;
        }
        try std.testing.expectEqualStrings("ZIGO024", (issue orelse return error.MissingDiagnostic).code);
    }
}

fn optionsCollisionIssue(allocator: std.mem.Allocator, document: semantic.Semantic, target: targets.Target) !?diagnostic.Diagnostic {
    for (document.functions, 0..) |function, index| {
        for (function.params) |param| {
            const opt_spec = param.goOptions() orelse continue;
            const fields = param.flatten orelse continue;
            const prefix_source = function.goOwner() orelse function.receiver;
            const options_names = try naming.resolveOptionsNamesAlloc(
                allocator,
                opt_spec.prefix,
                opt_spec.type_name,
                prefix_source,
                function.goName() orelse function.name,
            );
            defer options_names.deinit(allocator);

            // 1. Check collision against document.types
            for (document.types) |declaration| {
                if (!semantic.optionalStringEqual(declaration.package, function.package)) continue;
                if (std.mem.eql(u8, options_names.type_name, declaration.name)) {
                    const function_path = try site.functionDeclarationAlloc(allocator, function);
                    return .{
                        .severity = .@"error",
                        .code = "ZIGO024",
                        .message = try std.fmt.allocPrint(
                            allocator,
                            "public Go name `{s}` collides between type `{s}` and generated option for `{s}`",
                            .{ options_names.type_name, declaration.zig_path orelse declaration.name, function_path },
                        ),
                        .site = site.functionSiteFor(function, function_path),
                        .hint = "rename the type or configure a different `.prefix` or `.type_name` in `.options`",
                    };
                }
                for (fields) |field| {
                    const with_name = try options_names.withNameAlloc(allocator, field.name);
                    defer allocator.free(with_name);
                    if (std.mem.eql(u8, with_name, declaration.name)) {
                        const function_path = try site.functionDeclarationAlloc(allocator, function);
                        return .{
                            .severity = .@"error",
                            .code = "ZIGO024",
                            .message = try std.fmt.allocPrint(
                                allocator,
                                "public Go name `{s}` collides between type `{s}` and generated option for `{s}`",
                                .{ with_name, declaration.zig_path orelse declaration.name, function_path },
                            ),
                            .site = site.functionSiteFor(function, function_path),
                            .hint = "rename the type or configure a different `.prefix` in `.options`",
                        };
                    }
                }
            }

            // 2. Check collision against receiverless functions
            for (document.functions) |other| {
                if (other.receiver != null) continue;
                if (!semantic.optionalStringEqual(other.package, function.package)) continue;
                const other_name = try target.publicFunctionNameAlloc(allocator, document, other);
                defer allocator.free(other_name);
                if (std.mem.eql(u8, options_names.type_name, other_name)) {
                    const function_path = try site.functionDeclarationAlloc(allocator, function);
                    const other_path = try site.functionDeclarationAlloc(allocator, other);
                    defer allocator.free(other_path);
                    return .{
                        .severity = .@"error",
                        .code = "ZIGO024",
                        .message = try std.fmt.allocPrint(
                            allocator,
                            "public Go name `{s}` collides between `{s}` and generated option for `{s}`",
                            .{ options_names.type_name, other_path, function_path },
                        ),
                        .site = site.functionSiteFor(function, function_path),
                        .hint = "rename the function or configure a different `.prefix` in `.options`",
                    };
                }
                for (fields) |field| {
                    const with_name = try options_names.withNameAlloc(allocator, field.name);
                    defer allocator.free(with_name);
                    if (std.mem.eql(u8, with_name, other_name)) {
                        const function_path = try site.functionDeclarationAlloc(allocator, function);
                        const other_path = try site.functionDeclarationAlloc(allocator, other);
                        defer allocator.free(other_path);
                        return .{
                            .severity = .@"error",
                            .code = "ZIGO024",
                            .message = try std.fmt.allocPrint(
                                allocator,
                                "public Go name `{s}` collides between `{s}` and generated option for `{s}`",
                                .{ with_name, other_path, function_path },
                            ),
                            .site = site.functionSiteFor(function, function_path),
                            .hint = "rename the function or configure a different `.prefix` in `.options`",
                        };
                    }
                }
            }

            // 3. Check collision against previous functions' options
            for (document.functions[0..index]) |previous| {
                if (!semantic.optionalStringEqual(previous.package, function.package)) continue;
                for (previous.params) |prev_param| {
                    const prev_opt = prev_param.goOptions() orelse continue;
                    const prev_fields = prev_param.flatten orelse continue;
                    const prev_prefix_source = previous.goOwner() orelse previous.receiver;
                    const prev_names = try naming.resolveOptionsNamesAlloc(
                        allocator,
                        prev_opt.prefix,
                        prev_opt.type_name,
                        prev_prefix_source,
                        previous.goName() orelse previous.name,
                    );
                    defer prev_names.deinit(allocator);

                    var clashing: ?[]const u8 = null;
                    if (std.mem.eql(u8, options_names.type_name, prev_names.type_name)) {
                        clashing = options_names.type_name;
                    }
                    for (fields) |field| {
                        if (clashing != null) break;
                        const with_name = try options_names.withNameAlloc(allocator, field.name);
                        defer allocator.free(with_name);
                        for (prev_fields) |prev_field| {
                            const prev_with = try prev_names.withNameAlloc(allocator, prev_field.name);
                            defer allocator.free(prev_with);
                            if (std.mem.eql(u8, with_name, prev_with)) {
                                clashing = try allocator.dupe(u8, with_name);
                                break;
                            }
                        }
                    }
                    if (clashing) |clashing_name| {
                        const function_path = try site.functionDeclarationAlloc(allocator, function);
                        const prev_path = try site.functionDeclarationAlloc(allocator, previous);
                        defer allocator.free(prev_path);
                        return .{
                            .severity = .@"error",
                            .code = "ZIGO024",
                            .message = try std.fmt.allocPrint(
                                allocator,
                                "public Go name `{s}` collides between generated option for `{s}` and generated option for `{s}`",
                                .{ clashing_name, prev_path, function_path },
                            ),
                            .site = site.functionSiteFor(function, function_path),
                            .hint = "configure distinct `.prefix` or `.type_name` on each options parameter",
                        };
                    }
                }
            }
        }
    }
    return null;
}

test "functional options name collisions report ZIGO024 with colliding declarations" {
    const u16_type: semantic.TypeNode = .{ .int = .{ .bits = 16, .is_usize = false, .signed = false } };
    const opt_fields = [_]semantic.FlattenedField{
        .{ .name = "rows", .type = u16_type, .default = .{ .int = 24 } },
    };
    const opt_param: semantic.Parameter = .{
        .name = "options",
        .type = .{ .value_struct = .{ .ref = "Options" } },
        .flatten = &opt_fields,
        .go = .{ .options = .{} },
    };
    const terminal_init: semantic.SemanticFn = .{
        .name = "init",
        .namespace = "Terminal",
        .params = &.{opt_param},
        .@"return" = .{ .void = {} },
        .symbol = "zg_terminal_init",
    };

    // 1. Collision with registered type
    {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{terminal_init},
            .package = "term",
            .prefix = "zg",
            .types = &.{
                .{ .kind = .value_struct, .name = "TerminalOption" },
            },
            .zig_version = "0.16.0",
        };
        const issue = (try publicNameCollisionIssue(scratch.allocator(), document, targets.default)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO024", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "TerminalOption") != null);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "type `TerminalOption`") != null);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "generated option for `Terminal.init`") != null);
    }

    // 2. Collision with free function
    {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{
                terminal_init,
                .{
                    .name = "withTerminalRows",
                    .params = &.{},
                    .@"return" = .{ .void = {} },
                    .symbol = "zg_with_terminal_rows",
                },
            },
            .package = "term",
            .prefix = "zg",
            .types = &.{},
            .zig_version = "0.16.0",
        };
        const issue = (try publicNameCollisionIssue(scratch.allocator(), document, targets.default)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO024", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "WithTerminalRows") != null);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "withTerminalRows") != null);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "generated option for `Terminal.init`") != null);
    }

    // 3. Collision between two functions' options
    {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        var terminal_config = terminal_init;
        terminal_config.name = "configure";
        terminal_config.symbol = "zg_terminal_configure";
        const document: semantic.Semantic = .{
            .functions = &.{ terminal_init, terminal_config },
            .package = "term",
            .prefix = "zg",
            .types = &.{},
            .zig_version = "0.16.0",
        };
        const issue = (try publicNameCollisionIssue(scratch.allocator(), document, targets.default)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO024", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "TerminalOption") != null);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "generated option for `Terminal.init`") != null);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "generated option for `Terminal.configure`") != null);
    }
}
