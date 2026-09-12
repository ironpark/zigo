//! Writers for public Go signatures: parameter, return and callback types,
//! and the conversions between raw and public values.
const type_spelling = @import("type_spelling.zig");
const std = @import("std");
const naming = @import("naming");
const abi = @import("abi");
const semantic = @import("semantic");
const targets = @import("targets");
const common = @import("common.zig");
const docs = @import("docs.zig");
const emit = @import("emit.zig");
const public = @import("public.zig");
const lower = @import("lower");

/// A handle payload surfaces as a borrowed reference; everything else keeps
/// its ordinary public Go type.
pub fn writePayloadType(scope: PublicScope, writer: *std.Io.Writer, payload: semantic.TypeNode) !void {
    if (payload == .opaque_ptr) return writer.print("*{s}Ref", .{payload.opaque_ptr.ref});
    try writePublicGoType(scope, writer, payload);
}

/// Resolves every handle a call needs into a local pointer, returning the
/// caller's error on the first nil, closed, or poisoned one. Each handle
/// stays pinned open until the function returns; a nil optional handle was
/// never pinned, and releasing it is a no-op.
pub fn renderHandleChecks(
    scope: PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: semantic.SemanticFn,
    go_names: []const []const u8,
    operation: []const u8,
    constructor: ?semantic.Constructor,
    options: emit.Options,
) !void {
    if (if (function.receiverIsHandle()) function.receiver else null) |receiver| {
        const receiver_name = try common.typeReceiverNameAlloc(allocator, scope.program, receiver);
        defer allocator.free(receiver_name);
        if (function.childOfReceiver())
            try writer.print("\tptr, zigoChildParent, err := {s}.zigoAcquireChild(\"{s} receiver\")\n", .{ receiver_name, operation })
        else
            try writer.print("\tptr, err := zigoCheckedPointer(\"{s} receiver\", {s})\n", .{ operation, receiver_name });
        try writer.writeAll("\tif err != nil {\n\t\t");
        try writeHandleErrorReturn(scope, writer, function, constructor);
        if (function.childOfReceiver()) {
            try writer.print(
                "\t}}\n\tzigoChildCreated := false\n\tdefer func() {{\n\t\t{s}.zigoRelease()\n\t\tif !zigoChildCreated {{\n\t\t\tzigoChildParent.{s}()\n\t\t}}\n\t}}()\n",
                .{ receiver_name, if (options.shared_lifecycle) "ZigoDropChild" else "zigoDropChild" },
            );
        } else {
            try writer.print("\t}}\n\tdefer {s}.zigoRelease()\n", .{receiver_name});
        }
    }
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .opaque_ptr) continue;
        const name = go_names[parameter_index];
        if (parameter.type.opaque_ptr.nullable) {
            try writer.print(
                "\t{0s}Ptr, err := zigoOptionalPointer(\"{1s} parameter {0s}\", {0s} == nil, {0s})\n",
                .{ name, operation },
            );
        } else {
            try writer.print("\t{0s}Ptr, err := zigoCheckedPointer(\"{1s} parameter {0s}\", {0s})\n", .{ name, operation });
        }
        try writer.writeAll("\tif err != nil {\n\t\t");
        try writeHandleErrorReturn(scope, writer, function, constructor);
        if (options.shared_lifecycle)
            try writer.print("\t}}\n\tdefer lifecycle.Release({s})\n", .{name})
        else
            try writer.print("\t}}\n\tdefer {s}.zigoRelease()\n", .{name});
    }
}

/// The `zigoErrorForCode` call a failed native call returns. When the call reached
/// handles it goes through zigoPoisonAfterPanic, so a `-2` leaves them all
/// unusable; a call with no handles has nothing to poison.
pub fn writeErrorForCode(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    function: semantic.SemanticFn,
    go_names: []const []const u8,
    operation: []const u8,
) !void {
    if (!function.receiverIsHandle() and !lower.hasOpaqueParameter(function)) return writer.print("zigoErrorForCode(\"{s}\", code)\n", .{operation});
    try writer.print("zigoPoisonAfterPanic(zigoErrorForCode(\"{s}\", code)", .{operation});
    if (if (function.receiverIsHandle()) function.receiver else null) |receiver| {
        const receiver_name = try common.typeReceiverNameAlloc(allocator, program, receiver);
        defer allocator.free(receiver_name);
        try writer.print(", {s}", .{receiver_name});
    }
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type == .opaque_ptr) try writer.print(", {s}", .{go_names[parameter_index]});
    }
    try writer.writeAll(")\n");
}

/// The `return` statement a failed handle check uses. It mirrors whatever the
/// function already returns, with `err` in the error position.
fn writeHandleErrorReturn(scope: PublicScope, writer: *std.Io.Writer, function: semantic.SemanticFn, constructor: ?semantic.Constructor) !void {
    try writeCheckedErrorReturn(scope, writer, function, constructor, "err");
}

/// The same shape as `writeHandleErrorReturn`, with the error written out as
/// an expression. A range check has its error in hand and no `err` binding to
/// spend a line on.
pub fn writeCheckedErrorReturn(
    scope: PublicScope,
    writer: *std.Io.Writer,
    function: semantic.SemanticFn,
    constructor: ?semantic.Constructor,
    error_expression: []const u8,
) !void {
    if (constructor != null) return writer.print("return nil, {s}\n", .{error_expression});
    const payload = function.@"return".errorPayload();
    if (payload == .void) return writer.print("return {s}\n", .{error_expression});
    try writer.writeAll("return ");
    try writePublicFailureValues(scope, writer, function, payload);
    try writer.print("{s}\n", .{error_expression});
}

