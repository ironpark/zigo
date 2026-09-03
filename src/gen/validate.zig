const std = @import("std");
const abi = @import("abi");
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

pub fn mustVariantNames(allocator: std.mem.Allocator, document: semantic.Semantic) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    if (try findMustVariantIssue(scratch.allocator(), document) != null) return error.InvalidSemantic;
}

pub fn findMustVariantIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.functions) |function| {
        if (!mustVariantEligible(document, function)) continue;
        const public_name = try effectivePublicFunctionNameAlloc(allocator, document, function);
        defer allocator.free(public_name);
        if (std.mem.eql(u8, public_name, "Close")) continue;
        const must_name = try std.fmt.allocPrint(allocator, "Must{s}", .{public_name});
        defer allocator.free(must_name);
        if (function.receiver == null) for (document.types) |declaration| {
            if (!semantic.optionalStringEqual(declaration.package, function.package)) continue;
            if (!std.mem.eql(u8, declaration.name, must_name)) continue;
            const function_path = try functionDeclarationAlloc(allocator, function);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}` collides between type `{s}` and generated Must variant for `{s}`",
                    .{ must_name, declaration.zig_path orelse declaration.name, function_path },
                ),
                .site = functionSiteFor(function, function_path),
                .hint = "rename the function or conflicting type so the generated Must name is unique",
            };
        };
        for (document.functions) |other| {
            if (constructorDeinitFor(document, other) != null) continue;
            if (!std.mem.eql(u8, function.receiver orelse "", other.receiver orelse "")) continue;
            if (!semantic.optionalStringEqual(function.package, other.package)) continue;
            const other_name = try effectivePublicFunctionNameAlloc(allocator, document, other);
            defer allocator.free(other_name);
            if (!std.mem.eql(u8, must_name, other_name)) continue;
            const function_path = try functionDeclarationAlloc(allocator, function);
            const other_path = try functionDeclarationAlloc(allocator, other);
            defer allocator.free(other_path);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}` collides between `{s}` and generated Must variant for `{s}`",
                    .{ must_name, other_path, function_path },
                ),
                .site = functionSiteFor(function, function_path),
                .hint = "rename one declaration so the generated Must name is unique",
            };
        }
    }
    return null;
}

