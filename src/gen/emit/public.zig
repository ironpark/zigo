//! The public Go package: one wrapper per function and the file plumbing
//! that decides which imports each concern file needs.
const handles = @import("handles.zig");
const type_spelling = @import("type_spelling.zig");
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");
const callbacks = @import("callbacks.zig");
const common = @import("common.zig");
const docs = @import("docs.zig");
const emit = @import("emit.zig");
const must = @import("must.zig");
const iterators = @import("iterators.zig");
const public_runtime = @import("public_runtime.zig");
const public_types = @import("public_types.zig");
const public_writers = @import("public_writers.zig");
const raw = @import("raw.zig");
const references = @import("references.zig");
const lower = @import("lower");

/// The helper the public layer calls to turn a `[]TData` into `[]T`. A castable
/// element reinterprets the allocation the raw layer already owns, so the name
/// says view rather than copy; anything else still converts element by element.
pub fn publicSliceFromRawSuffix(program: abi.Program, element: []const u8) []const u8 {
    return if (program.structCastable(element)) "SliceView" else "SliceFromRaw";
}

fn isValueStructSlice(node: semantic.TypeNode) bool {
    return node == .slice and node.slice.element.* == .value_struct;
}

/// An `.out` value-struct slice the raw layer still reads back element by
/// element. A castable element is written into the caller's slice directly, so
/// it needs no read-back and no named result to sequence one after.
pub fn hasCopiedOutValueStructSlice(program: abi.Program, function: semantic.SemanticFn) bool {
    for (function.params) |parameter| {
        if (parameter.direction != .out or !isValueStructSlice(parameter.type)) continue;
        if (!program.structCastable(parameter.type.slice.element.*.value_struct.ref)) return true;
    }
    return false;
}

fn hasOutValueStructSlice(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| {
        if (parameter.direction == .out and isValueStructSlice(parameter.type)) return true;
    }
    return false;
}

/// Whether the public function emitter writes this function at all. Helper
/// use predicates deliberately share this filter with the emitter so a
/// hidden deinitializer cannot keep one alive by accident.
pub fn emitsPublicFunction(program: abi.Program, function: abi.AbiFn) bool {
    const constructor = common.constructorForInit(program, function.origin.*);
    if (constructor == null and common.constructorForDeinit(program, function.origin.*) != null) return false;
    // A release function is called for the caller by the raw layer. Exposing
    // it publicly would invite freeing a Go-owned copy, so it stays internal.
    return !common.isReleaseTarget(program, function.origin.*);
}

/// Hands the raw layer the `[]TData` it expects. A castable element makes that
/// a reinterpretation of the caller's own slice, so the call reads and writes
/// the caller's memory directly and neither direction copies. An `.out`
/// parameter of a copied element still allocates, but skips the entry
/// conversion: nothing in the buffer is read.
fn writePublicSliceRawSetup(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: emit.Options,
    parameter: semantic.Parameter,
    name: []const u8,
) !void {
    const element = parameter.type.slice.element.*.value_struct.ref;
    const record = raw.structRecord(program, element);
    const raw_type = try common.structRawTypeNameAlloc(allocator, record.name);
    defer allocator.free(raw_type);
    if (record.castable) {
        try writer.print("\tvar {s}Raw []", .{name});
        try public_writers.writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s}\n\tif len({s}) != 0 {{\n\t\t{s}Raw = unsafe.Slice((*", .{ raw_type, name, name });
        try public_writers.writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s})(unsafe.Pointer(&{s}[0])), len({s}))\n\t}}\n", .{ raw_type, name, name });
        return;
    }
    if (parameter.direction == .out) {
        try writer.print("\t{s}Raw := make([]", .{name});
        try public_writers.writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s}, len({s}))\n", .{ raw_type, name });
        return;
    }
    try writer.print("\t{s}Raw := zigo{s}SliceToRaw({s})\n", .{ name, element, name });
}

/// The public layer copies back exactly as many elements as the shim reported
/// written, which is why both read the same `.written` hint rather than each
/// guessing from the return type.
fn writePublicValueStructSliceCopyBacks(
    writer: *std.Io.Writer,
    program: abi.Program,
    function: semantic.SemanticFn,
    go_names: [][]u8,
) !void {
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.direction != .out or !isValueStructSlice(parameter.type)) continue;
        if (program.structCastable(parameter.type.slice.element.*.value_struct.ref)) continue;
        const name = go_names[parameter_index];
        try writer.print("\tzigo{s}SliceCopyFromRaw({s}, {s}Raw, ", .{ parameter.type.slice.element.*.value_struct.ref, name, name });
        switch (parameter.writtenHint()) {
            .all => try writer.print("len({s})", .{name}),
            .@"return" => try writer.writeAll("int(result)"),
        }
        try writer.writeAll(")\n");
    }
}

fn writePublicMaterializedOutCopy(writer: *std.Io.Writer, function: abi.AbiFn, go_names: [][]u8) !void {
    const output = function.materialized_out orelse return;
    const name = go_names[output.source_index];
    try writer.print("\tzigoDecoded := zigoDecode{s}SliceBuffer(zigoBuffer)\n\tcopy({s}, zigoDecoded)\n", .{ output.root, name });
}

fn writePublicCapturedReturn(writer: *std.Io.Writer, program: abi.Program, function: semantic.SemanticFn, needs_handle_check: bool) !void {
    try writer.writeAll("\treturn ");
    switch (function.@"return") {
        .value_struct => |value| if (type_spelling.isPackedValue(program, function.@"return"))
            try writer.print("{s}FromBacking(result)", .{value.ref})
        else
            try writer.print("zigo{s}FromRaw(result)", .{value.ref}),
        .slice => |value| if (value.element.* == .value_struct)
            try writer.print("zigo{s}{s}(result)", .{ value.element.*.value_struct.ref, publicSliceFromRawSuffix(program, value.element.*.value_struct.ref) })
        else if (semantic.isUtf8Slice(function.@"return", function.return_semantic))
            try writer.writeAll("string(result)")
        else
            try writer.writeAll("result"),
        .bool => try writer.writeAll("result != 0"),
        .@"enum" => |value| try writer.print("{s}(result)", .{value.ref}),
        else => try writer.writeAll("result"),
    }
    if (needs_handle_check) try writer.writeAll(", nil");
    try writer.writeByte('\n');
}

/// Whether the public function file reinterprets a slice rather than copying
/// it, which is the one `unsafe` use it can have.
/// Whether the public spelling of a `?T` differs from the raw one, so the
/// pointer has to be rebuilt over a converted value rather than handed over as
/// it is. Integers and floats share both spellings; a bool, an enum, and an
/// `extern struct` do not.
fn publicOptionalNeedsConversion(child: semantic.TypeNode) bool {
    return switch (child) {
        .bool, .@"enum", .value_struct => true,
        else => false,
    };
}

/// True when a `?[]const u8` parameter is spelled `*string` publicly but
/// `*[]uint8` in the raw layer, so the pointer has to be rebuilt over the
/// converted bytes. A NUL-terminated string is `*string` on both sides.
fn publicOptionalStringNeedsBytes(parameter: semantic.Parameter) bool {
    return semantic.isOptionalSlice(parameter.type) and semantic.isUtf8Slice(parameter.type, parameter.semantic);
}

