//! Function-level shape rules: what a parameter or return may be.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const lower = @import("lower");
const semantic = @import("semantic");
const callbacks = @import("callbacks.zig");
const materialized = @import("materialized.zig");
const names = @import("names.zig");
const ownership = @import("ownership.zig");
const site = @import("site.zig");
const types = @import("types.zig");
const validate = @import("validate.zig");

/// Every function-level shape rule, in one pass so each function is judged
/// on its sharpest fault first.
pub fn functionIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.functions) |function| {
        if (materialized.materializedOutCount(function) > 1) return .{
            .severity = .@"error",
            .code = "ZIGO048",
            .message = "function has more than one materialized output buffer",
            .site = site.functionSite(function),
            .hint = "use one materialized output slice per function",
        };
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
            .site = site.functionSite(function),
            .hint = "use an explicit error set in the Zig function signature",
        };
        if (try iteratorIssue(allocator, function)) |issue| return issue;
        if (function.has_comptime_params == true) return .{
            .severity = .@"error",
            .code = "ZIGO008",
            .message = "cannot expose a function with comptime parameters",
            .site = site.functionSite(function),
            .hint = "bind a concrete specialization instead of the generic function",
        };
        if (byValueOpaqueReturn(function.@"return")) |pointer| return .{
            .severity = .@"error",
            .code = "ZIGO003",
            .message = "cannot return a registered opaque type by value",
            .site = site.functionSite(function),
            .hint = try std.fmt.allocPrint(
                allocator,
                "return `*{s}` and use `.constructs`, or configure `.allocator` so zigo can box the value",
                .{pointer.ref},
            ),
        };
        if (function.childOfReceiver() and
            (function.receiver == null or semantic.constructorForInit(document.constructors, function) == null)) return .{
            .severity = .@"error",
            .code = "ZIGO030",
            .message = "child-of-receiver metadata requires a receiver constructor",
            .site = site.functionSite(function),
            .hint = "use `.child_of_receiver = true` only on a constructor method that returns its paired caller-owned handle",
        };
        if (function.returnsBorrowedHandle() and function.receiver == null) return .{
            .severity = .@"error",
            .code = "ZIGO033",
            .message = "borrowed return has no receiver to own its lifetime",
            .site = site.functionSite(function),
            .hint = "use `.returns = .borrowed` only on a method, or use `.returns = .caller` with a constructor and destructor",
        };
        if (function.returnsBorrowedHandle() and ownership.borrowedOpaqueReturn(document, function) == null) return .{
            .severity = .@"error",
            .code = "ZIGO034",
            .message = "borrowed return is not a registered opaque handle",
            .site = site.functionSite(function),
            .hint = "return `*T`, `?*T`, `!*T`, or `!?*T` where T is a registered opaque type, or drop `.returns = .borrowed`",
        };
        if (!function.returnsBorrowedHandle() and function.ownership == .borrowed and
            ownership.borrowedOpaqueReturn(document, function) != null) return .{
            .severity = .@"error",
            .code = "ZIGO035",
            .message = "opaque handle return has no explicit ownership",
            .site = site.functionSite(function),
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
                    .site = site.functionSite(function),
                    .hint = if (injection == .allocator)
                        "set `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator`, or a declaration path in the binding"
                    else
                        "set `.io = \"<declaration path>\"` in the binding",
                };
            }
            if (try streamParameterIssue(allocator, function, parameter)) |issue| return issue;
            if (try atomicPointerIssue(allocator, function, parameter)) |issue| return issue;
            if (try callbacks.callbackGoErrorIssue(allocator, function, parameter)) |issue| return issue;
            if (try callbacks.callbackFailureResultIssue(allocator, document, function, parameter)) |issue| return issue;
            if (try callbacks.callbackContractIssue(allocator, function, parameter)) |issue| return issue;
            if (materialized.containsMaterialized(parameter.type) and !materialized.isMaterializedReleaseTarget(document, function) and abi.materializedOutParameter(parameter) == null) return .{
                .severity = .@"error",
                .code = "ZIGO048",
                .message = "materialized structs are result-only",
                .site = site.functionSite(function),
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
                .site = site.functionSiteFor(function, try site.functionDeclarationAlloc(allocator, function)),
                .hint = "name it with `.cancel` on the function, or drop the parameter",
            };
            const tagged_union_value = types.taggedUnionValueDeclaration(document, parameter.type);
            if (tagged_union_value) |declaration| {
                if (document.taggedUnionUsedAsHandle(declaration.name)) return .{
                    .severity = .@"error",
                    .code = "ZIGO006",
                    .message = "cannot use one tagged union as both a value parameter and a pointer handle",
                    .site = site.functionSite(function),
                    .hint = "register a separate scalar-payload union type for the value parameter",
                };
                if (types.taggedUnionValueIneligibleVariant(document, declaration)) |variant| return .{
                    .severity = .@"error",
                    .code = "ZIGO006",
                    .message = "cannot pass a tagged union by value",
                    .site = site.functionSite(function),
                    .hint = try std.fmt.allocPrint(
                        allocator,
                        "variant `{s}` has an unsupported value payload; omit it with `.omit_variants` or use void, scalar, enum, packed struct, or extern struct payloads",
                        .{variant},
                    ),
                };
            } else if (types.containsTaggedUnionValue(document, parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO006",
                .message = "cannot pass a tagged union by value",
                .site = site.functionSite(function),
                .hint = "pass an eligible tagged union as a whole parameter; nested tagged-union values are not supported",
            };
            if (parameter.flatten) |fields| {
                if (parameter.type != .value_struct) return .{
                    .severity = .@"error",
                    .code = "ZIGO040",
                    .message = "flatten metadata requires a struct parameter",
                    .site = site.functionSite(function),
                    .hint = "apply `.flatten` only to a plain struct parameter",
                };
                for (fields) |field| if (!isFlattenLeaf(document, field.type)) return .{
                    .severity = .@"error",
                    .code = "ZIGO040",
                    .message = try std.fmt.allocPrint(allocator, "flattened field `{s}` has an unsupported type", .{field.name}),
                    .site = site.functionSite(function),
                    .hint = "flatten only bool, integer, float, registered enum, or optional scalar fields",
                };
            } else if (tagged_union_value == null and unsupportedValueStruct(document, parameter.type) != null) return .{
                .severity = .@"error",
                .code = "ZIGO003",
                .message = "cannot pass a non-extern struct by value",
                .site = site.functionSite(function),
                .hint = "declare it as `extern struct`, or expose it as opaque",
            };
            if (nestedValueStruct(document, parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO013",
                .message = "extern struct is only supported as a whole parameter or return value",
                .site = site.functionSite(function),
                .hint = "pass the struct on its own or as a direct slice element; optional and callback signatures are not supported",
            };
            if (containsNonCFunctionPointer(parameter.type)) return .{
                .severity = .@"error",
                .code = "ZIGO004",
                .message = "function pointer does not use the C calling convention",
                .site = site.functionSite(function),
                .hint = "declare the callback with `callconv(.c)`",
            };
            if (parameter.type == .slice and containsPointer(parameter.type.slice.element.*) and
                !semantic.isStringSliceParameter(parameter)) return .{
                .severity = .@"error",
                .code = "ZIGO005",
                .message = "slice element type contains a pointer",
                .site = site.functionSite(function),
                .hint = "pass scalar elements or opaque handle values instead of Go pointers",
            };
            if (parameter.retention == .retained and containsPointer(parameter.type) and !hasMatchingRelease(document, function)) return .{
                .severity = .@"error",
                .code = "ZIGO009",
                .message = "retained pointer has no matching release function",
                .site = site.functionSite(function),
                .hint = "expose a release, clear, close, destroy, or deinit function for the retained value",
                .note = try names.retentionNoteAlloc(allocator, function),
            };
        }
        if (try streamReturnIssue(allocator, function)) |issue| return issue;
        if (try cancelIssue(allocator, function)) |issue| return issue;
        if (types.taggedUnionValueDeclaration(document, function.@"return")) |declaration| {
            if (document.taggedUnionUsedAsHandle(declaration.name)) return .{
                .severity = .@"error",
                .code = "ZIGO006",
                .message = "cannot use one tagged union as both a value return and a pointer handle",
                .site = site.functionSite(function),
                .hint = "register a separate union type for the value return",
            };
            if (types.taggedUnionValueIneligibleVariant(document, declaration)) |variant| return .{
                .severity = .@"error",
                .code = "ZIGO006",
                .message = "cannot return a tagged union by value",
                .site = site.functionSite(function),
                .hint = try std.fmt.allocPrint(
                    allocator,
                    "variant `{s}` has an unsupported value payload; omit it with `.omit_variants` or use void, scalar, enum, packed struct, or extern struct payloads",
                    .{variant},
                ),
            };
        } else if (types.containsTaggedUnionValue(document, function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO006",
            .message = "cannot return a tagged union by value",
            .site = site.functionSite(function),
            .hint = "return an eligible tagged union directly; nested tagged-union values are not supported",
        };
        if (types.taggedUnionValueDeclaration(document, function.@"return") == null and
            unsupportedValueStruct(document, function.@"return") != null) return .{
            .severity = .@"error",
            .code = "ZIGO003",
            .message = "cannot pass a non-extern struct by value",
            .site = site.functionSite(function),
            .hint = "declare it as `extern struct`, or expose it as opaque",
        };
        if (nestedValueStruct(document, function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO013",
            .message = "extern struct is only supported as a whole parameter or return value",
            .site = site.functionSite(function),
            .hint = "pass the struct on its own or as a direct slice element; optional and callback signatures are not supported",
        };
        if (containsNonCFunctionPointer(function.@"return")) return .{
            .severity = .@"error",
            .code = "ZIGO004",
            .message = "function pointer does not use the C calling convention",
            .site = site.functionSite(function),
            .hint = "declare the callback with `callconv(.c)`",
        };
        // A returned slice crosses as `T*` plus a length, so its element has to
        // be a value the C ABI can name. The error-union payload uses the same
        // out parameters and answers to the same rule.
        if (lower.releasableSliceReturnElement(function)) |element| {
            if (containsPointer(element)) return .{
                .severity = .@"error",
                .code = "ZIGO005",
                .message = "slice element type contains a pointer",
                .site = site.functionSite(function),
                .hint = "return scalar, enum, or extern-struct elements instead of Go pointers",
            };
        }
        // A caller-owned slice is handed over through `release` instead of a
        // handle destructor, so it answers to ZIGO016 rather than ZIGO015.
        if (function.ownership == .caller and (abi.materializedReturn(function.@"return") != null or abi.materializedOut(function) != null)) {
            if (materialized.materializedReleaseTargetIssue(document, function)) |issue| return issue;
        } else if (function.ownership == .caller and ownership.isReleasableSliceReturn(function)) {
            if (ownership.releaseTargetIssue(document, function)) |issue| return issue;
        } else if (function.ownership == .caller and !ownership.ownedReturnIsWrappable(document, function)) return .{
            .severity = .@"error",
            .code = "ZIGO015",
            .message = "caller-owned return has no constructed handle to hand over",
            .site = site.functionSite(function),
            .hint = "return a pointer to an opaque type that has both a constructor and a destructor, or drop `.returns = .caller`",
        };
        for (function.params) |parameter| {
            if (parameter.written == null) continue;
            if (parameter.direction != .out) return .{
                .severity = .@"error",
                .code = "ZIGO017",
                .message = "written hint declared on a parameter that is not an output slice",
                .site = site.functionSite(function),
                .hint = "add `.direction = .out` to the parameter, or drop `.written`",
            };
            if (parameter.writtenHint() == .@"return" and !ownership.returnsCount(function.@"return")) return .{
                .severity = .@"error",
                .code = "ZIGO017",
                .message = "`.written = .return` needs a `usize` result to report the count",
                .site = site.functionSite(function),
                .hint = "return `usize` or `!usize` from the function, or use the default `.written = .all`",
            };
        }
        if (function.release != null and !ownership.isReleasableSliceReturn(function) and abi.materializedReturn(function.@"return") == null and abi.materializedOut(function) == null) return .{
            .severity = .@"error",
            .code = "ZIGO016",
            .message = "release function declared on a return that zigo does not free",
            .site = site.functionSite(function),
            .hint = "use `.release` only together with `.returns = .caller` on a slice return",
        };
    }
    return null;
}

// An `.out` slice is a buffer the caller already allocated, so making it
// optional asks the callee to decide whether that buffer exists -- there
// is no shape for that, and no reading of it the two sides would agree on.
pub fn optionalOutIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.functions) |function| {
        for (function.params) |parameter| {
            if (parameter.direction != .out or parameter.type != .optional) continue;
            const declaration = try site.functionDeclarationAlloc(allocator, function);
            return .{
                .severity = .@"error",
                .code = "ZIGO019",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "output parameter `{s}` cannot be optional",
                    .{parameter.name},
                ),
                .site = site.functionSiteFor(function, declaration),
                .hint = "an output buffer is supplied by the caller; drop the `?` or make the function return the optional instead",
            };
        }
    }
    return null;
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
    const declaration = try site.functionDeclarationAlloc(allocator, function);
    var target: ?semantic.Parameter = null;
    for (function.params) |parameter| {
        if (parameter.cancel orelse false) target = parameter;
    }
    const parameter = target orelse return .{
        .severity = .@"error",
        .code = "ZIGO026",
        .message = try std.fmt.allocPrint(allocator, "`.cancel` names `{s}`, which is not a parameter of this function", .{named}),
        .site = site.functionSiteFor(function, declaration),
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
        .site = site.functionSiteFor(function, declaration),
        .hint = "declare it as `*const std.atomic.Value(u32)` and poll it; Go writes the same four bytes with sync/atomic",
    };
    const canceled = function.cancelError();
    if (!functionErrorSetHas(function, canceled)) return .{
        .severity = .@"error",
        .code = "ZIGO026",
        .message = try std.fmt.allocPrint(allocator, "a cancellable function must be able to report `error.{s}`", .{canceled}),
        .site = site.functionSiteFor(function, declaration),
        .hint = try std.fmt.allocPrint(allocator, "return an error union whose set contains `{s}`; generated Go maps it back to `ctx.Err()`", .{canceled}),
    };
    return null;
}