fn mustVariantEligible(document: semantic.Semantic, function: semantic.SemanticFn) bool {
    if (constructorDeinitFor(document, function) != null) return false;
    if (constructorInitFor(document, function) != null or function.@"return" == .error_union or function.receiver != null) return true;
    for (function.params) |parameter| {
        if (parameter.type == .opaque_ptr or parameter.type == .io_stream or parameter.goError()) return true;
        if (abi.narrowInt(parameter.type) != null) return true;
        if (parameter.type == .slice and abi.narrowInt(parameter.type.slice.element.*) != null) return true;
        if (parameter.flatten) |fields| for (fields) |field| {
            const node = if (field.type == .optional) field.type.optional.child.* else field.type;
            if (abi.narrowInt(node) != null) return true;
        };
    }
    return false;
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
                .site = functionSite(function),
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
    if (packageMetadataIssue(document)) |issue| return issue;
    if (try packageCycleIssue(allocator, document)) |issue| return issue;
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
            .site = functionSite(function),
            .hint = "use an explicit error set in the Zig function signature",
        };
        if (function.has_comptime_params == true) return .{
            .severity = .@"error",
            .code = "ZIGO008",
            .message = "cannot expose a function with comptime parameters",
            .site = functionSite(function),
            .hint = "bind a concrete specialization instead of the generic function",
        };
        if (byValueOpaqueReturn(function.@"return")) |pointer| return .{
            .severity = .@"error",
            .code = "ZIGO003",
            .message = "cannot return a registered opaque type by value",
            .site = functionSite(function),
            .hint = try std.fmt.allocPrint(
                allocator,
                "return `*{s}` and use `.constructs`, or configure `.allocator` so zigo can box the value",
                .{pointer.ref},
            ),
        };
        if (function.childOfReceiver() and
            (function.receiver == null or constructorInitFor(document, function) == null)) return .{
            .severity = .@"error",
            .code = "ZIGO030",
            .message = "child-of-receiver metadata requires a receiver constructor",
            .site = functionSite(function),
            .hint = "use `.child_of_receiver = true` only on a constructor method that returns its paired caller-owned handle",
        };
        if (function.returnsBorrowedHandle() and function.receiver == null) return .{
            .severity = .@"error",
            .code = "ZIGO033",
            .message = "borrowed return has no receiver to own its lifetime",
            .site = functionSite(function),
            .hint = "use `.returns = .borrowed` only on a method, or use `.returns = .caller` with a constructor and destructor",
        };
        if (function.returnsBorrowedHandle() and borrowedOpaqueReturn(document, function) == null) return .{
            .severity = .@"error",
            .code = "ZIGO034",
            .message = "borrowed return is not a registered opaque handle",
            .site = functionSite(function),
            .hint = "return `*T`, `?*T`, `!*T`, or `!?*T` where T is a registered opaque type, or drop `.returns = .borrowed`",
        };
        if (!function.returnsBorrowedHandle() and function.ownership == .borrowed and
            borrowedOpaqueReturn(document, function) != null) return .{
            .severity = .@"error",
            .code = "ZIGO035",
            .message = "opaque handle return has no explicit ownership",
            .site = functionSite(function),
            .hint = "add `.returns = .borrowed` for a receiver-owned view, or pair `.returns = .caller` with its constructor and destructor",
        };
        for (function.params) |parameter| {
            if (parameter.injected) |injection| {
                const configured = switch (injection) {
                    .allocator => document.allocator,
                    .io => document.io,
                };
                if (configured != null) continue;
                return .{
                    .severity = .@"error",
                    .code = "ZIGO022",
                    .message = try std.fmt.allocPrint(
                        allocator,
                        "parameter `{s}` needs a {s} the binding has not named",
                        .{ parameter.name, if (injection == .allocator) "`std.mem.Allocator`" else "`std.Io`" },
                    ),
                    .site = functionSite(function),
                    .hint = if (injection == .allocator)
                        "set `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator`, or a declaration path in the binding"
                    else
                        "set `.io = \"<declaration path>\"` in the binding",
                };
            }
            if (try streamParameterIssue(allocator, function, parameter)) |issue| return issue;
            if (try atomicPointerIssue(allocator, function, parameter)) |issue| return issue;
            if (try callbackGoErrorIssue(allocator, function, parameter)) |issue| return issue;
            if (try callbackFailureResultIssue(allocator, document, function, parameter)) |issue| return issue;
            if (try callbackContractIssue(allocator, function, parameter)) |issue| return issue;
            if (containsMaterialized(parameter.type) and !isMaterializedReleaseTarget(document, function)) return .{
                .severity = .@"error",
                .code = "ZIGO048",
                .message = "materialized structs are result-only",
                .site = functionSite(function),
                .hint = "return the materialized struct, error-union payload, or slice from Zig; inbound materialized parameters are not supported",
            };
            if (parameter.type == .cancel_flag and !(parameter.cancel orelse false)) return .{
                .severity = .@"error",
                .code = "ZIGO026",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "parameter `{s}` is a cancellation flag but no `.cancel` names it",
                    .{parameter.name},
                ),
                .site = functionSiteFor(function, try functionDeclarationAlloc(allocator, function)),
                .hint = "name it with `.cancel` on the function, or drop the parameter",
            };
            const tagged_union_value = taggedUnionValueDeclaration(document, parameter.type);
            if (tagged_union_value) |declaration| {
                if (document.taggedUnionUsedAsHandle(declaration.name)) return .{
                    .severity = .@"error",
                    .code = "ZIGO006",
                    .message = "cannot use one tagged union as both a value parameter and a pointer handle",
                    .site = functionSite(function),
                    .hint = "register a separate scalar-payload union type for the value parameter",
                };
                if (taggedUnionValueIneligibleVariant(document, declaration)) |variant| return .{
                    .severity = .@"error",
                    .code = "ZIGO006",
                    .message = "cannot pass a tagged union by value",
                    .site = functionSite(function),
                    .hint = try std.fmt.allocPrint(
                        allocator,
                        "variant `{s}` has an unsupported value payload; omit it with `.omit_variants` or use void, scalar, enum, packed struct, or extern struct payloads",
                        .{variant},
                    ),
                };
            } else if (containsTaggedUnionValue(document, parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO006",
                .message = "cannot pass a tagged union by value",
                .site = functionSite(function),
                .hint = "pass an eligible tagged union as a whole parameter; nested tagged-union values are not supported",
            };
            if (parameter.flatten) |fields| {
                if (parameter.type != .value_struct) return .{
                    .severity = .@"error",
                    .code = "ZIGO040",
                    .message = "flatten metadata requires a struct parameter",
                    .site = functionSite(function),
                    .hint = "apply `.flatten` only to a plain struct parameter",
                };
                for (fields) |field| if (!isFlattenLeaf(document, field.type)) return .{
                    .severity = .@"error",
                    .code = "ZIGO040",
                    .message = try std.fmt.allocPrint(allocator, "flattened field `{s}` has an unsupported type", .{field.name}),
                    .site = functionSite(function),
                    .hint = "flatten only bool, integer, float, registered enum, or optional scalar fields",
                };
            } else if (tagged_union_value == null and unsupportedValueStruct(document, parameter.type) != null) return .{
                .severity = .@"error",
                .code = "ZIGO003",
                .message = "cannot pass a non-extern struct by value",
                .site = functionSite(function),
                .hint = "declare it as `extern struct`, or expose it as opaque",
            };
            if (nestedValueStruct(document, parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO013",
                .message = "extern struct is only supported as a whole parameter or return value",
                .site = functionSite(function),
                .hint = "pass the struct on its own or as a direct slice element; optional and callback signatures are not supported",
            };
            if (containsNonCFunctionPointer(parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO004",
                .message = "function pointer does not use the C calling convention",
                .site = functionSite(function),
                .hint = "declare the callback with `callconv(.c)`",
            };
            if (parameter.type == .slice and containsPointer(parameter.type.slice.element.*) and
                !semantic.isStringSliceParameter(parameter)) return .{
                .severity = .@"error",
                .code = "ZIGO005",
                .message = "slice element type contains a pointer",
                .site = functionSite(function),
                .hint = "pass scalar elements or opaque handle values instead of Go pointers",
            };
            if (parameter.retention == .retained and containsPointer(parameter.type) and !hasMatchingRelease(document, function)) return .{
                .severity = .@"error",
                .code = "ZIGO009",
                .message = "retained pointer has no matching release function",
                .site = functionSite(function),
                .hint = "expose a release, clear, close, destroy, or deinit function for the retained value",
                .note = try retentionNoteAlloc(allocator, function),
            };
        }
        if (try streamReturnIssue(allocator, function)) |issue| return issue;
        if (try cancelIssue(allocator, function)) |issue| return issue;
        if (taggedUnionValueDeclaration(document, function.@"return")) |declaration| {
            if (document.taggedUnionUsedAsHandle(declaration.name)) return .{
                .severity = .@"error",
                .code = "ZIGO006",
                .message = "cannot use one tagged union as both a value return and a pointer handle",
                .site = functionSite(function),
                .hint = "register a separate union type for the value return",
            };
            if (taggedUnionValueIneligibleVariant(document, declaration)) |variant| return .{
                .severity = .@"error",
                .code = "ZIGO006",
                .message = "cannot return a tagged union by value",
                .site = functionSite(function),
                .hint = try std.fmt.allocPrint(
                    allocator,
                    "variant `{s}` has an unsupported value payload; omit it with `.omit_variants` or use void, scalar, enum, packed struct, or extern struct payloads",
                    .{variant},
                ),
            };
        } else if (containsTaggedUnionValue(document, function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO006",
            .message = "cannot return a tagged union by value",
            .site = functionSite(function),
            .hint = "return an eligible tagged union directly; nested tagged-union values are not supported",
        };
        if (taggedUnionValueDeclaration(document, function.@"return") == null and
            unsupportedValueStruct(document, function.@"return") != null) return .{
            .severity = .@"error",
            .code = "ZIGO003",
            .message = "cannot pass a non-extern struct by value",
            .site = functionSite(function),
            .hint = "declare it as `extern struct`, or expose it as opaque",
        };
        if (nestedValueStruct(document, function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO013",
            .message = "extern struct is only supported as a whole parameter or return value",
            .site = functionSite(function),
            .hint = "pass the struct on its own or as a direct slice element; optional and callback signatures are not supported",
        };
        if (containsNonCFunctionPointer(function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO004",
            .message = "function pointer does not use the C calling convention",
            .site = functionSite(function),
            .hint = "declare the callback with `callconv(.c)`",
        };
        // A returned slice crosses as `T*` plus a length, so its element has to
        // be a value the C ABI can name. The error-union payload uses the same
        // out parameters and answers to the same rule.
        if (releasableSliceReturnElement(function)) |element| {
            if (containsPointer(element)) return .{
                .severity = .@"error",
                .code = "ZIGO005",
                .message = "slice element type contains a pointer",
                .site = functionSite(function),
                .hint = "return scalar, enum, or extern-struct elements instead of Go pointers",
            };
        }
        // A caller-owned slice is handed over through `release` instead of a
        // handle destructor, so it answers to ZIGO016 rather than ZIGO015.
        if (function.ownership == .caller and isMaterializedReturn(function.@"return")) {
            if (materializedReleaseTargetIssue(document, function)) |issue| return issue;
        } else if (function.ownership == .caller and isReleasableSliceReturn(function)) {
            if (releaseTargetIssue(document, function)) |issue| return issue;
        } else if (function.ownership == .caller and !ownedReturnIsWrappable(document, function)) return .{
            .severity = .@"error",
            .code = "ZIGO015",
            .message = "caller-owned return has no constructed handle to hand over",
            .site = functionSite(function),
            .hint = "return a pointer to an opaque type that has both a constructor and a destructor, or drop `.returns = .caller`",
        };
        for (function.params) |parameter| {
            if (parameter.written == null) continue;
            if (parameter.direction != .out) return .{
                .severity = .@"error",
                .code = "ZIGO017",
                .message = "written hint declared on a parameter that is not an output slice",
                .site = functionSite(function),
                .hint = "add `.direction = .out` to the parameter, or drop `.written`",
            };
            if (parameter.writtenHint() == .@"return" and !returnsCount(function.@"return")) return .{
                .severity = .@"error",
                .code = "ZIGO017",
                .message = "`.written = .return` needs a `usize` result to report the count",
                .site = functionSite(function),
                .hint = "return `usize` or `!usize` from the function, or use the default `.written = .all`",
            };
        }
        if (function.release != null and !isReleasableSliceReturn(function) and !isMaterializedReturn(function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO016",
            .message = "release function declared on a return that zigo does not free",
            .site = functionSite(function),
            .hint = "use `.release` only together with `.returns = .caller` on a slice return",
        };
    }
    for (document.functions) |function| if (isMaterializedReturn(function.@"return") and
        (function.ownership != .caller or function.release == null)) return .{
        .severity = .@"error",
        .code = "ZIGO048",
        .message = "materialized result has no caller-owned buffer release",
        .site = functionSite(function),
        .hint = "set `.returns = .caller` and `.release` to an exposed function that frees `[]u8` with the registered allocator",
    };
    for (document.types) |declaration| {
        if (declaration.kind == .materialized) {
            if (try materializedProblemAlloc(allocator, document, declaration)) |problem| return .{
                .severity = .@"error",
                .code = "ZIGO048",
                .message = try std.fmt.allocPrint(allocator, "materialized field `{s}` is unsupported", .{problem.path}),
                .site = .{ .path = "semantic.json", .declaration = declaration.name },
                .hint = problem.reason,
            };
        }
        if (declaration.omitted_variants) |omitted| {
            for (omitted, 0..) |name, index| {
                var found = false;
                for (declaration.fields) |field| if (std.mem.eql(u8, field.name, name)) {
                    found = true;
                    break;
                };
                for (omitted[0..index]) |earlier| if (std.mem.eql(u8, earlier, name)) {
                    found = false;
                    break;
                };
                if (!found) return .{
                    .severity = .@"error",
                    .code = "ZIGO039",
                    .message = "invalid omitted tagged-union variant",
                    .site = .{ .path = "semantic.json", .declaration = declaration.name },
                    .hint = try std.fmt.allocPrint(allocator, "name `{s}` exactly once in `.omit_variants` and ensure it is a variant of the registered union", .{name}),
                };
            }
        }
        for (declaration.fields) |field| {
            const node = field.type orelse continue;
            if (!containsIoStream(node)) continue;
            return .{
                .severity = .@"error",
                .code = "ZIGO023",
                .message = try std.fmt.allocPrint(allocator, "`*std.Io.Writer` and `*std.Io.Reader` are only supported as whole parameters, not in field `{s}`", .{field.name}),
                .site = .{ .path = "semantic.json", .declaration = declaration.name },
                .hint = "the shim adapter lives on the call stack, so a stream cannot be stored; take the stream as a parameter of the function that uses it",
            };
        }
        if (declaration.kind == .@"enum" and declaration.open == true and declaration.exhaustive) return .{
            .severity = .@"error",
            .code = "ZIGO029",
            .message = "open-enum opt-in applied to an exhaustive enum",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "remove `.exhaustive = false`, or make the Zig enum non-exhaustive",
        };
        if (declaration.kind == .@"enum" and !declaration.exhaustive and declaration.open != true) return .{
            .severity = .@"error",
            .code = "ZIGO002",
            .message = "cannot expose a non-exhaustive enum",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "make the enum exhaustive, or register it with `.exhaustive = false`",
        };
        if (declaration.kind == .tagged_union and
            !document.isValueOnlyTaggedUnion(declaration.name) and
            !taggedUnionAccessorsSupported(document, declaration)) return .{
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
        if (declaration.kind == .value_struct and declaration.layout == .@"packed") {
            if (packedStructProblem(document, declaration, 0)) |field| return .{
                .severity = .@"error",
                .code = "ZIGO044",
                .message = try std.fmt.allocPrint(allocator, "packed struct field `{s}` cannot cross as a value", .{field}),
                .site = .{ .path = "semantic.json", .declaration = declaration.name },
                .hint = "use only bool, integer, registered enum, or registered integer-backed packed struct fields",
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
    if (try cIdentifierIssue(allocator, document)) |issue| return issue;
    if (try findGeneratedAccessorCollision(allocator, document)) |declaration| return .{
        .severity = .@"error",
        .code = "ZIGO007",
        .message = "generated tagged-union accessor collides with another declaration",
        .site = .{ .path = "semantic.json", .declaration = declaration },
        .hint = "rename the conflicting function, type, or union variant",
    };
    // The C symbol check above catches collisions that would fail the linker.
    // It cannot catch this class: generation drops the owning namespace from
    // a receiverless function's public name (only a method's receiver scopes
    // it), so two functions in different namespaces -- or a namespace
    // function and a registered type -- can still resolve to the same public
    // Go identifier and fail `go build` with a duplicate declaration instead
    // of a zigo diagnostic.
    for (document.types) |declaration| {
        for (document.functions) |function| {
            if (function.receiver != null) continue;
            if (!semantic.optionalStringEqual(declaration.package, function.package)) continue;
            const function_name = try effectivePublicFunctionNameAlloc(allocator, document, function);
            defer allocator.free(function_name);
            if (!std.mem.eql(u8, function_name, declaration.name)) continue;
            // Kept alive: `site.declaration` below points directly at it.
            const function_path = try functionDeclarationAlloc(allocator, function);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}` collides between type `{s}` and function `{s}`",
                    .{ function_name, declaration.zig_path orelse declaration.name, function_path },
                ),
                .site = functionSiteFor(function, function_path),
                .hint = "rename the function, or register the type with a `.name` that resolves to a different Go identifier",
                .note = try typeRenameNoteAlloc(allocator, declaration),
            };
        }
    }
    for (document.functions, 0..) |function, index| {
        if (constructorDeinitFor(document, function) != null) continue;
        const bucket = function.receiver orelse "";
        const name = try effectivePublicFunctionNameAlloc(allocator, document, function);
        defer allocator.free(name);
        for (document.functions[0..index]) |previous| {
            if (constructorDeinitFor(document, previous) != null) continue;
            const previous_bucket = previous.receiver orelse "";
            if (!std.mem.eql(u8, bucket, previous_bucket)) continue;
            if (!semantic.optionalStringEqual(function.package, previous.package)) continue;
            const previous_name = try effectivePublicFunctionNameAlloc(allocator, document, previous);
            defer allocator.free(previous_name);
            if (!std.mem.eql(u8, name, previous_name)) continue;
            // Kept alive: `site.declaration` below points directly at it.
            const function_path = try functionDeclarationAlloc(allocator, function);
            const previous_path = try functionDeclarationAlloc(allocator, previous);
            defer allocator.free(previous_path);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}` collides between `{s}` and `{s}`",
                    .{ name, previous_path, function_path },
                ),
                .site = functionSiteFor(function, function_path),
                .hint = "rename one declaration, or give it a `.name` that resolves to a different Go identifier",
                .note = if (constructorInitFor(document, function) != null)
                    try functionOrConstructorRenameNoteAlloc(allocator, document, function)
                else if (constructorInitFor(document, previous) != null)
                    try functionOrConstructorRenameNoteAlloc(allocator, document, previous)
                else
                    try functionRenameNoteAlloc(allocator, function),
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
                    .note = try memberCollisionNoteAlloc(allocator, field.name),
                };
            }
        }
    }
    if (findIntegrityProblem(document)) |declaration| return .{
        .severity = .@"error",
        .code = "ZIGO010",
        .message = "semantic document contains an unresolved or incompatible declaration reference",
        .site = .{ .path = "semantic.json", .declaration = declaration },
        .hint = "regenerate semantic.json from matching bindings and source declarations",
    };
    // An `.out` slice is a buffer the caller already allocated, so making it
    // optional asks the callee to decide whether that buffer exists -- there
    // is no shape for that, and no reading of it the two sides would agree on.
    for (document.functions) |function| {
        for (function.params) |parameter| {
            if (parameter.direction != .out or parameter.type != .optional) continue;
            const declaration = try functionDeclarationAlloc(allocator, function);
            return .{
                .severity = .@"error",
                .code = "ZIGO019",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "output parameter `{s}` cannot be optional",
                    .{parameter.name},
                ),
                .site = functionSiteFor(function, declaration),
                .hint = "an output buffer is supplied by the caller; drop the `?` or make the function return the optional instead",
            };
        }
    }
    // Types the C ABI cannot name are reported last so that the sharper
    // diagnostics above keep naming the declarations they always did.
    for (document.functions) |function| {
        for (function.params) |parameter| {
            if (parameter.type == .atomic_ptr) continue;
            if (narrowSliceElement(parameter.type)) |_| {
                if (document.allocator == null) return .{
                    .severity = .@"error",
                    .code = "ZIGO045",
                    .message = try std.fmt.allocPrint(
                        allocator,
                        "narrow integer slice parameter `{s}` needs temporary storage",
                        .{parameter.name},
                    ),
                    .site = functionSiteFor(function, try functionDeclarationAlloc(allocator, function)),
                    .hint = "set `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator`, or a declaration path in the binding",
                };
            }
            if (try typeOffense(allocator, parameter.type, true)) |offense| {
                const root = try std.fmt.allocPrint(allocator, "parameter `{s}`", .{parameter.name});
                const location = try locationAlloc(allocator, offense.context, root);
                return try offenseDiagnostic(allocator, function, offense, location);
            }
        }
        if (narrowSliceElement(function.@"return")) |element| {
            if (function.ownership != .caller or function.release == null) {
                const spelling = try zigSpellingAlloc(allocator, element);
                return .{
                    .severity = .@"error",
                    .code = "ZIGO018",
                    .message = try std.fmt.allocPrint(allocator, "cannot promote integer width `{s}` in a borrowed slice return", .{spelling}),
                    .site = functionSiteFor(function, try functionDeclarationAlloc(allocator, function)),
                    .hint = "mark the slice return `.returns = .caller` and name its `.release`; borrowed narrow slices have no stable widened storage",
                };
            }
        }
        if (try typeOffense(allocator, function.@"return", true)) |offense| {
            const location = try locationAlloc(allocator, offense.context, "the return value");
            return try offenseDiagnostic(allocator, function, offense, location);
        }
    }
    return null;
}

fn packageMetadataIssue(document: semantic.Semantic) ?diagnostic.Diagnostic {
    const packages = document.packages orelse return null;
    for (packages, 0..) |package, index| {
        if (!naming.isGoIdentifier(package.name) or !semantic.validPackagePath(package.path)) return .{
            .severity = .@"error",
            .code = "ZIGO031",
            .message = "semantic document contains an invalid public package declaration",
            .site = .{ .path = "semantic.json", .declaration = package.name },
            .hint = "use a unique Go identifier and a portable relative package path",
        };
        for (packages[0..index]) |previous| if (std.mem.eql(u8, previous.name, package.name) or std.mem.eql(u8, previous.path, package.path)) return .{
            .severity = .@"error",
            .code = "ZIGO031",
            .message = "semantic document contains duplicate public packages",
            .site = .{ .path = "semantic.json", .declaration = package.name },
            .hint = "give every public package a unique name and path",
        };
    }
    for (document.types) |declaration| if (declaration.package) |name| if (!hasPackage(packages, name)) return unknownPackage(name);
    for (document.functions) |function| if (function.package) |name| {
        if (!hasPackage(packages, name)) return unknownPackage(name);
        const owner = function.receiver orelse function.goOwner() orelse continue;
        for (document.types) |declaration| if (std.mem.eql(u8, declaration.name, owner)) {
            if (!semantic.optionalStringEqual(declaration.package, function.package)) return .{
                .severity = .@"error",
                .code = "ZIGO031",
                .message = "a function is split from its owning type",
                .site = functionSite(function),
                .hint = "assign a type and all of its methods, constructors, destructor, and projections to the same package",
            };
        };
    };
    return null;
}

fn hasPackage(packages: []const semantic.Package, name: []const u8) bool {
    for (packages) |package| if (std.mem.eql(u8, package.name, name)) return true;
    return false;
}

fn unknownPackage(name: []const u8) diagnostic.Diagnostic {
    return .{
        .severity = .@"error",
        .code = "ZIGO031",
        .message = "declaration references an unknown public package",
        .site = .{ .path = "semantic.json", .declaration = name },
        .hint = "add the package to `packages`, or omit the declaration's `package` field",
    };
}

fn packageCycleIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    const packages = document.packages orelse return null;
    const count = packages.len + 1;
    const edges = try allocator.alloc(?[]const u8, count * count);
    @memset(edges, null);
    for (document.functions) |function| {
        const from = packageIndex(packages, function.package);
        for (function.params) |parameter| addTypeEdges(document, packages, edges, count, from, parameter.type, function.name);
        addTypeEdges(document, packages, edges, count, from, function.@"return", function.name);
    }
    for (document.types) |declaration| {
        const from = packageIndex(packages, declaration.package);
        if (declaration.tag_type) |node| addTypeEdges(document, packages, edges, count, from, node, declaration.name);
        for (declaration.fields) |field| if (field.type) |node| addTypeEdges(document, packages, edges, count, from, node, declaration.name);
    }
    const state = try allocator.alloc(u8, count);
    @memset(state, 0);
    const stack = try allocator.alloc(usize, count);
    for (0..count) |index| if (state[index] == 0) if (try visitPackage(allocator, packages, edges, count, state, stack, 0, index)) |issue| return issue;
    return null;
}

fn visitPackage(allocator: std.mem.Allocator, packages: []const semantic.Package, edges: []const ?[]const u8, count: usize, state: []u8, stack: []usize, depth: usize, current: usize) !?diagnostic.Diagnostic {
    state[current] = 1;
    stack[depth] = current;
    for (0..count) |next| {
        const declaration = edges[current * count + next] orelse continue;
        if (state[next] == 1) {
            var start: usize = 0;
            while (stack[start] != next) : (start += 1) {}
            var path: std.Io.Writer.Allocating = .init(allocator);
            for (stack[start .. depth + 1], 0..) |item, offset| {
                if (offset != 0) try path.writer.writeAll(" -> ");
                try path.writer.writeAll(packageName(packages, item));
            }
            try path.writer.print(" -> {s}", .{packageName(packages, next)});
            return .{
                .severity = .@"error",
                .code = "ZIGO032",
                .message = try std.fmt.allocPrint(allocator, "public package import cycle involves declaration `{s}`", .{declaration}),
                .site = .{ .path = "semantic.json", .declaration = declaration },
                .hint = try std.fmt.allocPrint(allocator, "move the declarations so the package graph is acyclic: {s}", .{path.written()}),
            };
        }
        if (state[next] == 0) if (try visitPackage(allocator, packages, edges, count, state, stack, depth + 1, next)) |issue| return issue;
    }
    state[current] = 2;
    return null;
}

fn packageIndex(packages: []const semantic.Package, package: ?[]const u8) usize {
    const name = package orelse return 0;
    for (packages, 0..) |entry, index| if (std.mem.eql(u8, entry.name, name)) return index + 1;
    return 0;
}

fn packageName(packages: []const semantic.Package, index: usize) []const u8 {
    return if (index == 0) "default" else packages[index - 1].name;
}

fn addTypeEdges(document: semantic.Semantic, packages: []const semantic.Package, edges: []?[]const u8, count: usize, from: usize, node: semantic.TypeNode, declaration: []const u8) void {
    switch (node) {
        .@"enum" => |value| addNamedEdge(document, packages, edges, count, from, value.ref, declaration),
        .opaque_ptr => |value| addNamedEdge(document, packages, edges, count, from, value.ref, declaration),
        .materialized => |value| addNamedEdge(document, packages, edges, count, from, value.ref, declaration),
        .value_struct => |value| addNamedEdge(document, packages, edges, count, from, value.ref, declaration),
        .slice => |value| addTypeEdges(document, packages, edges, count, from, value.element.*, declaration),
        .optional => |value| addTypeEdges(document, packages, edges, count, from, value.child.*, declaration),
        .error_union => |value| addTypeEdges(document, packages, edges, count, from, value.payload.*, declaration),
        .callback => |value| {
            for (value.params) |parameter| addTypeEdges(document, packages, edges, count, from, parameter, declaration);
            addTypeEdges(document, packages, edges, count, from, value.@"return".*, declaration);
        },
        else => {},
    }
}

fn addNamedEdge(document: semantic.Semantic, packages: []const semantic.Package, edges: []?[]const u8, count: usize, from: usize, name: []const u8, declaration: []const u8) void {
    for (document.types) |type_decl| if (std.mem.eql(u8, type_decl.name, name)) {
        const to = packageIndex(packages, type_decl.package);
        if (from != to) edges[from * count + to] = declaration;
        return;
    };
}

/// Every rejection a stream parameter can earn, in the order the author is
/// most likely to have caused them. A stream is a call-scoped adapter the shim
/// builds on its own stack around a Go callback, which is what every one of
/// these limits comes back to: nothing may outlive the call, and nothing may
/// `.cancel = .{ .param = "..." }` is what turns a long native call into one
/// Go can stop: the wrapper takes a `ctx`, a goroutine watching `ctx.Done()`
/// raises the flag, and the Zig side polls it. All three parts have to line
/// up, so all three are checked: the name has to reach a parameter, that
/// parameter has to be the flag the shim knows how to pass, and the function
/// has to have a way of saying it stopped.
fn cancelIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn) !?diagnostic.Diagnostic {
    const named = function.cancel orelse return null;
    const declaration = try functionDeclarationAlloc(allocator, function);
    var target: ?semantic.Parameter = null;
    for (function.params) |parameter| {
        if (parameter.cancel orelse false) target = parameter;
    }
    const parameter = target orelse return .{
        .severity = .@"error",
        .code = "ZIGO026",
        .message = try std.fmt.allocPrint(allocator, "`.cancel` names `{s}`, which is not a parameter of this function", .{named}),
        .site = functionSiteFor(function, declaration),
        .hint = "name one of the function's own parameters, spelled as it is in `.params`",
    };
    if (parameter.type != .cancel_flag) return .{
        .severity = .@"error",
        .code = "ZIGO026",
        .message = try std.fmt.allocPrint(
            allocator,
            "cancellation parameter `{s}` is not a `*const std.atomic.Value(u32)`",
            .{parameter.name},
        ),
        .site = functionSiteFor(function, declaration),
        .hint = "declare it as `*const std.atomic.Value(u32)` and poll it; Go writes the same four bytes with sync/atomic",
    };
    const canceled = function.cancelError();
    if (!functionErrorSetHas(function, canceled)) return .{
        .severity = .@"error",
        .code = "ZIGO026",
        .message = try std.fmt.allocPrint(allocator, "a cancellable function must be able to report `error.{s}`", .{canceled}),
        .site = functionSiteFor(function, declaration),
        .hint = try std.fmt.allocPrint(allocator, "return an error union whose set contains `{s}`; generated Go maps it back to `ctx.Err()`", .{canceled}),
    };
    return null;
}

fn atomicPointerIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn, parameter: semantic.Parameter) !?diagnostic.Diagnostic {
    if (parameter.type != .atomic_ptr) return null;
    const child = parameter.type.atomic_ptr.child.*;
    const supported = child == .int and !child.int.is_usize and
        (child.int.bits == 32 or child.int.bits == 64);
    if (!supported) return .{
        .severity = .@"error",
        .code = "ZIGO043",
        .message = try std.fmt.allocPrint(allocator, "parameter `{s}` points to an unsupported atomic scalar", .{parameter.name}),
        .site = functionSite(function),
        .hint = "use *std.atomic.Value(u32), i32, u64, or i64 for a shared atomic parameter",
    };
    if (parameter.retention == .retained) return .{
        .severity = .@"error",
        .code = "ZIGO043",
        .message = try std.fmt.allocPrint(allocator, "atomic parameter `{s}` cannot be retained", .{parameter.name}),
        .site = functionSite(function),
        .hint = "keep the default call-scoped borrowed retention; native code cannot keep a Go address after the call",
    };
    return null;
}