pub fn hasNarrowIntParameter(function: semantic.SemanticFn) bool {
    return lower.hasNarrowIntParameter(function);
}

pub fn programHasNarrowIntParameter(program: abi.Program) bool {
    for (program.functions) |function| if (hasNarrowIntParameter(function.origin.*)) return true;
    return false;
}

/// The range a promoted parameter must fit, checked in Go before the call. The
/// shim keeps its own guard as a second line of defence -- native code can be
/// reached through the raw package -- but the public API never spends a cgo
/// call on an argument it can already see is wrong, and never leaves the
/// caller reading `LastErrorMessage` to find out why.
fn writeRangeCheck(
    scope: PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    name: []const u8,
    type_node: semantic.TypeNode,
    hint: ?semantic.SemanticHint,
    operation: []const u8,
    constructor: ?semantic.Constructor,
) !void {
    return writeRangeCheckWithLabel(scope, allocator, writer, function, name, type_node, hint, operation, constructor, null);
}

fn writeRangeCheckWithLabel(
    scope: PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    name: []const u8,
    type_node: semantic.TypeNode,
    hint: ?semantic.SemanticHint,
    operation: []const u8,
    constructor: ?semantic.Constructor,
    label: ?[]const u8,
) !void {
    const report_name = label orelse name;
    const optional = type_node == .optional;
    const node = if (optional) type_node.optional.child.* else type_node;
    // A codepoint is checked against Unicode, whatever width carries it: a
    // `rune` is signed and `u32` holds far more than the scalar values.
    if (semantic.isCodepoint(node, hint)) {
        try writer.print("\tif {0s} < 0 || {0s} > {1d} {{\n\t\t", .{ name, semantic.max_codepoint });
        var expression: std.Io.Writer.Allocating = .init(allocator);
        defer expression.deinit();
        try expression.writer.print("&RangeError{{Operation: \"{s}\", Parameter: \"{s}\", Type: \"codepoint\"}}", .{ operation, report_name });
        try writeCheckedErrorReturn(scope, writer, function.origin.*, constructor, expression.written());
        try writer.writeAll("\t}\n");
        return;
    }
    const narrow = abi.narrowInt(node) orelse return;
    const spelling: u8 = if (narrow.signed) 'i' else 'u';
    const deref: []const u8 = if (optional) "*" else "";
    if (optional) try writer.print("\tif {s} != nil {{\n\t", .{name});
    if (narrow.signed) {
        const limit = @as(i128, 1) << @intCast(narrow.bits - 1);
        try writer.print("\tif {3s}{0s} < {1d} || {3s}{0s} > {2d} {{\n\t\t", .{ name, -limit, limit - 1, deref });
    } else {
        const limit = (@as(u128, 1) << @intCast(narrow.bits)) - 1;
        try writer.print("\tif {2s}{0s} > {1d} {{\n\t\t", .{ name, limit, deref });
    }
    var expression: std.Io.Writer.Allocating = .init(allocator);
    defer expression.deinit();
    try expression.writer.print(
        "&RangeError{{Operation: \"{s}\", Parameter: \"{s}\", Type: \"{c}{d}\"}}",
        .{ operation, report_name, spelling, narrow.bits },
    );
    try writeCheckedErrorReturn(scope, writer, function.origin.*, constructor, expression.written());
    try writer.writeAll("\t}\n");
    if (optional) try writer.writeAll("\t}\n");
}

pub fn renderRangeChecks(
    scope: PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    go_names: []const []const u8,
    operation: []const u8,
    constructor: ?semantic.Constructor,
) !void {
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (parameter.flatten) |fields| {
            for (fields, 0..) |field, field_index| {
                const abi_parameter = function.flattenedParam(parameter_index, field_index);
                const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                defer allocator.free(name);
                if (common.isOptionField(parameter, field)) {
                    const raw_names = try targets.go.paramNamesAlloc(allocator, &.{field.name});
                    defer naming.freeParamNames(allocator, raw_names);
                    const expr = try std.fmt.allocPrint(allocator, "cfg.{s}", .{raw_names[0]});
                    defer allocator.free(expr);
                    try writeRangeCheckWithLabel(scope, allocator, writer, function, expr, field.type, null, operation, constructor, field.name);
                } else {
                    try writeRangeCheck(scope, allocator, writer, function, name, field.type, null, operation, constructor);
                }
            }
            continue;
        }
        if (parameter.direction == .in and semantic.isCodepointSlice(parameter.type, parameter.semantic)) {
            const name = go_names[parameter_index];
            try writer.print("\tfor _, zigoValue := range {s} {{\n\t\tif zigoValue < 0 || zigoValue > {d} {{\n\t\t\t", .{ name, semantic.max_codepoint });
            var expression: std.Io.Writer.Allocating = .init(allocator);
            defer expression.deinit();
            try expression.writer.print("&RangeError{{Operation: \"{s}\", Parameter: \"{s}\", Type: \"codepoint\"}}", .{ operation, name });
            try writeCheckedErrorReturn(scope, writer, function.origin.*, constructor, expression.written());
            try writer.writeAll("\t\t}\n\t}\n");
            continue;
        }
        if (parameter.direction == .in) if (abi.narrowSliceElement(parameter.type)) |element| {
            const narrow = element.int;
            const name = go_names[parameter_index];
            const spelling: u8 = if (narrow.signed) 'i' else 'u';
            try writer.print("\tfor _, zigoValue := range {s} {{\n", .{name});
            if (narrow.signed) {
                const limit = @as(i128, 1) << @intCast(narrow.bits - 1);
                try writer.print("\t\tif zigoValue < {d} || zigoValue > {d} {{\n\t\t\t", .{ -limit, limit - 1 });
            } else {
                const limit = (@as(u128, 1) << @intCast(narrow.bits)) - 1;
                try writer.print("\t\tif zigoValue > {d} {{\n\t\t\t", .{limit});
            }
            var expression: std.Io.Writer.Allocating = .init(allocator);
            defer expression.deinit();
            try expression.writer.print(
                "&RangeError{{Operation: \"{s}\", Parameter: \"{s}\", Type: \"{c}{d}\"}}",
                .{ operation, name, spelling, narrow.bits },
            );
            try writeCheckedErrorReturn(scope, writer, function.origin.*, constructor, expression.written());
            try writer.writeAll("\t\t}\n\t}\n");
            continue;
        };
        try writeRangeCheck(scope, allocator, writer, function, go_names[parameter_index], parameter.type, parameter.semantic, operation, constructor);
    }
}