/// An iterator wrapper drives `next()` for the caller, so the method has to
/// be one Go can call with nothing but the receiver (and its `ctx`), and it
/// has to say when it is finished: `?T` or `!?T`.
fn iteratorIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn) !?diagnostic.Diagnostic {
    const iterator = function.iterator orelse return null;
    if (function.receiver == null) return .{
        .severity = .@"error",
        .code = "ZIGO050",
        .message = try std.fmt.allocPrint(allocator, "`.iterator` on `{s}`, which has no receiver", .{function.name}),
        .site = site.functionSite(function),
        .hint = "an iterator wrapper is a method of the handle it advances; move `.iterator` to a method of a registered opaque type",
    };
    if (function.@"return".errorPayload() != .optional) return .{
        .severity = .@"error",
        .code = "ZIGO050",
        .message = try std.fmt.allocPrint(allocator, "`.iterator` on `{s}.{s}`, which does not return `?T` or `!?T`", .{ function.receiver.?, function.name }),
        .site = site.functionSite(function),
        .hint = "the absent value is what ends the sequence; return an optional",
    };
    for (function.params) |parameter| {
        if (parameter.injected != null or parameter.type == .cancel_flag) continue;
        return .{
            .severity = .@"error",
            .code = "ZIGO050",
            .message = try std.fmt.allocPrint(allocator, "`.iterator` on `{s}.{s}`, which takes parameter `{s}`", .{ function.receiver.?, function.name, parameter.name }),
            .site = site.functionSite(function),
            .hint = try std.fmt.allocPrint(allocator, "`{s}()` is called with only the receiver; move the argument into the handle's constructor", .{iterator.name}),
        };
    }
    if (iterator.name.len == 0 or !std.ascii.isUpper(iterator.name[0])) return .{
        .severity = .@"error",
        .code = "ZIGO050",
        .message = try std.fmt.allocPrint(allocator, "`.iterator` name `{s}` on `{s}.{s}` is not an exported Go identifier", .{ iterator.name, function.receiver.?, function.name }),
        .site = site.functionSite(function),
        .hint = "start the wrapper name with an uppercase letter, or omit `.name` for `All`",
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
        .site = site.functionSite(function),
        .hint = "use *std.atomic.Value(u32), i32, u64, or i64 for a shared atomic parameter",
    };
    if (parameter.retention == .retained) return .{
        .severity = .@"error",
        .code = "ZIGO043",
        .message = try std.fmt.allocPrint(allocator, "atomic parameter `{s}` cannot be retained", .{parameter.name}),
        .site = site.functionSite(function),
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
    const declaration = try site.functionDeclarationAlloc(allocator, function);
    if (function.@"return" != .io_stream) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = "`*std.Io.Writer` and `*std.Io.Reader` can only be returned on their own",
        .site = site.functionSiteFor(function, declaration),
        .hint = "return the stream directly from a method; it cannot travel inside an error union, an optional, a slice, or a struct",
    };
    if (function.receiver == null) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = "only a method can return a `*std.Io.Writer` or `*std.Io.Reader`",
        .site = site.functionSiteFor(function, declaration),
        .hint = "the generated operations re-fetch the stream from the receiver on every call, so there has to be a receiver",
    };
    if (function.params.len != 0) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = "a stream-returning method cannot take parameters",
        .site = site.functionSiteFor(function, declaration),
        .hint = "the generated `Write`/`Read`/`Flush` methods have nowhere to carry them; take the arguments on the method that uses the stream instead",
    };
    return null;
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
    const declaration = try site.functionDeclarationAlloc(allocator, function);
    if (parameter.type != .io_stream and containsIoStream(parameter.type)) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = try std.fmt.allocPrint(
            allocator,
            "`*std.Io.Writer` and `*std.Io.Reader` are only supported as whole parameters, not inside parameter `{s}`",
            .{parameter.name},
        ),
        .site = site.functionSiteFor(function, declaration),
        .hint = "pass the stream as its own parameter; it cannot travel inside an optional, a slice, a callback signature, or a union payload",
    };
    if (parameter.type == .io_stream and parameter.retention == .retained) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = try std.fmt.allocPrint(allocator, "stream parameter `{s}` cannot be retained", .{parameter.name}),
        .site = site.functionSiteFor(function, declaration),
        .hint = "drop `.retention = .retained`; the shim adapter lives on the call stack and is invalid once the call returns",
    };
    const buffer = parameter.buffer orelse return null;
    if (parameter.type != .io_stream) return .{
        .severity = .@"error",
        .code = "ZIGO023",
        .message = try std.fmt.allocPrint(allocator, "buffer hint declared on parameter `{s}`, which is not a stream", .{parameter.name}),
        .site = site.functionSiteFor(function, declaration),
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
        .site = site.functionSiteFor(function, declaration),
        .hint = "choose a buffer between 4096 and 16777216 bytes, or drop `.buffer` for the 65536 default",
    };
    return null;
}