/// Rebuilds an optional parameter in its raw spelling ahead of the call. A nil
/// argument stays nil -- absence is the same on both sides -- and a present one
/// is converted into a local whose address travels instead.
fn writePublicOptionalRawSetup(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: emit.Options,
    child: semantic.TypeNode,
    name: []const u8,
) !void {
    if (!publicOptionalNeedsConversion(child)) return;
    try writer.print("\tvar {s}Raw *", .{name});
    if (child == .value_struct) {
        if (type_spelling.isPackedValue(program, child)) {
            try public_writers.writeRawGoType(writer, program, child);
        } else {
            const record = raw.structRecord(program, child.value_struct.ref);
            const raw_type = try common.structRawTypeNameAlloc(allocator, record.name);
            defer allocator.free(raw_type);
            try public_writers.writeRawTypeReferencePrefix(writer, options);
            try writer.writeAll(raw_type);
        }
    } else {
        try public_writers.writeRawGoType(writer, program, child);
    }
    try writer.print("\n\tif {0s} != nil {{\n\t\t{0s}RawValue := ", .{name});
    switch (child) {
        .bool => try writer.print("boolToUint8(*{s})", .{name}),
        .@"enum" => {
            try writer.writeAll(type_spelling.rawGoTypeName(program, child));
            try writer.print("(*{s})", .{name});
        },
        .value_struct => |value| if (type_spelling.isPackedValue(program, child))
            try writer.print("(*{s}).Backing()", .{name})
        else
            try writer.print("zigo{s}ToRaw(*{s})", .{ value.ref, name }),
        else => unreachable,
    }
    try writer.print("\n\t\t{0s}Raw = &{0s}RawValue\n\t}}\n", .{name});
}

fn publicNeedsUnsafe(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (parameter.type == .atomic_ptr) return true;
            if (!isValueStructSlice(parameter.type)) continue;
            if (program.structCastable(parameter.type.slice.element.*.value_struct.ref)) return true;
        }
    }
    return false;
}