/// The zero value of a public result type. A UTF-8 slice surfaces as a string,
/// so its zero is the empty string rather than `nil`.
fn writePublicZeroValue(scope: PublicScope, writer: *std.Io.Writer, function: semantic.SemanticFn, payload: semantic.TypeNode) !void {
    // `*new(T)` is the zero of any type, which is all that is known about an
    // adapted one.
    if (function.returnGoAdapter()) |adapter| return writer.print("*new({s})", .{adapter.type});
    if (semantic.isStringSlice(payload, function.return_semantic)) return writer.writeAll("\"\"");
    // A `?T` payload returns the zero of `T` beside a false presence flag:
    // there is no zero value of the optional itself to write.
    if (payload == .optional) return writeGoZeroValue(scope, writer, payload.optional.child.*);
    try writeGoZeroValue(scope, writer, payload);
}

/// The result values that precede an error on a failed public call. Optional
/// payloads include their presence flag between the zero value and the error.
pub fn writePublicFailureValues(scope: PublicScope, writer: *std.Io.Writer, function: semantic.SemanticFn, payload: semantic.TypeNode) !void {
    try writePublicZeroValue(scope, writer, function, payload);
    try writer.writeAll(", ");
    if (payload == .optional or
        (payload == .opaque_ptr and payload.opaque_ptr.nullable and docs.returnsBorrowedView(function)))
        try writer.writeAll("false, ");
}

/// The public return type when a nil or closed handle reaches the caller as an
/// error: a value return grows into a tuple, a void return becomes `error`.
pub fn writeCheckedFunctionReturnType(scope: PublicScope, writer: *std.Io.Writer, function: semantic.SemanticFn) !void {
    if (function.@"return" == .void) return writer.writeAll(" error");
    if (function.@"return" == .optional) {
        try writer.writeAll(" (");
        try writeOptionalPublicPayloadType(scope, writer, function.@"return".optional.child.*, function.return_semantic);
        try writer.writeAll(", bool, error)");
        return;
    }
    try writer.writeAll(" (");
    if (docs.returnsBorrowedView(function) and function.@"return".opaque_ptr.nullable) {
        try writer.print("*{s}, bool, error)", .{function.@"return".opaque_ptr.ref});
        return;
    } else if (semantic.isStringSlice(function.@"return", function.return_semantic)) {
        try writer.writeAll("string");
    } else if (docs.returnsBorrowedView(function)) {
        try writer.print("*{s}", .{function.@"return".opaque_ptr.ref});
    } else if (docs.returnsBorrowedOpaque(function)) {
        try writer.print("*{s}Ref", .{function.@"return".opaque_ptr.ref});
    } else if (function.returnGoAdapter()) |adapter| {
        try writer.writeAll(adapter.type);
    } else if (codepointTypeName(function.@"return", function.return_semantic)) |name| {
        try writer.writeAll(name);
    } else {
        try writePublicGoType(scope, writer, function.@"return");
    }
    try writer.writeAll(", error)");
}

pub fn writePublicFunctionReturnType(scope: PublicScope, writer: *std.Io.Writer, function: semantic.SemanticFn) !void {
    // An optional string is a `(string, bool)` pair, so it goes through the
    // optional spelling rather than the bare `string` one.
    if (function.@"return" != .optional and semantic.isStringSlice(function.@"return", function.return_semantic)) {
        try writer.writeAll(" string");
        return;
    }
    if (function.@"return" == .opaque_ptr and docs.returnsBorrowedView(function)) {
        if (function.@"return".opaque_ptr.nullable)
            try writer.print(" (*{s}, bool)", .{function.@"return".opaque_ptr.ref})
        else
            try writer.print(" *{s}", .{function.@"return".opaque_ptr.ref});
        return;
    }
    if (function.@"return" == .opaque_ptr and docs.returnsBorrowedOpaque(function)) {
        try writer.print(" *{s}Ref", .{function.@"return".opaque_ptr.ref});
        return;
    }
    if (function.@"return" == .error_union and function.@"return".error_union.payload.* == .opaque_ptr and docs.returnsBorrowedView(function)) {
        const pointer = function.@"return".error_union.payload.opaque_ptr;
        if (pointer.nullable)
            try writer.print(" (*{s}, bool, error)", .{pointer.ref})
        else
            try writer.print(" (*{s}, error)", .{pointer.ref});
        return;
    }
    if (function.@"return" == .error_union and function.@"return".error_union.payload.* == .opaque_ptr and docs.returnsBorrowedOpaque(function)) {
        try writer.print(" (*{s}Ref, error)", .{function.@"return".error_union.payload.opaque_ptr.ref});
        return;
    }
    try writePublicReturnType(scope, writer, function.@"return", function.return_semantic, function.returnGoAdapter());
}