/// True when a stream appears anywhere in the node, including as the node
/// itself. Callers that allow the whole-parameter position test the tag first.
pub fn containsIoStream(node: semantic.TypeNode) bool {
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
    if (node == .value_struct) return !semantic.isPackedValue(document.types, node);
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

fn unsupportedValueStruct(document: semantic.Semantic, node: semantic.TypeNode) ?[]const u8 {
    return switch (node) {
        .value_struct => |value| blk: {
            const declaration = semantic.typeDecl(document.types, value.ref) orelse break :blk value.ref;
            if (declaration.kind != .value_struct) break :blk value.ref;
            break :blk if (declaration.layout != .@"extern" and declaration.layout != .@"packed") declaration.name else null;
        },
        .slice => |value| unsupportedValueStruct(document, value.element.*),
        .optional => |value| unsupportedValueStruct(document, value.child.*),
        .error_union => |value| unsupportedValueStruct(document, value.payload.*),
        else => null,
    };
}

fn byValueOpaqueReturn(node: semantic.TypeNode) ?semantic.OpaquePtr {
    const payload = node.errorPayload();
    if (payload != .opaque_ptr or !payload.opaque_ptr.by_value) return null;
    return payload.opaque_ptr;
}

fn isFlattenLeaf(document: semantic.Semantic, node: semantic.TypeNode) bool {
    const leaf = if (node == .optional) node.optional.child.* else node;
    return leaf == .bool or leaf == .int or leaf == .float or leaf == .@"enum" or semantic.isPackedValue(document.types, leaf);
}

fn containsPointer(node: semantic.TypeNode) bool {
    return switch (node) {
        .opaque_ptr, .slice, .callback => true,
        .materialized => |value| value.pointer,
        .optional => |value| containsPointer(value.child.*),
        else => false,
    };
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
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(std.testing.allocator, accepted));

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
        const issue = (try validate.findIssue(scratch.allocator(), case.document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO023", issue.code);
        try std.testing.expectEqualStrings(case.message, issue.message);
    }
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
        const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
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
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(std.testing.allocator, accepted));

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
    const issue = (try validate.findIssue(arena.allocator(), rejected)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO003", issue.code);
    try std.testing.expectEqualStrings("cannot return a registered opaque type by value", issue.message);
    try std.testing.expect(std.mem.indexOf(u8, issue.hint, ".constructs") != null);
    try std.testing.expect(std.mem.indexOf(u8, issue.hint, "box") != null);
}