pub fn renderPublic(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    const scope: public_writers.PublicScope = .{ .program = program, .options = options };
    const package = try common.publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    try writer.writeAll("// Code generated by zigo. DO NOT EDIT.\n\n");
    try docs.writePublicPackageDoc(writer, package, program, options);
    try writer.print("package {s}\n\n", .{package});
    const needs_runtime = common.publicNeedsRuntime(program);
    // Reinterpreting a castable struct slice as its raw mirror is the only
    // thing this file needs `unsafe` for.
    const needs_unsafe = publicNeedsUnsafe(program);
    const needs_raw = !options.raw_colocated;
    // A stream parameter is spelled with the caller's own `io` interfaces.
    const needs_io = common.programHasStreams(program) or common.programHasStreamRead(program);
    // A cancellable call takes a `context.Context`, matches the native error
    // against a sentinel, and raises its flag with an atomic store.
    const needs_cancel = common.programHasCancellation(program);
    // An iterator wrapper is spelled with `iter.Seq`/`iter.Seq2`.
    const needs_iter = common.programHasIterators(program);
    const needs_atomic_pointer = common.programHasAtomicPointers(program);
    var needs_lifecycle = false;
    if (options.shared_lifecycle) for (program.functions) |function| {
        if (lower.hasOpaqueParameter(function.origin.*)) {
            needs_lifecycle = true;
            break;
        }
    };
    const default_foreign = options.active_package != null and options.active_package.?.len != 0 and programReferencesPackage(program, options.active_package.?, "");
    var foreign: std.ArrayList(semantic.Package) = .empty;
    defer foreign.deinit(allocator);
    if (options.active_package != null) if (program.packages) |packages| for (packages) |foreign_package| {
        if (std.mem.eql(u8, foreign_package.name, options.active_package.?)) continue;
        if (programReferencesPackage(program, options.active_package.?, foreign_package.name)) try foreign.append(allocator, foreign_package);
    };
    const import_count = @as(usize, @intFromBool(needs_io)) + @as(usize, @intFromBool(needs_runtime)) +
        @as(usize, @intFromBool(needs_unsafe)) + @as(usize, @intFromBool(needs_raw)) +
        @as(usize, @intFromBool(needs_cancel)) * 3 + @as(usize, @intFromBool(needs_iter)) + @as(usize, @intFromBool(needs_atomic_pointer)) + @as(usize, @intFromBool(needs_lifecycle)) +
        @as(usize, @intFromBool(default_foreign)) + foreign.items.len;
    if (import_count > 1) {
        try writer.writeAll("import (\n");
        if (needs_cancel) try writer.writeAll("\t\"context\"\n\t\"errors\"\n");
        if (needs_io) try writer.writeAll("\t\"io\"\n");
        if (needs_iter) try writer.writeAll("\t\"iter\"\n");
        if (needs_runtime) try writer.writeAll("\t\"runtime\"\n");
        if (needs_cancel or needs_atomic_pointer) try writer.writeAll("\t\"sync/atomic\"\n");
        if (needs_unsafe) try writer.writeAll("\t\"unsafe\"\n");
        if (needs_raw) {
            if (needs_io or needs_iter or needs_runtime or needs_unsafe or needs_cancel or needs_atomic_pointer) try writer.writeByte('\n');
            try public_writers.writeRawImport(writer, options, "\t");
        }
        if (needs_lifecycle) try writer.print("\tlifecycle \"{s}/{s}\"\n", .{ options.go_module, options.lifecycle_package_path });
        if (default_foreign) try writeDefaultPackageImport(writer, options, "\t");
        for (foreign.items) |foreign_package| try writeForeignImport(writer, foreign_package, options, "\t");
        try writer.writeAll(")\n\n");
    } else if (needs_io) {
        try writer.writeAll("import \"io\"\n\n");
    } else if (needs_iter) {
        try writer.writeAll("import \"iter\"\n\n");
    } else if (needs_runtime) {
        try writer.writeAll("import \"runtime\"\n\n");
    } else if (needs_unsafe) {
        try writer.writeAll("import \"unsafe\"\n\n");
    } else if (needs_raw) {
        try writer.writeAll("import ");
        try public_writers.writeRawImport(writer, options, "");
        try writer.writeByte('\n');
    } else if (needs_lifecycle) {
        try writer.print("import lifecycle \"{s}/{s}\"\n\n", .{ options.go_module, options.lifecycle_package_path });
    } else if (default_foreign) {
        try writer.writeAll("import ");
        try writeDefaultPackageImport(writer, options, "");
        try writer.writeByte('\n');
    } else if (foreign.items.len == 1) {
        try writer.writeAll("import ");
        try writeForeignImport(writer, foreign.items[0], options, "");
        try writer.writeByte('\n');
    }
    // An internal loader keeps the public package limited to the bound API.
    if (options.backend == .purego and !options.raw_colocated and options.library_exported_api) try writer.writeAll(
        "// LibraryError reports a native shared-library loading failure.\n" ++
            "type LibraryError = raw.LibraryError\n\n" ++
            "// LoadLibrary atomically loads all generated native entry points.\n" ++
            "func LoadLibrary(path string) error { return raw.LoadLibrary(path) }\n\n" ++
            "// LibraryLoaded reports whether the native call surface is ready.\n" ++
            "func LibraryLoaded() bool { return raw.LibraryLoaded() }\n\n" ++
            "// DefaultLibraryName is the installed shared-library basename for the running platform.\n" ++
            "// LoadLibrary falls back to it when no explicit path and no ZIGO_LIBRARY_PATH are set.\n" ++
            "var DefaultLibraryName = raw.DefaultLibraryName\n\n",
    );
    for (program.functions) |function| {
        if (!emitsPublicFunction(program, function)) continue;
        const constructor = common.constructorForInit(program, function.origin.*);
        const owned_type: ?[]const u8 = if (function.ownership == .handle) function.ownership.handle.type_name else null;
        const go_names = try common.goParamNamesForAlloc(allocator, function.origin.params);
        defer naming.freeParamNames(allocator, go_names);
        const receiver_name = if (function.origin.receiver) |receiver|
            try common.receiverVariableAlloc(allocator, receiver, go_names)
        else
            null;
        defer if (receiver_name) |name| allocator.free(name);
        const go_name = if (constructor) |value|
            if (value.name) |name|
                try naming.pascalAlloc(allocator, name)
            else
                try std.fmt.allocPrint(allocator, "New{s}", .{value.type})
        else
            try naming.pascalAlloc(allocator, function.origin.name);
        defer allocator.free(go_name);
        const operation = if (function.origin.receiver) |receiver|
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ receiver, go_name })
        else
            try allocator.dupe(u8, go_name);
        defer allocator.free(operation);
        const shape = signatureShape(function);
        const needs_handle_check = shape.needs_handle_check;
        const needs_range_check = shape.needs_range_check;
        const has_stream = shape.has_stream;
        const has_callback_error = shape.has_callback_error;
        const needs_check = shape.needs_check;
        try docs.writePublicFunctionDoc(writer, function.origin.*, go_name, owned_type, public_writers.functionReachesCallbacks(program, function.origin.*), has_callback_error);
        if (function.origin.receiver) |receiver| {
            try writer.print("func ({s} *{s}) {s}", .{ receiver_name.?, receiver, go_name });
        } else {
            try writer.print("func {s}", .{go_name});
        }
        try writePublicSignature(scope, allocator, writer, function, go_names, constructor);
        try writer.writeAll(" {\n");
        // No runtime.KeepAlive for handles here: renderHandleChecks emits a
        // `defer x.zigoRelease()` per acquired handle, which already holds the
        // handle live to the end of the function. What still needs KeepAlive is
        // (a) Close, which must outlive cleanup.Stop, and (b) Go memory whose
        // pointer was handed to native for the duration of the call.
        // errorForCode reads the panic message out of native thread-local
        // storage in a second cgo call, so the goroutine must stay on the
        // thread that made the first one until it has been read.
        // Before the thread pin, because a rejected argument costs no cgo call
        // at all: nothing native has run, so there is no panic message to read
        // back off this thread.
        if (function.origin.cancel != null) try renderCancelSetup(writer, options);
        try renderAtomicPointerPins(writer, function, go_names, options);
        if (needs_range_check)
            try public_writers.renderRangeChecks(scope, allocator, writer, function, go_names, operation, constructor);
        if (has_stream)
            try renderStreamNilChecks(scope, allocator, writer, function.origin.*, go_names, operation, constructor);
        if (function.origin.@"return" == .error_union)
            try writer.writeAll("\truntime.LockOSThread()\n\tdefer runtime.UnlockOSThread()\n");
        // The handle checks run before any callback handle is registered, so
        // an early return cannot strand a retained callback.
        if (needs_handle_check)
            try public_writers.renderHandleChecks(scope, allocator, writer, function.origin.*, go_names, operation, constructor, options);
        try renderCallbackHandleSetup(allocator, writer, program, function);
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (!isValueStructSlice(parameter.type)) continue;
            try writePublicSliceRawSetup(allocator, writer, program, options, parameter, go_names[parameter_index]);
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.flatten) |fields| for (fields, 0..) |field, field_index| {
                if (field.type != .optional) continue;
                const abi_parameter = function.flattenedParam(parameter_index, field_index);
                const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                defer allocator.free(name);
                try writePublicOptionalRawSetup(allocator, writer, program, options, field.type.optional.child.*, name);
            };
            if (parameter.type != .optional) continue;
            if (publicOptionalStringNeedsBytes(parameter)) {
                try writer.print(
                    "\tvar {0s}Raw *[]byte\n\tif {0s} != nil {{\n\t\t{0s}RawValue := []byte(*{0s})\n\t\t{0s}Raw = &{0s}RawValue\n\t}}\n",
                    .{go_names[parameter_index]},
                );
                continue;
            }
            try writePublicOptionalRawSetup(allocator, writer, program, options, parameter.type.optional.child.*, go_names[parameter_index]);
        }
        try writer.writeByte('\t');
        const returns_error = function.origin.@"return" == .error_union;
        const error_payload = if (returns_error) function.origin.@"return".error_union.payload.* else semantic.TypeNode{ .void = {} };
        const borrowed_direct = !returns_error and docs.returnsBorrowedOpaque(function.origin.*);
        // A caller-owned handle returned without an error union still has to be
        // wrapped, so it is captured into `result` exactly like a borrowed one.
        const owned_direct = !returns_error and owned_type != null;
        // A callback panic is rethrown after the call, so a call that can reach
        // one cannot be the return expression itself.
        const needs_rethrow = public_writers.functionReachesCallbacks(program, function.origin.*);
        const captures_return = !returns_error and !borrowed_direct and !owned_direct and
            (hasOutValueStructSlice(function.origin.*) or function.materialized_out != null or needs_rethrow) and function.origin.@"return" != .void;
        if (returns_error) {
            if (function.materialized_out != null)
                try writer.writeAll("zigoBuffer, result, code := ")
            else if (error_payload == .void)
                try writer.writeAll("code := ")
            else if (error_payload == .optional)
                try writer.writeAll("result, zigoHas, code := ")
            else
                try writer.writeAll("result, code := ");
            try public_writers.writeRawReferencePrefix(writer, options);
        } else if (borrowed_direct or owned_direct) {
            try writer.writeAll("result := ");
            try public_writers.writeRawReferencePrefix(writer, options);
        } else if (captures_return) {
            try writer.writeAll(if (function.materialized_out != null) "zigoBuffer, result := " else "result := ");
            try public_writers.writeRawReferencePrefix(writer, options);
        } else if (function.origin.@"return" == .optional) {
            // Presence comes back beside the value, so both are named and the
            // value is converted into its public spelling on the way out.
            try writer.writeAll("zigoResult, zigoHas := ");
            try public_writers.writeRawReferencePrefix(writer, options);
        } else if ((function.ret_string == .c_string)) {
            try writer.writeAll("return ");
            try public_writers.writeRawReferencePrefix(writer, options);
        } else if (semantic.isUtf8Slice(function.origin.@"return", function.origin.return_semantic)) {
            try writer.writeAll("return string(");
            try public_writers.writeRawReferencePrefix(writer, options);
        } else if (function.origin.@"return" != .void) {
            if (function.origin.@"return" == .@"enum") {
                try writer.writeAll("return ");
                try scope.writeTypeName(writer, function.origin.@"return".@"enum".ref);
                try writer.writeByte('(');
                try public_writers.writeRawReferencePrefix(writer, options);
            } else if (function.origin.@"return" == .value_struct) {
                if (type_spelling.isPackedValue(program, function.origin.@"return"))
                    try writer.print("return {s}FromBacking(", .{function.origin.@"return".value_struct.ref})
                else
                    try writer.print("return zigo{s}FromRaw(", .{function.origin.@"return".value_struct.ref});
                try public_writers.writeRawReferencePrefix(writer, options);
            } else if (isValueStructSlice(function.origin.@"return")) {
                try writer.print("return zigo{s}{s}(", .{ function.origin.@"return".slice.element.*.value_struct.ref, publicSliceFromRawSuffix(program, function.origin.@"return".slice.element.*.value_struct.ref) });
                try public_writers.writeRawReferencePrefix(writer, options);
            } else if (function.origin.@"return" == .materialized) {
                try writer.print("return zigoDecode{s}Buffer(", .{function.origin.@"return".materialized.ref});
                try public_writers.writeRawReferencePrefix(writer, options);
            } else if (function.origin.@"return" == .slice and function.origin.@"return".slice.element.* == .materialized) {
                try writer.print("return zigoDecode{s}SliceBuffer(", .{function.origin.@"return".slice.element.materialized.ref});
                try public_writers.writeRawReferencePrefix(writer, options);
            } else {
                try writer.writeAll("return ");
                try public_writers.writeRawReferencePrefix(writer, options);
            }
        } else {
            try public_writers.writeRawReferencePrefix(writer, options);
        }
        const raw_name = try common.rawGoNameAlloc(allocator, function.origin.*);
        defer allocator.free(raw_name);
        try writer.print("{s}(", .{raw_name});
        var call_index: usize = 0;
        if (function.origin.receiver != null) {
            try writer.writeAll("ptr");
            call_index = 1;
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (function.userdataFor(parameter_index) != null) continue;
            if (parameter.injected != null) continue;
            if (parameter.flatten) |fields| {
                for (fields, 0..) |field, field_index| {
                    const abi_parameter = function.flattenedParam(parameter_index, field_index);
                    const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                    defer allocator.free(name);
                    if (call_index != 0) try writer.writeAll(", ");
                    const node = if (field.type == .optional) field.type.optional.child.* else field.type;
                    if (field.type == .optional and publicOptionalNeedsConversion(node)) {
                        try writer.print("{s}Raw", .{name});
                    } else switch (node) {
                        .bool => try writer.print("boolToUint8({s})", .{name}),
                        .@"enum" => {
                            try writer.writeAll(type_spelling.rawGoTypeName(program, node));
                            try writer.print("({s})", .{name});
                        },
                        .value_struct => if (type_spelling.isPackedValue(program, node))
                            try writer.print("{s}.Backing()", .{name})
                        else
                            try writer.writeAll(name),
                        else => try writer.writeAll(name),
                    }
                    call_index += 1;
                }
                continue;
            }
            if (call_index != 0) try writer.writeAll(", ");
            switch (parameter.type) {
                .callback => {
                    if (options.backend == .purego) {
                        const signature_index = callbacks.callbackSignatureIndex(program, parameter);
                        try public_writers.writeRawReferencePrefix(writer, options);
                        try writer.print("CallbackPointer{d}(), uintptr({s}Handle)", .{ signature_index, go_names[parameter_index] });
                        call_index += 1;
                    } else {
                        try writer.print("uintptr({s}Handle)", .{go_names[parameter_index]});
                    }
                },
                .io_stream => |stream| {
                    if (options.backend == .purego) {
                        try public_writers.writeRawReferencePrefix(writer, options);
                        try writer.print("Stream{s}CallbackPointer(), uintptr({s}Handle)", .{
                            common.streamHandleName(stream.direction),
                            go_names[parameter_index],
                        });
                        call_index += 1;
                    } else {
                        try writer.print("uintptr({s}Handle)", .{go_names[parameter_index]});
                    }
                    if (stream.direction == .reader) try writer.print(", {s}Data", .{go_names[parameter_index]});
                },
                .cancel_flag => try writer.writeAll("&zigoCancel"),
                .atomic_ptr => try writer.print("unsafe.Pointer({s})", .{go_names[parameter_index]}),
                .bool => try writer.print("boolToUint8({s})", .{go_names[parameter_index]}),
                .value_struct => |value| if (common.isTaggedUnionValue(program, parameter.type))
                    try public_writers.writePublicTaggedUnionRawArguments(allocator, writer, program, type_spelling.enumDecl(program, value.ref), go_names[parameter_index])
                else if (type_spelling.isPackedValue(program, parameter.type))
                    try writer.print("{s}.Backing()", .{go_names[parameter_index]})
                else
                    try writer.print("zigo{s}ToRaw({s})", .{ value.ref, go_names[parameter_index] }),
                .@"enum" => {
                    try writer.writeAll(type_spelling.rawGoTypeName(program, parameter.type));
                    try writer.print("({s})", .{go_names[parameter_index]});
                },
                .opaque_ptr => try writer.print("{s}Ptr", .{go_names[parameter_index]}),
                .optional => |optional| if (publicOptionalNeedsConversion(optional.child.*) or
                    publicOptionalStringNeedsBytes(parameter))
                    try writer.print("{s}Raw", .{go_names[parameter_index]})
                else
                    try writer.writeAll(go_names[parameter_index]),
                .slice => if (function.materializesParam(parameter_index))
                    try writer.print("len({s})", .{go_names[parameter_index]})
                else if (isValueStructSlice(parameter.type))
                    try writer.print("{s}Raw", .{go_names[parameter_index]})
                else if (function.paramString(parameter_index).role == .string_slice)
                    try writer.writeAll(go_names[parameter_index])
                else if (function.paramString(parameter_index).role == .c_string)
                    try writer.writeAll(go_names[parameter_index])
                else if (semantic.isUtf8Slice(parameter.type, parameter.semantic))
                    try writer.print("[]byte({s})", .{go_names[parameter_index]})
                else
                    try writer.writeAll(go_names[parameter_index]),
                else => try writer.writeAll(go_names[parameter_index]),
            }
            call_index += 1;
        }
        try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .@"enum") try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .value_struct) try writer.writeByte(')');
        if (!returns_error and !captures_return and isValueStructSlice(function.origin.@"return")) try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .materialized) try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .slice and function.origin.@"return".slice.element.* == .materialized) try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .bool) try writer.writeAll(" != 0");
        if (!returns_error and !captures_return and function.origin.@"return" != .optional and
            semantic.isUtf8Slice(function.origin.@"return", function.origin.return_semantic)) try writer.writeByte(')');
        if (!returns_error and !captures_return and !borrowed_direct and !owned_direct and needs_check and
            function.origin.@"return" != .void and function.origin.@"return" != .optional) try writer.writeAll(", nil");
        try writer.writeByte('\n');
        if (needs_rethrow) try renderCallbackRethrows(allocator, writer, program, function.origin.*, operation);
        // Before the status check: a stream that failed is the caller's own
        // error, and it is what they want back whatever the library returned.
        if (has_stream) try renderStreamErrorChecks(scope, writer, function.origin.*, go_names, operation, constructor);
        if (has_callback_error) try renderCallbackErrorChecks(scope, allocator, writer, program, function.origin.*, go_names, operation, constructor);
        if (!returns_error and hasOutValueStructSlice(function.origin.*)) {
            try writePublicValueStructSliceCopyBacks(writer, program, function.origin.*, go_names);
        }
        if (!returns_error and function.materialized_out != null)
            try writePublicMaterializedOutCopy(writer, function, go_names);
        if (!returns_error and function.origin.@"return" == .optional) {
            const child = function.origin.@"return".optional.child.*;
            try writer.writeAll("\treturn ");
            if (semantic.isStringSlice(child, function.origin.return_semantic))
                try writer.writeAll("string(zigoResult)")
            else
                try public_writers.writePublicResultConversion(scope, writer, program, child, "zigoResult");
            try writer.writeAll(", zigoHas");
            if (needs_check) try writer.writeAll(", nil");
            try writer.writeByte('\n');
        }
        if (captures_return) try writePublicCapturedReturn(writer, program, function.origin.*, needs_check);
        if (borrowed_direct or owned_direct) {
            if (function.origin.childOfReceiver()) try writer.writeAll("\tzigoChildCreated = true\n");
            if (docs.returnsBorrowedView(function.origin.*) and function.origin.@"return".opaque_ptr.nullable)
                try writer.writeAll("\tif result == nil {\n\t\treturn nil, false, nil\n\t}\n");
            try writer.writeAll("\treturn ");
            if (owned_type != null)
                try handles.writeOwnedHandleResult(allocator, writer, function, "result")
            else
                try public_writers.writeBorrowedResult(allocator, writer, function.origin.*, go_names, "result");
            if (docs.returnsBorrowedView(function.origin.*) and function.origin.@"return".opaque_ptr.nullable) try writer.writeAll(", true");
            if (needs_check) try writer.writeAll(", nil");
            try writer.writeByte('\n');
        }
        if (!returns_error) try writeAdoptRetainedMethodCallbacks(allocator, writer, program, function);
        if (!returns_error and needs_check and function.origin.@"return" == .void) try writer.writeAll("\treturn nil\n");
        if (returns_error) {
            try writer.writeAll("\tif code != 0 {\n");
            if (common.hasRetainedCallback(function.origin.*) and !common.retainedCallbacksBelongToReceiver(program, function.origin.*)) {
                try writeDeleteRetainedCallbacks(allocator, writer, function.origin.*);
            }
            // A stop the caller asked for is the caller's own answer, not the
            // library's: `context.Canceled` or `context.DeadlineExceeded`,
            // whichever their context says. The Zig error is still what the
            // native side reported, so it only gives way when the context
            // agrees that it was cancelled.
            const cancellable = function.origin.cancel != null;
            if (cancellable) {
                const canceled_name = try naming.pascalAlloc(allocator, function.origin.cancelError());
                defer allocator.free(canceled_name);
                try writer.writeAll("\t\tzigoErr := ");
                try public_writers.writeErrorForCode(allocator, writer, function.origin.*, go_names, operation);
                try writer.print("\t\tif errors.Is(zigoErr, Err{s}) && ctx.Err() != nil {{\n\t\t\treturn ", .{canceled_name});
                if (error_payload != .void) {
                    try public_writers.writePublicFailureValues(scope, writer, function.origin.*, error_payload);
                }
                try writer.writeAll("ctx.Err()\n\t\t}\n");
            }
            try writer.writeAll("\t\treturn ");
            if (error_payload != .void) {
                try public_writers.writePublicFailureValues(scope, writer, function.origin.*, error_payload);
            }
            if (cancellable)
                try writer.writeAll("zigoErr\n")
            else
                try public_writers.writeErrorForCode(allocator, writer, function.origin.*, go_names, operation);
            try writer.writeAll("\t}\n");
            try writeAdoptRetainedMethodCallbacks(allocator, writer, program, function);
            if (hasOutValueStructSlice(function.origin.*)) {
                try writePublicValueStructSliceCopyBacks(writer, program, function.origin.*, go_names);
            }
            if (function.materialized_out != null)
                try writePublicMaterializedOutCopy(writer, function, go_names);
            if (error_payload == .void) {
                try writer.writeAll("\treturn nil\n");
            } else {
                // `io.Reader` says a read that returns nothing has hit the end
                // of the stream, and says so with `io.EOF` rather than with a
                // count of zero alone. `readSliceShort` reports the end the
                // same way, as a short count, so the two only have to be
                // spelled for each other here.
                if (common.streamAccessorOp(function.origin.*) == .read)
                    try writer.writeAll("\tif result == 0 {\n\t\treturn 0, io.EOF\n\t}\n");
                if (function.origin.childOfReceiver()) try writer.writeAll("\tzigoChildCreated = true\n");
                if (error_payload == .opaque_ptr and error_payload.opaque_ptr.nullable and docs.returnsBorrowedView(function.origin.*)) {
                    try writer.writeAll("\tif result == nil {\n\t\treturn nil, false, nil\n\t}\n\treturn ");
                    try public_writers.writeBorrowedResult(allocator, writer, function.origin.*, go_names, "result");
                    try writer.writeAll(", true, nil\n");
                } else {
                    try writer.writeAll("\treturn ");
                    if (owned_type != null) {
                        try handles.writeOwnedHandleResult(allocator, writer, function, "result");
                    } else if (error_payload == .opaque_ptr and docs.returnsBorrowedOpaque(function.origin.*)) {
                        try public_writers.writeBorrowedResult(allocator, writer, function.origin.*, go_names, "result");
                    } else if (error_payload == .optional) {
                        if (semantic.isStringSlice(error_payload.optional.child.*, function.origin.return_semantic))
                            try writer.writeAll("string(result)")
                        else
                            try public_writers.writePublicResultConversion(scope, writer, program, error_payload.optional.child.*, "result");
                        try writer.writeAll(", zigoHas");
                    } else if (semantic.isStringSlice(error_payload, function.origin.return_semantic)) {
                        try writer.writeAll("string(result)");
                    } else {
                        try public_writers.writePublicResultConversion(scope, writer, program, error_payload, "result");
                    }
                    try writer.writeAll(", nil\n");
                }
            }
        }
        try writer.writeAll("}\n");
        if (options.go_must_variants and function.must_variant)
            try must.renderMustVariant(scope, allocator, writer, function, go_names, receiver_name, go_name, owned_type);
        if (function.origin.iterator != null)
            try iterators.renderIteratorWrapper(scope, allocator, writer, function, go_names, receiver_name.?, go_name, needs_check);
    }
}