pub fn writeBorrowedResult(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    function: semantic.SemanticFn,
    expression: []const u8,
) !void {
    const node = function.@"return".errorPayload();
    const parent = if (if (function.receiverIsHandle()) function.receiver else null) |receiver| try common.typeReceiverNameAlloc(allocator, program, receiver) else null;
    defer if (parent) |value| allocator.free(value);
    if (function.returnsBorrowedHandle())
        try writer.print("zigoNewBorrowed{s}({s}, {s})", .{ node.opaque_ptr.ref, expression, parent orelse "nil" })
    else
        try writer.print("&{s}Ref{{ptr: {s}, parent: {s}}}", .{ node.opaque_ptr.ref, expression, parent orelse "nil" });
}

pub fn writeRawImport(writer: *std.Io.Writer, options: emit.Options, indent: []const u8) !void {
    try writer.writeAll(indent);
    if (!std.mem.eql(u8, options.raw_package_name, "raw")) try writer.writeAll("raw ");
    try writer.print("\"{s}/{s}\"\n", .{ options.go_module, options.raw_package_path });
}

pub fn writeRawReferencePrefix(writer: *std.Io.Writer, options: emit.Options) !void {
    try writer.writeAll(if (options.raw_colocated) "zigoRaw" else "raw.");
}

pub fn writeRawTypeReferencePrefix(writer: *std.Io.Writer, options: emit.Options) !void {
    if (!options.raw_colocated) try writer.writeAll("raw.");
}

/// True when the function's result is a UTF-8 byte slice the raw layer hands
/// over as a Go `string` (built with one copy) rather than as `[]uint8`.
pub fn rawReturnsUtf8String(function: abi.AbiFn) bool {
    return function.materialized_return == null and function.materialized_out == null and
        semantic.isUtf8Slice(function.origin.@"return".errorPayload(), function.origin.return_semantic);
}

/// True when a UTF-8 input crosses the raw layer as a Go `string` (or
/// `*string` when optional), read in place through `unsafe.StringData`.
pub fn rawTakesUtf8String(parameter: semantic.Parameter) bool {
    return parameter.direction == .in and semantic.isUtf8Slice(parameter.type, parameter.semantic);
}

/// The raw spelling of a result payload: `string` for UTF-8 text, otherwise
/// the raw Go type.
fn writeRawResultType(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode, text: bool) !void {
    if (text) return writer.writeAll("string");
    try writeRawGoType(writer, program, node);
}

pub fn writeRawReturnType(writer: *std.Io.Writer, program: abi.Program, function: abi.AbiFn) !void {
    if ((function.ret_string == .c_string)) return writer.writeAll(" string");
    const text = rawReturnsUtf8String(function);
    if (function.materialized_return) |materialized| {
        if (materialized.optional) return writer.writeAll(if (materialized.fallible) " ([]byte, bool, int32)" else " ([]byte, bool)");
        return writer.writeAll(if (materialized.fallible) " ([]byte, int32)" else " []byte");
    }
    if (function.materialized_out) |output| {
        try writer.writeAll(" ([]byte, ");
        try writeRawGoType(writer, program, function.origin.@"return".errorPayload());
        return writer.writeAll(if (output.fallible) ", int32)" else ")");
    }
    switch (function.origin.@"return") {
        .void => {},
        .error_union => |value| {
            if (value.payload.* == .void) {
                try writer.writeAll(" int32");
            } else if (value.payload.* == .optional) {
                try writer.writeAll(" (");
                try writeRawResultType(writer, program, value.payload.optional.child.*, text);
                try writer.writeAll(", bool, int32)");
            } else {
                try writer.writeAll(" (");
                try writeRawResultType(writer, program, value.payload.*, text);
                try writer.writeAll(", int32)");
            }
        },
        .optional => |value| {
            try writer.writeAll(" (");
            try writeRawResultType(writer, program, value.child.*, text);
            try writer.writeAll(", bool)");
        },
        else => {
            try writer.writeByte(' ');
            try writeRawResultType(writer, program, function.origin.@"return", text);
        },
    }
}

pub fn writeRawParameterType(writer: *std.Io.Writer, program: abi.Program, parameter: semantic.Parameter) !void {
    if (semantic.isStringSliceParameter(parameter)) return writer.writeAll("[]string");
    // A NUL-terminated string is a Go `string`; an optional one is a pointer
    // to it, because an empty string is a real value here.
    if (semantic.isCStringSliceThroughOptional(parameter.type, parameter.semantic))
        return writer.writeAll(if (semantic.isOptionalSlice(parameter.type)) "*string" else "string");
    // UTF-8 text is a Go string on both sides; the raw layer reads its bytes
    // in place, so the public layer never has to copy it into a []byte.
    if (rawTakesUtf8String(parameter))
        return writer.writeAll(if (semantic.isOptionalSlice(parameter.type)) "*string" else "string");
    try writeRawGoType(writer, program, parameter.type);
}

pub fn typeBelongsToPackage(program: abi.Program, name: []const u8, active: ?[]const u8) bool {
    const declaration = semantic.typeDecl(program.types, name) orelse return false;
    return emit.packageMatches(declaration.package, active);
}