fn functionErrorSetHas(function: semantic.SemanticFn, name: []const u8) bool {
    if (function.@"return" != .error_union) return false;
    for (function.@"return".error_union.error_set) |value| {
        if (std.mem.eql(u8, value, name)) return true;
    }
    return false;
}

/// A method may hand a stream out: `fn writer(self) *std.Io.Writer` becomes
/// Go `Write`/`Flush`, and `fn reader(self) *std.Io.Reader` becomes `Read`.
/// The pointer never crosses -- each generated operation asks the object for
/// the stream again -- so the rules are about what makes that possible: it has
/// to be the whole return of a method that takes nothing else, because there
/// is no call for extra arguments to travel on.
fn streamReturnIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn) !?diagnostic.Diagnostic {
    if (!containsIoStream(function.@"return")) return null;
    const declaration = try functionDeclarationAlloc(allocator, function);
    if (function.@"return" != .io_stream) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = "`*std.Io.Writer` and `*std.Io.Reader` can only be returned on their own",
        .site = functionSiteFor(function, declaration),
        .hint = "return the stream directly from a method; it cannot travel inside an error union, an optional, a slice, or a struct",
    };
    if (function.receiver == null) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = "only a method can return a `*std.Io.Writer` or `*std.Io.Reader`",
        .site = functionSiteFor(function, declaration),
        .hint = "the generated operations re-fetch the stream from the receiver on every call, so there has to be a receiver",
    };
    if (function.params.len != 0) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = "a stream-returning method cannot take parameters",
        .site = functionSiteFor(function, declaration),
        .hint = "the generated `Write`/`Read`/`Flush` methods have nowhere to carry them; take the arguments on the method that uses the stream instead",
    };
    return null;
}

/// `go_error` widens the Go callback type to `(i32, error)` and spends the
/// native result to say so: the trampoline returns `-5` instead of whatever
/// the callback computed. That only works when the native result is an `i32`
/// the target function reads as a status, so the two other callback shapes --
/// `void`, which has no result at all, and anything else, which `ZIGO014`
/// already refuses on purego -- are rejected here rather than silently
/// dropping the error.
fn callbackGoErrorIssue(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    parameter: semantic.Parameter,
) !?diagnostic.Diagnostic {
    if (!parameter.goError()) return null;
    if (parameter.type != .callback) {
        const declaration = try functionDeclarationAlloc(allocator, function);
        return .{
            .severity = .@"error",
            .code = "ZIGO025",
            .message = try std.fmt.allocPrint(
                allocator,
                "`go_error` declared on parameter `{s}`, which is not a callback",
                .{parameter.name},
            ),
            .site = functionSiteFor(function, declaration),
            .hint = "use `.go_error = true` only on a function-pointer parameter",
        };
    }
    const result = parameter.type.callback.@"return".*;
    if (result == .int and result.int.signed and result.int.bits == 32) return null;
    const declaration = try functionDeclarationAlloc(allocator, function);
    return .{
        .severity = .@"error",
        .code = "ZIGO025",
        .message = try std.fmt.allocPrint(
            allocator,
            "callback `{s}` cannot return a Go error: its Zig result is not `i32`",
            .{parameter.name},
        ),
        .site = functionSiteFor(function, declaration),
        .hint = "declare the Zig callback as `*const fn (...) callconv(.c) i32`; the trampoline reports a Go error as the result `-5`",
    };
}

fn callbackFailureResult(document: semantic.Semantic, parameter: semantic.Parameter) ?semantic.CallbackFailure {
    if (parameter.on_callback_failure) |value| return value;
    if (parameter.type != .callback) return null;
    const ref = parameter.type.callback.ref orelse return null;
    for (document.types) |declaration| {
        if (declaration.kind == .callback and std.mem.eql(u8, declaration.name, ref))
            return declaration.on_callback_failure;
    }
    return null;
}

fn callbackFailureResultIssue(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    function: semantic.SemanticFn,
    parameter: semantic.Parameter,
) !?diagnostic.Diagnostic {
    const failure = callbackFailureResult(document, parameter) orelse return null;
    const declaration = try functionDeclarationAlloc(allocator, function);
    if (parameter.type != .callback) return .{
        .severity = .@"error",
        .code = "ZIGO046",
        .message = try std.fmt.allocPrint(allocator, "callback failure result declared on parameter `{s}`, which is not a callback", .{parameter.name}),
        .site = functionSiteFor(function, declaration),
        .hint = "use `.on_callback_failure` only on a callback type entry or callback parameter",
    };
    const result = parameter.type.callback.@"return".*;
    if (result == .void) return .{
        .severity = .@"error",
        .code = "ZIGO046",
        .message = try std.fmt.allocPrint(allocator, "callback `{s}` cannot declare a failure result because it returns void", .{parameter.name}),
        .site = functionSiteFor(function, declaration),
        .hint = "remove `.on_callback_failure`, or give the callback a scalar return type",
    };
    if (callbackFailureValueFits(document, result, failure.result)) return null;
    return .{
        .severity = .@"error",
        .code = "ZIGO046",
        .message = try std.fmt.allocPrint(allocator, "callback failure result {d} does not fit callback `{s}`'s return type", .{ failure.result, parameter.name }),
        .site = functionSiteFor(function, declaration),
        .hint = "choose a `.result` value representable by the callback return type",
    };
}

fn callbackFailureValueFits(document: semantic.Semantic, node: semantic.TypeNode, value: i128) bool {
    return switch (node) {
        .bool => value == 0 or value == 1,
        .int => |integer| blk: {
            if (integer.bits == 0 or integer.bits > 64) break :blk false;
            if (integer.signed) {
                const magnitude = @as(i128, 1) << @intCast(integer.bits - 1);
                break :blk value >= -magnitude and value < magnitude;
            }
            break :blk value >= 0 and value < (@as(i128, 1) << @intCast(integer.bits));
        },
        .float => true,
        .@"enum" => |enum_ref| blk: {
            for (document.types) |declaration| {
                if (declaration.kind != .@"enum" or !std.mem.eql(u8, declaration.name, enum_ref.ref)) continue;
                const tag = declaration.tag_type orelse break :blk false;
                break :blk callbackFailureValueFits(document, tag, value);
            }
            break :blk false;
        },
        else => false,
    };
}

fn callbackContractIssue(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    parameter: semantic.Parameter,
) !?diagnostic.Diagnostic {
    const field = if (parameter.reentrancy != null)
        "reentrancy"
    else if (parameter.thread != null)
        "thread"
    else
        return null;
    if (parameter.type == .callback) return null;
    const declaration = try functionDeclarationAlloc(allocator, function);
    return .{
        .severity = .@"error",
        .code = "ZIGO025",
        .message = try std.fmt.allocPrint(
            allocator,
            "`{s}` declared on parameter `{s}`, which is not a callback",
            .{ field, parameter.name },
        ),
        .site = functionSiteFor(function, declaration),
        .hint = try std.fmt.allocPrint(allocator, "use `.{s}` only on a function-pointer parameter", .{field}),
    };
}

/// carry the adapter anywhere the shim cannot see.
fn streamParameterIssue(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    parameter: semantic.Parameter,
) !?diagnostic.Diagnostic {
    // A document that validates must not allocate, so the declaration text is
    // only built once something is known to be wrong with it.
    const offends = (parameter.type != .io_stream and containsIoStream(parameter.type)) or
        (parameter.type == .io_stream and parameter.retention == .retained) or
        (parameter.buffer != null and parameter.type != .io_stream) or
        (parameter.buffer != null and (parameter.buffer.? < semantic.min_stream_buffer or parameter.buffer.? > semantic.max_stream_buffer));
    if (!offends) return null;
    const declaration = try functionDeclarationAlloc(allocator, function);
    if (parameter.type != .io_stream and containsIoStream(parameter.type)) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = try std.fmt.allocPrint(
            allocator,
            "`*std.Io.Writer` and `*std.Io.Reader` are only supported as whole parameters, not inside parameter `{s}`",
            .{parameter.name},
        ),
        .site = functionSiteFor(function, declaration),
        .hint = "pass the stream as its own parameter; it cannot travel inside an optional, a slice, a callback signature, or a union payload",
    };
    if (parameter.type == .io_stream and parameter.retention == .retained) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = try std.fmt.allocPrint(allocator, "stream parameter `{s}` cannot be retained", .{parameter.name}),
        .site = functionSiteFor(function, declaration),
        .hint = "drop `.retention = .retained`; the shim adapter lives on the call stack and is invalid once the call returns",
    };
    const buffer = parameter.buffer orelse return null;
    if (parameter.type != .io_stream) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = try std.fmt.allocPrint(allocator, "buffer hint declared on parameter `{s}`, which is not a stream", .{parameter.name}),
        .site = functionSiteFor(function, declaration),
        .hint = "use `.buffer` only on a `*std.Io.Writer` or `*std.Io.Reader` parameter",
    };
    if (buffer < semantic.min_stream_buffer or buffer > semantic.max_stream_buffer) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = try std.fmt.allocPrint(
            allocator,
            "stream buffer {d} on parameter `{s}` is outside {d}..{d}",
            .{ buffer, parameter.name, semantic.min_stream_buffer, semantic.max_stream_buffer },
        ),
        .site = functionSiteFor(function, declaration),
        .hint = "choose a buffer between 4096 and 16777216 bytes, or drop `.buffer` for the 65536 default",
    };
    return null;
}