/// Renders one concern-scoped file of the public package: the generated
/// marker, the package clause, the import block the body actually needs, and
/// the body. A body that declares nothing leaves the file at its prelude, and
/// the generator drops it.
fn renderPublicFile(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: emit.Options,
    renderBody: *const fn (std.mem.Allocator, *std.Io.Writer, abi.Program, emit.Options) anyerror!void,
) !void {
    const package = try common.publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    try writer.print("// Code generated by zigo. DO NOT EDIT.\n\npackage {s}\n", .{package});
    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();
    try renderBody(allocator, &body.writer, program, options);
    if (body.written().len == 0) return;
    // The emitters qualify type references as they write them, so the import
    // block is read straight off the finished body: it answers for the
    // selectors the file really uses.
    const text = body.written();
    try writePublicImports(allocator, writer, text, program, options);
    try writer.writeAll(text);
}

/// Every standard-library package a generated public file can need, in the
/// order gofmt sorts them. The qualifier is what the body writes, so the
/// import block is derived from the body instead of from a second, parallel
/// set of predicates that could disagree with it.
const public_std_imports = [_]struct { qualifier: []const u8, path: []const u8 }{
    .{ .qualifier = "binary", .path = "encoding/binary" },
    .{ .qualifier = "io", .path = "io" },
    .{ .qualifier = "math", .path = "math" },
    .{ .qualifier = "runtime", .path = "runtime" },
    .{ .qualifier = "cgo", .path = "runtime/cgo" },
    .{ .qualifier = "strconv", .path = "strconv" },
    .{ .qualifier = "strings", .path = "strings" },
    .{ .qualifier = "sync", .path = "sync" },
    .{ .qualifier = "atomic", .path = "sync/atomic" },
    .{ .qualifier = "unsafe", .path = "unsafe" },
};