fn writePublicReturnType(scope: PublicScope, writer: *std.Io.Writer, node: semantic.TypeNode, hint: ?semantic.SemanticHint, adapter: ?semantic.GoAdapter) !void {
    switch (node) {
        .void => {},
        .error_union => |value| {
            if (value.payload.* == .void) {
                try writer.writeAll(" error");
            } else if (value.payload.* == .optional) {
                try writer.writeAll(" (");
                try writeOptionalPublicPayloadType(scope, writer, value.payload.optional.child.*, hint);
                try writer.writeAll(", bool, error)");
            } else {
                try writer.writeAll(" (");
                if (adapter) |value_adapter|
                    try writer.writeAll(value_adapter.type)
                else if (semantic.isStringSlice(value.payload.*, hint))
                    try writer.writeAll("string")
                else if (codepointTypeName(value.payload.*, hint)) |name|
                    try writer.writeAll(name)
                else
                    try writePublicGoType(scope, writer, value.payload.*);
                try writer.writeAll(", error)");
            }
        },
        .optional => |value| {
            try writer.writeAll(" (");
            try writeOptionalPublicPayloadType(scope, writer, value.child.*, hint);
            try writer.writeAll(", bool)");
        },
        else => {
            try writer.writeByte(' ');
            if (adapter) |value_adapter|
                try writer.writeAll(value_adapter.type)
            else if (codepointTypeName(node, hint)) |name|
                try writer.writeAll(name)
            else
                try writePublicGoType(scope, writer, node);
        },
    }
}

/// The public spelling of a codepoint position: `rune` for the scalar,
/// `[]rune` for a plain slice, null when the hint does not apply.
pub fn codepointTypeName(node: semantic.TypeNode, hint: ?semantic.SemanticHint) ?[]const u8 {
    if (semantic.isCodepoint(node, hint)) return "rune";
    if (semantic.isCodepointSlice(node, hint)) return "[]rune";
    return null;
}

/// Writes the public value of a raw codepoint result -- `rune(x)` or the
/// `[]rune` view of a `[]uint32` -- and reports whether the hint applied.
pub fn writeCodepointResult(writer: *std.Io.Writer, node: semantic.TypeNode, hint: ?semantic.SemanticHint, expression: []const u8) !bool {
    if (semantic.isCodepoint(node, hint)) {
        try writer.print("rune({s})", .{expression});
        return true;
    }
    if (semantic.isCodepointSlice(node, hint)) {
        try writer.print("zigoUint32ToRunes({s})", .{expression});
        return true;
    }
    return false;
}

/// Writes the raw argument of a public codepoint parameter and reports
/// whether the hint applied. A `[]rune` is viewed as `[]uint32` in place, so
/// an `.out` slice is written straight into the caller's memory.
pub fn writeCodepointArgument(writer: *std.Io.Writer, parameter: semantic.Parameter, expression: []const u8) !bool {
    if (semantic.isCodepoint(parameter.type, parameter.semantic)) {
        try writer.print("uint32({s})", .{expression});
        return true;
    }
    if (semantic.isCodepointSlice(parameter.type, parameter.semantic)) {
        try writer.print("zigoRunesToUint32({s})", .{expression});
        return true;
    }
    return false;
}

pub fn writeRawConversionPrefix(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode) !void {
    try writeRawGoType(writer, program, node);
    try writer.writeByte('(');
}

pub fn writeRawResultConversion(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode, expression: []const u8, options: emit.Options) !void {
    // A purego handle already arrives as an unsafe.Pointer; only the cgo
    // backend has a C pointer type to convert.
    if (options.backend == .purego and node == .opaque_ptr) return writer.writeAll(expression);
    try writeRawGoType(writer, program, node);
    try writer.print("({s})", .{expression});
}

/// The public spelling of the value half of an optional return. A UTF-8 or
/// NUL-terminated byte slice keeps the `string` it would have had without the
/// optional; everything else spells its own Go type.
fn writeOptionalPublicPayloadType(scope: PublicScope, writer: *std.Io.Writer, child: semantic.TypeNode, hint: ?semantic.SemanticHint) !void {
    if (semantic.isStringSlice(child, hint)) return writer.writeAll("string");
    if (semantic.isCodepoint(child, hint)) return writer.writeAll("rune");
    try writePublicGoType(scope, writer, child);
}

pub fn writePublicResultConversion(scope: PublicScope, writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode, expression: []const u8) !void {
    switch (node) {
        .bool => try writer.print("{s} != 0", .{expression}),
        .value_struct => |value| if (type_spelling.isPackedValue(program, node))
            try writer.print("{s}FromBacking({s})", .{ value.ref, expression })
        else
            try writer.print("zigo{s}FromRaw({s})", .{ value.ref, expression }),
        .slice => |value| if (value.element.* == .value_struct)
            try writer.print("zigo{s}{s}({s})", .{ value.element.*.value_struct.ref, public.publicSliceFromRawSuffix(program, value.element.*.value_struct.ref), expression })
        else if (value.element.* == .materialized)
            try writer.print("zigoDecode{s}SliceBuffer({s})", .{ value.element.materialized.ref, expression })
        else if (value.element.* == .@"enum" and enumAdapter(program, value.element.@"enum".ref) != null)
            try writer.print("zigo{s}SliceFromRaw({s})", .{ value.element.@"enum".ref, expression })
        else
            try writer.writeAll(expression),
        .materialized => |value| try writer.print("zigoDecode{s}Buffer({s})", .{ value.ref, expression }),
        .@"enum" => |value| try writeEnumFromRaw(scope, writer, value.ref, expression),
        else => try writer.writeAll(expression),
    }
}

/// The type-level `.go` adapter of a registered enum, if any.
pub fn enumAdapter(program: abi.Program, ref: []const u8) ?semantic.GoAdapter {
    const declaration = semantic.typeDecl(program.types, ref) orelse return null;
    return if (declaration.kind == .@"enum") declaration.goAdapter() else null;
}

/// `expression` as the raw integer an enum crosses as: through the adapter's
/// helper when the enum has one, otherwise a plain conversion.
pub fn writeEnumToRaw(program: abi.Program, writer: *std.Io.Writer, ref: []const u8, expression: []const u8) !void {
    if (enumAdapter(program, ref) != null) return writer.print("zigo{s}ToRaw({s})", .{ ref, expression });
    try writer.writeAll(type_spelling.rawGoTypeName(program, .{ .@"enum" = .{ .ref = ref } }));
    try writer.print("({s})", .{expression});
}

