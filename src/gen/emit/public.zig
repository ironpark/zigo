//! The public Go package: one wrapper per function and the file plumbing
//! that decides which imports each concern file needs.
const handles = @import("handles.zig");
const type_spelling = @import("type_spelling.zig");
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const targets = @import("targets");
const naming = @import("naming");
const callbacks = @import("callbacks.zig");
const common = @import("common.zig");
const docs = @import("docs.zig");
const emit = @import("emit.zig");
const public_runtime = @import("public_runtime.zig");
const public_types = @import("public_types.zig");
const public_writers = @import("public_writers.zig");
const raw = @import("raw.zig");
const plugin = @import("plugin");
const plugin_hooks = @import("plugin_hooks.zig");
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
    try writer.print("\tzigoDecode{s}SliceInto(zigoBuffer, {s})\n", .{ output.root, name });
}

/// The raw layer returns a materialized buffer as a view of native memory;
/// decoding copies everything it keeps, so the buffer is released when the
/// wrapper returns. A failed call never produced a buffer, so this is written
/// after the status check.
fn writePublicMaterializedRelease(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: emit.Options,
    function: abi.AbiFn,
    buffer_name: []const u8,
) !void {
    _ = program;
    if (function.materialized_return == null and function.materialized_out == null) return;
    const owned = function.ownership.asBuffer() orelse return;
    const release = owned.release_function;
    const release_name = try common.rawGoNameAlloc(allocator, release.*);
    defer allocator.free(release_name);
    try writer.writeAll("\tdefer ");
    try public_writers.writeRawReferencePrefix(writer, options);
    try writer.print("{s}({s}{s})\n", .{ release_name, if (release.receiver != null) "ptr, " else "", buffer_name });
}

fn writePublicMaterializedAbsent(scope: public_writers.PublicScope, writer: *std.Io.Writer, function: abi.AbiFn, needs_check: bool) !void {
    const materialized = function.materialized_return orelse return;
    if (!materialized.optional) return;
    try writer.writeAll("\tif !zigoHas {\n\t\treturn ");
    try public_writers.writeGoZeroValue(scope, writer, function.origin.@"return".errorPayload().optional.child.*);
    try writer.writeAll(", false");
    if (materialized.fallible or needs_check) try writer.writeAll(", nil");
    try writer.writeAll("\n\t}\n");
}

fn writePublicCapturedReturn(scope: public_writers.PublicScope, writer: *std.Io.Writer, program: abi.Program, function: semantic.SemanticFn, needs_handle_check: bool) !void {
    try writer.writeAll("\treturn ");
    if (function.returnGoAdapter()) |adapter| try writer.print("{s}(", .{adapter.from_raw});
    switch (function.@"return") {
        .materialized => |value| try writer.print("zigoDecode{s}Buffer(result)", .{value.ref}),
        .value_struct => |value| if (type_spelling.isPackedValue(program, function.@"return"))
            try writer.print("{s}FromBacking(result)", .{value.ref})
        else
            try writer.print("zigo{s}FromRaw(result)", .{value.ref}),
        .slice => |value| if (value.element.* == .value_struct)
            try writer.print("zigo{s}{s}(result)", .{ value.element.*.value_struct.ref, publicSliceFromRawSuffix(program, value.element.*.value_struct.ref) })
        else if (value.element.* == .@"enum" and public_writers.enumAdapter(program, value.element.@"enum".ref) != null)
            try writer.print("zigo{s}SliceFromRaw(result)", .{value.element.@"enum".ref})
        else
            try writer.writeAll("result"),
        .bool => try writer.writeAll("result != 0"),
        .@"enum" => |value| try public_writers.writeEnumFromRaw(scope, writer, value.ref, "result"),
        else => if (!try public_writers.writeCodepointResult(writer, function.@"return", function.return_semantic, "result"))
            try writer.writeAll("result"),
    }
    if (function.returnGoAdapter() != null) try writer.writeByte(')');
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
    return writePublicOptionalRawSetupWithSource(allocator, writer, program, options, child, name, name);
}

fn writePublicOptionalRawSetupWithSource(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: emit.Options,
    child: semantic.TypeNode,
    name: []const u8,
    source: []const u8,
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
    try writer.print("\n\tif {s} != nil {{\n\t\t{s}RawValue := ", .{ source, name });
    switch (child) {
        .bool => try writer.print("zigoBoolToUint8(*{s})", .{source}),
        .@"enum" => |value| {
            const deref = try std.fmt.allocPrint(allocator, "*{s}", .{source});
            defer allocator.free(deref);
            try public_writers.writeEnumToRaw(program, writer, value.ref, deref);
        },
        .value_struct => |value| if (type_spelling.isPackedValue(program, child))
            try writer.print("(*{s}).Backing()", .{source})
        else
            try writer.print("zigo{s}ToRaw(*{s})", .{ value.ref, source }),
        else => unreachable,
    }
    try writer.print("\n\t\t{0s}Raw = &{0s}RawValue\n\t}}\n", .{name});
}

pub fn functionOptions(function: semantic.SemanticFn) ?struct {
    param_index: usize,
    spec: semantic.OptionsSpec,
    fields: []const semantic.FlattenedField,
} {
    for (function.params, 0..) |parameter, index| {
        if (parameter.goOptions()) |spec| {
            return .{
                .param_index = index,
                .spec = spec,
                .fields = parameter.flatten orelse &.{},
            };
        }
    }
    return null;
}