/// True when a stream appears anywhere in the node, including as the node
/// itself. Callers that allow the whole-parameter position test the tag first.
fn containsIoStream(node: semantic.TypeNode) bool {
    return switch (node) {
        .io_stream => true,
        .slice => |value| containsIoStream(value.element.*),
        .optional => |value| containsIoStream(value.child.*),
        .error_union => |value| containsIoStream(value.payload.*),
        .callback => |value| blk: {
            for (value.params) |parameter| if (containsIoStream(parameter)) break :blk true;
            break :blk containsIoStream(value.@"return".*);
        },
        else => false,
    };
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
        })) |issue| {
            var result = issue;
            result.note = try invalidTypeNameNoteAlloc(allocator, declaration);
            return result;
        }
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
                result.note = try invalidMemberNameNoteAlloc(allocator, member_label, field.name);
                return result;
            }
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
            .source = function.source,
            .hint = "give the entry a `.name` that converts to a Go identifier",
        })) |issue| {
            var result = issue;
            result.note = try functionOrConstructorRenameNoteAlloc(allocator, document, function);
            return result;
        }
    }
    return null;
}

/// The C header has one ordinary identifier namespace shared by typedefs,
/// exported functions, and macros. Check the exact names lowering will emit
/// for both backends before generation writes an uncompilable header.
fn cIdentifierIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    if (try cIdentifierBackendIssue(allocator, document, false)) |issue| return issue;
    return cIdentifierBackendIssue(allocator, document, true);
}

fn cIdentifierBackendIssue(allocator: std.mem.Allocator, document: semantic.Semantic, purego: bool) !?diagnostic.Diagnostic {
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
        const label = try std.fmt.allocPrint(scratch, "function `{s}`", .{try functionDeclarationAlloc(scratch, function)});
        // A constructor's symbol is named after the type it builds, so a
        // collision on it is answered by renaming that type.
        const note: CIdentifierOrigin.Note = if (constructorInitFor(document, function)) |constructor|
            .{ .type = try typeNameRenameNoteAlloc(scratch, constructor.type, .@"opaque") }
        else
            .{ .function = try functionRenameNoteAlloc(scratch, function) };
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

fn nameIssue(allocator: std.mem.Allocator, check: NameCheck) !?diagnostic.Diagnostic {
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
        if (suffix.len != 0 and naming.isGoIdentifier(candidate)) return null;
    } else if (naming.isGoIdentifier(candidate)) return null;
    const message = if (check.zig_path) |path|
        try std.fmt.allocPrint(allocator, "{s} `{s}` from Zig type `{s}` is not a valid Go identifier", .{ check.label, check.spelling, path })
    else
        try std.fmt.allocPrint(allocator, "{s} `{s}` is not a valid Go identifier", .{ check.label, check.spelling });
    const site: diagnostic.Site = if (check.source) |source| .{
        .path = source.path,
        .declaration = check.declaration,
        .line = source.line,
        .column = source.column,
    } else .{ .path = "semantic.json", .declaration = check.declaration };
    return .{
        .severity = .@"error",
        .code = "ZIGO021",
        .message = message,
        .site = site,
        .hint = check.hint,
    };
}

fn typeRenameNoteAlloc(allocator: std.mem.Allocator, declaration: semantic.TypeDecl) ![]u8 {
    return typeNameRenameNoteAlloc(allocator, declaration.name, declaration.kind);
}

fn retentionNoteAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]u8 {
    const path = try functionDeclarationAlloc(allocator, function);
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

fn functionRenameNoteAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]u8 {
    const converted = try naming.pascalAlloc(allocator, function.name);
    defer allocator.free(converted);
    const public_name = try validGoNameAlloc(allocator, converted, "Function");
    defer allocator.free(public_name);
    const path = try functionDeclarationAlloc(allocator, function);
    defer allocator.free(path);
    return std.fmt.allocPrint(allocator, "consider .name = \"{s}Binding\" on function {s}", .{ public_name, path });
}

fn functionOrConstructorRenameNoteAlloc(allocator: std.mem.Allocator, document: semantic.Semantic, function: semantic.SemanticFn) ![]u8 {
    if (constructorInitFor(document, function)) |constructor| {
        for (document.types) |declaration| {
            if (std.mem.eql(u8, declaration.name, constructor.type)) return typeRenameNoteAlloc(allocator, declaration);
        }
        return typeNameRenameNoteAlloc(allocator, constructor.type, .@"opaque");
    }
    return functionRenameNoteAlloc(allocator, function);
}

fn invalidTypeNameNoteAlloc(allocator: std.mem.Allocator, declaration: semantic.TypeDecl) ![]u8 {
    const converted = try naming.pascalAlloc(allocator, declaration.name);
    defer allocator.free(converted);
    const suggestion = try validGoNameAlloc(allocator, converted, if (declaration.kind == .@"enum") "Enum" else "Type");
    defer allocator.free(suggestion);
    return std.fmt.allocPrint(
        allocator,
        "consider .name = \"{s}\" on type {s}",
        .{ suggestion, declaration.zig_path orelse declaration.name },
    );
}

fn invalidMemberNameNoteAlloc(allocator: std.mem.Allocator, label: []const u8, name: []const u8) ![]u8 {
    const converted = try naming.camelAlloc(allocator, name);
    defer allocator.free(converted);
    const suggestion = try validGoNameAlloc(allocator, converted, "value");
    defer allocator.free(suggestion);
    return std.fmt.allocPrint(allocator, "consider renaming {s} `{s}` to `{s}`", .{ label, name, suggestion });
}

fn memberCollisionNoteAlloc(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const converted = try naming.camelAlloc(allocator, name);
    defer allocator.free(converted);
    const base = try validGoNameAlloc(allocator, converted, "value");
    defer allocator.free(base);
    return std.fmt.allocPrint(allocator, "consider renaming enum tag `{s}` to `{s}Value`", .{ name, base });
}

fn validGoNameAlloc(allocator: std.mem.Allocator, candidate: []const u8, fallback: []const u8) ![]u8 {
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
    if (!naming.isGoIdentifier(result.items)) try result.appendSlice(allocator, "Value");
    return result.toOwnedSlice(allocator);
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
        .void, .bool, .@"enum", .materialized, .opaque_ptr, .value_struct, .io_stream, .cancel_flag => return null,
        .atomic_ptr => return Offense{ .node = node },
        .int => |value| {
            if (integerSupported(value)) return null;
            if (promotable and promotableInteger(value)) return null;
            return Offense{ .node = node, .reason = if (promotableInteger(value)) .narrow_position else .unsupported };
        },
        .float => |value| return if (floatSupported(value)) null else Offense{ .node = node },
        // `?T` only has an ABI shape as a whole parameter, return value, or
        // error payload -- `promotable` doubles as "is this that position"
        // for every caller here, so a slice element or callback signature
        // reaches this the same way a bare unsupported type would. The
        // allowed children are the ones `walk.zig` can reflect: bool, an
        // integer (narrow ones promoted exactly as a bare parameter would
        // be), float, enum, or an extern struct (checked for `extern`-ness by
        // `unsupportedValueStruct`, not here).
        .optional => |value| {
            if (!promotable) return Offense{ .node = node };
            return switch (value.child.*) {
                .bool, .@"enum", .value_struct => null,
                .int => |integer| if (integerSupported(integer) or promotableInteger(integer))
                    null
                else
                    Offense{ .node = value.child.*, .reason = .unsupported },
                .float => |float| if (floatSupported(float)) null else Offense{ .node = value.child.* },
                // `?[]T` spends the slice's own pointer on absence, so the
                // element rules are exactly the slice ones. A slice of slices
                // is the exception: its lowering builds a second array of
                // pointers, and there is no NULL left to mean absent.
                .slice => |slice| if (slice.element.* == .slice)
                    Offense{ .node = node }
                else
                    wrapOffense(allocator, try typeOffense(allocator, slice.element.*, false), "the slice element"),
                else => Offense{ .node = node },
            };
        },
        // A direct slice of narrow integers has a promoted C element type and
        // is converted element by element by the shim. Sentinel slices retain
        // their existing rule.
        .slice => |value| return wrapOffense(
            allocator,
            try typeOffense(allocator, value.element.*, value.sentinel == null and value.element.* == .int),
            "the slice element",
        ),
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
            .site = functionSiteFor(function, declaration),
            .hint = "zigo widens narrow integers only as whole values or direct non-sentinel slice elements; value-struct fields, union payloads, callbacks, and nested slices must use 8, 16, 32, or 64 bits",
        } else .{
            .severity = .@"error",
            .code = "ZIGO018",
            .message = try std.fmt.allocPrint(allocator, "unsupported integer width `{s}` in {s}", .{ spelling, location }),
            .site = functionSiteFor(function, declaration),
            .hint = "use an integer of 64 bits or fewer",
        },
        .float => .{
            .severity = .@"error",
            .code = "ZIGO018",
            .message = try std.fmt.allocPrint(allocator, "unsupported float width `{s}` in {s}", .{ spelling, location }),
            .site = functionSiteFor(function, declaration),
            .hint = "use `f32` or `f64`",
        },
        // `?T` has a C shape only as a whole parameter, return value, or
        // error payload; anywhere else there is nowhere to put presence, so
        // the generic hint would send the reader looking for the wrong fix.
        .optional => .{
            .severity = .@"error",
            .code = "ZIGO019",
            .message = try std.fmt.allocPrint(allocator, "unsupported optional in {s}", .{location}),
            .site = functionSiteFor(function, declaration),
            .hint = "zigo carries an optional only as a whole parameter, return value, or error payload, and only over a bool, integer, float, enum, extern struct, or pointer to a declared opaque type",
        },
        else => .{
            .severity = .@"error",
            .code = "ZIGO019",
            .message = try std.fmt.allocPrint(allocator, "unsupported type `{s}` in {s}", .{ spelling, location }),
            .site = functionSiteFor(function, declaration),
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

/// The `Site` a function- or parameter-level diagnostic points at: the
/// function's own AST location when `names.zig` recorded one, else the
/// `semantic.json` fallback every diagnostic used before source locations
/// existed. `declaration` stays whatever the caller already had -- usually
/// `function.name` or a dotted owner path -- so this only ever changes
/// `path`/`line`/`column`.
fn functionSiteFor(function: semantic.SemanticFn, declaration: []const u8) diagnostic.Site {
    if (function.source) |source| return .{
        .path = source.path,
        .declaration = declaration,
        .line = source.line,
        .column = source.column,
    };
    return .{ .path = "semantic.json", .declaration = declaration };
}

fn functionSite(function: semantic.SemanticFn) diagnostic.Site {
    return functionSiteFor(function, function.name);
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
        } else if (declaration.tag_type) |tag| {
            // A tagged union names its tag enum through `tag_type`, and
            // lowering resolves that reference the same way it resolves a
            // field's: an unresolved one has to be reported here, not met as
            // an `unreachable` inside `lower`.
            if (!referencesValid(document, tag)) return declaration.name;
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
            // A flattened parameter's selected fields are lowered on their
            // own, so their references have to resolve on their own too.
            if (parameter.flatten) |fields| {
                for (fields) |field| if (!referencesValid(document, field.type)) return function.name;
            }
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
        .value_struct => |value| hasTypeKind(document, value.ref, .value_struct) or hasTypeKind(document, value.ref, .tagged_union),
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

fn taggedUnionValueDeclaration(document: semantic.Semantic, node: semantic.TypeNode) ?semantic.TypeDecl {
    if (node != .value_struct) return null;
    for (document.types) |declaration| {
        if (declaration.kind == .tagged_union and std.mem.eql(u8, declaration.name, node.value_struct.ref))
            return declaration;
    }
    return null;
}

/// The first variant that prevents a tagged union from crossing as flattened
/// scalar arguments. The field name is returned so ZIGO006 identifies the
/// actionable payload rather than suggesting the unrelated pointer-handle API.
fn taggedUnionValueIneligibleVariant(document: semantic.Semantic, declaration: semantic.TypeDecl) ?[]const u8 {
    if (declaration.fields.len == 0) return declaration.name;
    for (declaration.fields) |field| {
        if (declaration.variantOmitted(field.name)) continue;
        const payload = field.type orelse return field.name;
        if (payload != .void and !taggedUnionValuePayloadSupported(document, payload)) return field.name;
    }
    return null;
}

fn taggedUnionValuePayloadSupported(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .bool => true,
        .int => |value| integerSupported(value),
        .float => |value| floatSupported(value),
        .@"enum" => |value| hasTypeKind(document, value.ref, .@"enum"),
        .value_struct => |value| for (document.types) |declaration| {
            if (!std.mem.eql(u8, declaration.name, value.ref) or declaration.kind != .value_struct) continue;
            break switch (declaration.layout orelse return false) {
                .@"packed" => declaration.backing_type != null and declaration.backing_type.? == .int and
                    promotableInteger(declaration.backing_type.?.int),
                .@"extern" => externStructProblem(document, declaration, 0) == null,
            };
        } else false,
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
        .value_struct => isPackedValue(document, node),
        else => false,
    };
}

fn isPackedValue(document: semantic.Semantic, node: semantic.TypeNode) bool {
    if (node != .value_struct) return false;
    for (document.types) |declaration| {
        if (std.mem.eql(u8, declaration.name, node.value_struct.ref))
            return declaration.kind == .value_struct and declaration.layout == .@"packed";
    }
    return false;
}

fn packedStructProblem(document: semantic.Semantic, declaration: semantic.TypeDecl, depth: usize) ?[]const u8 {
    if (depth >= 16 or declaration.backing_type == null or declaration.backing_type.? != .int or
        !promotableInteger(declaration.backing_type.?.int)) return declaration.name;
    for (declaration.fields) |field| {
        const node = field.type orelse return field.name;
        switch (node) {
            .bool, .int => {},
            .@"enum" => |value| if (!hasTypeKind(document, value.ref, .@"enum")) return field.name,
            .value_struct => |value| {
                var found = false;
                for (document.types) |nested| {
                    if (!std.mem.eql(u8, nested.name, value.ref)) continue;
                    found = true;
                    if (nested.kind != .value_struct or nested.layout != .@"packed" or
                        packedStructProblem(document, nested, depth + 1) != null) return field.name;
                    break;
                }
                if (!found) return field.name;
            },
            else => return field.name,
        }
    }
    return null;
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
            break nested.kind == .value_struct and ((nested.layout == .@"extern" and
                externStructProblem(document, nested, depth + 1) == null) or
                (nested.layout == .@"packed" and packedStructProblem(document, nested, depth + 1) == null));
        } else false,
        else => scalarPayloadSupported(document, node),
    };
}