/// The public value of a raw enum integer: the adapter's helper or the
/// generated enum type.
pub fn writeEnumFromRaw(scope: PublicScope, writer: *std.Io.Writer, ref: []const u8, expression: []const u8) !void {
    if (enumAdapter(scope.program, ref) != null) return writer.print("zigo{s}FromRaw({s})", .{ ref, expression });
    try scope.writeTypeName(writer, ref);
    try writer.print("({s})", .{expression});
}

pub fn writeRawGoType(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode) !void {
    switch (node) {
        .atomic_ptr => try writer.writeAll("unsafe.Pointer"),
        .slice => |value| {
            try writer.writeAll("[]");
            try writeRawGoType(writer, program, value.element.*);
        },
        .@"enum" => try writer.writeAll(type_spelling.rawGoTypeName(program, node)),
        .opaque_ptr => try writer.writeAll("unsafe.Pointer"),
        .materialized => try writer.writeAll("[]byte"),
        .value_struct => |value| if (type_spelling.isPackedValue(program, node))
            try writeRawGoType(writer, program, type_spelling.enumDecl(program, value.ref).backing_type.?)
        else
            try writer.print("{s}{s}", .{ value.ref, common.raw_struct_suffix }),
        // `?T` crosses the C ABI as one nullable pointer, and the raw layer
        // spells it the same way: a nil Go pointer stands for `null`.
        .optional => |value| {
            try writer.writeByte('*');
            try writeRawGoType(writer, program, value.child.*);
        },
        else => try type_spelling.writeGoScalar(writer, type_spelling.semanticScalar(program, node)),
    }
}

/// Where a public type reference is being written. A reference to a type that
/// another package owns has to name that package, and only the emitter knows
/// it is writing a type reference rather than a field name, a composite-literal
/// key, or a selector -- which is why this decision lives here and not in a
/// pass over the rendered Go.
pub const PublicScope = struct {
    program: abi.Program,
    options: emit.Options,

    /// The same rule as `writeTypeName`, as a string, for the templates that
    /// interleave a type reference with other uses of the bare name -- a
    /// generated function name or a doc comment, neither of which is qualified.
    pub fn typeNameAlloc(self: PublicScope, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
        var buffer: std.Io.Writer.Allocating = .init(allocator);
        errdefer buffer.deinit();
        try self.writeTypeName(&buffer.writer, name);
        return buffer.toOwnedSlice();
    }

    pub fn writeTypeName(self: PublicScope, writer: *std.Io.Writer, name: []const u8) !void {
        // An adapted type is spelled the way the user wrote it, in every
        // package: the qualifier it carries is an import, not a sub-package.
        if (semantic.typeDecl(self.program.types, name)) |declaration| {
            if (declaration.goAdapter()) |adapter| return writer.writeAll(adapter.type);
        }
        const active = self.options.active_package orelse return writer.writeAll(name);
        for (self.program.types) |declaration| {
            if (!std.mem.eql(u8, declaration.name, name)) continue;
            if (emit.packageMatches(declaration.package, active)) break;
            if (declaration.package) |package| return writer.print("zigo_pkg_{s}.{s}", .{ package, name });
            if (active.len != 0) return writer.print("zigo_default.{s}", .{name});
            break;
        }
        return writer.writeAll(name);
    }
};

pub fn writePublicGoType(scope: PublicScope, writer: *std.Io.Writer, node: semantic.TypeNode) !void {
    if (node == .io_stream) return writer.writeAll(switch (node.io_stream.direction) {
        .writer => "io.Writer",
        .reader => "io.Reader",
    });
    switch (node) {
        .atomic_ptr => |value| {
            try writer.writeAll("*atomic.");
            try type_spelling.writeAtomicGoName(writer, value.child.*);
        },
        .slice => |value| {
            if (semantic.isByte(value.element.*)) {
                try writer.writeAll("[]byte");
            } else {
                try writer.writeAll("[]");
                try writePublicGoType(scope, writer, value.element.*);
            }
        },
        .@"enum" => |value| try scope.writeTypeName(writer, value.ref),
        .bool => try writer.writeAll("bool"),
        .int => |integer| if (integer.is_usize)
            try writer.writeAll(if (integer.signed) "int" else "uint")
        else
            // Go spells only the widths C names, so a narrow Zig integer
            // shows up in the public API as the one carrying it.
            try type_spelling.writeIntegerName(writer, integer.signed, abi.promotedIntBits(integer.bits), false),
        .float => |value| try writer.print("float{d}", .{value.bits}),
        .opaque_ptr => |value| {
            try writer.writeByte('*');
            try scope.writeTypeName(writer, value.ref);
        },
        .materialized => |value| {
            if (value.pointer) try writer.writeByte('*');
            try scope.writeTypeName(writer, value.ref);
        },
        .value_struct => |value| try scope.writeTypeName(writer, value.ref),
        // `?T` is spelled `*T` in public Go too: nil stands for absent, a
        // non-nil pointer carries the value, for both scalar and extern
        // struct children.
        .optional => |value| {
            try writer.writeByte('*');
            try writePublicGoType(scope, writer, value.child.*);
        },
        else => unreachable,
    }
}