fn formatGoDefaultAlloc(
    allocator: std.mem.Allocator,
    scope: public_writers.PublicScope,
    field_type: semantic.TypeNode,
    default_value: semantic.FlattenedField.Value,
) ![]u8 {
    switch (default_value) {
        .null => return allocator.dupe(u8, "nil"),
        .bool => |b| return allocator.dupe(u8, if (b) "true" else "false"),
        .int => |i| return std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| {
            const raw_str = try std.fmt.allocPrint(allocator, "{d}", .{f});
            if (std.mem.indexOfScalar(u8, raw_str, '.') == null and
                std.mem.indexOfScalar(u8, raw_str, 'e') == null and
                std.mem.indexOfScalar(u8, raw_str, 'E') == null)
            {
                defer allocator.free(raw_str);
                return std.fmt.allocPrint(allocator, "{s}.0", .{raw_str});
            }
            return raw_str;
        },
        .@"enum" => |tag| {
            const enum_ref = switch (field_type) {
                .@"enum" => |e| e.ref,
                .optional => |opt| switch (opt.child.*) {
                    .@"enum" => |e| e.ref,
                    else => unreachable,
                },
                else => unreachable,
            };
            const pascal_tag = try naming.pascalAlloc(allocator, tag);
            defer allocator.free(pascal_tag);
            var expression: std.Io.Writer.Allocating = .init(allocator);
            defer expression.deinit();
            try scope.writeTypeName(&expression.writer, enum_ref);
            try expression.writer.writeAll(pascal_tag);
            return allocator.dupe(u8, expression.written());
        },
    }
}

fn renderFunctionOptions(
    scope: public_writers.PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    options_info: anytype,
    operation: []const u8,
) !void {
    const prefix_source = function.origin.goOwner() orelse function.origin.receiver;
    const opt_names = try naming.resolveOptionsNamesAlloc(
        allocator,
        options_info.spec.prefix,
        options_info.spec.type_name,
        prefix_source,
        function.origin.goName() orelse function.origin.name,
    );
    defer opt_names.deinit(allocator);

    const config_type_name = try opt_names.configTypeNameAlloc(allocator);
    defer allocator.free(config_type_name);

    // 1. Option type
    try writer.print("\n// {s} configures {s}.\ntype {s} func(*{s})\n\n", .{
        opt_names.type_name,
        operation,
        opt_names.type_name,
        config_type_name,
    });

    var zig_field_names = try allocator.alloc([]const u8, options_info.fields.len);
    defer allocator.free(zig_field_names);
    for (options_info.fields, 0..) |field, i| zig_field_names[i] = field.name;
    const field_go_names = try targets.go.paramNamesAlloc(allocator, zig_field_names);
    defer naming.freeParamNames(allocator, field_go_names);

    // 2. Unexported config struct
    try writer.print("type {s} struct {{\n", .{config_type_name});
    for (options_info.fields, 0..) |field, i| {
        try writer.print("\t{s} ", .{field_go_names[i]});
        try public_writers.writePublicGoType(scope, writer, field.type);
        try writer.writeByte('\n');
    }
    try writer.writeAll("}\n");

    // 3. With* constructor functions
    for (options_info.fields, 0..) |field, i| {
        const with_name = try opt_names.withNameAlloc(allocator, field.name);
        defer allocator.free(with_name);

        const default_str = if (field.default) |default_val|
            try formatGoDefaultAlloc(allocator, scope, field.type, default_val)
        else
            try allocator.dupe(u8, "nil");
        defer allocator.free(default_str);

        try writer.print("\n// {s} configures {s}. Default: {s}.\n", .{
            with_name,
            field.name,
            default_str,
        });
        try writer.print("func {s}({s} ", .{ with_name, field_go_names[i] });
        try public_writers.writePublicGoType(scope, writer, field.type);
        try writer.print(") {s} {{\n", .{opt_names.type_name});
        try writer.print("\treturn func(cfg *{s}) {{\n\t\tcfg.{s} = {s}\n\t}}\n}}\n", .{
            config_type_name,
            field_go_names[i],
            field_go_names[i],
        });
    }
}

fn renderFunctionOptionsInit(
    scope: public_writers.PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    options_info: anytype,
) !void {
    const prefix_source = function.origin.goOwner() orelse function.origin.receiver;
    const opt_names = try naming.resolveOptionsNamesAlloc(
        allocator,
        options_info.spec.prefix,
        options_info.spec.type_name,
        prefix_source,
        function.origin.goName() orelse function.origin.name,
    );
    defer opt_names.deinit(allocator);

    const config_type_name = try opt_names.configTypeNameAlloc(allocator);
    defer allocator.free(config_type_name);

    var zig_field_names = try allocator.alloc([]const u8, options_info.fields.len);
    defer allocator.free(zig_field_names);
    for (options_info.fields, 0..) |field, i| zig_field_names[i] = field.name;
    const field_go_names = try targets.go.paramNamesAlloc(allocator, zig_field_names);
    defer naming.freeParamNames(allocator, field_go_names);

    try writer.print("\tcfg := {s}{{\n", .{config_type_name});
    for (options_info.fields, 0..) |field, i| {
        const default_str = if (field.default) |default_val|
            try formatGoDefaultAlloc(allocator, scope, field.type, default_val)
        else
            try allocator.dupe(u8, "nil");
        defer allocator.free(default_str);
        try writer.print("\t\t{s}: {s},\n", .{ field_go_names[i], default_str });
    }
    try writer.writeAll("\t}\n\tfor _, opt := range opts {\n\t\topt(&cfg)\n\t}\n");
}

fn publicNeedsUnsafe(program: abi.Program) bool {
    if (programHasCodepointSlice(program)) return true;
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (parameter.type == .atomic_ptr) return true;
            if (!isValueStructSlice(parameter.type)) continue;
            if (program.structCastable(parameter.type.slice.element.*.value_struct.ref)) return true;
        }
    }
    return false;
}

/// Whether any public signature carries a `[]rune`, which the two view
/// helpers at the end of the file reinterpret as the raw `[]uint32`.
fn programHasCodepointSlice(program: abi.Program) bool {
    for (program.functions) |function| {
        if (!emitsPublicFunction(program, function)) continue;
        if (semantic.isCodepointSlice(function.origin.@"return".errorPayload(), function.origin.return_semantic)) return true;
        for (function.origin.params) |parameter| {
            if (semantic.isCodepointSlice(parameter.type, parameter.semantic)) return true;
        }
    }
    return false;
}