/// True when a value struct appears anywhere other than as a whole parameter,
/// return value, error-union payload, or direct slice element. Those positions
/// lower to a pointer to the struct (or a pointer-plus-length pair for slices);
/// optional and callback signatures still do not have an aggregate ABI shape.
fn nestedValueStruct(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        // A direct value-struct node is a supported aggregate position.
        .value_struct => false,
        // The slice lowering already carries the element as `T*`; only the
        // direct element is allowed. A slice of optional/slice/callback values
        // would still contain the struct in an unsupported nested position.
        .slice => |value| switch (value.element.*) {
            .value_struct => false,
            else => containsUnsupportedNestedValueStruct(document, value.element.*),
        },
        // `?ExternStruct` lowers to a single nullable pointer, the same
        // aggregate-friendly shape a bare value struct gets, so the whole
        // position is supported; only a struct nested *inside* the child
        // (there is none reachable today) would still be unsupported.
        // `?ExternStruct` lowers to a single nullable pointer, the same
        // aggregate-friendly shape a bare value struct gets. `?[]Point` does
        // not: the optional slice lowering has no place for the element
        // conversion the bare slice one performs.
        .optional => |value| switch (value.child.*) {
            .value_struct => false,
            else => containsUnsupportedNestedValueStruct(document, value.child.*),
        },
        .error_union => |value| nestedValueStruct(document, value.payload.*),
        else => containsUnsupportedNestedValueStruct(document, node),
    };
}

fn containsUnsupportedNestedValueStruct(document: semantic.Semantic, node: semantic.TypeNode) bool {
    if (node == .value_struct) return !isPackedValue(document, node);
    return switch (node) {
        .slice => |value| containsUnsupportedNestedValueStruct(document, value.element.*),
        .optional => |value| containsUnsupportedNestedValueStruct(document, value.child.*),
        .error_union => |value| containsUnsupportedNestedValueStruct(document, value.payload.*),
        .callback => |value| blk: {
            for (value.params) |parameter| if (containsUnsupportedNestedValueStruct(document, parameter)) break :blk true;
            break :blk containsUnsupportedNestedValueStruct(document, value.@"return".*);
        },
        else => false,
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

/// The narrow integer directly carried by a plain slice parameter or return.
/// Optional and sentinel forms deliberately do not qualify: their ABI shapes
/// are separate features and remain rejected by the ordinary type walk.
fn narrowSliceElement(node: semantic.TypeNode) ?semantic.TypeNode {
    const payload = if (node == .error_union) node.error_union.payload.* else node;
    if (payload != .slice or payload.slice.sentinel != null) return null;
    return if (abiNarrowInt(payload.slice.element.*)) payload.slice.element.* else null;
}

fn abiNarrowInt(node: semantic.TypeNode) bool {
    if (node != .int) return false;
    const value = node.int;
    return promotableInteger(value) and !integerSupported(value);
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

/// The registered opaque type behind a borrowed result. Optional pointers are
/// represented by `opaque_ptr.nullable`; error unions wrap the same node.
fn borrowedOpaqueReturn(document: semantic.Semantic, function: semantic.SemanticFn) ?[]const u8 {
    const payload = if (function.@"return" == .error_union) function.@"return".error_union.payload.* else function.@"return";
    if (payload != .opaque_ptr or !hasTypeKind(document, payload.opaque_ptr.ref, .@"opaque")) return null;
    return payload.opaque_ptr.ref;
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
    return releasableSliceReturnElement(function) != null;
}

/// The release target must exist and take exactly the returned slice, otherwise
/// the generated free call would pass a pointer the library cannot interpret.
fn releaseTargetIssue(document: semantic.Semantic, function: semantic.SemanticFn) ?diagnostic.Diagnostic {
    const missing: diagnostic.Diagnostic = .{
        .severity = .@"error",
        .code = "ZIGO016",
        .message = "caller-owned slice return has no matching release function",
        .site = functionSite(function),
        .hint = "add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type",
    };
    const name = function.release orelse return missing;
    for (document.functions) |candidate| {
        if (!std.mem.eql(u8, candidate.name, name)) continue;
        if (candidate.@"return" != .void) return missing;
        // An injected argument is not part of the signature the release call
        // has to match: the shim fills it in, so a `fn(gpa, slice) void` frees
        // exactly the same slice a `fn(slice) void` does.
        const parameter = onlyExposedParameter(candidate.params) orelse return missing;
        if (parameter.direction != .in or parameter.type != .slice) return missing;
        if (!typeNodeEqual(parameter.type.slice.element.*, releasableSliceReturnElement(function).?)) return missing;
        return null;
    }
    return missing;
}

/// The one parameter a release target passes on from Go, or null when it takes
/// any other number of them. Injected arguments do not count: they never reach
/// the C signature the release call goes through.
fn onlyExposedParameter(params: []const semantic.Parameter) ?semantic.Parameter {
    var found: ?semantic.Parameter = null;
    for (params) |parameter| {
        if (parameter.injected != null) continue;
        if (found != null) return null;
        found = parameter;
    }
    return found;
}

/// The element of a slice return that needs a release target, or null when
/// the function returns something else. This is the ownership question, not
/// the calling-convention one: a caller-owned C-string return counts here
/// because it still has to be freed, even though `emit.sliceReturnElement`
/// excludes it -- that one asks which returns cross as an out-pointer plus
/// length. Optional and error-union wrappers do not change the ownership of
/// the underlying slice.
fn releasableSliceReturnElement(function: semantic.SemanticFn) ?semantic.TypeNode {
    const payload = switch (function.@"return") {
        .error_union => |value| value.payload.*,
        else => function.@"return",
    };
    const slice = switch (payload) {
        .optional => |value| value.child.*,
        else => payload,
    };
    return switch (slice) {
        .slice => |value| value.element.*,
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
        .materialized => |value| value.pointer == rhs.materialized.pointer and value.nullable == rhs.materialized.nullable and std.mem.eql(u8, value.ref, rhs.materialized.ref),
        .value_struct => |value| std.mem.eql(u8, value.ref, rhs.value_struct.ref),
        .slice => |value| value.@"const" == rhs.slice.@"const" and typeNodeEqual(value.element.*, rhs.slice.element.*),
        else => false,
    };
}

fn isMaterializedReturn(node: semantic.TypeNode) bool {
    const payload = if (node == .error_union) node.error_union.payload.* else node;
    return payload == .materialized or (payload == .slice and payload.slice.element.* == .materialized);
}

fn materializedReleaseTargetIssue(document: semantic.Semantic, function: semantic.SemanticFn) ?diagnostic.Diagnostic {
    const missing: diagnostic.Diagnostic = .{
        .severity = .@"error",
        .code = "ZIGO048",
        .message = "materialized result has no matching buffer release function",
        .site = functionSite(function),
        .hint = "name an exposed `fn([]u8) void` release function that frees the serialized buffer with the registered allocator",
    };
    const name = function.release orelse return missing;
    for (document.functions) |candidate| {
        if (!std.mem.eql(u8, candidate.name, name) or candidate.@"return" != .void) continue;
        const parameter = onlyExposedParameter(candidate.params) orelse return missing;
        if (parameter.type != .slice or parameter.type.slice.element.* != .int or
            parameter.type.slice.element.int.bits != 8 or parameter.type.slice.element.int.signed) return missing;
        return null;
    }
    return missing;
}

fn isMaterializedReleaseTarget(document: semantic.Semantic, candidate: semantic.SemanticFn) bool {
    for (document.functions) |function| {
        if (isMaterializedReturn(function.@"return") and function.release != null and
            std.mem.eql(u8, function.release.?, candidate.name)) return true;
    }
    return false;
}

fn hasConstructorInit(document: semantic.Semantic, constructor: semantic.Constructor) bool {
    for (document.functions) |function| {
        if (!std.mem.eql(u8, function.name, constructor.init) or
            !std.mem.eql(u8, function.goOwner() orelse "", constructor.type)) continue;
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
        // An injected parameter is not part of the C signature, so a
        // destructor that takes the allocator back is still a destructor.
        for (function.params) |parameter| if (parameter.injected == null) return false;
        return function.@"return" == .void;
    }
    return false;
}

/// The constructor a function serves as `.init` for, if any. A boxed `create`
/// reaches the public API as `New<Type>` rather than the
/// pascal-cased Zig name, so the collision check must resolve it the same way
/// or it would flag two unrelated constructors (`Counter.create`,
/// `Context.create`) as though they shared a Go identifier.
fn constructorInitFor(document: semantic.Semantic, function: semantic.SemanticFn) ?semantic.Constructor {
    for (document.constructors) |constructor| {
        if (std.mem.eql(u8, constructor.init, function.name) and
            std.mem.eql(u8, constructor.type, function.goOwner() orelse "")) return constructor;
    }
    return null;
}

/// The constructor pairing a method serves as `.deinit` for, if any. That
/// method never reaches the public API on its own -- generation emits a
/// shared `zigoRelease` instead -- so it takes no public Go name and drops
/// out of the collision check entirely.
fn constructorDeinitFor(document: semantic.Semantic, function: semantic.SemanticFn) ?semantic.Constructor {
    const receiver = function.receiver orelse return null;
    for (document.constructors) |constructor| {
        if (std.mem.eql(u8, constructor.type, receiver) and
            std.mem.eql(u8, constructor.deinit, function.name)) return constructor;
    }
    return null;
}

/// The public Go name a function reaches generated code under, ignoring the
/// receiver: a method's name is scoped by its receiver type, so two methods
/// on different receivers never collide even when this returns the same
/// spelling for both. Constructors are the one function shape whose public
/// name is not simply the pascal-cased Zig name (see `constructorInitFor`).
fn effectivePublicFunctionNameAlloc(allocator: std.mem.Allocator, document: semantic.Semantic, function: semantic.SemanticFn) ![]u8 {
    if (constructorInitFor(document, function)) |constructor| {
        if (constructor.name) |name| return naming.pascalAlloc(allocator, name);
        return std.fmt.allocPrint(allocator, "New{s}", .{constructor.type});
    }
    return naming.pascalAlloc(allocator, function.name);
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

test "generated Must names participate in ZIGO024 collision checks" {
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "ping",
                .params = &.{},
                .receiver = "Handle",
                .@"return" = .{ .void = {} },
                .symbol = "zg_handle_ping",
            },
            .{
                .name = "mustPing",
                .params = &.{},
                .receiver = "Handle",
                .@"return" = .{ .void = {} },
                .symbol = "zg_handle_must_ping",
            },
        },
        .package = "collision",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Handle" }},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const issue = (try findMustVariantIssue(arena.allocator(), document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO024", issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "MustPing") != null);
    try std.testing.expectError(error.InvalidSemantic, mustVariantNames(std.testing.allocator, document));
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
                    break :blk if (declaration.layout != .@"extern" and declaration.layout != .@"packed") declaration.name else null;
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

fn byValueOpaqueReturn(node: semantic.TypeNode) ?semantic.OpaquePtr {
    const payload = if (node == .error_union) node.error_union.payload.* else node;
    if (payload != .opaque_ptr or !payload.opaque_ptr.by_value) return null;
    return payload.opaque_ptr;
}

fn isFlattenLeaf(document: semantic.Semantic, node: semantic.TypeNode) bool {
    const leaf = if (node == .optional) node.optional.child.* else node;
    return leaf == .bool or leaf == .int or leaf == .float or leaf == .@"enum" or isPackedValue(document, leaf);
}

fn containsPointer(node: semantic.TypeNode) bool {
    return switch (node) {
        .opaque_ptr, .slice, .callback => true,
        .materialized => |value| value.pointer,
        .optional => |value| containsPointer(value.child.*),
        else => false,
    };
}

fn containsMaterialized(node: semantic.TypeNode) bool {
    return switch (node) {
        .materialized => true,
        .slice => |value| containsMaterialized(value.element.*),
        .optional => |value| containsMaterialized(value.child.*),
        .error_union => |value| containsMaterialized(value.payload.*),
        .callback => |value| blk: {
            for (value.params) |parameter| if (containsMaterialized(parameter)) break :blk true;
            break :blk containsMaterialized(value.@"return".*);
        },
        else => false,
    };
}

const MaterializedProblem = struct { path: []const u8, reason: []const u8 };

fn materializedProblemAlloc(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    root: semantic.TypeDecl,
) !?MaterializedProblem {
    var ancestors: [128][]const u8 = undefined;
    ancestors[0] = root.name;
    for (root.fields) |field| {
        const node = field.type orelse return .{
            .path = try allocator.dupe(u8, field.name),
            .reason = "give every materialized field a reflected type",
        };
        if (try materializedNodeProblemAlloc(allocator, document, node, field.name, &ancestors, 1, false)) |problem| return problem;
    }
    return null;
}

fn materializedNodeProblemAlloc(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    node: semantic.TypeNode,
    path: []const u8,
    ancestors: *[128][]const u8,
    depth: usize,
    in_slice: bool,
) !?MaterializedProblem {
    switch (node) {
        .bool => return null,
        .int => |value| if (integerSupported(value)) return null,
        .float => |value| if (floatSupported(value)) return null,
        .@"enum" => return null,
        .slice => |value| {
            const element = value.element.*;
            if (element == .slice) {
                const inner = element.slice.element.*;
                if (inner == .int and inner.int.bits == 8 and !inner.int.signed) return null;
                return .{ .path = try allocator.dupe(u8, path), .reason = "slices may contain scalars, strings, or materialized structs" };
            }
            return materializedNodeProblemAlloc(allocator, document, element, path, ancestors, depth, true);
        },
        .materialized => |value| {
            if (in_slice and value.pointer) return .{ .path = try allocator.dupe(u8, path), .reason = "slices may contain materialized struct values, not pointers" };
            for (ancestors[0..depth]) |ancestor| if (std.mem.eql(u8, ancestor, value.ref)) return .{
                .path = try allocator.dupe(u8, path),
                .reason = "materialized trees cannot contain cycles",
            };
            const declaration = findTypeDecl(document, value.ref) orelse return .{
                .path = try allocator.dupe(u8, path),
                .reason = "register the referenced struct with `.repr = .materialized`",
            };
            if (declaration.kind != .materialized or depth == ancestors.len) return .{
                .path = try allocator.dupe(u8, path),
                .reason = "register the referenced struct with `.repr = .materialized`",
            };
            ancestors[depth] = value.ref;
            for (declaration.fields) |field| {
                const child_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ path, field.name });
                const child = field.type orelse return .{ .path = child_path, .reason = "give every materialized field a reflected type" };
                if (try materializedNodeProblemAlloc(allocator, document, child, child_path, ancestors, depth + 1, false)) |problem| return problem;
            }
            return null;
        },
        else => {},
    }
    return .{
        .path = try allocator.dupe(u8, path),
        .reason = "use scalars, bool, registered enums, strings, supported slices, or materialized structs and pointers",
    };
}