/// What grows a public function's Go signature beyond its parameters.
pub const SignatureShape = struct {
    /// A nil or closed handle is a caller error, so it leaves through the
    /// return value instead of a panic. Functions that do not touch a
    /// handle keep their plain signature.
    needs_handle_check: bool,
    /// A promoted integer parameter is checked in Go, before the cgo call,
    /// so an out-of-range argument costs nothing native and the caller gets
    /// a `RangeError` rather than a panic the C wrapper would swallow.
    needs_range_check: bool,
    /// A stream parameter can be nil, and the Go value behind it can fail
    /// inside the call. Either way the caller needs somewhere to be told,
    /// so a stream grows the signature by an `error` just as a handle does.
    has_stream: bool,
    /// A callback that can return a Go error grows the signature the same
    /// way a stream does: the error happened while native code was running
    /// and has nowhere else to be told.
    has_callback_error: bool,
    /// Any of the above.
    needs_check: bool,
};

pub fn signatureShape(function: abi.AbiFn) SignatureShape {
    const needs_handle_check = function.origin.receiver != null or lower.hasOpaqueParameter(function.origin.*);
    const needs_range_check = public_writers.hasNarrowIntParameter(function.origin.*);
    const has_stream = common.functionHasStream(function.origin.*);
    const has_callback_error = function.reaches_callback_errors;
    return .{
        .needs_handle_check = needs_handle_check,
        .needs_range_check = needs_range_check,
        .has_stream = has_stream,
        .has_callback_error = has_callback_error,
        .needs_check = needs_handle_check or needs_range_check or has_stream or has_callback_error,
    };
}