/// `[]rune` and `[]uint32` share one memory layout, so a public codepoint
/// slice is viewed rather than copied in both directions.
fn renderCodepointSliceHelpers(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        "\n// zigoRunesToUint32 views a []rune as the []uint32 the raw layer takes, without copying.\n" ++
            "func zigoRunesToUint32(values []rune) []uint32 {\n" ++
            "\treturn unsafe.Slice((*uint32)(unsafe.Pointer(unsafe.SliceData(values))), len(values))\n" ++
            "}\n\n" ++
            "// zigoUint32ToRunes views a []uint32 from the raw layer as a []rune, without copying.\n" ++
            "func zigoUint32ToRunes(values []uint32) []rune {\n" ++
            "\treturn unsafe.Slice((*rune)(unsafe.Pointer(unsafe.SliceData(values))), len(values))\n" ++
            "}\n",
    );
}

pub fn renderPublic(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    var file_options = options;
    if (file_options.file == null) file_options.file = .{ .path = "", .kind = .api };
    return renderPublicFile(allocator, writer, program, file_options, renderPublicBody);
}

fn renderPublicBody(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    const scope: public_writers.PublicScope = .{ .program = program, .options = options };
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
            try common.typeReceiverNameAlloc(allocator, program, receiver)
        else
            null;
        defer if (receiver_name) |name| allocator.free(name);
        const go_name = try targets.go.publicFunctionNameAlloc(allocator, .{ .constructors = program.constructors, .package = program.package, .prefix = program.prefix, .zig_version = "" }, function.origin.*);
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
        if (functionOptions(function.origin.*)) |options_info| {
            try renderFunctionOptions(scope, allocator, writer, function, options_info, operation);
        }
        try docs.writePublicFunctionDoc(writer, function.origin.*, go_name, owned_type, public_writers.functionReachesCallbacks(program, function.origin.*), has_callback_error);
        if (function.origin.receiver) |receiver| {
            // A value receiver is spelled by value: there is no handle to
            // point at, and nothing the method could mutate through a pointer.
            const pointer = if (function.origin.receiverIsValue()) "" else "*";
            try writer.print("func ({s} {s}{s}) {s}", .{ receiver_name.?, pointer, receiver, go_name });
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
        // zigoErrorForCode reads the panic message out of native thread-local
        // storage in a second cgo call, so the goroutine must stay on the
        // thread that made the first one until it has been read.
        // Before the thread pin, because a rejected argument costs no cgo call
        // at all: nothing native has run, so there is no panic message to read
        // back off this thread.
        if (function.origin.cancel != null) try renderCancelSetup(writer, options);
        if (functionOptions(function.origin.*)) |options_info| {
            try renderFunctionOptionsInit(scope, allocator, writer, function, options_info);
        }
        try renderAtomicPointerPins(writer, function, go_names, options);
        if (needs_range_check)
            try public_writers.renderRangeChecks(scope, allocator, writer, function, go_names, operation, constructor);
        if (has_stream)
            try renderStreamNilChecks(scope, allocator, writer, function.origin.*, go_names, operation, constructor);
        // The handle checks run before any callback handle is registered, so
        // an early return cannot strand a retained callback.
        if (needs_handle_check)
            try public_writers.renderHandleChecks(scope, allocator, writer, function.origin.*, go_names, operation, constructor, options);
        // Check every callback before allocating any handle or changing a native slot.
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .callback) continue;
            try writer.print("\tif {s} == nil {{\n\t\t", .{go_names[parameter_index]});
            var expression: std.Io.Writer.Allocating = .init(allocator);
            defer expression.deinit();
            try expression.writer.print("&CallbackError{{Operation: \"{s}\", Callback: \"{s}\", Err: ErrNilCallback}}", .{ operation, go_names[parameter_index] });
            if (shape.needs_check or function.origin.@"return" == .error_union)
                try public_writers.writeCheckedErrorReturn(scope, writer, function.origin.*, constructor, expression.written())
            else
                try writer.print("panic({s})\n", .{expression.written()});
            try writer.writeAll("\t}\n");
        }
        try renderCallbackHandleSetup(allocator, writer, program, function);
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (!isValueStructSlice(parameter.type)) continue;
            try writePublicSliceRawSetup(allocator, writer, program, options, parameter, go_names[parameter_index]);
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.flatten) |fields| {
                const is_options = parameter.goOptions() != null;
                for (fields, 0..) |field, field_index| {
                    if (field.type != .optional) continue;
                    const abi_parameter = function.flattenedParam(parameter_index, field_index);
                    const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                    defer allocator.free(name);
                    if (is_options) {
                        const raw_names = try targets.go.paramNamesAlloc(allocator, &.{field.name});
                        defer naming.freeParamNames(allocator, raw_names);
                        const source = try std.fmt.allocPrint(allocator, "cfg.{s}", .{raw_names[0]});
                        defer allocator.free(source);
                        try writePublicOptionalRawSetupWithSource(allocator, writer, program, options, field.type.optional.child.*, name, source);
                    } else {
                        try writePublicOptionalRawSetup(allocator, writer, program, options, field.type.optional.child.*, name);
                    }
                }
                continue;
            }
            if (parameter.type != .optional) continue;
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
        const captures_return = !returns_error and !borrowed_direct and !owned_direct and function.origin.@"return" != .optional and
            (hasOutValueStructSlice(function.origin.*) or function.materialized_out != null or function.materialized_return != null or needs_rethrow) and function.origin.@"return" != .void;
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
        } else if (function.origin.@"return" != .void) {
            if (function.origin.@"return" == .@"enum") {
                const ref = function.origin.@"return".@"enum".ref;
                if (public_writers.enumAdapter(program, ref) != null) {
                    try writer.print("return zigo{s}FromRaw(", .{ref});
                } else {
                    try writer.writeAll("return ");
                    try scope.writeTypeName(writer, ref);
                    try writer.writeByte('(');
                }
                try public_writers.writeRawReferencePrefix(writer, options);
            } else if (function.origin.returnGoAdapter()) |adapter| {
                try writer.print("return {s}(", .{adapter.from_raw});
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
            } else if (isAdaptedEnumSlice(program, function.origin.@"return")) {
                try writer.print("return zigo{s}SliceFromRaw(", .{function.origin.@"return".slice.element.@"enum".ref});
                try public_writers.writeRawReferencePrefix(writer, options);
            } else if (function.origin.@"return" == .materialized) {
                try writer.print("return zigoDecode{s}Buffer(", .{function.origin.@"return".materialized.ref});
                try public_writers.writeRawReferencePrefix(writer, options);
            } else if (function.origin.@"return" == .slice and function.origin.@"return".slice.element.* == .materialized) {
                try writer.print("return zigoDecode{s}SliceBuffer(", .{function.origin.@"return".slice.element.materialized.ref});
                try public_writers.writeRawReferencePrefix(writer, options);
            } else if (public_writers.codepointTypeName(function.origin.@"return", function.origin.return_semantic)) |name| {
                try writer.writeAll(if (name[0] == '[') "return zigoUint32ToRunes(" else "return rune(");
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
        if (function.origin.receiver) |receiver| {
            if (function.origin.receiverIsValue()) {
                // The receiver is the value itself; the raw layer takes the
                // enum's backing integer.
                const variable = try common.typeReceiverNameAlloc(allocator, program, receiver);
                defer allocator.free(variable);
                try public_writers.writeRawGoType(writer, program, .{ .@"enum" = .{ .ref = receiver } });
                try writer.print("({s})", .{variable});
            } else try writer.writeAll("ptr");
            call_index = 1;
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (function.userdataFor(parameter_index) != null) continue;
            if (parameter.injected != null) continue;
            if (parameter.flatten) |fields| {
                const is_options = parameter.goOptions() != null;
                for (fields, 0..) |field, field_index| {
                    const abi_parameter = function.flattenedParam(parameter_index, field_index);
                    const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                    defer allocator.free(name);
                    const field_source = if (is_options) blk: {
                        const raw_names = try targets.go.paramNamesAlloc(allocator, &.{field.name});
                        defer naming.freeParamNames(allocator, raw_names);
                        break :blk try std.fmt.allocPrint(allocator, "cfg.{s}", .{raw_names[0]});
                    } else try allocator.dupe(u8, name);
                    defer allocator.free(field_source);

                    if (call_index != 0) try writer.writeAll(", ");
                    const node = if (field.type == .optional) field.type.optional.child.* else field.type;
                    if (field.type == .optional and publicOptionalNeedsConversion(node)) {
                        try writer.print("{s}Raw", .{name});
                    } else switch (node) {
                        .bool => try writer.print("zigoBoolToUint8({s})", .{field_source}),
                        .@"enum" => |value| try public_writers.writeEnumToRaw(program, writer, value.ref, field_source),
                        .value_struct => if (type_spelling.isPackedValue(program, node))
                            try writer.print("{s}.Backing()", .{field_source})
                        else
                            try writer.writeAll(field_source),
                        else => try writer.writeAll(field_source),
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
                // A per-site adapter converts the scalar first; the raw
                // conversion (if any) wraps the converted value.
                .bool => if (parameter.goAdapter()) |adapter|
                    try writer.print("zigoBoolToUint8({s}({s}))", .{ adapter.to_raw, go_names[parameter_index] })
                else
                    try writer.print("zigoBoolToUint8({s})", .{go_names[parameter_index]}),
                .value_struct => |value| if (common.isTaggedUnionValue(program, parameter.type))
                    try public_writers.writePublicTaggedUnionRawArguments(allocator, writer, program, type_spelling.enumDecl(program, value.ref), go_names[parameter_index])
                else if (type_spelling.isPackedValue(program, parameter.type))
                    try writer.print("{s}.Backing()", .{go_names[parameter_index]})
                else
                    try writer.print("zigo{s}ToRaw({s})", .{ value.ref, go_names[parameter_index] }),
                .@"enum" => |value| try public_writers.writeEnumToRaw(program, writer, value.ref, go_names[parameter_index]),
                .opaque_ptr => try writer.print("{s}Ptr", .{go_names[parameter_index]}),
                .optional => |optional| if (publicOptionalNeedsConversion(optional.child.*))
                    try writer.print("{s}Raw", .{go_names[parameter_index]})
                else
                    try writer.writeAll(go_names[parameter_index]),
                .slice => if (function.materializesParam(parameter_index))
                    try writer.print("len({s})", .{go_names[parameter_index]})
                else if (isValueStructSlice(parameter.type))
                    try writer.print("{s}Raw", .{go_names[parameter_index]})
                else if (function.paramString(parameter_index).role == .string_slice)
                    try writer.writeAll(go_names[parameter_index])
                else if (parameter.type.slice.element.* == .@"enum" and public_writers.enumAdapter(program, parameter.type.slice.element.@"enum".ref) != null)
                    try writer.print("zigo{s}SliceToRaw({s})", .{ parameter.type.slice.element.@"enum".ref, go_names[parameter_index] })
                else if (!try public_writers.writeCodepointArgument(writer, parameter, go_names[parameter_index]))
                    try writer.writeAll(go_names[parameter_index]),
                else => if (parameter.goAdapter()) |adapter|
                    try writer.print("{s}({s})", .{ adapter.to_raw, go_names[parameter_index] })
                else if (!try public_writers.writeCodepointArgument(writer, parameter, go_names[parameter_index]))
                    try writer.writeAll(go_names[parameter_index]),
            }
            call_index += 1;
        }
        try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .@"enum") try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .value_struct) try writer.writeByte(')');
        if (!returns_error and !captures_return and isValueStructSlice(function.origin.@"return")) try writer.writeByte(')');
        if (!returns_error and !captures_return and isAdaptedEnumSlice(program, function.origin.@"return")) try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .materialized) try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .slice and function.origin.@"return".slice.element.* == .materialized) try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .bool) try writer.writeAll(" != 0");
        if (!returns_error and !captures_return and function.origin.returnGoAdapter() != null) try writer.writeByte(')');
        if (!returns_error and !captures_return and public_writers.codepointTypeName(function.origin.@"return", function.origin.return_semantic) != null) try writer.writeByte(')');
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
        if (!returns_error) try writePublicMaterializedAbsent(scope, writer, function, needs_check);
        if (!returns_error) try writePublicMaterializedRelease(allocator, writer, program, options, function, if (function.materialized_out != null) "zigoBuffer" else if (function.origin.@"return" == .optional) "zigoResult" else "result");
        if (!returns_error and function.materialized_out != null)
            try writePublicMaterializedOutCopy(writer, function, go_names);
        if (!returns_error and function.origin.@"return" == .optional) {
            const child = function.origin.@"return".optional.child.*;
            try writer.writeAll("\treturn ");
            if (semantic.isStringSlice(child, function.origin.return_semantic))
                try writer.writeAll("zigoResult")
            else if (!try public_writers.writeCodepointResult(writer, child, function.origin.return_semantic, "zigoResult"))
                try public_writers.writePublicResultConversion(scope, writer, program, child, "zigoResult");
            try writer.writeAll(", zigoHas");
            if (needs_check) try writer.writeAll(", nil");
            try writer.writeByte('\n');
        }
        if (captures_return) try writePublicCapturedReturn(scope, writer, program, function.origin.*, needs_check);
        if (borrowed_direct or owned_direct) {
            if (function.origin.childOfReceiver()) try writer.writeAll("\tzigoChildCreated = true\n");
            if (docs.returnsBorrowedView(function.origin.*) and function.origin.@"return".opaque_ptr.nullable)
                try writer.writeAll("\tif result == nil {\n\t\treturn nil, false, nil\n\t}\n");
            try writer.writeAll("\treturn ");
            if (owned_type != null)
                try handles.writeOwnedHandleResult(allocator, writer, function, "result")
            else
                try public_writers.writeBorrowedResult(allocator, writer, program, function.origin.*, "result");
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
                try public_writers.writeErrorForCode(allocator, writer, program, function.origin.*, go_names, operation);
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
                try public_writers.writeErrorForCode(allocator, writer, program, function.origin.*, go_names, operation);
            try writer.writeAll("\t}\n");
            try writeAdoptRetainedMethodCallbacks(allocator, writer, program, function);
            if (hasOutValueStructSlice(function.origin.*)) {
                try writePublicValueStructSliceCopyBacks(writer, program, function.origin.*, go_names);
            }
            try writePublicMaterializedAbsent(scope, writer, function, needs_check);
            try writePublicMaterializedRelease(allocator, writer, program, options, function, if (function.materialized_out != null) "zigoBuffer" else "result");
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
                    try public_writers.writeBorrowedResult(allocator, writer, program, function.origin.*, "result");
                    try writer.writeAll(", true, nil\n");
                } else {
                    try writer.writeAll("\treturn ");
                    if (owned_type != null) {
                        try handles.writeOwnedHandleResult(allocator, writer, function, "result");
                    } else if (error_payload == .opaque_ptr and docs.returnsBorrowedOpaque(function.origin.*)) {
                        try public_writers.writeBorrowedResult(allocator, writer, program, function.origin.*, "result");
                    } else if (error_payload == .optional) {
                        if (semantic.isStringSlice(error_payload.optional.child.*, function.origin.return_semantic))
                            try writer.writeAll("result")
                        else if (!try public_writers.writeCodepointResult(writer, error_payload.optional.child.*, function.origin.return_semantic, "result"))
                            try public_writers.writePublicResultConversion(scope, writer, program, error_payload.optional.child.*, "result");
                        try writer.writeAll(", zigoHas");
                    } else if (semantic.isStringSlice(error_payload, function.origin.return_semantic)) {
                        try writer.writeAll("result");
                    } else if (function.origin.returnGoAdapter()) |adapter| {
                        try writer.print("{s}(", .{adapter.from_raw});
                        try public_writers.writePublicResultConversion(scope, writer, program, error_payload, "result");
                        try writer.writeByte(')');
                    } else if (!try public_writers.writeCodepointResult(writer, error_payload, function.origin.return_semantic, "result")) {
                        try public_writers.writePublicResultConversion(scope, writer, program, error_payload, "result");
                    }
                    try writer.writeAll(", nil\n");
                }
            }
        }
        try writer.writeAll("}\n");
        try plugin_hooks.runMethodHooks(plugin_hooks.methodContext(allocator, program, options, .{
            .public_name = go_name,
            .receiver = function.origin.receiver,
            .receiver_name = receiver_name,
            .param_names = go_names,
            .owned_type = owned_type,
            .needs_check = needs_check,
        }), writer, function);
    }
    if (programHasCodepointSlice(program)) try renderCodepointSliceHelpers(writer);
}