fn findTypeDecl(document: semantic.Semantic, name: []const u8) ?semantic.TypeDecl {
    for (document.types) |declaration| if (std.mem.eql(u8, declaration.name, name)) return declaration;
    return null;
}

test "materialized validation reports nested unsupported field paths and cycles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var callback_return: semantic.TypeNode = .{ .void = {} };
    const callback: semantic.TypeNode = .{ .callback = .{ .has_userdata = false, .params = &.{}, .@"return" = &callback_return } };
    const bad_leaf = semantic.TypeDecl{
        .fields = &.{.{ .name = "visit", .type = callback }},
        .kind = .materialized,
        .name = "Leaf",
    };
    const leaf_node: semantic.TypeNode = .{ .materialized = .{ .ref = "Leaf", .pointer = true } };
    const root = semantic.TypeDecl{
        .fields = &.{.{ .name = "child", .type = leaf_node }},
        .kind = .materialized,
        .name = "Root",
    };
    const bad_document: semantic.Semantic = .{
        .package = "tree",
        .prefix = "zg",
        .types = &.{ root, bad_leaf },
        .zig_version = "0.16.0",
    };
    const unsupported = (try findIssue(allocator, bad_document)).?;
    try std.testing.expectEqualStrings("ZIGO048", unsupported.code);
    try std.testing.expect(std.mem.indexOf(u8, unsupported.message, "child.visit") != null);

    const root_node: semantic.TypeNode = .{ .materialized = .{ .ref = "Root", .pointer = true, .nullable = true } };
    const cyclic_leaf = semantic.TypeDecl{
        .fields = &.{.{ .name = "parent", .type = root_node }},
        .kind = .materialized,
        .name = "Leaf",
    };
    const cyclic_document: semantic.Semantic = .{
        .package = "tree",
        .prefix = "zg",
        .types = &.{ root, cyclic_leaf },
        .zig_version = "0.16.0",
    };
    const cycle = (try findIssue(allocator, cyclic_document)).?;
    try std.testing.expectEqualStrings("ZIGO048", cycle.code);
    try std.testing.expect(std.mem.indexOf(u8, cycle.message, "child.parent") != null);
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
    var optional_word_node: semantic.TypeNode = .{ .optional = .{ .child = &word_element } };
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
        }, .snapshot = "error[ZIGO002]: cannot expose a non-exhaustive enum\n  --> semantic.json (Open)\n  hint: make the enum exhaustive, or register it with `.exhaustive = false`\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"enum", .name = "Closed", .open = true }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO029]: open-enum opt-in applied to an exhaustive enum\n  --> semantic.json (Closed)\n  hint: remove `.exhaustive = false`, or make the Zig enum non-exhaustive\n" },
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
            .types = &.{
                .{ .fields = &.{.{ .name = "bytes", .type = byte_slice_node, .value = 0 }}, .kind = .tagged_union, .name = "Value", .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } } },
                .{ .fields = &.{.{ .name = "bytes", .value = 0 }}, .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            },
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO006]: cannot pass a tagged union by value\n  --> semantic.json (consume)\n  hint: variant `bytes` has an unsupported value payload; omit it with `.omit_variants` or use void, scalar, enum, packed struct, or extern struct payloads\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "consume",
                .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_consume",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{
                .{ .fields = &.{.{ .name = "child", .type = pointer_node, .value = 0 }}, .kind = .tagged_union, .name = "Value", .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } } },
                .{ .fields = &.{.{ .name = "child", .value = 0 }}, .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
                .{ .kind = .@"opaque", .name = "Thing" },
            },
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO006]: cannot pass a tagged union by value\n  --> semantic.json (consume)\n  hint: variant `child` has an unsupported value payload; omit it with `.omit_variants` or use void, scalar, enum, packed struct, or extern struct payloads\n" },
        .{ .document = .{
            .functions = &.{
                .{ .name = "lookupID", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
                .{ .name = "lookup_id", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
            },
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO036]: C identifier `zg_lookup_id` collides between function `lookupID` and function `lookup_id`\n  --> semantic.json (function `lookup_id`)\n  hint: give one declaration a distinct `.name`, or choose a different binding `.prefix`\n  note: consider .name = \"LookupIDBinding\" on function lookup_id\n" },
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
        }, .snapshot = "error[ZIGO009]: retained pointer has no matching release function\n  --> semantic.json (remember)\n  hint: expose a release, clear, close, destroy, or deinit function for the retained value\n  note: consider exposing `pub fn release() void` alongside `remember`\n" },
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
        }, .snapshot = "error[ZIGO045]: narrow integer slice parameter `cps` needs temporary storage\n  --> semantic.json (widths)\n  hint: set `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator`, or a declaration path in the binding\n" },
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
        }, .snapshot = "error[ZIGO018]: cannot promote integer width `u21` in callback parameter 0 of parameter `callback`\n  --> semantic.json (onCodepoint)\n  hint: zigo widens narrow integers only as whole values or direct non-sentinel slice elements; value-struct fields, union payloads, callbacks, and nested slices must use 8, 16, 32, or 64 bits\n" },
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
                .params = &.{.{ .name = "value", .type = .{ .optional = .{ .child = &optional_word_node } } }},
                .@"return" = .{ .void = {} },
                .receiver = "Thing",
                .symbol = "zg_thing_maybe",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Thing" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO019]: unsupported optional in parameter `value`\n  --> semantic.json (Thing.maybe)\n  hint: zigo carries an optional only as a whole parameter, return value, or error payload, and only over a bool, integer, float, enum, extern struct, or pointer to a declared opaque type\n" },
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
        }, .snapshot = "error[ZIGO021]: registered type name `4])` from Zig type `vt.lib.Enum([_][]const u8{ \"block\", \"bar\" }[0..4])` is not a valid Go identifier\n  --> semantic.json (4]))\n  hint: register the type in `.types` with an explicit `.name` that is a Go identifier\n  note: consider .name = \"Enum4\" on type vt.lib.Enum([_][]const u8{ \"block\", \"bar\" }[0..4])\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "_", .value = 0 }},
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: enum tag `_` is not a valid Go identifier\n  --> semantic.json (Mode)\n  hint: rename the declaration in Zig so its name converts to a Go identifier\n  note: consider renaming enum tag `_` to `value`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "open",
                .params = &.{.{ .injected = .allocator, .name = "alloc", .type = .{ .void = {} } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_open",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO022]: parameter `alloc` needs a `std.mem.Allocator` the binding has not named\n  --> semantic.json (open)\n  hint: set `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator`, or a declaration path in the binding\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "flush",
                .params = &.{.{ .injected = .io, .name = "io", .type = .{ .void = {} } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_flush",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO022]: parameter `io` needs a `std.Io` the binding has not named\n  --> semantic.json (flush)\n  hint: set `.io = \"<declaration path>\"` in the binding\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "range" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: registered type name `range` is not a valid Go identifier\n  --> semantic.json (range)\n  hint: register the type in `.types` with an explicit `.name` that is a Go identifier\n  note: consider .name = \"Range\" on type range\n" },
        // `open` in namespace `File` and `open` in namespace `Socket` have no
        // receiver, so `ZIGO007`'s symbol check tells them apart (their C
        // symbols carry the namespace) but the public Go layer drops it: both
        // resolve to the top-level function `Open`.
        .{ .document = .{
            .functions = &.{
                .{ .name = "open", .namespace = "File", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_file_open" },
                .{ .name = "open", .namespace = "Socket", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_socket_open" },
            },
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO024]: public Go name `Open` collides between `File.open` and `Socket.open`\n  --> semantic.json (Socket.open)\n  hint: rename one declaration, or give it a `.name` that resolves to a different Go identifier\n  note: consider .name = \"OpenBinding\" on function Socket.open\n" },
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

test "child-of-receiver metadata on a non-receiver constructor has a stable diagnostic" {
    var child: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Child" } };
    const document: semantic.Semantic = .{
        .constructors = &.{.{ .type = "Child", .init = "newChild", .deinit = "freeChild" }},
        .functions = &.{
            .{
                .child_of_receiver = true,
                .go_owner = "Child",
                .name = "newChild",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{}, .payload = &child } },
                .symbol = "zg_new_child",
            },
            .{ .name = "freeChild", .params = &.{}, .receiver = "Child", .@"return" = .{ .void = {} }, .symbol = "zg_child_free_child" },
        },
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Child" }},
        .zig_version = "0.16.0",
    };
    const issue = (try findIssue(std.testing.allocator, document)) orelse return error.MissingDiagnostic;
    const rendered = try issue.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        "error[ZIGO030]: child-of-receiver metadata requires a receiver constructor\n" ++
            "  --> semantic.json (newChild)\n" ++
            "  hint: use `.child_of_receiver = true` only on a constructor method that returns its paired caller-owned handle\n",
        rendered,
    );
}

test "borrowed return ownership diagnostics are stable" {
    const pointer: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "View" } };
    const base: semantic.Semantic = .{
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "View" }},
        .zig_version = "0.16.0",
    };
    const cases = [_]struct { function: semantic.SemanticFn, snapshot: []const u8 }{
        .{ .function = .{
            .borrowed_return = true,
            .name = "view",
            .params = &.{},
            .@"return" = pointer,
            .symbol = "zg_view",
        }, .snapshot = "error[ZIGO033]: borrowed return has no receiver to own its lifetime\n  --> semantic.json (view)\n  hint: use `.returns = .borrowed` only on a method, or use `.returns = .caller` with a constructor and destructor\n" },
        .{ .function = .{
            .borrowed_return = true,
            .name = "count",
            .params = &.{},
            .receiver = "Owner",
            .@"return" = .{ .int = .{ .bits = 32, .signed = false } },
            .symbol = "zg_owner_count",
        }, .snapshot = "error[ZIGO034]: borrowed return is not a registered opaque handle\n  --> semantic.json (count)\n  hint: return `*T`, `?*T`, `!*T`, or `!?*T` where T is a registered opaque type, or drop `.returns = .borrowed`\n" },
        .{ .function = .{
            .name = "view",
            .params = &.{},
            .receiver = "Owner",
            .@"return" = pointer,
            .symbol = "zg_owner_view",
        }, .snapshot = "error[ZIGO035]: opaque handle return has no explicit ownership\n  --> semantic.json (view)\n  hint: add `.returns = .borrowed` for a receiver-owned view, or pair `.returns = .caller` with its constructor and destructor\n" },
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    for (cases) |case| {
        var document = base;
        document.functions = @as(*const [1]semantic.SemanticFn, &case.function);
        const issue = (try findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
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

test "narrow integer slices require an allocator and borrowed returns stay rejected" {
    var narrow: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    const narrow_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &narrow } };
    const input_params = [_]semantic.Parameter{.{ .name = "text", .type = narrow_slice }};
    const release_params = [_]semantic.Parameter{.{ .name = "value", .type = narrow_slice }};
    const accepted_functions = [_]semantic.SemanticFn{
        .{ .name = "width", .params = &input_params, .@"return" = .{ .void = {} }, .symbol = "zg_width" },
        .{ .name = "take", .ownership = .caller, .params = &.{}, .release = "free", .@"return" = narrow_slice, .symbol = "zg_take" },
        .{ .name = "free", .params = &release_params, .@"return" = .{ .void = {} }, .symbol = "zg_free" },
    };
    const accepted: semantic.Semantic = .{
        .allocator = "std.heap.c_allocator",
        .functions = &accepted_functions,
        .package = "narrow",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(std.testing.allocator, accepted));

    var missing_allocator = accepted;
    missing_allocator.allocator = null;
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const allocator_issue = (try findIssue(scratch.allocator(), missing_allocator)).?;
    try std.testing.expectEqualStrings("ZIGO045", allocator_issue.code);
    try std.testing.expect(std.mem.indexOf(u8, allocator_issue.hint, ".allocator") != null);

    const borrowed_functions = [_]semantic.SemanticFn{.{
        .name = "view",
        .params = &.{},
        .@"return" = narrow_slice,
        .symbol = "zg_view",
    }};
    var borrowed = accepted;
    borrowed.functions = &borrowed_functions;
    const borrowed_issue = (try findIssue(scratch.allocator(), borrowed)).?;
    try std.testing.expectEqualStrings("ZIGO018", borrowed_issue.code);
    try std.testing.expect(std.mem.indexOf(u8, borrowed_issue.hint, "borrowed narrow slices") != null);
}

test "a release target may take the allocator zigo injects" {
    var byte_element: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const document: semantic.Semantic = .{
        .allocator = "std.heap.smp_allocator",
        .functions = &.{
            .{
                .name = "render",
                .ownership = .caller,
                .params = &.{},
                .release = "freeString",
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &byte_element } },
                .symbol = "zg_render",
            },
            .{
                .name = "freeString",
                .params = &.{
                    .{ .injected = .allocator, .name = "allocator", .type = .{ .void = {} } },
                    .{ .name = "str", .type = .{ .slice = .{ .@"const" = true, .element = &byte_element } } },
                },
                .@"return" = .{ .void = {} },
                .symbol = "zg_free_string",
            },
        },
        .package = "render",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(scratch.allocator(), document));
}