/// The parameter list and result of a public function, from the opening
/// parenthesis to the end of the result: everything in the signature after
/// the name. `go_names` null writes the parameter types alone, which is the
/// spelling that decides whether two methods satisfy one interface.
pub fn writePublicSignature(
    scope: public_writers.PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    go_names: ?[][]u8,
    constructor: ?semantic.Constructor,
) !void {
    try writer.writeByte('(');
    try writePublicParameters(scope, allocator, writer, function, go_names);
    try writer.writeByte(')');
    if (constructor) |value| {
        try writer.print(" (*{s}, error)", .{value.type});
    } else if (signatureShape(function).needs_check and function.origin.@"return" != .error_union) {
        try public_writers.writeCheckedFunctionReturnType(scope, writer, function.origin.*);
    } else {
        try public_writers.writePublicFunctionReturnType(scope, writer, function.origin.*);
    }
}

/// The public parameter list, without its parentheses. A cancellable call
/// takes the context first, the way every Go API that can be cancelled does;
/// the flag behind it is the binding's business, so the parameter carrying
/// it is not in the signature, and neither are userdata tokens or injected
/// arguments.
pub fn writePublicParameters(
    scope: public_writers.PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    go_names: ?[][]u8,
) !void {
    var index: usize = 0;
    if (function.origin.cancel != null) {
        try writer.writeAll(if (go_names != null) "ctx context.Context" else "context.Context");
        index = 1;
    }
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (function.userdataFor(parameter_index) != null) continue;
        if (parameter.injected != null) continue;
        if (parameter.type == .cancel_flag) continue;
        if (parameter.flatten) |fields| {
            for (fields, 0..) |field, field_index| {
                const abi_parameter = function.flattenedParam(parameter_index, field_index);
                const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                defer allocator.free(name);
                if (index != 0) try writer.writeAll(", ");
                if (go_names != null) try writer.print("{s} ", .{name});
                try public_writers.writePublicGoType(scope, writer, field.type);
                index += 1;
            }
            continue;
        }
        if (index != 0) try writer.writeAll(", ");
        if (go_names) |names| try writer.print("{s} ", .{names[parameter_index]});
        if (parameter.type == .callback) {
            try writer.writeAll(function.callbackType(parameter_index).?.name);
        } else {
            try public_writers.writePublicParameterType(scope, writer, parameter);
        }
        index += 1;
    }
}

pub fn writePublicImports(allocator: std.mem.Allocator, writer: *std.Io.Writer, body: []const u8, program: abi.Program, options: emit.Options) !void {
    var needed: [public_std_imports.len][]const u8 = undefined;
    var count: usize = 0;
    for (public_std_imports) |entry| {
        if (!bodyUsesQualifier(body, entry.qualifier)) continue;
        needed[count] = entry.path;
        count += 1;
    }
    // The raw package is always reached through the `raw` qualifier: a raw
    // package with another name is imported under that alias.
    const uses_raw = !options.raw_colocated and bodyUsesQualifier(body, "raw");
    const lifecycle = bodyUsesQualifier(body, "lifecycle");
    const default_foreign = bodyUsesQualifier(body, "zigo_default");
    var foreign: std.ArrayList(semantic.Package) = .empty;
    defer foreign.deinit(allocator);
    if (options.active_package != null) if (program.packages) |packages| for (packages) |package| {
        if (std.mem.eql(u8, package.name, options.active_package.?)) continue;
        var qualifier_buffer: [256]u8 = undefined;
        const qualifier = std.fmt.bufPrint(&qualifier_buffer, "zigo_pkg_{s}", .{package.name}) catch continue;
        if (bodyUsesQualifier(body, qualifier)) try foreign.append(allocator, package);
    };
    if (count == 0 and !uses_raw and !lifecycle and !default_foreign and foreign.items.len == 0) return writer.writeByte('\n');
    if (count + @as(usize, @intFromBool(uses_raw)) + @as(usize, @intFromBool(lifecycle)) + @as(usize, @intFromBool(default_foreign)) + foreign.items.len == 1) {
        try writer.writeAll("\nimport ");
        if (uses_raw) {
            try public_writers.writeRawImport(writer, options, "");
        } else if (foreign.items.len == 1) {
            try writeForeignImport(writer, foreign.items[0], options, "");
        } else if (default_foreign) {
            try writeDefaultPackageImport(writer, options, "");
        } else if (lifecycle) {
            try writer.print("\"{s}/{s}\"\n", .{ options.go_module, options.lifecycle_package_path });
        } else {
            try writer.print("\"{s}\"\n", .{needed[0]});
        }
        return writer.writeByte('\n');
    }
    try writer.writeAll("\nimport (\n");
    for (needed[0..count]) |path| try writer.print("\t\"{s}\"\n", .{path});
    if (uses_raw) {
        if (count != 0) try writer.writeByte('\n');
        try public_writers.writeRawImport(writer, options, "\t");
    }
    if (lifecycle) try writer.print("\tlifecycle \"{s}/{s}\"\n", .{ options.go_module, options.lifecycle_package_path });
    if (default_foreign) try writeDefaultPackageImport(writer, options, "\t");
    if (foreign.items.len != 0) {
        if (count != 0 or uses_raw) try writer.writeByte('\n');
        for (foreign.items) |package| try writeForeignImport(writer, package, options, "\t");
    }
    try writer.writeAll(")\n\n");
}

fn writeDefaultPackageImport(writer: *std.Io.Writer, options: emit.Options, indent: []const u8) !void {
    const base = naming.optionalPathSegment(options.default_package_path);
    try writer.print("{s}zigo_default \"{s}{s}{s}\"\n", .{ indent, options.go_module, base.separator, base.value });
}

/// True when the body uses `qualifier.` as a package selector in code. Line
/// comments and string literals are skipped: a generated doc comment ending in
/// a Zig tag name, or a `String()` case returning one, must not be mistaken for
/// an import the file does not have.
fn bodyUsesQualifier(body: []const u8, qualifier: []const u8) bool {
    var index: usize = 0;
    while (index < body.len) {
        const byte = body[index];
        if (byte == '/' and index + 1 < body.len and body[index + 1] == '/') {
            index = std.mem.indexOfScalarPos(u8, body, index, '\n') orelse body.len;
            continue;
        }
        if (byte == '`') {
            index = 1 + (std.mem.indexOfScalarPos(u8, body, index + 1, '`') orelse body.len - 1);
            continue;
        }
        if (byte == '"' or byte == '\'') {
            index += 1;
            while (index < body.len and body[index] != byte) : (index += 1) {
                if (body[index] == '\\') index += 1;
            }
            index += 1;
            continue;
        }
        if (!references.isIdentifierByte(byte)) {
            index += 1;
            continue;
        }
        const begin = index;
        while (index < body.len and references.isIdentifierByte(body[index])) index += 1;
        if (index < body.len and body[index] == '.' and std.mem.eql(u8, body[begin..index], qualifier)) return true;
    }
    return false;
}

fn writeForeignImport(writer: *std.Io.Writer, package: semantic.Package, options: emit.Options, indent: []const u8) !void {
    const base = naming.optionalPathSegment(options.default_package_path);
    try writer.print("{s}zigo_pkg_{s} \"{s}{s}{s}/{s}\"\n", .{
        indent,
        package.name,
        options.go_module,
        base.separator,
        base.value,
        package.path,
    });
}

/// The one traversal both reference questions need: every type name a package
/// can reach through its functions and its own declarations. The two callers
/// differ only in what they ask about the name at the leaf.
const RefLeaf = union(enum) {
    /// The named type is declared in `package`.
    package: []const u8,
    /// The named type is `name`.
    name: []const u8,
};