pub fn writePublicParameterType(scope: PublicScope, writer: *std.Io.Writer, parameter: semantic.Parameter) !void {
    if (parameter.goAdapter()) |adapter| return writer.writeAll(adapter.type);
    if (semantic.isCodepoint(parameter.type, parameter.semantic)) return writer.writeAll("rune");
    if (semantic.isCodepointSlice(parameter.type, parameter.semantic)) return writer.writeAll("[]rune");
    if (semantic.isStringSliceParameter(parameter)) return writer.writeAll("[]string");
    // `?[]T` and `?[]const u8` become `*[]T` and `*string`: a Go slice or
    // string has no spelling for absence that an empty one does not also have.
    if (semantic.isOptionalSlice(parameter.type)) {
        try writer.writeByte('*');
        if (semantic.isStringSlice(parameter.type, parameter.semantic)) return writer.writeAll("string");
        return writePublicGoType(scope, writer, parameter.type.optional.child.*);
    }
    if (semantic.isStringSlice(parameter.type, parameter.semantic)) return writer.writeAll("string");
    try writePublicGoType(scope, writer, parameter.type);
}

/// The Go type a callback's byte payload has, raw and public alike: `string`
/// for text, `[]byte` otherwise. Either is a copy the callback may keep.
pub fn writeBytePayloadGoType(writer: *std.Io.Writer, callback: semantic.Callback, index: usize) !void {
    try writer.writeAll(if (semantic.isTextHint(callback.paramHint(index))) "string" else "[]byte");
}

/// The type the raw closure receives for callback value `index`.
pub fn writeCallbackRawGoType(writer: *std.Io.Writer, program: abi.Program, callback: semantic.Callback, index: usize) !void {
    if (semantic.isBytePayload(callback.params[index])) return writeBytePayloadGoType(writer, callback, index);
    try writeRawGoType(writer, program, callback.params[index]);
}

pub fn writePublicCallbackType(scope: PublicScope, writer: *std.Io.Writer, program: abi.Program, callback: semantic.Callback) !void {
    const value_count = if (callback.has_userdata and callback.params.len != 0) callback.params.len - 1 else callback.params.len;
    try writer.writeAll("func(");
    for (callback.params[0..value_count], 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        if (semantic.isCodepoint(parameter, callback.paramHint(index)))
            try writer.writeAll("rune")
        else if (semantic.isBytePayload(parameter))
            try writeBytePayloadGoType(writer, callback, index)
        else
            try writePublicGoType(scope, writer, parameter);
    }
    try writer.writeByte(')');
    // `go_error` widens the result to a Go pair. The Zig result is always
    // `i32` here -- ZIGO025 refuses anything else -- so there is always a
    // value to pair the error with.
    if (common.callbackSignatureHasGoError(program, callback)) {
        try writer.writeAll(" (");
        try writePublicGoType(scope, writer, callback.@"return".*);
        return writer.writeAll(", error)");
    }
    if (callback.@"return".* != .void) {
        try writer.writeByte(' ');
        if (semantic.isCodepoint(callback.@"return".*, callback.return_semantic))
            try writer.writeAll("rune")
        else
            try writePublicGoType(scope, writer, callback.@"return".*);
    }
}

/// Whether the public callback type and the raw closure the trampoline
/// stores spell any position differently, so the handle constructor has to
/// wrap the user's function instead of converting its type.
pub fn callbackNeedsAdapter(program: abi.Program, callback: semantic.Callback) bool {
    const value_count = if (callback.has_userdata and callback.params.len != 0) callback.params.len - 1 else callback.params.len;
    for (callback.params[0..value_count]) |parameter| if (type_spelling.isPackedValue(program, parameter) or parameter == .bool or parameter == .@"enum" or parameter == .opaque_ptr) return true;
    return callback.@"return".* == .bool or callback.@"return".* == .@"enum" or callback.hasCodepoints();
}

pub fn writeCallbackAdapter(scope: PublicScope, writer: *std.Io.Writer, callback: semantic.Callback, value_name: []const u8) !void {
    const program = scope.program;
    const value_count = if (callback.has_userdata and callback.params.len != 0) callback.params.len - 1 else callback.params.len;
    const go_error = common.callbackSignatureHasGoError(program, callback);
    const codepoint_result = semantic.isCodepoint(callback.@"return".*, callback.return_semantic);
    const bool_result = callback.@"return".* == .bool;
    const enum_result = callback.@"return".* == .@"enum";
    // A result whose public spelling differs from the wire has to be
    // converted after the call; with `go_error` the pair is taken apart first.
    const converted_result = codepoint_result or bool_result or enum_result;
    try writer.writeAll("func(");
    for (callback.params[0..value_count], 0..) |_, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("p{d} ", .{index});
        try writeCallbackRawGoType(writer, program, callback, index);
    }
    try writer.writeByte(')');
    if (callback.@"return".* != .void) {
        try writer.writeByte(' ');
        if (go_error) try writer.writeByte('(');
        try writeRawGoType(writer, program, callback.@"return".*);
        if (go_error) try writer.writeAll(", error)");
    }
    try writer.writeAll(" {\n\t\t");
    // A nullable handle pointer keeps `nil` as a nil handle rather than a
    // handle around a null pointer.
    for (callback.params[0..value_count], 0..) |parameter, index| {
        if (parameter != .opaque_ptr or !parameter.opaque_ptr.nullable) continue;
        try writer.print("var h{d} *", .{index});
        try scope.writeTypeName(writer, parameter.opaque_ptr.ref);
        try writer.print("\n\t\tif p{d} != nil {{\n\t\t\th{d} = zigoNewBorrowed{s}(p{d}, nil)\n\t\t}}\n\t\t", .{ index, index, parameter.opaque_ptr.ref, index });
    }
    // A `rune` result is converted back to its carrier; with `go_error` the
    // pair has to be taken apart first.
    if (callback.@"return".* != .void) {
        if (converted_result and go_error) {
            try writer.writeAll("zigoResult, err := ");
        } else {
            try writer.writeAll("return ");
            if (converted_result) try writeCallbackAdapterResultOpen(scope, writer, callback);
        }
    }
    try writer.print("{s}(", .{value_name});
    for (callback.params[0..value_count], 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        try writeCallbackAdapterArgument(scope, writer, callback, index, parameter);
    }
    try writer.writeByte(')');
    if (converted_result and go_error) {
        try writer.writeAll("\n\t\treturn ");
        try writeCallbackAdapterResultOpen(scope, writer, callback);
        try writer.writeAll("zigoResult), err");
    } else if (converted_result) try writer.writeByte(')');
    try writer.writeAll("\n\t}");
}