test "caller-owned optional slices use the underlying slice release contract" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var bytes: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    var c_string: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte, .sentinel = 0 } };
    var optional_bytes: semantic.TypeNode = .{ .optional = .{ .child = &bytes } };
    var optional_c_string: semantic.TypeNode = .{ .optional = .{ .child = &c_string } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "takeBytes",
                .ownership = .caller,
                .params = &.{},
                .release = "freeBytes",
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &optional_bytes } },
                .symbol = "zg_take_bytes",
            },
            .{
                .name = "takeCString",
                .ownership = .caller,
                .params = &.{},
                .release = "freeCString",
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &optional_c_string } },
                .return_semantic = .c_string,
                .symbol = "zg_take_c_string",
            },
            .{
                .name = "freeBytes",
                .params = &.{.{ .name = "value", .type = bytes }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_free_bytes",
            },
            .{
                .name = "freeCString",
                .params = &.{.{ .name = "value", .type = c_string }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_free_c_string",
            },
        },
        .package = "good",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try semanticDocument(std.testing.allocator, document);
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

test "scalar extern struct slices and whole optional structs are valid while an optional slice element stays rejected" {
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

    // A whole `?Point` parameter is a supported position: it lowers to a
    // single nullable pointer, the same shape a bare `Point` gets.
    const point_types = [_]semantic.TypeDecl{.{
        .fields = &.{.{ .name = "x", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
        .kind = .value_struct,
        .layout = .@"extern",
        .name = "Point",
    }};
    const optional: semantic.TypeNode = .{ .optional = .{ .child = &element } };
    const valid: semantic.Semantic = .{
        .functions = &.{.{
            .name = "optional",
            .params = &.{.{ .name = "value", .type = optional }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_optional",
        }},
        .package = "good",
        .prefix = "zg",
        .types = &point_types,
        .zig_version = "0.16.0",
    };
    try semanticDocument(std.testing.allocator, valid);

    // `[]?Point`: the struct is nested inside an optional slice element,
    // which has no C ABI shape -- `?T` only lowers as a whole parameter,
    // return value, or error payload.
    var optional_element: semantic.TypeNode = optional;
    const optional_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &optional_element } };
    const invalid: semantic.Semantic = .{
        .functions = &.{.{
            .name = "consumeOptional",
            .params = &.{.{ .name = "values", .type = optional_slice }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_consume_optional",
        }},
        .package = "bad",
        .prefix = "zg",
        .types = &point_types,
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

test "tagged union value parameters accept only scalar and void payloads" {
    const eligible: semantic.Semantic = .{
        .functions = &.{.{
            .name = "consume",
            .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "small", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
                    .{ .name = "active", .type = .{ .bool = {} }, .value = 2 },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } }, .value = 3 },
                },
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{
                    .{ .name = "none", .value = 0 },
                    .{ .name = "small", .value = 1 },
                    .{ .name = "active", .value = 2 },
                    .{ .name = "mode", .value = 3 },
                },
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{
                .fields = &.{.{ .name = "idle", .value = 0 }},
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    try std.testing.expect((try findIssue(std.testing.allocator, eligible)) == null);
}

test "tagged union value parameter names the first ineligible payload" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const cases = [_]struct { name: []const u8, payload: semantic.TypeNode }{
        .{ .name = "bytes", .payload = .{ .slice = .{ .@"const" = true, .element = &byte } } },
        .{ .name = "child", .payload = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Child" } } },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "consume",
                .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "variant",
            .prefix = "zg",
            .types = &.{
                .{
                    .fields = &.{.{ .name = case.name, .type = case.payload, .value = 0 }},
                    .kind = .tagged_union,
                    .name = "Value",
                    .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
                },
                .{ .fields = &.{.{ .name = case.name, .value = 0 }}, .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
                .{ .kind = .@"opaque", .name = "Child" },
                .{ .fields = &.{.{ .name = "count", .type = .{ .int = .{ .bits = 32, .signed = false } } }}, .kind = .value_struct, .layout = .@"extern", .name = "Config" },
            },
            .zig_version = "0.16.0",
        };
        const issue = (try findIssue(arena.allocator(), document)).?;
        try std.testing.expectEqualStrings("ZIGO006", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.hint, case.name) != null);
    }
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
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try findIssue(scratch.allocator(), document)).?;
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
        const issue = (try findIssue(scratch.allocator(), document)).?;
        try std.testing.expectEqualStrings("ZIGO036", issue.code);
    }
}

test "symbol collision validation propagates every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expectSymbolCollision, .{});
}

test "C typedef and function symbol collisions have a stable diagnostic" {
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "select",
            .params = &.{},
            .receiver = "Search",
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "bad",
        .prefix = "zg",
        .types = &.{
            .{ .kind = .@"opaque", .name = "Search" },
            .{
                .fields = &.{.{ .name = "none", .value = 0 }},
                .kind = .@"enum",
                .name = "SearchSelect",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
    const rendered = try issue.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        "error[ZIGO036]: C identifier `zg_search_select` collides between type `SearchSelect` and function `Search.select`\n" ++
            "  --> semantic.json (function `Search.select`)\n" ++
            "  hint: give one declaration a distinct `.name`, or choose a different binding `.prefix`\n" ++
            "  note: consider .name = \"SearchSelectKind\" on type SearchSelect\n",
        rendered,
    );
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
        // A tagged union names its tag enum through `tag_type`; lowering
        // resolves it, so an unresolved one is an integrity problem.
        .{ .document = .{
            .functions = &.{.{
                .name = "take",
                .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "none", .type = .{ .void = {} }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "MissingValueTag" } },
            }},
            .zig_version = "0.16.0",
        }, .declaration = "Value" },
        // A flattened parameter's selected fields are lowered on their own.
        .{ .document = .{
            .functions = &.{.{
                .name = "configure",
                .params = &.{.{
                    .name = "options",
                    .type = .{ .value_struct = .{ .ref = "Options" } },
                    .flatten = &.{.{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "MissingMode" } } }},
                }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
                .kind = .value_struct,
                .name = "Options",
                .layout = .@"extern",
            }},
            .zig_version = "0.16.0",
        }, .declaration = "configure" },
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
    try std.testing.expect((try findIssue(std.testing.allocator, document)) == null);
    try semanticDocument(std.testing.allocator, document);
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
    const issue = (try findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
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
    const issue = (try findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
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
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const issue = (try findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
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

test "a supported packed struct passes and unsupported packed and extern fields are diagnosed" {
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
            .backing_type = .{ .int = .{ .bits = 8, .signed = false } },
            .fields = &.{.{ .name = "enabled", .type = .{ .bool = {} } }},
            .kind = .value_struct,
            .layout = .@"packed",
            .name = "Flags",
        }},
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(std.testing.allocator, packed_document));

    var unsupported_packed = packed_document;
    const unsupported_fields = [_]semantic.TypeField{.{ .name = "ratio", .type = .{ .float = .{ .bits = 32 } } }};
    const unsupported_types = [_]semantic.TypeDecl{.{
        .backing_type = .{ .int = .{ .bits = 32, .signed = false } },
        .fields = &unsupported_fields,
        .kind = .value_struct,
        .layout = .@"packed",
        .name = "Flags",
    }};
    unsupported_packed.types = &unsupported_types;
    const packed_issue = (try findIssue(std.testing.allocator, unsupported_packed)) orelse return error.MissingDiagnostic;
    defer std.testing.allocator.free(packed_issue.message);
    try std.testing.expectEqualStrings("ZIGO044", packed_issue.code);
    try std.testing.expect(std.mem.indexOf(u8, packed_issue.message, "ratio") != null);

    const unknown_enum_fields = [_]semantic.TypeField{.{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "UnregisteredMode" } } }};
    const plain_struct_fields = [_]semantic.TypeField{.{ .name = "child", .type = .{ .value_struct = .{ .ref = "Plain" } } }};
    const pointer_fields = [_]semantic.TypeField{.{ .name = "owner", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Thing" } } }};
    const invalid_fields = [_][]const semantic.TypeField{ &unknown_enum_fields, &plain_struct_fields, &pointer_fields };
    const invalid_names = [_][]const u8{ "mode", "child", "owner" };
    for (invalid_fields, invalid_names) |fields, field_name| {
        const declarations = [_]semantic.TypeDecl{
            .{
                .backing_type = .{ .int = .{ .bits = 64, .signed = false } },
                .fields = fields,
                .kind = .value_struct,
                .layout = .@"packed",
                .name = "Flags",
            },
            .{ .kind = .value_struct, .name = "Plain" },
            .{ .kind = .@"opaque", .name = "Thing" },
        };
        var invalid = packed_document;
        invalid.types = &declarations;
        const issue = (try findIssue(std.testing.allocator, invalid)) orelse return error.MissingDiagnostic;
        defer std.testing.allocator.free(issue.message);
        try std.testing.expectEqualStrings("ZIGO044", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, field_name) != null);
    }

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

test "stream parameters are accepted only as whole call-scoped parameters" {
    const writer: semantic.TypeNode = .{ .io_stream = .{ .direction = .writer } };
    const reader: semantic.TypeNode = .{ .io_stream = .{ .direction = .reader } };
    const stream_child: semantic.TypeNode = writer;
    const stream_return: semantic.TypeNode = reader;
    var fallible_stream: semantic.TypeNode = reader;
    var callback_return: semantic.TypeNode = .{ .void = {} };
    var callback_params = [_]semantic.TypeNode{writer};
    const count: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };

    const accepted: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "dump",
                .params = &.{.{ .name = "w", .type = writer }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_dump",
            },
            .{
                .name = "load",
                .params = &.{.{ .buffer = 4096, .name = "r", .type = reader }},
                .@"return" = count,
                .symbol = "zg_load",
            },
        },
        .package = "stream",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(std.testing.allocator, accepted));

    const rejected = [_]struct { document: semantic.Semantic, message: []const u8 }{
        // A free function has no object to ask for the stream again.
        .{ .document = .{
            .functions = &.{.{
                .name = "open",
                .params = &.{},
                .@"return" = stream_return,
                .symbol = "zg_open",
            }},
            .package = "stream",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .message = "only a method can return a `*std.Io.Writer` or `*std.Io.Reader`" },
        // The generated `Write`/`Read`/`Flush` have nowhere to carry them.
        .{ .document = .{
            .functions = &.{.{
                .name = "open",
                .params = &.{.{ .name = "mode", .type = count }},
                .receiver = "Doc",
                .@"return" = stream_return,
                .symbol = "zg_doc_open",
            }},
            .package = "stream",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .message = "a stream-returning method cannot take parameters" },
        // Only on its own: an error union has no lowering for the pointer.
        .{ .document = .{
            .functions = &.{.{
                .name = "open",
                .params = &.{},
                .receiver = "Doc",
                .@"return" = .{ .error_union = .{ .error_set = &.{"Closed"}, .payload = &fallible_stream } },
                .symbol = "zg_doc_open",
            }},
            .package = "stream",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .message = "`*std.Io.Writer` and `*std.Io.Reader` can only be returned on their own" },
        .{ .document = .{
            .functions = &.{.{
                .name = "visit",
                .params = &.{.{ .name = "callback", .type = .{ .callback = .{
                    .has_userdata = false,
                    .params = &callback_params,
                    .@"return" = &callback_return,
                } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_visit",
            }},
            .package = "stream",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .message = "`*std.Io.Writer` and `*std.Io.Reader` are only supported as whole parameters, not inside parameter `callback`" },
        .{ .document = .{
            .functions = &.{.{
                .name = "keep",
                .params = &.{.{ .name = "w", .retention = .retained, .type = writer }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_keep",
            }},
            .package = "stream",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .message = "stream parameter `w` cannot be retained" },
        .{ .document = .{
            .functions = &.{.{
                .name = "sink",
                .params = &.{.{ .buffer = 512, .name = "w", .type = writer }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_sink",
            }},
            .package = "stream",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .message = "stream buffer 512 on parameter `w` is outside 4096..16777216" },
        .{ .document = .{
            .functions = &.{.{
                .name = "count",
                .params = &.{.{ .buffer = 8192, .name = "n", .type = count }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_count",
            }},
            .package = "stream",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .message = "buffer hint declared on parameter `n`, which is not a stream" },
        .{ .document = .{
            .functions = &.{},
            .package = "stream",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "sink", .type = stream_child }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Pipe",
            }},
            .zig_version = "0.16.0",
        }, .message = "`*std.Io.Writer` and `*std.Io.Reader` are only supported as whole parameters, not in field `sink`" },
    };
    for (rejected) |case| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const issue = (try findIssue(scratch.allocator(), case.document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO023", issue.code);
        try std.testing.expectEqualStrings(case.message, issue.message);
    }
}

test "an optional is rejected everywhere it has no presence to carry" {
    var word: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var optional_word: semantic.TypeNode = .{ .optional = .{ .child = &word } };
    var void_node: semantic.TypeNode = .{ .void = {} };

    // A slice element: the lowered `T*, len` pair has room for the elements
    // and nothing else.
    const slice_of_optional: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &optional_word } };
    // A callback signature: the function pointer's C type is fixed by the
    // callback declaration, so there is no second argument to add.
    const callback_of_optional: semantic.TypeNode = .{ .callback = .{
        .has_userdata = false,
        .params = &.{optional_word},
        .@"return" = &void_node,
    } };
    // An optional of an optional collapses to one presence flag in C, which
    // could not tell the two levels apart.
    const nested_optional: semantic.TypeNode = .{ .optional = .{ .child = &optional_word } };

    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    for ([_]semantic.TypeNode{ slice_of_optional, callback_of_optional, nested_optional }) |node| {
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "take",
                .params = &.{.{ .name = "value", .type = node }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_take",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try findIssue(scratch.allocator(), document)).?;
        try std.testing.expectEqualStrings("ZIGO019", issue.code);
    }

    // An `extern struct` field: the C mirror is a flat record, and a presence
    // flag beside the member would change its layout.
    const struct_document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "take",
            .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Point" } } }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_take",
        }},
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "x", .type = optional_word }},
            .kind = .value_struct,
            .layout = .@"extern",
            .name = "Point",
        }},
        .zig_version = "0.16.0",
    };
    const struct_issue = (try findIssue(scratch.allocator(), struct_document)).?;
    try std.testing.expect(struct_issue.severity == .@"error");
}

test "an optional is accepted as a whole parameter, return value, and error payload" {
    var word: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var optional_word: semantic.TypeNode = .{ .optional = .{ .child = &word } };
    var flag: semantic.TypeNode = .{ .bool = {} };
    var mode: semantic.TypeNode = .{ .@"enum" = .{ .ref = "Mode" } };
    var point: semantic.TypeNode = .{ .value_struct = .{ .ref = "Point" } };
    // A narrow integer is promoted inside an optional exactly as it is bare,
    // because both travel in the same widened C parameter.
    var narrow: semantic.TypeNode = .{ .int = .{ .bits = 12, .signed = false } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "double",
                .params = &.{.{ .name = "value", .type = optional_word }},
                .@"return" = optional_word,
                .symbol = "zg_double",
            },
            .{
                .name = "checked",
                .params = &.{
                    .{ .name = "flag", .type = .{ .optional = .{ .child = &flag } } },
                    .{ .name = "mode", .type = .{ .optional = .{ .child = &mode } } },
                    .{ .name = "point", .type = .{ .optional = .{ .child = &point } } },
                    .{ .name = "narrow", .type = .{ .optional = .{ .child = &narrow } } },
                },
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &optional_word } },
                .symbol = "zg_checked",
            },
        },
        .package = "good",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "x", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Point",
            },
            .{
                .fields = &.{.{ .name = "idle", .value = 0 }},
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    try semanticDocument(std.testing.allocator, document);
}