fn programReferences(program: abi.Program, active: []const u8, leaf: RefLeaf) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| if (nodeReferences(program, parameter.type, leaf)) return true;
        if (nodeReferences(program, function.origin.@"return", leaf)) return true;
    }
    for (program.types) |declaration| {
        if (!emit.packageMatches(declaration.package, active)) continue;
        if (declaration.tag_type) |node| if (nodeReferences(program, node, leaf)) return true;
        for (declaration.fields) |field| if (field.type) |node| if (nodeReferences(program, node, leaf)) return true;
    }
    return false;
}

fn nodeReferences(program: abi.Program, node: semantic.TypeNode, leaf: RefLeaf) bool {
    const referenced: []const u8 = switch (node) {
        .@"enum" => |value| value.ref,
        .opaque_ptr => |value| value.ref,
        .value_struct => |value| value.ref,
        .slice => |value| return nodeReferences(program, value.element.*, leaf),
        .optional => |value| return nodeReferences(program, value.child.*, leaf),
        .error_union => |value| return nodeReferences(program, value.payload.*, leaf),
        .callback => |value| {
            for (value.params) |parameter| if (nodeReferences(program, parameter, leaf)) return true;
            return nodeReferences(program, value.@"return".*, leaf);
        },
        else => return false,
    };
    return switch (leaf) {
        .package => |target| public_writers.typeBelongsToPackage(program, referenced, target),
        .name => |target| std.mem.eql(u8, referenced, target),
    };
}

fn programReferencesPackage(program: abi.Program, active: []const u8, target: []const u8) bool {
    return programReferences(program, active, .{ .package = target });
}

pub fn programReferencesType(program: abi.Program, active: []const u8, target: []const u8) bool {
    return programReferences(program, active, .{ .name = target });
}

pub fn renderPublicEnumsFile(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    try renderPublicFile(allocator, writer, program, options, renderPublicEnumsBody);
}

fn renderPublicEnumsBody(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    try public_types.renderGoEnums(allocator, writer, program, options);
}

pub fn renderPublicStructsFile(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    try renderPublicFile(allocator, writer, program, options, public_types.renderPublicValueStructs);
}

pub fn renderPublicHandlesFile(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    try renderPublicFile(allocator, writer, program, options, public_types.renderGoHandles);
}

pub fn renderPublicRuntimeFile(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    try renderPublicFile(allocator, writer, program, options, renderPublicRuntimeBody);
}

/// The fixed part of every generated public package: the handle interface the
/// projections take, the projection status vocabulary, the `Must*` wrappers,
/// and the callback plumbing. None of it grows with the binding.
pub fn renderPublicRuntimeBody(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    // Every part of the runtime now renders from the lowered program alone.
    _ = allocator;
    try public_types.renderGoHandleRuntime(writer, program, options);
    try public_types.renderGoProjectionRuntime(writer, program, options);
    try public_types.renderGoCallbackTypes(writer, program, options);
    try public_runtime.renderPublicHelpers(writer, program, options);
}

/// After the native call: rethrow any panic a reachable callback recorded.
/// The receiver is pinned for the call, and each retained slot is read under
/// its mutex so a concurrent re-registration cannot race the scan.
/// The sweep runs only when some callback recorded a panic: one atomic load
/// on the fast path instead of a lock and a handle lookup per slot.
fn renderCallbackRethrows(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, function: semantic.SemanticFn, operation: []const u8) !void {
    const go_names = try common.goParamNamesForAlloc(allocator, function.params);
    defer naming.freeParamNames(allocator, go_names);
    try writer.writeAll("\tif zigoCallbackPanicPending() {\n");
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .callback and parameter.type != .io_stream) continue;
        try writer.print("\t\tzigoRethrowCallbackPanic(\"{s}\", {s}Handle)\n", .{ operation, go_names[parameter_index] });
    }
    if (function.receiver) |receiver| {
        if (common.typeOwnsCallbacks(program, receiver)) {
            const receiver_name = try common.receiverVariableAlloc(allocator, receiver, go_names);
            defer allocator.free(receiver_name);
            try writer.print("\t\tfor slot := range {d} {{\n\t\t\tzigoRethrowCallbackPanic(\"{s}\", {s}.zigoCallbackHandle(slot))\n\t\t}}\n", .{ program.retainedCallbackSlotCount(receiver), operation, receiver_name });
        }
    }
    for (function.params, 0..) |parameter, parameter_index| switch (parameter.type) {
        .opaque_ptr => |pointer| if (common.typeOwnsCallbacks(program, pointer.ref))
            try writer.print("\t\tif {0s} != nil {{\n\t\t\tfor slot := range {2d} {{\n\t\t\t\tzigoRethrowCallbackPanic(\"{1s}\", {0s}.zigoCallbackHandle(slot))\n\t\t\t}}\n\t\t}}\n", .{ go_names[parameter_index], operation, program.retainedCallbackSlotCount(pointer.ref) }),
        else => {},
    };
    try writer.writeAll("\t}\n");
}

/// A nil `io.Writer` or `io.Reader` is refused before anything native runs,
/// the same way a nil handle is: there is nothing to stream through, and the
/// shim adapter would call into a nil interface on the first crossing.
fn renderStreamNilChecks(
    scope: public_writers.PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: semantic.SemanticFn,
    go_names: []const []const u8,
    operation: []const u8,
    constructor: ?semantic.Constructor,
) !void {
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .io_stream) continue;
        const name = go_names[parameter_index];
        try writer.print("\tif {s} == nil {{\n\t\t", .{name});
        var expression: std.Io.Writer.Allocating = .init(allocator);
        defer expression.deinit();
        try expression.writer.print(
            "&StreamError{{Operation: \"{s}\", Parameter: \"{s}\", Err: ErrNilStream}}",
            .{ operation, name },
        );
        try public_writers.writeCheckedErrorReturn(scope, writer, function, constructor, expression.written());
        try writer.writeAll("\t}\n");
    }
}

/// After the call: the error the Go stream reported while the native code was
/// running, if it reported one.
fn renderStreamErrorChecks(
    scope: public_writers.PublicScope,
    writer: *std.Io.Writer,
    function: semantic.SemanticFn,
    go_names: []const []const u8,
    operation: []const u8,
    constructor: ?semantic.Constructor,
) !void {
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .io_stream) continue;
        const name = go_names[parameter_index];
        try writer.print(
            "\tif err := zigoStreamError(\"{s}\", \"{s}\", {s}Handle); err != nil {{\n\t\t",
            .{ operation, name, name },
        );
        try public_writers.writeCheckedErrorReturn(scope, writer, function, constructor, "err");
        try writer.writeAll("\t}\n");
    }
}

/// The cancellation flag and the goroutine that raises it. The word is Go's,
/// declared on this frame, and the native call borrows its address for exactly
/// as long as it runs -- which is what makes handing a Go pointer to C legal
/// here: the word holds no Go pointers and nothing keeps it afterwards.
///
/// A context that can never be cancelled costs no goroutine at all, and one
/// that already is raises the flag without starting one: the native call still
/// happens, sees the flag at its first polling point, and returns having done
/// nothing, which is the same answer by the same path.
fn renderCancelSetup(writer: *std.Io.Writer, options: emit.Options) !void {
    try writer.writeAll("\tvar zigoCancel uint32\n");
    // cgo pins a Go pointer it passes to C for the duration of the call, so
    // the address the native side polls cannot move under it. purego makes no
    // such promise -- it is an ordinary Go call into machine code -- so the
    // word is pinned explicitly there.
    if (options.backend == .purego)
        try writer.writeAll("\tvar zigoPinner runtime.Pinner\n\tzigoPinner.Pin(&zigoCancel)\n\tdefer zigoPinner.Unpin()\n");
    try writer.writeAll(
        "\tif ctx.Err() != nil {\n" ++
            "\t\tatomic.StoreUint32(&zigoCancel, 1)\n" ++
            "\t} else if zigoDone := ctx.Done(); zigoDone != nil {\n" ++
            "\t\tzigoStop := make(chan struct{})\n" ++
            "\t\tdefer close(zigoStop)\n" ++
            "\t\tgo func() {\n" ++
            "\t\t\tselect {\n" ++
            "\t\t\tcase <-zigoDone:\n" ++
            "\t\t\t\tatomic.StoreUint32(&zigoCancel, 1)\n" ++
            "\t\t\tcase <-zigoStop:\n" ++
            "\t\t\t}\n" ++
            "\t\t}()\n" ++
            "\t}\n",
    );
}