/// One raw parameter `p{index}` spelled as the public value the user's
/// function takes.
fn writeCallbackAdapterArgument(scope: PublicScope, writer: *std.Io.Writer, callback: semantic.Callback, index: usize, parameter: semantic.TypeNode) !void {
    const program = scope.program;
    if (type_spelling.isPackedValue(program, parameter))
        try writer.print("{s}FromBacking(p{d})", .{ parameter.value_struct.ref, index })
    else if (parameter == .bool)
        try writer.print("p{d} != 0", .{index})
    else if (parameter == .opaque_ptr and parameter.opaque_ptr.nullable)
        try writer.print("h{d}", .{index})
    else if (parameter == .opaque_ptr)
        try writer.print("zigoNewBorrowed{s}(p{d}, nil)", .{ parameter.opaque_ptr.ref, index })
    else if (parameter == .@"enum") {
        var buffer: [16]u8 = undefined;
        const name = try std.fmt.bufPrint(&buffer, "p{d}", .{index});
        try writeEnumFromRaw(scope, writer, parameter.@"enum".ref, name);
    } else if (semantic.isCodepoint(parameter, callback.paramHint(index)))
        try writer.print("rune(p{d})", .{index})
    else
        try writer.print("p{d}", .{index});
}

/// The opening of the conversion that takes a public result back to its wire
/// spelling; the caller writes the expression and the closing parenthesis.
fn writeCallbackAdapterResultOpen(scope: PublicScope, writer: *std.Io.Writer, callback: semantic.Callback) !void {
    const result = callback.@"return".*;
    if (semantic.isCodepoint(result, callback.return_semantic))
        try writer.writeAll("uint32(")
    else if (result == .bool)
        try writer.writeAll("zigoBoolToUint8(")
    else if (result == .@"enum") {
        const ref = result.@"enum".ref;
        if (enumAdapter(scope.program, ref) != null) return writer.print("zigo{s}ToRaw(", .{ref});
        try writer.writeAll(type_spelling.rawGoTypeName(scope.program, result));
        try writer.writeByte('(');
    }
}

/// True when native code running under this call can invoke a Go callback:
/// one passed to the call, or one retained by a handle the call touches.
pub fn functionReachesCallbacks(program: abi.Program, function: semantic.SemanticFn) bool {
    if (function.receiverIsHandle()) {
        if (common.typeOwnsCallbacks(program, function.receiver.?)) return true;
    }
    for (function.params) |parameter| switch (parameter.type) {
        .callback, .io_stream => return true,
        .opaque_ptr => |pointer| if (common.typeOwnsCallbacks(program, pointer.ref)) return true,
        else => {},
    };
    return false;
}

/// The zero value an error path returns. A struct needs its own composite
/// literal, so callers that can see one use this instead of `goZero`.
pub fn writeGoZeroValue(scope: PublicScope, writer: *std.Io.Writer, node: semantic.TypeNode) !void {
    if (node == .@"enum") if (enumAdapter(scope.program, node.@"enum".ref)) |adapter| return writer.print("*new({s})", .{adapter.type});
    if (node == .value_struct) if (semantic.typeDecl(scope.program.types, node.value_struct.ref)) |declaration| {
        if (declaration.goAdapter()) |adapter| return writer.print("*new({s})", .{adapter.type});
    };
    if (node == .value_struct or (node == .materialized and !node.materialized.pointer)) {
        try scope.writeTypeName(writer, if (node == .value_struct) node.value_struct.ref else node.materialized.ref);
        return writer.writeAll("{}");
    }
    try writer.writeAll(type_spelling.goZero(node));
}

pub fn writePublicTaggedUnionRawArguments(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    declaration: semantic.TypeDecl,
    value_name: []const u8,
) !void {
    try writer.writeAll(type_spelling.rawGoTypeName(program, declaration.tag_type.?));
    try writer.print("({s}.tag)", .{value_name});
    for (program.liveFields(declaration.name)) |field| {
        const payload = field.type.?;
        if (payload == .void) continue;
        const member = try naming.camelAlloc(allocator, field.name);
        defer allocator.free(member);
        const expression = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ value_name, member });
        defer allocator.free(expression);
        try writePublicTaggedUnionPayloadRawArguments(allocator, writer, program, payload, expression);
    }
}

fn writePublicTaggedUnionPayloadRawArguments(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    node: semantic.TypeNode,
    expression: []const u8,
) !void {
    if (node == .value_struct) {
        const declaration = type_spelling.enumDecl(program, node.value_struct.ref);
        if (declaration.layout == .@"packed") {
            try writer.print(", zigo{s}ToBacking({s})", .{ declaration.name, expression });
            return;
        }
        for (declaration.fields) |field| {
            const member = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(member);
            const child = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ expression, member });
            defer allocator.free(child);
            try writePublicTaggedUnionPayloadRawArguments(allocator, writer, program, field.type.?, child);
        }
        return;
    }
    try writer.writeAll(", ");
    switch (node) {
        .bool => try writer.print("zigoBoolToUint8({s})", .{expression}),
        .@"enum" => |value| try writeEnumToRaw(program, writer, value.ref, expression),
        else => try writer.writeAll(expression),
    }
}