test "an optional slice is accepted while its unsupported combinations are not" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var word: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var point: semantic.TypeNode = .{ .value_struct = .{ .ref = "Point" } };
    var bytes: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    var words: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &word } };
    const points: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &point } };
    const strings: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &bytes } };
    const point_types = [_]semantic.TypeDecl{.{
        .fields = &.{.{ .name = "x", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
        .kind = .value_struct,
        .layout = .@"extern",
        .name = "Point",
    }};

    // `?[]T` in and out: the slice's own pointer is what says "present".
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "total",
            .params = &.{.{ .name = "values", .type = .{ .optional = .{ .child = &words } } }},
            .@"return" = .{ .optional = .{ .child = &bytes } },
            .symbol = "zg_total",
        }},
        .package = "good",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try semanticDocument(std.testing.allocator, document);

    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();

    // An `.out` slice is the caller's own buffer, so it cannot be absent.
    const out_document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "fill",
            .params = &.{.{
                .name = "buffer",
                .direction = .out,
                .type = .{ .optional = .{ .child = &words } },
            }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_fill",
        }},
        .package = "bad",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const out_issue = (try findIssue(scratch.allocator(), out_document)).?;
    try std.testing.expectEqualStrings("ZIGO019", out_issue.code);
    try std.testing.expect(std.mem.containsAtLeast(u8, out_issue.message, 1, "cannot be optional"));

    // A slice of slices builds a second array of pointers, and there is no
    // NULL left over to mean absent. A slice of extern structs is rejected for
    // the same reason the bare nested position is.
    for ([_]semantic.TypeNode{ strings, points }) |child| {
        var node = child;
        const rejected: semantic.Semantic = .{
            .functions = &.{.{
                .name = "take",
                .params = &.{.{ .name = "values", .type = .{ .optional = .{ .child = &node } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_take",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &point_types,
            .zig_version = "0.16.0",
        };
        try std.testing.expect((try findIssue(scratch.allocator(), rejected)) != null);
    }
}

test "a Go error on a callback is refused unless the Zig result is i32" {
    var i32_node: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const usize_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    var void_node: semantic.TypeNode = .{ .void = {} };
    var i64_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .signed = true } };
    const params = [_]semantic.TypeNode{ i32_node, usize_node };

    const accepted: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &params,
        .@"return" = &i32_node,
    } };
    const returns_void: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &params,
        .@"return" = &void_node,
    } };
    const returns_wide: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &params,
        .@"return" = &i64_node,
    } };

    const Case = struct { type: semantic.TypeNode, message: []const u8 };
    const rejected = [_]Case{
        .{ .type = returns_void, .message = "callback `observer` cannot return a Go error: its Zig result is not `i32`" },
        .{ .type = returns_wide, .message = "callback `observer` cannot return a Go error: its Zig result is not `i32`" },
        // The flag only means anything on a callback: on anything else it is
        // a typo that would otherwise generate nothing at all.
        .{ .type = usize_node, .message = "`go_error` declared on parameter `observer`, which is not a callback" },
    };
    for (rejected) |case| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "watch",
                .params = &.{
                    .{ .go_error = true, .name = "observer", .type = case.type },
                    .{ .name = "userdata", .type = usize_node },
                },
                .@"return" = .{ .void = {} },
                .symbol = "zg_watch",
            }},
            .package = "cb",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO025", issue.code);
        try std.testing.expectEqualStrings(case.message, issue.message);
    }

    // The accepted shape is what every generated callback already is, so the
    // opt-in must not reject the case it exists for.
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "watch",
            .params = &.{
                .{ .go_error = true, .name = "observer", .type = accepted },
                .{ .name = "userdata", .type = usize_node },
            },
            .@"return" = .{ .void = {} },
            .symbol = "zg_watch",
        }},
        .package = "cb",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(scratch.allocator(), document));
}

test "callback failure result must fit a non-void callback return" {
    var i8_node: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = true } };
    var void_node: semantic.TypeNode = .{ .void = {} };
    const usize_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    const callback_params = [_]semantic.TypeNode{usize_node};
    const narrow_callback: semantic.TypeNode = .{ .callback = .{
        .has_userdata = true,
        .params = &callback_params,
        .@"return" = &i8_node,
    } };
    const void_callback: semantic.TypeNode = .{ .callback = .{
        .has_userdata = true,
        .params = &callback_params,
        .@"return" = &void_node,
    } };
    const good_params = [_]semantic.Parameter{.{ .name = "callback", .on_callback_failure = .{ .result = -128 }, .type = narrow_callback }};
    const wide_params = [_]semantic.Parameter{.{ .name = "callback", .on_callback_failure = .{ .result = -129 }, .type = narrow_callback }};
    const void_params = [_]semantic.Parameter{.{ .name = "callback", .on_callback_failure = .{ .result = 0 }, .type = void_callback }};
    const good_functions = [_]semantic.SemanticFn{.{ .name = "run", .params = &good_params, .@"return" = .{ .void = {} }, .symbol = "zg_run" }};
    const wide_functions = [_]semantic.SemanticFn{.{ .name = "run", .params = &wide_params, .@"return" = .{ .void = {} }, .symbol = "zg_run" }};
    const void_functions = [_]semantic.SemanticFn{.{ .name = "run", .params = &void_params, .@"return" = .{ .void = {} }, .symbol = "zg_run" }};
    const good: semantic.Semantic = .{ .functions = &good_functions, .package = "cb", .prefix = "zg", .zig_version = "0.16.0" };
    const wide: semantic.Semantic = .{ .functions = &wide_functions, .package = "cb", .prefix = "zg", .zig_version = "0.16.0" };
    const no_result: semantic.Semantic = .{ .functions = &void_functions, .package = "cb", .prefix = "zg", .zig_version = "0.16.0" };
    try semanticDocument(std.testing.allocator, good);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const wide_issue = (try findIssue(arena.allocator(), wide)).?;
    try std.testing.expectEqualStrings("ZIGO046", wide_issue.code);
    try std.testing.expect(std.mem.containsAtLeast(u8, wide_issue.message, 1, "does not fit"));
    const void_issue = (try findIssue(arena.allocator(), no_result)).?;
    try std.testing.expectEqualStrings("ZIGO046", void_issue.code);
    try std.testing.expect(std.mem.containsAtLeast(u8, void_issue.message, 1, "returns void"));
}

test "callback contracts are refused on non-callback parameters" {
    const scalar: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const cases = [_]semantic.Parameter{
        .{ .name = "value", .reentrancy = .allowed, .type = scalar },
        .{ .name = "value", .thread = .caller, .type = scalar },
    };
    for (cases) |parameter| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "watch",
                .params = &.{parameter},
                .@"return" = .{ .void = {} },
                .symbol = "zg_watch",
            }},
            .package = "callbacks",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO025", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "which is not a callback") != null);
    }
}

test "a cancellable function has to name a flag its shim can pass and an error it can report" {
    const flag: semantic.TypeNode = .{ .cancel_flag = {} };
    const rounds: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = false } };
    const payload = struct {
        var node: semantic.TypeNode = .{ .void = {} };
    };

    const Case = struct {
        function: semantic.SemanticFn,
        message: []const u8,
    };
    const rejected = [_]Case{
        // A name that reaches nothing: the author probably renamed the
        // parameter and left the meta behind.
        .{ .function = .{
            .cancel = "stop",
            .name = "crunch",
            .params = &.{.{ .name = "rounds", .type = rounds }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Canceled"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }, .message = "`.cancel` names `stop`, which is not a parameter of this function" },
        // Named, but not the type the contract is written against.
        .{ .function = .{
            .cancel = "cancel",
            .name = "crunch",
            .params = &.{.{ .cancel = true, .name = "cancel", .type = rounds }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Canceled"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }, .message = "cancellation parameter `cancel` is not a `*const std.atomic.Value(u32)`" },
        // Nothing to say with: a cancelled call has no way to report that it
        // stopped rather than finished.
        .{ .function = .{
            .cancel = "cancel",
            .cancel_error = "Cancelled",
            .name = "crunch",
            .params = &.{.{ .cancel = true, .name = "cancel", .type = flag }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Empty"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }, .message = "a cancellable function must be able to report `error.Cancelled`" },
        // The flag without the meta: the C parameter would be there with no
        // Go `ctx` to raise it.
        .{ .function = .{
            .name = "crunch",
            .params = &.{.{ .name = "cancel", .type = flag }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Canceled"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }, .message = "parameter `cancel` is a cancellation flag but no `.cancel` names it" },
    };
    for (rejected) |case| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{case.function},
            .package = "job",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO026", issue.code);
        try std.testing.expectEqualStrings(case.message, issue.message);
    }

    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const accepted: semantic.Semantic = .{
        .functions = &.{.{
            .cancel = "cancel",
            .name = "crunch",
            .params = &.{
                .{ .name = "rounds", .type = rounds },
                .{ .cancel = true, .name = "cancel", .type = flag },
            },
            .@"return" = .{ .error_union = .{ .error_set = &.{ "Canceled", "Empty" }, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }},
        .package = "job",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(scratch.allocator(), accepted));

    const configured: semantic.Semantic = .{
        .functions = &.{.{
            .cancel = "cancel",
            .cancel_error = "Cancelled",
            .name = "crunch",
            .params = &.{.{ .cancel = true, .name = "cancel", .type = flag }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Cancelled"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }},
        .package = "job",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(scratch.allocator(), configured));
}

test "atomic pointer parameters reject unsupported scalars and retained addresses" {
    var bool_child: semantic.TypeNode = .{ .bool = {} };
    var word_child: semantic.TypeNode = .{ .int = .{ .bits = 64, .signed = false } };
    const cases = [_]struct { parameter: semantic.Parameter, message: []const u8 }{
        .{
            .parameter = .{ .name = "flag", .type = .{ .atomic_ptr = .{ .child = &bool_child, .@"const" = false } } },
            .message = "parameter `flag` points to an unsupported atomic scalar",
        },
        .{
            .parameter = .{ .name = "counter", .retention = .retained, .type = .{ .atomic_ptr = .{ .child = &word_child, .@"const" = false } } },
            .message = "atomic parameter `counter` cannot be retained",
        },
    };
    for (cases) |case| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "share",
                .params = &.{case.parameter},
                .@"return" = .{ .void = {} },
                .symbol = "zg_share",
            }},
            .package = "atomic",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO043", issue.code);
        try std.testing.expectEqualStrings(case.message, issue.message);
    }
}

test "registered opaque values are accepted as parameters but rejected as returns" {
    const handle = semantic.TypeNode{ .opaque_ptr = .{
        .by_value = true,
        .@"const" = true,
        .nullable = false,
        .ref = "Screen",
    } };
    const declarations = [_]semantic.TypeDecl{.{ .kind = .@"opaque", .name = "Screen" }};
    const parameters = [_]semantic.Parameter{.{ .name = "screen", .type = handle }};
    const accepted_functions = [_]semantic.SemanticFn{.{
        .name = "inspect",
        .params = &parameters,
        .@"return" = .{ .void = {} },
        .symbol = "zg_inspect",
    }};
    const accepted: semantic.Semantic = .{
        .functions = &accepted_functions,
        .package = "screen",
        .prefix = "zg",
        .types = &declarations,
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(std.testing.allocator, accepted));

    const rejected_functions = [_]semantic.SemanticFn{.{
        .name = "snapshot",
        .params = &.{},
        .@"return" = handle,
        .symbol = "zg_snapshot",
    }};
    var rejected = accepted;
    rejected.functions = &rejected_functions;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const issue = (try findIssue(arena.allocator(), rejected)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO003", issue.code);
    try std.testing.expectEqualStrings("cannot return a registered opaque type by value", issue.message);
    try std.testing.expect(std.mem.indexOf(u8, issue.hint, ".constructs") != null);
    try std.testing.expect(std.mem.indexOf(u8, issue.hint, "box") != null);
}

test "cross-package type cycles are diagnosed with the package path" {
    const a_ref = semantic.TypeNode{ .value_struct = .{ .ref = "A" } };
    const b_ref = semantic.TypeNode{ .value_struct = .{ .ref = "B" } };
    const document: semantic.Semantic = .{
        .package = "cycle",
        .packages = &.{
            .{ .name = "a", .path = "a" },
            .{ .name = "b", .path = "b" },
        },
        .prefix = "zg",
        .types = &.{
            .{ .fields = &.{.{ .name = "b", .type = b_ref }}, .kind = .value_struct, .name = "A", .package = "a" },
            .{ .fields = &.{.{ .name = "a", .type = a_ref }}, .kind = .value_struct, .name = "B", .package = "b" },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const issue = (try findIssue(arena.allocator(), document)).?;
    const rendered = try issue.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        "error[ZIGO032]: public package import cycle involves declaration `B`\n" ++
            "  --> semantic.json (B)\n" ++
            "  hint: move the declarations so the package graph is acyclic: a -> b -> a\n",
        rendered,
    );
}