/// Keeps a caller-owned typed atomic at a stable address for exactly one
/// native call. cgo pins pointer arguments itself; purego needs Pinner because
/// its dynamic call bypasses cgo's pointer rules.
fn renderAtomicPointerPins(writer: *std.Io.Writer, function: abi.AbiFn, go_names: []const []const u8, options: emit.Options) !void {
    for (function.origin.params, 0..) |parameter, index| {
        if (parameter.type != .atomic_ptr) continue;
        const name = go_names[index];
        try writer.print("\tdefer runtime.KeepAlive({s})\n", .{name});
        if (options.backend == .purego) try writer.print(
            "\tvar {0s}Pinner runtime.Pinner\n\t{0s}Pinner.Pin({0s})\n\tdefer {0s}Pinner.Unpin()\n",
            .{name},
        );
    }
}

/// After the native call: the error a reachable Go callback returned, if one
/// did. Mirrors the panic rethrow, including the walk over a handle's retained
/// callbacks -- a retained callback's error is reported by the next call that
/// touches the handle, because the call it happened under had already left.
fn renderCallbackErrorChecks(
    scope: public_writers.PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    function: semantic.SemanticFn,
    go_names: []const []const u8,
    operation: []const u8,
    constructor: ?semantic.Constructor,
) !void {
    for (function.params, 0..) |parameter, parameter_index| {
        if (!common.callbackHasGoError(program, parameter)) continue;
        const name = go_names[parameter_index];
        try writer.print("\tif err := zigoCallbackError(\"{s}\", \"{s}\", {s}Handle); err != nil {{\n", .{ operation, name, name });
        // A retained callback is only deleted on the success path, so an early
        // return here has to release it exactly as the status check does.
        if (common.hasRetainedCallback(function) and !common.retainedCallbacksBelongToReceiver(program, function))
            try writeDeleteRetainedCallbacks(allocator, writer, function);
        try writer.writeAll("\t\t");
        try public_writers.writeCheckedErrorReturn(scope, writer, function, constructor, "err");
        try writer.writeAll("\t}\n");
    }
    if (function.receiver) |receiver| {
        if (common.typeOwnsErrorCallbacks(program, receiver)) {
            const receiver_name = try common.receiverVariableAlloc(allocator, receiver, go_names);
            defer allocator.free(receiver_name);
            try writer.print("\tfor slot := range {d} {{\n\t\tif err := zigoCallbackError(\"{s}\", \"callback\", {s}.zigoCallbackHandle(slot)); err != nil {{\n\t\t\t", .{ program.retainedCallbackSlotCount(receiver), operation, receiver_name });
            try public_writers.writeCheckedErrorReturn(scope, writer, function, constructor, "err");
            try writer.writeAll("\t\t}\n\t}\n");
        }
    }
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .opaque_ptr) continue;
        if (!common.typeOwnsErrorCallbacks(program, parameter.type.opaque_ptr.ref)) continue;
        const name = go_names[parameter_index];
        try writer.print("\tif {0s} != nil {{\n\t\tfor slot := range {2d} {{\n\t\t\tif err := zigoCallbackError(\"{1s}\", \"callback\", {0s}.zigoCallbackHandle(slot)); err != nil {{\n\t\t\t\t", .{ name, operation, program.retainedCallbackSlotCount(parameter.type.opaque_ptr.ref) });
        try public_writers.writeCheckedErrorReturn(scope, writer, function, constructor, "err");
        try writer.writeAll("\t\t\t}\n\t\t}\n\t}\n");
    }
}

fn renderCallbackHandleSetup(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, function: abi.AbiFn) !void {
    const go_names = try common.goParamNamesForAlloc(allocator, function.origin.params);
    defer naming.freeParamNames(allocator, go_names);
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (parameter.type == .io_stream) {
            // A stream is always call-scoped: the shim adapter around it lives
            // on the native stack, so the handle dies with the call.
            try writer.print("\t{0s}Handle := newZigo{1s}Handle({0s})\n\tdefer deleteCallbackHandle({0s}Handle)\n", .{
                go_names[parameter_index],
                common.streamHandleName(parameter.type.io_stream.direction),
            });
            if (common.isReaderStream(parameter))
                try writer.print("\t{0s}Data := zigoReaderBytes({0s})\n", .{go_names[parameter_index]});
            continue;
        }
        if (parameter.type != .callback) continue;
        const callback_name = function.callbackType(parameter_index).?.name;
        try writer.print("\t{s}Handle := new{s}Handle({s})\n", .{ go_names[parameter_index], callback_name, go_names[parameter_index] });
        if (parameter.retention == .borrowed) {
            try writer.print("\tdefer deleteCallbackHandle({s}Handle)\n", .{go_names[parameter_index]});
        } else if (common.retainedCallbacksBelongToReceiver(program, function.origin.*)) {
            try writer.print(
                "\t{0s}HandleAdopted := false\n" ++
                    "\tdefer func() {{ if !{0s}HandleAdopted {{ deleteCallbackHandle({0s}Handle) }} }}()\n",
                .{go_names[parameter_index]},
            );
        }
        if (function.origin.cancel != null) try writer.print(
            "\tsetCallbackCancel({0s}Handle, &zigoCancel)\n\tdefer setCallbackCancel({0s}Handle, nil)\n",
            .{go_names[parameter_index]},
        );
    }
}

fn writeDeleteRetainedCallbacks(allocator: std.mem.Allocator, writer: *std.Io.Writer, function: semantic.SemanticFn) !void {
    const go_names = try common.goParamNamesForAlloc(allocator, function.params);
    defer naming.freeParamNames(allocator, go_names);
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type == .callback and parameter.retention == .retained)
            try writer.print("\t\tdeleteCallbackHandle({s}Handle)\n", .{go_names[parameter_index]});
    }
}

/// Once a retaining method has successfully returned, native code has replaced
/// the callback pointer for this slot. Publish the matching Go handle under the
/// receiver lock, then release the displaced handle after dropping the lock.
fn writeAdoptRetainedMethodCallbacks(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    function: abi.AbiFn,
) !void {
    const receiver = function.origin.receiver orelse return;
    const owner = common.retainedCallbackOwner(program, function) orelse return;
    if (!std.mem.eql(u8, owner, receiver)) return;
    // A method that constructs an owned result transfers its retained callbacks
    // to that result, not to its receiver.
    if (function.ownership == .handle) return;
    const go_names = try common.goParamNamesForAlloc(allocator, function.origin.params);
    defer naming.freeParamNames(allocator, go_names);
    const receiver_name = try common.receiverVariableAlloc(allocator, receiver, go_names);
    defer allocator.free(receiver_name);
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .callback or parameter.retention != .retained) continue;
        const slot = function.callbackSlot(parameter_index) orelse unreachable;
        try writer.print(
            "\t{0s}PreviousHandle := {1s}.zigoReplaceCallbackHandle({2d}, {0s}Handle)\n" ++
                "\t{0s}HandleAdopted = true\n" ++
                "\tdeleteCallbackHandle({0s}PreviousHandle)\n",
            .{ go_names[parameter_index], receiver_name, slot },
        );
    }
}