/// Renders one concern-scoped file of the public package: the generated
/// marker, the package clause, the import block the body actually needs, and
/// the body. A body that declares nothing leaves the file at its prelude, and
/// the generator drops it.
pub fn renderPublicFile(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: emit.Options,
    renderBody: *const fn (std.mem.Allocator, *std.Io.Writer, abi.Program, emit.Options) anyerror!void,
) !void {
    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();
    try renderBody(allocator, &body.writer, program, options);
    try writePublicFileBody(allocator, writer, program, options, body.written());
}

/// Every public file, including union and plugin files, uses this frame.
pub fn writePublicFileBody(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options, contents: []const u8) !void {
    const go = if (options.file) |file| file.source_file else null;
    if (go != null and std.mem.trim(u8, contents, " \t\r\n").len == 0) return;
    const target: plugin.PackageKind = if (go) |file| file.package else .public;
    const public_package = try common.publicPackageAlloc(allocator, program, options);
    defer allocator.free(public_package);
    const package = switch (target) {
        .public => try allocator.dupe(u8, public_package),
        .external_test => try std.fmt.allocPrint(allocator, "{s}_test", .{public_package}),
        .raw => try allocator.dupe(u8, options.raw_package_name),
    };
    defer allocator.free(package);
    const production_hooks = if (go) |file| file.package == .public and file.kind == .source and file.scope == .package else true;
    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();
    const context = plugin_hooks.context(allocator, program, options);
    if (production_hooks) try plugin_hooks.runFileHooks(context, &body.writer, .begin);
    try body.writer.writeAll(contents);
    if (production_hooks) try plugin_hooks.runFileHooks(context, &body.writer, .end);
    if (go != null and std.mem.trim(u8, body.written(), " \t\r\n").len == 0) return;
    if (go) |file| if (file.build_constraint) |constraint| try writer.print("//go:build {s}\n\n", .{constraint});
    try writer.writeAll("// Code generated by zigo. DO NOT EDIT.\n\n");
    if (options.file != null and options.file.?.kind == .api) try docs.writePublicPackageDoc(writer, package, program, options);
    try writer.print("package {s}\n", .{package});
    if (body.written().len == 0) return;
    if (target == .public) {
        try writePublicImports(allocator, writer, body.written(), program, options);
    } else {
        try writeStandaloneImports(allocator, writer, body.written(), if (go.?.imports) |imports| try imports(context) else &.{});
    }
    try writer.writeAll(body.written());
}

/// Foreign Go packages have explicit imports and no public helper/type inference.
fn writeStandaloneImports(allocator: std.mem.Allocator, writer: *std.Io.Writer, body: []const u8, local: []const plugin.Import) !void {
    var imports: std.ArrayList(plugin.Import) = .empty;
    defer imports.deinit(allocator);
    for (public_std_imports) |entry| try appendGoImport(allocator, &imports, .{ .qualifier = entry.qualifier, .path = entry.path }, body);
    for (plugin_hooks.declaredImports()) |entry| try appendGoImport(allocator, &imports, entry, body);
    for (local) |entry| try appendGoImport(allocator, &imports, entry, body);
    std.mem.sort(plugin.Import, imports.items, {}, struct {
        fn lessThan(_: void, a: plugin.Import, b: plugin.Import) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);
    if (imports.items.len == 0) return writer.writeByte('\n');
    if (imports.items.len == 1) {
        try writer.writeAll("\nimport ");
        try writePluginImport(writer, imports.items[0], "");
        return writer.writeByte('\n');
    }
    try writer.writeAll("\nimport (\n");
    for (imports.items) |entry| try writePluginImport(writer, entry, "\t");
    try writer.writeAll(")\n\n");
}

fn appendGoImport(allocator: std.mem.Allocator, imports: *std.ArrayList(plugin.Import), entry: plugin.Import, body: []const u8) !void {
    if (!std.mem.eql(u8, entry.qualifier, "_") and !std.mem.eql(u8, entry.qualifier, ".") and !bodyUsesQualifier(body, entry.qualifier)) return;
    for (imports.items) |existing| {
        if (!std.mem.eql(u8, existing.qualifier, entry.qualifier)) continue;
        if ((std.mem.eql(u8, entry.qualifier, "_") or std.mem.eql(u8, entry.qualifier, ".")) and !std.mem.eql(u8, existing.path, entry.path)) continue;
        if (!std.mem.eql(u8, existing.path, entry.path)) return error.AmbiguousGoImport;
        return;
    }
    try imports.append(allocator, entry);
}

/// Every standard-library package a generated public file can need, in the
/// order gofmt sorts them. The qualifier is what the body writes, so the
/// import block is derived from the body instead of from a second, parallel
/// set of predicates that could disagree with it.
const public_std_imports = [_]struct { qualifier: []const u8, path: []const u8 }{
    .{ .qualifier = "context", .path = "context" },
    .{ .qualifier = "errors", .path = "errors" },
    .{ .qualifier = "fmt", .path = "fmt" },
    .{ .qualifier = "iter", .path = "iter" },
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
    const needs_handle_check = function.origin.receiverIsHandle() or lower.hasOpaqueParameter(function.origin.*);
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
    _ = try writePublicResults(scope, writer, function, constructor, .{});
}

/// The same result spelling used by normal methods and external wrappers.
/// Returns arity after applying the trailing-error policy.
pub fn writePublicResults(scope: public_writers.PublicScope, writer: *std.Io.Writer, function: abi.AbiFn, constructor: ?semantic.Constructor, options: @import("plugin").ResultOptions) !usize {
    const origin = function.origin.*;
    const payload = origin.@"return".errorPayload();
    const has_error = constructor != null or origin.@"return" == .error_union or signatureShape(function).needs_check;
    const value_count: usize = if (constructor != null) 1 else if (payload == .void) 0 else if (payload == .optional or
        (payload == .opaque_ptr and payload.opaque_ptr.nullable and docs.returnsBorrowedView(origin))) 2 else 1;
    if (options.omit_error) {
        if (constructor) |value| {
            try writer.print(" *{s}", .{value.type});
        } else {
            var unwrapped = origin;
            unwrapped.@"return" = payload;
            try public_writers.writePublicFunctionReturnType(scope, writer, unwrapped);
        }
        return value_count;
    }
    if (constructor) |value| {
        try writer.print(" (*{s}, error)", .{value.type});
    } else if (signatureShape(function).needs_check and function.origin.@"return" != .error_union) {
        try public_writers.writeCheckedFunctionReturnType(scope, writer, function.origin.*);
    } else {
        try public_writers.writePublicFunctionReturnType(scope, writer, function.origin.*);
    }
    return value_count + @intFromBool(has_error);
}

/// Forward the exact public argument list, including flattened fields and
/// context, while omitting native-only userdata and injected parameters.
pub fn writePublicCallArguments(allocator: std.mem.Allocator, writer: *std.Io.Writer, function: abi.AbiFn, go_names: [][]u8) !void {
    var index: usize = 0;
    if (function.origin.cancel != null) {
        try writer.writeAll("ctx");
        index = 1;
    }
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (function.userdataFor(parameter_index) != null or parameter.injected != null or parameter.type == .cancel_flag) continue;
        if (parameter.flatten) |fields| {
            if (parameter.goOptions() != null) continue;
            for (fields, 0..) |_, field_index| {
                const abi_parameter = function.flattenedParam(parameter_index, field_index);
                const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                defer allocator.free(name);
                if (index != 0) try writer.writeAll(", ");
                try writer.writeAll(name);
                index += 1;
            }
            continue;
        }
        if (index != 0) try writer.writeAll(", ");
        try writer.writeAll(go_names[parameter_index]);
        index += 1;
    }
    for (function.origin.params) |parameter| {
        if (parameter.goOptions() != null) {
            if (index != 0) try writer.writeAll(", ");
            try writer.writeAll("opts...");
            break;
        }
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
            if (parameter.goOptions() != null) continue;
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
    for (function.origin.params) |parameter| {
        const opt_spec = parameter.goOptions() orelse continue;
        const prefix_source = function.origin.goOwner() orelse function.origin.receiver;
        const opt_names = try naming.resolveOptionsNamesAlloc(
            allocator,
            opt_spec.prefix,
            opt_spec.type_name,
            prefix_source,
            function.origin.goName() orelse function.origin.name,
        );
        defer opt_names.deinit(allocator);
        if (index != 0) try writer.writeAll(", ");
        if (go_names != null) {
            try writer.print("opts ...{s}", .{opt_names.type_name});
        } else {
            try writer.print("...{s}", .{opt_names.type_name});
        }
        break;
    }
}

pub fn writePublicImports(allocator: std.mem.Allocator, writer: *std.Io.Writer, body: []const u8, program: abi.Program, options: emit.Options) !void {
    // The standard-library group, which a plugin can add to: `encoding/json`
    // sits between `encoding/binary` and `io` rather than in a group of its
    // own, since that is where gofmt would put it.
    var std_group: std.ArrayList(plugin.Import) = .empty;
    defer std_group.deinit(allocator);
    for (public_std_imports) |entry| try appendGoImport(allocator, &std_group, .{ .qualifier = entry.qualifier, .path = entry.path }, body);
    for (plugin_hooks.declaredImports()) |entry| try appendGoImport(allocator, &std_group, entry, body);
    if (options.file) |info| if (info.source_file) |file| {
        if (file.imports) |imports| for (try imports(plugin_hooks.context(allocator, program, options))) |entry| try appendGoImport(allocator, &std_group, entry, body);
    };
    std.mem.sort(plugin.Import, std_group.items, {}, struct {
        fn lessThan(_: void, lhs: plugin.Import, rhs: plugin.Import) bool {
            return std.mem.lessThan(u8, lhs.path, rhs.path);
        }
    }.lessThan);
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
    if (uses_raw) try removeInferredImportAlloc(allocator, &std_group, "raw", "{s}/{s}", .{ options.go_module, options.raw_package_path });
    if (lifecycle) try removeInferredImportAlloc(allocator, &std_group, "lifecycle", "{s}/{s}", .{ options.go_module, options.lifecycle_package_path });
    const base = naming.optionalPathSegment(options.default_package_path);
    if (default_foreign) try removeInferredImportAlloc(allocator, &std_group, "zigo_default", "{s}{s}{s}", .{ options.go_module, base.separator, base.value });
    for (foreign.items) |package| {
        const qualifier = try std.fmt.allocPrint(allocator, "zigo_pkg_{s}", .{package.name});
        defer allocator.free(qualifier);
        try removeInferredImportAlloc(allocator, &std_group, qualifier, "{s}{s}{s}/{s}", .{ options.go_module, base.separator, base.value, package.path });
    }
    const count = std_group.items.len;
    var adapters: std.ArrayList(semantic.GoAdapter) = .empty;
    defer adapters.deinit(allocator);
    for (program.types) |declaration| {
        const adapter = declaration.goAdapter() orelse continue;
        try appendAdapterImportIfUsed(allocator, &adapters, std_group.items, adapter, body);
    }
    for (program.functions) |function| {
        if (function.origin.returnGoAdapter()) |adapter| try appendAdapterImportIfUsed(allocator, &adapters, std_group.items, adapter, body);
        for (function.origin.params) |parameter| if (parameter.goAdapter()) |adapter| try appendAdapterImportIfUsed(allocator, &adapters, std_group.items, adapter, body);
    }
    if (count == 0 and !uses_raw and !lifecycle and !default_foreign and foreign.items.len == 0 and adapters.items.len == 0) return writer.writeByte('\n');
    if (count + @as(usize, @intFromBool(uses_raw)) + @as(usize, @intFromBool(lifecycle)) + @as(usize, @intFromBool(default_foreign)) + foreign.items.len + adapters.items.len == 1) {
        try writer.writeAll("\nimport ");
        if (adapters.items.len == 1) {
            try writeAdapterImport(writer, adapters.items[0], "");
        } else if (uses_raw) {
            try public_writers.writeRawImport(writer, options, "");
        } else if (foreign.items.len == 1) {
            try writeForeignImport(writer, foreign.items[0], options, "");
        } else if (default_foreign) {
            try writeDefaultPackageImport(writer, options, "");
        } else if (lifecycle) {
            try writer.print("lifecycle \"{s}/{s}\"\n", .{ options.go_module, options.lifecycle_package_path });
        } else {
            try writePluginImport(writer, std_group.items[0], "");
        }
        return writer.writeByte('\n');
    }
    try writer.writeAll("\nimport (\n");
    for (std_group.items) |entry| try writePluginImport(writer, entry, "\t");
    for (adapters.items) |adapter| try writeAdapterImport(writer, adapter, "\t");
    if (uses_raw) {
        if (count != 0 or adapters.items.len != 0) try writer.writeByte('\n');
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

/// A locally declared import can agree with an inferred package import, but
/// cannot silently redirect a qualifier the generated body already owns.
fn removeInferredImportAlloc(allocator: std.mem.Allocator, imports: *std.ArrayList(plugin.Import), qualifier: []const u8, comptime format: []const u8, args: anytype) !void {
    const path = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(path);
    for (imports.items, 0..) |entry, index| {
        if (!std.mem.eql(u8, entry.qualifier, qualifier)) continue;
        if (!std.mem.eql(u8, entry.path, path)) return error.AmbiguousGoImport;
        _ = imports.orderedRemove(index);
        return;
    }
}

/// One `import` line of the standard-library group: aliased when the
/// qualifier the body writes is not the import path's last segment, which
/// only a plugin-declared import can be.
fn writePluginImport(writer: *std.Io.Writer, entry: plugin.Import, indent: []const u8) !void {
    const path = entry.path;
    const last = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| path[slash + 1 ..] else path;
    if (std.mem.eql(u8, entry.qualifier, last))
        try writer.print("{s}\"{s}\"\n", .{ indent, path })
    else
        try writer.print("{s}{s} \"{s}\"\n", .{ indent, entry.qualifier, path });
}

/// One `import` line for a `.go` adapter: aliased when the qualifier the
/// type is written with is not the import path's last segment.
fn writeAdapterImport(writer: *std.Io.Writer, adapter: semantic.GoAdapter, indent: []const u8) !void {
    const path = adapter.import.?;
    const last = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| path[slash + 1 ..] else path;
    const qualifier = adapter.qualifier() orelse last;
    if (std.mem.eql(u8, qualifier, last))
        try writer.print("{s}\"{s}\"\n", .{ indent, path })
    else
        try writer.print("{s}{s} \"{s}\"\n", .{ indent, qualifier, path });
}

/// Adds an adapter's import when the rendered body spells its qualifier.
fn appendAdapterImportIfUsed(allocator: std.mem.Allocator, list: *std.ArrayList(semantic.GoAdapter), existing_imports: []const plugin.Import, adapter: semantic.GoAdapter, body: []const u8) !void {
    const path = adapter.import orelse return;
    const last = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| path[slash + 1 ..] else path;
    const qualifier = adapter.qualifier() orelse last;
    if (!bodyUsesQualifier(body, qualifier)) return;
    for (existing_imports) |entry| {
        if (!std.mem.eql(u8, entry.qualifier, qualifier)) continue;
        if (!std.mem.eql(u8, entry.path, path)) return error.AmbiguousGoImport;
        return;
    }
    try appendAdapterImport(allocator, list, adapter);
}

/// Adds an adapter's import once per file, keyed by import path.
fn appendAdapterImport(allocator: std.mem.Allocator, list: *std.ArrayList(semantic.GoAdapter), adapter: semantic.GoAdapter) !void {
    for (list.items) |existing| {
        if (!semantic.optionalStringEqual(existing.qualifier(), adapter.qualifier())) continue;
        if (!std.mem.eql(u8, existing.import.?, adapter.import.?)) return error.AmbiguousGoImport;
        return;
    }
    try list.append(allocator, adapter);
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

/// A `[]E` whose enum carries a type-level `.go` adapter: it is converted
/// element by element rather than handed over as the raw integer slice.
fn isAdaptedEnumSlice(program: abi.Program, node: semantic.TypeNode) bool {
    return node == .slice and node.slice.element.* == .@"enum" and public_writers.enumAdapter(program, node.slice.element.@"enum".ref) != null;
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
    var file_options = options;
    if (file_options.file == null) file_options.file = .{ .kind = .runtime, .path = "" };
    try renderPublicFile(allocator, writer, program, file_options, renderPublicRuntimeBody);
}

/// The fixed part of every generated public package: the handle interface the
/// projections take, the projection status vocabulary, the `Must*` wrappers,
/// and the callback plumbing. None of it grows with the binding.
pub fn renderPublicRuntimeBody(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    try public_types.renderGoHandleRuntime(writer, program, options);
    try public_types.renderGoProjectionRuntime(writer, program, options);
    try public_types.renderGoCallbackTypes(allocator, writer, program, options);
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
    if (if (function.receiverIsHandle()) function.receiver else null) |receiver| {
        if (common.typeOwnsCallbacks(program, receiver)) {
            const receiver_name = try common.typeReceiverNameAlloc(allocator, program, receiver);
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
    if (if (function.receiverIsHandle()) function.receiver else null) |receiver| {
        if (common.typeOwnsErrorCallbacks(program, receiver)) {
            const receiver_name = try common.typeReceiverNameAlloc(allocator, program, receiver);
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
            try writer.print("\t{0s}Handle := zigoNew{1s}StreamHandle({0s})\n\tdefer zigoDeleteCallbackHandle({0s}Handle)\n", .{
                go_names[parameter_index],
                common.streamHandleName(parameter.type.io_stream.direction),
            });
            if (common.isReaderStream(parameter))
                try writer.print("\t{0s}Data := zigoReaderBytes({0s})\n", .{go_names[parameter_index]});
            continue;
        }
        if (parameter.type != .callback) continue;
        const callback_name = function.callbackType(parameter_index).?.name;
        try writer.print("\t{s}Handle := zigoNew{s}Handle({s})\n", .{ go_names[parameter_index], callback_name, go_names[parameter_index] });
        if (parameter.retention == .borrowed) {
            try writer.print("\tdefer zigoDeleteCallbackHandle({s}Handle)\n", .{go_names[parameter_index]});
        } else if (common.retainedCallbacksBelongToReceiver(program, function.origin.*)) {
            try writer.print(
                "\t{0s}HandleAdopted := false\n" ++
                    "\tdefer func() {{ if !{0s}HandleAdopted {{ zigoDeleteCallbackHandle({0s}Handle) }} }}()\n",
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
            try writer.print("\t\tzigoDeleteCallbackHandle({s}Handle)\n", .{go_names[parameter_index]});
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
    const receiver_name = try common.typeReceiverNameAlloc(allocator, program, receiver);
    defer allocator.free(receiver_name);
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .callback or parameter.retention != .retained) continue;
        const slot = function.callbackSlot(parameter_index) orelse unreachable;
        try writer.print(
            "\t{0s}PreviousHandle := {1s}.zigoReplaceCallbackHandle({2d}, {0s}Handle)\n" ++
                "\t{0s}HandleAdopted = true\n" ++
                "\tzigoDeleteCallbackHandle({0s}PreviousHandle)\n",
            .{ go_names[parameter_index], receiver_name, slot },
        );
    }
}
