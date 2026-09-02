const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");

pub fn semanticDocument(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    package: []const u8,
    prefix: []const u8,
    error_codes: []const abi.ErrorCode,
) !abi.Program {
    return semanticDocumentForBackend(allocator, document, package, prefix, error_codes, .cgo);
}

pub fn semanticDocumentForBackend(
    allocator: std.mem.Allocator,
    source_document: semantic.Semantic,
    package: []const u8,
    prefix: []const u8,
    error_codes: []const abi.ErrorCode,
    backend: abi.Program.Backend,
) !abi.Program {
    var document = source_document;
    document.functions = try promoteCheckedFunctions(allocator, document.functions);
    // Lowered ahead of the functions, so a function can point at the mirror it
    // fills rather than making a backend find it again by name.
    const structs = try lowerValueStructs(allocator, document, prefix);
    const functions = try allocator.alloc(abi.AbiFn, document.functions.len);
    for (document.functions, 0..) |*function, function_index| {
        var params: std.ArrayList(abi.AbiParam) = .empty;
        if (function.receiver) |receiver| {
            const child = try allocator.create(abi.AbiScalar);
            child.* = .{ .@"opaque" = try lowerOpaque(allocator, prefix, receiver) };
            try params.append(allocator, .{
                .name = "self",
                .role = .receiver,
                .scalar = .{ .pointer = .{ .child = child, .is_const = false } },
            });
        }
        for (function.params, 0..) |parameter, parameter_index| {
            // The shim writes the value itself, so the parameter is absent
            // from the C signature and from everything derived from it.
            if (parameter.injected != null) continue;
            // `?[]T` reuses the slice lowering whole: the same pointer and
            // length cross, and absence rides on the pointer being NULL, so
            // an absent slice and an empty one stay different.
            if (parameter.type == .optional and parameter.type.optional.child.* == .slice) {
                const slice_node = parameter.type.optional.child.*;
                const element = try allocator.create(abi.AbiScalar);
                element.* = try lowerValue(allocator, document, prefix, slice_node.slice.element.*);
                if (isCStringSlice(slice_node, parameter.semantic)) {
                    try params.append(allocator, .{
                        .name = parameter.name,
                        .role = .value,
                        .scalar = .{ .pointer = .{
                            .child = element,
                            .is_const = true,
                            .is_many = true,
                            .is_c_string = true,
                            .is_optional = true,
                        } },
                        .source_index = parameter_index,
                    });
                    continue;
                }
                try params.append(allocator, .{
                    .name = try std.fmt.allocPrint(allocator, "{s}_ptr", .{parameter.name}),
                    .role = .slice_pointer,
                    .scalar = .{ .pointer = .{
                        .child = element,
                        .is_const = slice_node.slice.@"const",
                        .is_many = true,
                        .is_optional = true,
                    } },
                    .source_index = parameter_index,
                });
                try params.append(allocator, .{
                    .name = try std.fmt.allocPrint(allocator, "{s}_len", .{parameter.name}),
                    .role = .slice_length,
                    .scalar = .usize,
                    .source_index = parameter_index,
                });
                continue;
            }
            if (isStringSliceParameter(parameter)) {
                const data_child = try allocator.create(abi.AbiScalar);
                data_child.* = try lowerValue(allocator, document, prefix, parameter.type.slice.element.*.slice.element.*);
                const lengths_child = try allocator.create(abi.AbiScalar);
                lengths_child.* = .usize;
                const data_name = try std.fmt.allocPrint(allocator, "{s}_data", .{parameter.name});
                const data_len_name = try std.fmt.allocPrint(allocator, "{s}_data_len", .{parameter.name});
                const lengths_name = try std.fmt.allocPrint(allocator, "{s}_lens", .{parameter.name});
                const count_name = try std.fmt.allocPrint(allocator, "{s}_count", .{parameter.name});
                try params.append(allocator, .{
                    .name = data_name,
                    .role = .string_data,
                    .scalar = .{ .pointer = .{ .child = data_child, .is_const = true, .is_many = true } },
                    .source_index = parameter_index,
                });
                try params.append(allocator, .{
                    .name = data_len_name,
                    .role = .string_data_length,
                    .scalar = .usize,
                    .source_index = parameter_index,
                });
                try params.append(allocator, .{
                    .name = lengths_name,
                    .role = .string_lengths,
                    .scalar = .{ .pointer = .{ .child = lengths_child, .is_const = true, .is_many = true } },
                    .source_index = parameter_index,
                });
                try params.append(allocator, .{
                    .name = count_name,
                    .role = .string_count,
                    .scalar = .usize,
                    .source_index = parameter_index,
                });
                continue;
            }
            if (isCStringSlice(parameter.type, parameter.semantic)) {
                const child = try allocator.create(abi.AbiScalar);
                child.* = try lowerValue(allocator, document, prefix, parameter.type.slice.element.*);
                try params.append(allocator, .{
                    .name = parameter.name,
                    .role = .value,
                    .scalar = .{ .pointer = .{
                        .child = child,
                        .is_const = true,
                        .is_many = true,
                        .is_c_string = true,
                    } },
                    .source_index = parameter_index,
                });
                continue;
            }
            if (parameter.type == .cancel_flag) {
                const child = try allocator.create(abi.AbiScalar);
                child.* = .{ .unsigned_int = 32 };
                try params.append(allocator, .{
                    .name = parameter.name,
                    .role = .cancel_flag,
                    .scalar = .{ .pointer = .{ .child = child, .is_const = true } },
                    .source_index = parameter_index,
                });
                continue;
            }
            if (parameter.type == .io_stream) {
                try appendStreamParams(allocator, &params, backend, parameter, parameter_index);
                continue;
            }
            switch (parameter.type) {
                .callback => |callback| {
                    if (backend == .cgo) continue;
                    const callback_params = try allocator.alloc(abi.AbiScalar, callback.params.len);
                    for (callback.params, 0..) |callback_parameter, callback_index|
                        callback_params[callback_index] = callbackWireScalar(try lowerValue(allocator, document, prefix, callback_parameter));
                    const callback_return = try allocator.create(abi.AbiScalar);
                    callback_return.* = try lowerValue(allocator, document, prefix, callback.@"return".*);
                    try params.append(allocator, .{
                        .name = parameter.name,
                        .scalar = .{ .callback = .{ .params = callback_params, .ret = callback_return } },
                        .source_index = parameter_index,
                    });
                },
                .slice => |slice| {
                    const child = try allocator.create(abi.AbiScalar);
                    child.* = try lowerValue(allocator, document, prefix, slice.element.*);
                    try params.append(allocator, .{
                        .name = try std.fmt.allocPrint(allocator, "{s}_ptr", .{parameter.name}),
                        .role = .slice_pointer,
                        .scalar = .{ .pointer = .{ .child = child, .is_const = slice.@"const", .is_many = true } },
                        .source_index = parameter_index,
                    });
                    try params.append(allocator, .{
                        .name = try std.fmt.allocPrint(allocator, "{s}_len", .{parameter.name}),
                        .role = .slice_length,
                        .scalar = .usize,
                        .source_index = parameter_index,
                    });
                    // `.return` reports the count through the function's own
                    // return value, so it needs no out parameter; only `.all`
                    // has something extra to report.
                    if (parameter.direction == .out and parameter.writtenHint() == .all) {
                        const usize_child = try allocator.create(abi.AbiScalar);
                        usize_child.* = .usize;
                        try params.append(allocator, .{
                            .name = try std.fmt.allocPrint(allocator, "{s}_written", .{parameter.name}),
                            .role = .slice_written,
                            .scalar = .{ .pointer = .{ .child = usize_child, .is_const = false } },
                            .source_index = parameter_index,
                        });
                    }
                },
                // Aggregates never cross the boundary by value: an input
                // struct travels as `const T*` and Go takes the address.
                .value_struct => |value| {
                    if (typeDeclaration(document, value.ref).kind == .tagged_union) {
                        try appendTaggedUnionValueParams(
                            allocator,
                            document,
                            prefix,
                            &params,
                            parameter,
                            parameter_index,
                        );
                        continue;
                    }
                    const child = try allocator.create(abi.AbiScalar);
                    child.* = try lowerValue(allocator, document, prefix, parameter.type);
                    try params.append(allocator, .{
                        .name = parameter.name,
                        .role = .struct_in,
                        .scalar = .{ .pointer = .{ .child = child, .is_const = true } },
                        .source_index = parameter_index,
                    });
                },
                // `?T` crosses as one nullable pointer, `NULL` standing for
                // `null`: a bool, integer, float, enum, or extern struct all
                // fit behind the same single argument, so no separate
                // presence flag is needed on the parameter side (only the
                // return side needs one, because a return has nowhere else to
                // put a pointer's absence).
                .optional => |optional| {
                    const child = try allocator.create(abi.AbiScalar);
                    child.* = try lowerValue(allocator, document, prefix, optional.child.*);
                    try params.append(allocator, .{
                        .name = parameter.name,
                        .role = .optional_in,
                        .scalar = .{ .pointer = .{ .child = child, .is_const = true, .is_optional = true } },
                        .source_index = parameter_index,
                    });
                },
                else => try params.append(allocator, .{
                    .name = parameter.name,
                    .scalar = try lowerValue(allocator, document, prefix, parameter.type),
                    .source_index = parameter_index,
                }),
            }
        }

        var function_errors: []const abi.ErrorCode = &.{};
        const return_scalar = if (isCStringSlice(function.@"return", function.return_semantic)) blk: {
            const child = try allocator.create(abi.AbiScalar);
            child.* = try lowerValue(allocator, document, prefix, function.@"return".slice.element.*);
            break :blk abi.AbiScalar{ .pointer = .{
                .child = child,
                .is_const = true,
                .is_many = true,
                .is_c_string = true,
            } };
        } else switch (function.@"return") {
            .slice => |slice| result: {
                try appendSliceReturnOuts(allocator, document, prefix, &params, slice, false);
                break :result abi.AbiScalar.void;
            },
            .error_union => |error_union| result: {
                function_errors = try codesFor(allocator, error_union.error_set, error_codes);
                // A slice payload takes the same pair of out parameters as a
                // plain slice return, so every emitter downstream sees one
                // slice-return shape whether or not the function can fail.
                if (error_union.payload.* == .slice and
                    !isCStringSlice(error_union.payload.*, function.return_semantic))
                {
                    try appendSliceReturnOuts(allocator, document, prefix, &params, error_union.payload.slice, false);
                } else if (error_union.payload.* == .optional and
                    error_union.payload.optional.child.* == .slice and
                    !isCStringSlice(error_union.payload.optional.child.*, function.return_semantic))
                {
                    // `E!?[]T`: the returned pointer is already nullable, so
                    // absence needs no flag of its own.
                    try appendSliceReturnOuts(allocator, document, prefix, &params, error_union.payload.optional.child.slice, true);
                } else if (error_union.payload.* == .optional) {
                    // `!?T`: the status code alone cannot carry both the error
                    // and the optional's own presence, so presence gets its
                    // own out parameter alongside the value.
                    const optional = error_union.payload.optional;
                    const has_child = try allocator.create(abi.AbiScalar);
                    has_child.* = .bool_u8;
                    try params.append(allocator, .{
                        .name = "out_result_has",
                        .role = .payload_has_out,
                        .scalar = .{ .pointer = .{ .child = has_child, .is_const = false } },
                        .source_index = function.params.len,
                    });
                    const payload = try allocator.create(abi.AbiScalar);
                    payload.* = try lowerValue(allocator, document, prefix, optional.child.*);
                    try params.append(allocator, .{
                        .name = "out_result",
                        .role = if (optional.child.* == .value_struct) .struct_out else .payload_out,
                        .scalar = .{ .pointer = .{ .child = payload, .is_const = false } },
                        .source_index = function.params.len,
                    });
                } else if (error_union.payload.* != .void) {
                    const payload = try allocator.create(abi.AbiScalar);
                    payload.* = try lowerValue(allocator, document, prefix, error_union.payload.*);
                    try params.append(allocator, .{
                        .name = "out_result",
                        .role = .payload_out,
                        .scalar = .{ .pointer = .{ .child = payload, .is_const = false } },
                        .source_index = function.params.len,
                    });
                }
                break :result abi.AbiScalar{ .signed_int = 32 };
            },
            .value_struct => result: {
                const child = try allocator.create(abi.AbiScalar);
                child.* = try lowerValue(allocator, document, prefix, function.@"return");
                try params.append(allocator, .{
                    .name = "out_result",
                    .role = .struct_out,
                    .scalar = .{ .pointer = .{ .child = child, .is_const = false } },
                });
                break :result abi.AbiScalar.void;
            },
            // `?[]T` hands back a nullable pointer and a length: NULL is the
            // absent slice, which a length of zero cannot be confused with.
            .optional => |optional| result: {
                if (optional.child.* == .slice and
                    !isCStringSlice(optional.child.*, function.return_semantic))
                {
                    try appendSliceReturnOuts(allocator, document, prefix, &params, optional.child.slice, true);
                    break :result abi.AbiScalar{ .void = {} };
                }
                const child = try allocator.create(abi.AbiScalar);
                child.* = try lowerValue(allocator, document, prefix, optional.child.*);
                try params.append(allocator, .{
                    .name = "out_result",
                    .role = if (optional.child.* == .value_struct) .struct_out else .payload_out,
                    .scalar = .{ .pointer = .{ .child = child, .is_const = false } },
                });
                break :result abi.AbiScalar.bool_u8;
            },
            else => try lowerValue(allocator, document, prefix, function.@"return"),
        };
        // The undecorated name comes from the shared rule that also fills
        // `semantic.json`; only the purego callback ABI decorates it further.
        const base_symbol = try naming.functionSymbolAlloc(
            allocator,
            prefix,
            function.receiver orelse function.namespace,
            function.name,
        );
        const symbol = if (backend == .purego and functionHasCallback(function.*))
            try std.fmt.allocPrint(allocator, "{s}_purego_v2", .{base_symbol})
        else
            base_symbol;
        functions[function_index] = .{
            .symbol = symbol,
            .params = try params.toOwnedSlice(allocator),
            .ret = return_scalar,
            .errors = function_errors,
            .origin = function,
            .ret_struct = if (function.@"return" == .value_struct)
                structRecord(structs, function.@"return".value_struct.ref)
            else if (function.@"return" == .optional and function.@"return".optional.child.* == .value_struct)
                structRecord(structs, function.@"return".optional.child.value_struct.ref)
            else
                null,
            // A slice optional carries absence in its own pointer, so it
            // takes none of the presence machinery a scalar one needs.
            .ret_optional = function.@"return" == .optional and function.@"return".optional.child.* != .slice,
            .payload_struct = if (function.@"return" == .error_union and
                function.@"return".error_union.payload.* == .value_struct)
                structRecord(structs, function.@"return".error_union.payload.value_struct.ref)
            else if (function.@"return" == .error_union and
                function.@"return".error_union.payload.* == .optional and
                function.@"return".error_union.payload.optional.child.* == .value_struct)
                structRecord(structs, function.@"return".error_union.payload.optional.child.value_struct.ref)
            else
                null,
            .payload_optional = function.@"return" == .error_union and
                function.@"return".error_union.payload.* == .optional and
                function.@"return".error_union.payload.optional.child.* != .slice,
        };
    }
    // The release target is another exported function, so its symbol is only
    // known once every function has been named.
    for (functions) |*lowered| {
        const release = lowered.origin.release orelse continue;
        for (functions) |candidate| {
            if (std.mem.eql(u8, candidate.origin.name, release)) {
                lowered.release_symbol = candidate.symbol;
                break;
            }
        }
    }
    const projections = try lowerTaggedUnionProjections(allocator, document, prefix);
    const snapshots = try lowerTaggedUnionSnapshots(allocator, document, prefix);
    return .{
        .backend = backend,
        .callback_convention = if (backend == .purego) .function_pointer_userdata_v2 else .fixed_go_export,
        .constructors = document.constructors,
        .allocator = document.allocator,
        .doc = document.doc,
        .io = document.io,
        .enums = try lowerEnums(allocator, document, prefix),
        .error_codes = error_codes,
        .handles = try lowerHandles(allocator, document, prefix),
        .functions = functions,
        .package = package,
        .packages = document.packages,
        .prefix = prefix,
        .projections = projections,
        .snapshots = snapshots,
        .structs = structs,
        .types = document.types,
    };
}

fn appendTaggedUnionValueParams(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    prefix: []const u8,
    params: *std.ArrayList(abi.AbiParam),
    parameter: semantic.Parameter,
    parameter_index: usize,
) !void {
    const declaration = typeDeclaration(document, parameter.type.value_struct.ref);
    try params.append(allocator, .{
        .name = try std.fmt.allocPrint(allocator, "{s}_tag", .{parameter.name}),
        .role = .union_tag,
        .scalar = try lowerValue(allocator, document, prefix, declaration.tag_type.?),
        .source_index = parameter_index,
    });
    for (declaration.fields) |field| {
        const payload = field.type.?;
        if (payload == .void) continue;
        try params.append(allocator, .{
            .name = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ parameter.name, field.name }),
            .role = .union_payload,
            .scalar = try lowerValue(allocator, document, prefix, payload),
            .source_index = parameter_index,
        });
    }
}

/// A float never travels through the purego callback ABI as a float. Windows
/// compiles a Go callback through `syscall.NewCallback`, whose `compileCallback`
/// refuses a floating-point argument outright, so every float parameter crosses
/// as its IEEE-754 bit pattern in an integer of the same width. The lowering is
/// unconditional -- one wire shape on every platform keeps the committed
/// generated tree identical no matter which host or `--target-os` produced it.
fn callbackWireScalar(scalar: abi.AbiScalar) abi.AbiScalar {
    return switch (scalar) {
        .float => |bits| .{ .unsigned_int = bits },
        else => scalar,
    };
}

fn functionHasCallback(function: semantic.SemanticFn) bool {
    // A stream parameter counts: under purego it too carries a Go dispatcher
    // pointer, so it answers to the same versioned symbol as a user callback.
    for (function.params) |parameter| {
        if (parameter.type == .callback or parameter.type == .io_stream) return true;
    }
    return false;
}

/// The C parameters one stream parameter lowers to. A writer needs only the
/// Go value behind it; a reader also carries the byte-slice pair that lets a
/// caller hand its bytes over directly instead of being read a chunk at a
/// time. Both shapes are fixed by the direction, so nothing about the Zig
/// signature can change them.
fn appendStreamParams(
    allocator: std.mem.Allocator,
    params: *std.ArrayList(abi.AbiParam),
    backend: abi.Program.Backend,
    parameter: semantic.Parameter,
    parameter_index: usize,
) !void {
    const direction = parameter.type.io_stream.direction;
    if (backend == .purego) {
        const byte = try allocator.create(abi.AbiScalar);
        byte.* = .{ .unsigned_int = 8 };
        const callback_params = try allocator.alloc(abi.AbiScalar, 3);
        callback_params[0] = .{ .pointer = .{ .child = byte, .is_const = direction == .writer, .is_many = true } };
        callback_params[1] = .usize;
        callback_params[2] = .usize;
        const callback_return = try allocator.create(abi.AbiScalar);
        callback_return.* = .{ .signed_int = 32 };
        try params.append(allocator, .{
            .name = try std.fmt.allocPrint(allocator, "{s}_fn", .{parameter.name}),
            .role = .stream_callback,
            .scalar = .{ .callback = .{ .params = callback_params, .ret = callback_return } },
            .source_index = parameter_index,
        });
    }
    if (direction == .reader) {
        const byte = try allocator.create(abi.AbiScalar);
        byte.* = .{ .unsigned_int = 8 };
        try params.append(allocator, .{
            .name = try std.fmt.allocPrint(allocator, "{s}_data", .{parameter.name}),
            .role = .stream_data,
            .scalar = .{ .pointer = .{ .child = byte, .is_const = true, .is_many = true } },
            .source_index = parameter_index,
        });
        try params.append(allocator, .{
            .name = try std.fmt.allocPrint(allocator, "{s}_data_len", .{parameter.name}),
            .role = .stream_data_length,
            .scalar = .usize,
            .source_index = parameter_index,
        });
    }
    try params.append(allocator, .{
        .name = try std.fmt.allocPrint(allocator, "{s}_userdata", .{parameter.name}),
        .role = .stream_userdata,
        .scalar = .usize,
        .source_index = parameter_index,
    });
}

fn lowerTaggedUnionProjections(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) ![]const abi.AbiProjection {
    var projections: std.ArrayList(abi.AbiProjection) = .empty;
    for (document.types) |*declaration| {
        if (declaration.kind != .tagged_union) continue;
        if (taggedUnionUsedByValue(document, declaration.name) and !taggedUnionUsedAsHandle(document, declaration.name)) continue;
        const tag_params = try allocator.alloc(abi.AbiParam, 2);
        tag_params[0] = try projectionReceiver(allocator, prefix, declaration.name);
        const tag_output = try allocator.create(abi.AbiScalar);
        tag_output.* = try lowerValue(allocator, document, prefix, declaration.tag_type.?);
        tag_params[1] = .{
            .name = "out_value",
            .role = .payload_out,
            .scalar = .{ .pointer = .{ .child = tag_output, .is_const = false } },
        };
        try projections.append(allocator, .{
            .kind = .tag,
            .symbol = try naming.projectionSymbolAlloc(allocator, prefix, declaration.name, "tag"),
            .params = tag_params,
            .ret = .bool_u8,
            .owner = declaration,
        });
        for (declaration.fields) |*field| {
            const payload = field.type.?;
            if (payload == .void) continue;
            var params: std.ArrayList(abi.AbiParam) = .empty;
            try params.append(allocator, try projectionReceiver(allocator, prefix, declaration.name));
            if (payload == .slice) {
                const element = try allocator.create(abi.AbiScalar);
                element.* = try lowerValue(allocator, document, prefix, payload.slice.element.*);
                const many = try allocator.create(abi.AbiScalar);
                many.* = .{ .pointer = .{ .child = element, .is_const = payload.slice.@"const", .is_many = true } };
                try params.append(allocator, .{
                    .name = "out_value_ptr",
                    .role = .return_slice_pointer,
                    .scalar = .{ .pointer = .{ .child = many, .is_const = false } },
                });
                const length = try allocator.create(abi.AbiScalar);
                length.* = .usize;
                try params.append(allocator, .{
                    .name = "out_value_len",
                    .role = .return_slice_length,
                    .scalar = .{ .pointer = .{ .child = length, .is_const = false } },
                });
            } else {
                const lowered = try allocator.create(abi.AbiScalar);
                lowered.* = try lowerValue(allocator, document, prefix, payload);
                try params.append(allocator, .{
                    .name = "out_value",
                    .role = .payload_out,
                    .scalar = .{ .pointer = .{ .child = lowered, .is_const = false } },
                });
            }
            try projections.append(allocator, .{
                .kind = .payload,
                .symbol = try naming.projectionSymbolAlloc(allocator, prefix, declaration.name, field.name),
                .params = try params.toOwnedSlice(allocator),
                .ret = .bool_u8,
                .owner = declaration,
                .field = field,
            });
        }
    }
    return projections.toOwnedSlice(allocator);
}

fn taggedUnionUsedAsHandle(document: semantic.Semantic, name: []const u8) bool {
    for (document.constructors) |constructor| if (std.mem.eql(u8, constructor.type, name)) return true;
    for (document.functions) |function| {
        if (function.receiver) |receiver| if (std.mem.eql(u8, receiver, name)) return true;
        for (function.params) |parameter| if (containsHandleReference(parameter.type, name)) return true;
        if (containsHandleReference(function.@"return", name)) return true;
    }
    return false;
}

fn taggedUnionUsedByValue(document: semantic.Semantic, name: []const u8) bool {
    for (document.functions) |function| {
        for (function.params) |parameter| {
            if (parameter.type == .value_struct and std.mem.eql(u8, parameter.type.value_struct.ref, name)) return true;
        }
    }
    return false;
}

fn containsHandleReference(node: semantic.TypeNode, name: []const u8) bool {
    return switch (node) {
        .opaque_ptr => |value| std.mem.eql(u8, value.ref, name),
        .slice => |value| containsHandleReference(value.element.*, name),
        .optional => |value| containsHandleReference(value.child.*, name),
        .error_union => |value| containsHandleReference(value.payload.*, name),
        .callback => |value| blk: {
            for (value.params) |parameter| if (containsHandleReference(parameter, name)) break :blk true;
            break :blk containsHandleReference(value.@"return".*, name);
        },
        else => false,
    };
}

/// Value snapshot layout. zigo owns this struct outright: the tag comes first,
/// payloads follow in descending width, and every gap is an explicit
/// `reserved_<n>` member. Ordering by width means no member ever needs implicit
/// padding, so the C, Zig and Go spellings of the struct agree by construction.
fn lowerTaggedUnionSnapshots(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) ![]const abi.AbiSnapshot {
    var snapshots: std.ArrayList(abi.AbiSnapshot) = .empty;
    for (document.types) |*declaration| {
        if (declaration.kind != .tagged_union or declaration.accessStrategy() != .snapshot) continue;
        const type_name = try snapshotTypeNameAlloc(allocator, prefix, declaration.name);
        const layout = try snapshotLayout(allocator, document, prefix, declaration.*);

        const receiver = try projectionReceiver(allocator, prefix, declaration.name);
        const out_child = try allocator.create(abi.AbiScalar);
        out_child.* = .{ .snapshot = type_name };
        const params = try allocator.alloc(abi.AbiParam, 2);
        params[0] = receiver;
        params[1] = .{
            .name = "out_snapshot",
            .role = .payload_out,
            .scalar = .{ .pointer = .{ .child = out_child, .is_const = false } },
        };
        try snapshots.append(allocator, .{
            .owner = declaration,
            .symbol = try snapshotSymbolAlloc(allocator, prefix, declaration.name),
            .type_name = type_name,
            .fields = layout.fields,
            .size = layout.size,
            .alignment = layout.alignment,
            .params = params,
            .ret = .bool_u8,
        });
    }
    return snapshots.toOwnedSlice(allocator);
}

/// The C mirror of an `extern struct`. The members are the user's own in the
/// user's order: `extern` already means C layout, so nothing is reordered or
/// padded here. Size and alignment are computed with the same rules the C
/// compiler applies, purely so the shim can assert the Zig type still agrees.
/// A function whose public Go signature already carries an `error` gets the
/// same C ABI as one that returns an error union: a status code, with the
/// result moved into `out_result`. That is the only place a native panic can
/// be reported from, and without it the C wrapper's `longjmp` landing pad has
/// nothing to say and returns a zero value -- turning Zig's fatal panic into a
/// silent success. The rewritten error set is empty: there are no Zig errors
/// to name, only the `-2` the panic bridge produces.
///
/// Doing it here rather than in each emitter means the shim, the header, the
/// raw layer, the public layer, and both backends all see one shape.
fn promoteCheckedFunctions(allocator: std.mem.Allocator, functions: []const semantic.SemanticFn) ![]const semantic.SemanticFn {
    const promoted = try allocator.alloc(semantic.SemanticFn, functions.len);
    for (functions, 0..) |function, index| {
        promoted[index] = function;
        if (function.@"return" == .error_union or !reportsPanics(function)) continue;
        const payload = try allocator.create(semantic.TypeNode);
        payload.* = function.@"return";
        promoted[index].@"return" = .{ .error_union = .{ .error_set = &.{}, .payload = payload } };
    }
    return promoted;
}

/// The rule the whole binding is built on: a Go signature with an `error` in
/// it reports every native panic through that error. A handle parameter or
/// receiver puts one there (a nil or closed handle has to be reportable), and
/// so does a promoted integer parameter (an out-of-range argument has to be).
fn reportsPanics(function: semantic.SemanticFn) bool {
    if (function.receiver != null) return true;
    for (function.params) |parameter| {
        if (parameter.type == .opaque_ptr) return true;
        if (abi.narrowInt(parameter.type) != null) return true;
    }
    return false;
}

fn lowerValueStructs(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) ![]const abi.AbiStruct {
    var structs: std.ArrayList(abi.AbiStruct) = .empty;
    // A C struct must be complete before another names it by value, so a
    // nested struct is emitted ahead of the struct that embeds it.
    var ordered: std.ArrayList(*const semantic.TypeDecl) = .empty;
    defer ordered.deinit(allocator);
    for (document.types) |*declaration| {
        if (declaration.kind != .value_struct or declaration.layout != .@"extern") continue;
        if (!valueStructUsed(document, declaration.name)) continue;
        try appendStructInDependencyOrder(allocator, document, declaration, &ordered);
    }
    for (ordered.items) |declaration| {
        const fields = try allocator.alloc(abi.AbiStruct.Field, declaration.fields.len);
        var offset: usize = 0;
        var alignment: usize = 1;
        for (declaration.fields, 0..) |field, index| {
            const node = field.type.?;
            const scalar = try lowerValue(allocator, document, prefix, node);
            const member = memberLayout(structs.items, node, scalar);
            const bytes = member.bytes;
            offset += padding(offset, member.alignment);
            fields[index] = .{
                .name = field.name,
                .scalar = scalar,
                .node = node,
                .offset = offset,
                .bytes = bytes,
            };
            offset += bytes;
            alignment = @max(alignment, member.alignment);
        }
        try structs.append(allocator, .{
            .owner = declaration,
            .name = declaration.name,
            .c_name = try cTypeNameAlloc(allocator, prefix, declaration.name),
            .fields = fields,
            .size = offset + padding(offset, alignment),
            .alignment = alignment,
        });
    }
    return structs.toOwnedSlice(allocator);
}

fn structRecord(structs: []const abi.AbiStruct, name: []const u8) *const abi.AbiStruct {
    for (structs) |*record| if (std.mem.eql(u8, record.name, name)) return record;
    unreachable;
}

fn appendStructInDependencyOrder(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    declaration: *const semantic.TypeDecl,
    ordered: *std.ArrayList(*const semantic.TypeDecl),
) !void {
    for (ordered.items) |present| if (present == declaration) return;
    for (declaration.fields) |field| {
        const node = field.type orelse continue;
        if (node != .value_struct) continue;
        for (document.types) |*nested| {
            if (nested.kind != .value_struct or !std.mem.eql(u8, nested.name, node.value_struct.ref)) continue;
            try appendStructInDependencyOrder(allocator, document, nested, ordered);
        }
    }
    for (ordered.items) |present| if (present == declaration) return;
    try ordered.append(allocator, declaration);
}

/// Only structs a function actually mentions reach the header, so registering
/// a type without using it adds nothing to the generated surface.
fn valueStructUsed(document: semantic.Semantic, name: []const u8) bool {
    for (document.functions) |function| {
        for (function.params) |parameter| if (mentionsValueStruct(document, parameter.type, name)) return true;
        if (mentionsValueStruct(document, function.@"return", name)) return true;
    }
    return false;
}

fn mentionsValueStruct(document: semantic.Semantic, node: semantic.TypeNode, name: []const u8) bool {
    return switch (node) {
        .value_struct => |value| blk: {
            if (std.mem.eql(u8, value.ref, name)) break :blk true;
            for (document.types) |declaration| {
                if (declaration.kind != .value_struct or !std.mem.eql(u8, declaration.name, value.ref)) continue;
                for (declaration.fields) |field| {
                    if (field.type) |child| if (mentionsValueStruct(document, child, name)) break :blk true;
                }
            }
            break :blk false;
        },
        .slice => |value| mentionsValueStruct(document, value.element.*, name),
        .error_union => |value| mentionsValueStruct(document, value.payload.*, name),
        .optional => |value| mentionsValueStruct(document, value.child.*, name),
        else => false,
    };
}

/// A nested struct is lowered before the struct that embeds it, so its final
/// size and alignment are already recorded and never recomputed here.
fn memberLayout(lowered: []const abi.AbiStruct, node: semantic.TypeNode, scalar: abi.AbiScalar) struct { bytes: usize, alignment: usize } {
    if (node != .value_struct) {
        const bytes = scalarBytes(scalar);
        return .{ .bytes = bytes, .alignment = bytes };
    }
    for (lowered) |record| {
        if (std.mem.eql(u8, record.name, node.value_struct.ref))
            return .{ .bytes = record.size, .alignment = record.alignment };
    }
    unreachable;
}

/// Every C name a backend needs for an `opaque` or tagged union handle.
fn lowerOpaque(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) !abi.AbiOpaque {
    return .{ .name = name, .c_name = try cTypeNameAlloc(allocator, prefix, name) };
}

/// The handle typedefs the header declares, in declaration order. A tagged
/// union is a handle too: C only ever holds a pointer to it.
fn lowerHandles(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) ![]const abi.AbiOpaque {
    var handles: std.ArrayList(abi.AbiOpaque) = .empty;
    for (document.types) |declaration| {
        if (declaration.kind != .@"opaque" and declaration.kind != .tagged_union) continue;
        try handles.append(allocator, try lowerOpaque(allocator, prefix, declaration.name));
    }
    return handles.toOwnedSlice(allocator);
}

/// The enum typedefs and their member constants. The constant name is already
/// uppercased here, so no backend re-spells it.
fn lowerEnums(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) ![]const abi.AbiEnum {
    var enums: std.ArrayList(abi.AbiEnum) = .empty;
    for (document.types) |declaration| {
        if (declaration.kind != .@"enum") continue;
        const c_name = try cTypeNameAlloc(allocator, prefix, declaration.name);
        const constants = try allocator.alloc(abi.AbiEnum.Constant, declaration.fields.len);
        for (declaration.fields, 0..) |field, index| {
            const member = try naming.snakeAlloc(allocator, field.name);
            defer allocator.free(member);
            const combined = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ c_name, member });
            defer allocator.free(combined);
            constants[index] = .{
                .name = field.name,
                .c_name = try std.ascii.allocUpperString(allocator, combined),
                .value = field.value.?,
            };
        }
        try enums.append(allocator, .{
            .name = declaration.name,
            .c_name = c_name,
            .tag = try lowerValue(allocator, document, prefix, declaration.tag_type.?),
            .constants = constants,
        });
    }
    return enums.toOwnedSlice(allocator);
}

fn cTypeNameAlloc(allocator: std.mem.Allocator, prefix: []const u8, type_name: []const u8) ![]u8 {
    const owner = try naming.snakeAlloc(allocator, type_name);
    defer allocator.free(owner);
    return std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, owner });
}

const SnapshotLayout = struct { fields: []const abi.AbiSnapshot.Field, size: usize, alignment: usize };

fn snapshotLayout(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8, declaration: semantic.TypeDecl) !SnapshotLayout {
    const Payload = struct { field: *const semantic.TypeField, scalar: abi.AbiScalar, bytes: usize };
    var payloads: std.ArrayList(Payload) = .empty;
    defer payloads.deinit(allocator);
    for (declaration.fields) |*field| {
        const node = field.type.?;
        if (node == .void) continue;
        const scalar = try lowerValue(allocator, document, prefix, node);
        try payloads.append(allocator, .{ .field = field, .scalar = scalar, .bytes = scalarBytes(scalar) });
    }
    // A stable descending-width sort keeps declaration order inside each width,
    // so the layout only ever changes when the variants themselves change.
    std.mem.sort(Payload, payloads.items, {}, struct {
        fn lessThan(_: void, lhs: Payload, rhs: Payload) bool {
            return lhs.bytes > rhs.bytes;
        }
    }.lessThan);

    const tag_scalar = try lowerValue(allocator, document, prefix, declaration.tag_type.?);
    const tag_bytes = scalarBytes(tag_scalar);
    var alignment = tag_bytes;
    for (payloads.items) |payload| alignment = @max(alignment, payload.bytes);

    var fields: std.ArrayList(abi.AbiSnapshot.Field) = .empty;
    try fields.append(allocator, .{
        .kind = .tag,
        .name = "tag",
        .bytes = tag_bytes,
        .scalar = tag_scalar,
        .node = declaration.tag_type.?,
    });
    var offset = tag_bytes;
    var reserved: usize = 0;
    if (payloads.items.len != 0) {
        const gap = padding(offset, payloads.items[0].bytes);
        if (gap != 0) {
            try fields.append(allocator, try paddingField(allocator, &reserved, gap));
            offset += gap;
        }
    }
    for (payloads.items) |payload| {
        try fields.append(allocator, .{
            .kind = .payload,
            .name = payload.field.name,
            .bytes = payload.bytes,
            .scalar = payload.scalar,
            .node = payload.field.type.?,
            .source = payload.field,
        });
        offset += payload.bytes;
    }
    const tail = padding(offset, alignment);
    if (tail != 0) {
        try fields.append(allocator, try paddingField(allocator, &reserved, tail));
        offset += tail;
    }
    return .{ .fields = try fields.toOwnedSlice(allocator), .size = offset, .alignment = alignment };
}

fn paddingField(allocator: std.mem.Allocator, counter: *usize, bytes: usize) !abi.AbiSnapshot.Field {
    const name = try std.fmt.allocPrint(allocator, "reserved_{d}", .{counter.*});
    counter.* += 1;
    return .{ .kind = .padding, .name = name, .bytes = bytes, .scalar = .{ .unsigned_int = 8 } };
}

fn padding(offset: usize, alignment: usize) usize {
    if (alignment == 0) return 0;
    const remainder = offset % alignment;
    return if (remainder == 0) 0 else alignment - remainder;
}

/// Snapshot members are limited to the scalars the eligibility rule admits, so
/// every width here is a power of two and equals the member's alignment.
fn scalarBytes(scalar: abi.AbiScalar) usize {
    return switch (scalar) {
        .bool_u8 => 1,
        .usize, .isize => @sizeOf(usize),
        .signed_int, .unsigned_int => |bits| bits / 8,
        .float => |bits| bits / 8,
        else => unreachable,
    };
}

fn snapshotSymbolAlloc(allocator: std.mem.Allocator, prefix: []const u8, type_name: []const u8) ![]u8 {
    const owner = try naming.snakeAlloc(allocator, type_name);
    defer allocator.free(owner);
    return std.fmt.allocPrint(allocator, "{s}_{s}_snapshot", .{ prefix, owner });
}

fn snapshotTypeNameAlloc(allocator: std.mem.Allocator, prefix: []const u8, type_name: []const u8) ![]u8 {
    const owner = try naming.snakeAlloc(allocator, type_name);
    defer allocator.free(owner);
    return std.fmt.allocPrint(allocator, "{s}_{s}_snapshot_t", .{ prefix, owner });
}

fn projectionReceiver(allocator: std.mem.Allocator, prefix: []const u8, owner: []const u8) !abi.AbiParam {
    const child = try allocator.create(abi.AbiScalar);
    child.* = .{ .@"opaque" = try lowerOpaque(allocator, prefix, owner) };
    return .{
        .name = "self",
        .role = .receiver,
        .scalar = .{ .pointer = .{ .child = child, .is_const = true } },
    };
}

/// The `T** out_result_ptr, size_t* out_result_len` pair a slice return hands
/// back. Plain `[]T` and the `![]T` payload share it so the C signature, the
/// shim epilogue and both raw emitters only ever handle one slice-return shape.
fn appendSliceReturnOuts(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    prefix: []const u8,
    params: *std.ArrayList(abi.AbiParam),
    slice: semantic.Slice,
    is_optional: bool,
) !void {
    const element = try allocator.create(abi.AbiScalar);
    element.* = try lowerValue(allocator, document, prefix, slice.element.*);
    const many = try allocator.create(abi.AbiScalar);
    many.* = .{ .pointer = .{
        .child = element,
        .is_const = slice.@"const",
        .is_many = true,
        .is_optional = is_optional,
    } };
    try params.append(allocator, .{
        .name = "out_result_ptr",
        .role = .return_slice_pointer,
        .scalar = .{ .pointer = .{ .child = many, .is_const = false } },
    });
    const usize_child = try allocator.create(abi.AbiScalar);
    usize_child.* = .usize;
    try params.append(allocator, .{
        .name = "out_result_len",
        .role = .return_slice_length,
        .scalar = .{ .pointer = .{ .child = usize_child, .is_const = false } },
    });
}

fn lowerValue(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8, node: semantic.TypeNode) !abi.AbiScalar {
    return switch (node) {
        .void => .void,
        .bool => .bool_u8,
        .int => |value| if (value.is_usize)
            (if (value.signed) .isize else .usize)
        else if (value.signed)
            .{ .signed_int = abi.promotedIntBits(value.bits) }
        else
            .{ .unsigned_int = abi.promotedIntBits(value.bits) },
        .float => |value| .{ .float = value.bits },
        .@"enum" => |value| lowerValue(allocator, document, prefix, enumDeclaration(document, value.ref).tag_type.?),
        .opaque_ptr => |value| blk: {
            const child = try allocator.create(abi.AbiScalar);
            child.* = .{ .@"opaque" = try lowerOpaque(allocator, prefix, value.ref) };
            break :blk .{ .pointer = .{ .child = child, .is_const = value.@"const", .is_optional = value.nullable } };
        },
        .value_struct => |value| .{ .value_struct = .{
            .name = value.ref,
            .c_name = try cTypeNameAlloc(allocator, prefix, value.ref),
        } },
        // Validation rejects every node that cannot be lowered, so this is a
        // backstop against a malformed document rather than a reachable path.
        else => error.UnsupportedType,
    };
}

fn isCStringSlice(node: semantic.TypeNode, hint: ?semantic.SemanticHint) bool {
    return hint == .c_string and node == .slice and node.slice.@"const" and
        node.slice.element.* == .int and !node.slice.element.int.signed and node.slice.element.int.bits == 8;
}

fn isStringSliceParameter(parameter: semantic.Parameter) bool {
    if (parameter.direction != .in or parameter.type != .slice or !parameter.type.slice.@"const") return false;
    const element = parameter.type.slice.element.*;
    if (element != .slice or !element.slice.@"const" or
        element.slice.element.* != .int or element.slice.element.int.signed or element.slice.element.int.bits != 8) return false;
    if (element.slice.sentinel) |sentinel| return sentinel == 0;
    return parameter.semantic == .utf8_string;
}

fn enumDeclaration(document: semantic.Semantic, name: []const u8) semantic.TypeDecl {
    for (document.types) |declaration| if (std.mem.eql(u8, declaration.name, name)) return declaration;
    unreachable;
}

fn typeDeclaration(document: semantic.Semantic, name: []const u8) semantic.TypeDecl {
    for (document.types) |declaration| if (std.mem.eql(u8, declaration.name, name)) return declaration;
    unreachable;
}

fn codesFor(allocator: std.mem.Allocator, names: []const []const u8, all_codes: []const abi.ErrorCode) ![]const abi.ErrorCode {
    const result = try allocator.alloc(abi.ErrorCode, names.len);
    for (names, 0..) |name, index| {
        for (all_codes) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                result[index] = entry;
                break;
            }
        } else unreachable;
    }
    return result;
}

test "semantic lowering assigns receiver slice return error and scalar ABI roles" {
    var float_node: semantic.TypeNode = .{ .float = .{ .bits = 32 } };
    var enum_payload: semantic.TypeNode = .{ .@"enum" = .{ .ref = "Mode" } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "fill",
                .params = &.{.{
                    .direction = .out,
                    .name = "output",
                    .type = .{ .slice = .{ .@"const" = false, .element = &float_node } },
                }},
                .receiver = "Context",
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            },
            .{
                .name = "values",
                .params = &.{},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &float_node } },
                .symbol = "ignored",
            },
            .{
                .name = "mode",
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Failed"}, .payload = &enum_payload } },
                .symbol = "ignored",
            },
            .{
                .name = "sizes",
                .params = &.{
                    .{ .name = "unsigned", .type = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } } },
                    .{ .name = "signed", .type = .{ .int = .{ .bits = 64, .is_usize = true, .signed = true } } },
                },
                .@"return" = .{ .@"enum" = .{ .ref = "Mode" } },
                .symbol = "ignored",
            },
        },
        .package = "roles",
        .prefix = "zg",
        .types = &.{
            .{ .kind = .@"opaque", .name = "Context" },
            .{ .kind = .@"enum", .name = "Mode", .tag_type = .{ .int = .{ .bits = 16, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "roles", "zg", &.{.{ .code = 7, .name = "Failed" }});

    const fill = program.functions[0];
    try std.testing.expectEqualStrings("zg_context_fill", fill.symbol);
    try std.testing.expectEqual(@as(usize, 4), fill.params.len);
    try std.testing.expectEqual(abi.AbiParam.Role.receiver, fill.params[0].role);
    try std.testing.expect(fill.params[0].scalar == .pointer);
    try std.testing.expectEqual(abi.AbiParam.Role.slice_pointer, fill.params[1].role);
    try std.testing.expect(fill.params[1].scalar.pointer.is_many);
    try std.testing.expect(!fill.params[1].scalar.pointer.is_const);
    try std.testing.expectEqual(abi.AbiParam.Role.slice_length, fill.params[2].role);
    try std.testing.expect(fill.params[2].scalar == .usize);
    try std.testing.expectEqual(abi.AbiParam.Role.slice_written, fill.params[3].role);
    try std.testing.expect(fill.params[3].scalar.pointer.child.* == .usize);

    const values = program.functions[1];
    try std.testing.expectEqual(@as(usize, 2), values.params.len);
    try std.testing.expectEqual(abi.AbiParam.Role.return_slice_pointer, values.params[0].role);
    try std.testing.expect(values.params[0].scalar.pointer.child.pointer.is_many);
    try std.testing.expect(values.params[0].scalar.pointer.child.pointer.is_const);
    try std.testing.expectEqual(abi.AbiParam.Role.return_slice_length, values.params[1].role);
    try std.testing.expect(values.ret == .void);

    const mode = program.functions[2];
    try std.testing.expect(mode.ret == .signed_int);
    try std.testing.expectEqual(@as(u16, 32), mode.ret.signed_int);
    try std.testing.expectEqual(@as(usize, 1), mode.params.len);
    try std.testing.expectEqual(abi.AbiParam.Role.payload_out, mode.params[0].role);
    try std.testing.expect(mode.params[0].scalar.pointer.child.* == .unsigned_int);
    try std.testing.expectEqual(@as(u16, 16), mode.params[0].scalar.pointer.child.unsigned_int);
    try std.testing.expectEqual(@as(i32, 7), mode.errors[0].code);

    const sizes = program.functions[3];
    try std.testing.expect(sizes.params[0].scalar == .usize);
    try std.testing.expect(sizes.params[1].scalar == .isize);
    try std.testing.expect(sizes.ret == .unsigned_int);
    try std.testing.expectEqual(@as(u16, 16), sizes.ret.unsigned_int);
}

test "tagged union value parameters flatten tag and payloads in variant order" {
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "consume",
            .params = &.{.{ .name = "behavior", .type = .{ .value_struct = .{ .ref = "Behavior" } } }},
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "top", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "delta", .type = .{ .int = .{ .bits = 64, .signed = true, .is_usize = true } }, .value = 1 },
                    .{ .name = "ratio", .type = .{ .float = .{ .bits = 32 } }, .value = 2 },
                },
                .kind = .tagged_union,
                .name = "Behavior",
                .tag_type = .{ .@"enum" = .{ .ref = "BehaviorTag" } },
            },
            .{
                .fields = &.{ .{ .name = "top", .value = 0 }, .{ .name = "delta", .value = 1 }, .{ .name = "ratio", .value = 2 } },
                .kind = .@"enum",
                .name = "BehaviorTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const function = (try semanticDocument(arena.allocator(), document, "variant", "zg", &.{})).functions[0];
    try std.testing.expectEqual(@as(usize, 3), function.params.len);
    try std.testing.expectEqualStrings("behavior_tag", function.params[0].name);
    try std.testing.expectEqual(abi.AbiParam.Role.union_tag, function.params[0].role);
    try std.testing.expectEqualStrings("behavior_delta", function.params[1].name);
    try std.testing.expectEqual(abi.AbiScalar.isize, function.params[1].scalar);
    try std.testing.expectEqualStrings("behavior_ratio", function.params[2].name);
    try std.testing.expectEqual(@as(u16, 32), function.params[2].scalar.float);
}

test "sentinel byte strings lower to one const C pointer" {
    var byte_node: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const c_string: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte_node } };
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "echo",
            .params = &.{.{ .name = "text", .semantic = .c_string, .type = c_string }},
            .@"return" = c_string,
            .return_semantic = .c_string,
            .symbol = "ignored",
        }},
        .package = "sentinel",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const function = (try semanticDocument(arena.allocator(), document, "sentinel", "zg", &.{})).functions[0];

    try std.testing.expectEqual(@as(usize, 1), function.params.len);
    try std.testing.expectEqual(abi.AbiParam.Role.value, function.params[0].role);
    try std.testing.expect(function.params[0].scalar.pointer.is_c_string);
    try std.testing.expect(function.params[0].scalar.pointer.is_many);
    try std.testing.expect(function.params[0].scalar.pointer.is_const);
    try std.testing.expect(function.ret.pointer.is_c_string);
    try std.testing.expect(function.ret.pointer.is_many);
}

test "string slice parameters lower to data and length roles" {
    var byte_node: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var string_element: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte_node } };
    const strings: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &string_element } };
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "extract",
            .params = &.{.{ .name = "paths", .semantic = .utf8_string, .type = strings }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_extract",
        }},
        .package = "strings",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const function = (try semanticDocument(arena.allocator(), document, "strings", "zg", &.{})).functions[0];

    try std.testing.expectEqual(@as(usize, 4), function.params.len);
    try std.testing.expectEqual(abi.AbiParam.Role.string_data, function.params[0].role);
    try std.testing.expectEqualStrings("paths_data", function.params[0].name);
    try std.testing.expectEqual(abi.AbiParam.Role.string_data_length, function.params[1].role);
    try std.testing.expectEqual(abi.AbiParam.Role.string_lengths, function.params[2].role);
    try std.testing.expectEqual(abi.AbiParam.Role.string_count, function.params[3].role);
    try std.testing.expect(function.params[0].scalar.pointer.is_const);
    try std.testing.expect(function.params[0].scalar.pointer.is_many);
    try std.testing.expect(function.params[2].scalar.pointer.is_const);
    try std.testing.expect(function.params[2].scalar.pointer.is_many);
}

test "tagged union lowering records tag scalar slice and handle projections" {
    var i16_node: semantic.TypeNode = .{ .int = .{ .bits = 16, .signed = true } };
    const document: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "number", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
                    .{ .name = "samples", .type = .{ .slice = .{ .@"const" = true, .element = &i16_node } }, .value = 2 },
                    .{ .name = "child", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Child" } }, .value = 3 },
                },
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{
                    .{ .name = "none", .value = 0 },
                    .{ .name = "number", .value = 1 },
                    .{ .name = "samples", .value = 2 },
                    .{ .name = "child", .value = 3 },
                },
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{ .kind = .@"opaque", .name = "Child" },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "variant", "zg", &.{});

    try std.testing.expectEqual(@as(usize, 4), program.projections.len);

    const tag = program.projections[0];
    try std.testing.expectEqual(abi.AbiProjection.Kind.tag, tag.kind);
    try std.testing.expectEqualStrings("zg_value_project_tag", tag.symbol);
    try std.testing.expectEqual(@as(usize, 2), tag.params.len);
    try std.testing.expectEqual(abi.AbiParam.Role.receiver, tag.params[0].role);
    try std.testing.expect(tag.params[0].scalar.pointer.is_const);
    try std.testing.expectEqualStrings("Value", tag.params[0].scalar.pointer.child.@"opaque".name);
    try std.testing.expectEqual(abi.AbiParam.Role.payload_out, tag.params[1].role);
    try std.testing.expectEqual(@as(u16, 8), tag.params[1].scalar.pointer.child.unsigned_int);
    try std.testing.expect(tag.ret == .bool_u8);
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(abi.AbiProjection.Status.mismatch));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(abi.AbiProjection.Status.success));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(abi.AbiProjection.Status.invalid_handle));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(abi.AbiProjection.Status.panic));

    const number = program.projections[1];
    try std.testing.expectEqual(abi.AbiProjection.Kind.payload, number.kind);
    try std.testing.expectEqualStrings("zg_value_project_number", number.symbol);
    try std.testing.expectEqualStrings("number", number.field.?.name);
    try std.testing.expectEqual(abi.AbiParam.Role.payload_out, number.params[1].role);
    try std.testing.expectEqual(@as(u16, 32), number.params[1].scalar.pointer.child.signed_int);
    try std.testing.expect(number.ret == .bool_u8);

    const samples = program.projections[2];
    try std.testing.expectEqual(abi.AbiParam.Role.return_slice_pointer, samples.params[1].role);
    try std.testing.expect(samples.params[1].scalar.pointer.child.pointer.is_many);
    try std.testing.expect(samples.params[1].scalar.pointer.child.pointer.is_const);
    try std.testing.expectEqual(@as(u16, 16), samples.params[1].scalar.pointer.child.pointer.child.signed_int);
    try std.testing.expectEqual(abi.AbiParam.Role.return_slice_length, samples.params[2].role);
    try std.testing.expect(samples.params[2].scalar.pointer.child.* == .usize);

    const child = program.projections[3];
    try std.testing.expectEqualStrings("zg_value_project_child", child.symbol);
    try std.testing.expectEqual(abi.AbiParam.Role.payload_out, child.params[1].role);
    const child_pointer = child.params[1].scalar.pointer.child.pointer;
    try std.testing.expect(child_pointer.is_const);
    try std.testing.expectEqualStrings("Child", child_pointer.child.@"opaque".name);
}

test "multiple tagged unions keep custom normalized projection symbols isolated" {
    const document: semantic.Semantic = .{
        .package = "multi_variant",
        .prefix = "api",
        .types = &.{
            .{
                .fields = &.{.{ .name = "URLValue", .type = .{ .int = .{ .bits = 64, .signed = false } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "HTTPResult",
                .tag_type = .{ .@"enum" = .{ .ref = "HTTPResultTag" } },
            },
            .{ .fields = &.{.{ .name = "URLValue", .value = 0 }}, .kind = .@"enum", .name = "HTTPResultTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            .{
                .fields = &.{.{ .name = "number", .type = .{ .float = .{ .bits = 64 } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Metric",
                .tag_type = .{ .@"enum" = .{ .ref = "MetricTag" } },
            },
            .{ .fields = &.{.{ .name = "number", .value = 0 }}, .kind = .@"enum", .name = "MetricTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "multi_variant", "api", &.{});

    try std.testing.expectEqual(@as(usize, 4), program.projections.len);
    try std.testing.expectEqualStrings("api_http_result_project_tag", program.projections[0].symbol);
    try std.testing.expectEqualStrings("api_http_result_project_url_value", program.projections[1].symbol);
    try std.testing.expectEqualStrings("api_metric_project_tag", program.projections[2].symbol);
    try std.testing.expectEqualStrings("api_metric_project_number", program.projections[3].symbol);
    try std.testing.expectEqualStrings("HTTPResult", program.projections[1].owner.name);
    try std.testing.expectEqualStrings("Metric", program.projections[3].owner.name);
}

test "mutable tagged union slice projection preserves element mutability" {
    var element: semantic.TypeNode = .{ .int = .{ .bits = 16, .signed = true } };
    const document: semantic.Semantic = .{
        .package = "mutable_variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "buffer", .type = .{ .slice = .{ .@"const" = false, .element = &element } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{ .fields = &.{.{ .name = "buffer", .value = 0 }}, .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "mutable_variant", "zg", &.{});

    const output_pointer = program.projections[1].params[1].scalar.pointer.child.pointer;
    try std.testing.expect(output_pointer.is_many);
    try std.testing.expect(!output_pointer.is_const);
}

test "value snapshot lowering orders payloads by width and spells out padding" {
    const document: semantic.Semantic = .{
        .package = "signal",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "idle", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "ticks", .type = .{ .int = .{ .bits = 32, .signed = false } }, .value = 1 },
                    .{ .name = "level", .type = .{ .float = .{ .bits = 64 } }, .value = 2 },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } }, .value = 3 },
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
                },
                .kind = .@"enum",
                .name = "SignalTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{ .fields = &.{.{ .name = "idle", .value = 0 }}, .kind = .@"enum", .name = "Mode", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "signal", "zg", &.{});

    try std.testing.expectEqual(@as(usize, 1), program.snapshots.len);
    const snapshot = program.snapshots[0];
    try std.testing.expectEqualStrings("zg_signal_snapshot", snapshot.symbol);
    try std.testing.expectEqualStrings("zg_signal_snapshot_t", snapshot.type_name);
    try std.testing.expectEqual(@as(usize, 24), snapshot.size);
    try std.testing.expectEqual(@as(usize, 8), snapshot.alignment);

    // tag, padding to the widest payload, then the payloads widest first.
    const expected = [_]struct { kind: abi.AbiSnapshot.Field.Kind, name: []const u8, bytes: usize }{
        .{ .kind = .tag, .name = "tag", .bytes = 1 },
        .{ .kind = .padding, .name = "reserved_0", .bytes = 7 },
        .{ .kind = .payload, .name = "level", .bytes = 8 },
        .{ .kind = .payload, .name = "ticks", .bytes = 4 },
        .{ .kind = .payload, .name = "mode", .bytes = 1 },
        .{ .kind = .padding, .name = "reserved_1", .bytes = 3 },
    };
    try std.testing.expectEqual(expected.len, snapshot.fields.len);
    for (expected, snapshot.fields) |want, got| {
        try std.testing.expectEqual(want.kind, got.kind);
        try std.testing.expectEqualStrings(want.name, got.name);
        try std.testing.expectEqual(want.bytes, got.bytes);
    }

    // The void variant carries no payload member, and the snapshot never
    // replaces the projections.
    try std.testing.expectEqual(@as(usize, 4), program.projections.len);

    // One call reaches the tag and every payload.
    try std.testing.expectEqual(@as(usize, 2), snapshot.params.len);
    try std.testing.expectEqual(abi.AbiParam.Role.receiver, snapshot.params[0].role);
    try std.testing.expect(snapshot.params[0].scalar.pointer.is_const);
    try std.testing.expectEqualStrings("zg_signal_snapshot_t", snapshot.params[1].scalar.pointer.child.snapshot);
    try std.testing.expect(snapshot.ret == .bool_u8);
}

test "the projection representation lowers no snapshot" {
    const document: semantic.Semantic = .{
        .package = "signal",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "ticks", .type = .{ .int = .{ .bits = 32, .signed = false } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Signal",
                .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
            },
            .{ .fields = &.{.{ .name = "ticks", .value = 0 }}, .kind = .@"enum", .name = "SignalTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "signal", "zg", &.{});
    try std.testing.expectEqual(@as(usize, 0), program.snapshots.len);
    try std.testing.expectEqual(@as(usize, 2), program.projections.len);
}

test "extern struct parameters and returns lower to pointers with a mirrored layout" {
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
                    .{ .name = "enabled", .type = .{ .bool = {} } },
                    .{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } } },
                    .{ .name = "ratio", .type = .{ .float = .{ .bits = 64 } } },
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "config", "zg", &.{});

    // An input struct travels as `const T*`, never by value.
    const configure = program.functions[0];
    try std.testing.expectEqual(@as(usize, 1), configure.params.len);
    try std.testing.expectEqual(abi.AbiParam.Role.struct_in, configure.params[0].role);
    try std.testing.expect(configure.params[0].scalar.pointer.is_const);
    try std.testing.expectEqualStrings("Config", configure.params[0].scalar.pointer.child.value_struct.name);
    try std.testing.expectEqualStrings("zg_config", configure.params[0].scalar.pointer.child.value_struct.c_name);
    try std.testing.expect(configure.ret == .void);

    // A returned struct becomes a mutable out parameter and a void return.
    const default_config = program.functions[1];
    try std.testing.expectEqual(@as(usize, 1), default_config.params.len);
    try std.testing.expectEqual(abi.AbiParam.Role.struct_out, default_config.params[0].role);
    try std.testing.expectEqualStrings("out_result", default_config.params[0].name);
    try std.testing.expect(!default_config.params[0].scalar.pointer.is_const);
    try std.testing.expect(default_config.ret == .void);
    // The function points at the mirror it fills, so no backend looks it up.
    try std.testing.expectEqualStrings("Config", default_config.ret_struct.?.name);
    try std.testing.expect(default_config.payload_struct == null);
    try std.testing.expect(configure.ret_struct == null);

    // A nested struct is emitted before the struct that embeds it, so the C
    // header never names an incomplete type.
    try std.testing.expectEqual(@as(usize, 2), program.structs.len);
    try std.testing.expectEqualStrings("Point", program.structs[0].name);
    try std.testing.expectEqualStrings("Config", program.structs[1].name);

    // The mirror keeps the user's field order and the C compiler's offsets.
    const config = program.structs[1];
    try std.testing.expectEqualStrings("zg_config", config.c_name);
    try std.testing.expectEqual(@as(usize, 8), config.alignment);
    try std.testing.expectEqual(@as(usize, 32), config.size);
    const expected = [_]struct { name: []const u8, offset: usize, bytes: usize }{
        .{ .name = "enabled", .offset = 0, .bytes = 1 },
        .{ .name = "width", .offset = 4, .bytes = 4 },
        .{ .name = "mode", .offset = 8, .bytes = 1 },
        .{ .name = "ratio", .offset = 16, .bytes = 8 },
        .{ .name = "origin", .offset = 24, .bytes = 4 },
    };
    try std.testing.expectEqual(expected.len, config.fields.len);
    for (expected, config.fields) |want, got| {
        try std.testing.expectEqualStrings(want.name, got.name);
        try std.testing.expectEqual(want.offset, got.offset);
        try std.testing.expectEqual(want.bytes, got.bytes);
    }

    const point = program.structs[0];
    try std.testing.expectEqual(@as(usize, 4), point.size);
    try std.testing.expectEqual(@as(usize, 2), point.alignment);
}

test "an extern struct error payload keeps the existing out parameter shape" {
    var payload: semantic.TypeNode = .{ .value_struct = .{ .ref = "Config" } };
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "load",
            .params = &.{},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Failed"}, .payload = &payload } },
            .symbol = "ignored",
        }},
        .package = "config",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
            .kind = .value_struct,
            .layout = .@"extern",
            .name = "Config",
        }},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "config", "zg", &.{.{ .code = 7, .name = "Failed" }});

    const load = program.functions[0];
    try std.testing.expect(load.ret == .signed_int);
    try std.testing.expectEqual(abi.AbiParam.Role.payload_out, load.params[0].role);
    try std.testing.expect(!load.params[0].scalar.pointer.is_const);
    try std.testing.expectEqualStrings("zg_config", load.params[0].scalar.pointer.child.value_struct.c_name);
    try std.testing.expect(load.ret_struct == null);
    try std.testing.expectEqualStrings("Config", load.payload_struct.?.name);
    try std.testing.expectEqual(&program.structs[0], load.payload_struct.?);
}

test "a registered but unused extern struct stays out of the generated surface" {
    const document: semantic.Semantic = .{
        .package = "config",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
            .kind = .value_struct,
            .layout = .@"extern",
            .name = "Config",
        }},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "config", "zg", &.{});
    try std.testing.expectEqual(@as(usize, 0), program.structs.len);
}

test "lowering mints every C type name the header needs" {
    const document: semantic.Semantic = .{
        .package = "names",
        .prefix = "zg",
        .types = &.{
            .{ .kind = .@"opaque", .name = "EventQueue" },
            .{
                .fields = &.{
                    .{ .name = "idle", .value = 0 },
                    .{ .name = "inFlight", .value = 1 },
                },
                .kind = .@"enum",
                .name = "QueueState",
                .tag_type = .{ .int = .{ .bits = 16, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "names", "zg", &.{});

    try std.testing.expectEqual(@as(usize, 1), program.handles.len);
    try std.testing.expectEqualStrings("EventQueue", program.handles[0].name);
    try std.testing.expectEqualStrings("zg_event_queue", program.handles[0].c_name);

    try std.testing.expectEqual(@as(usize, 1), program.enums.len);
    const state = program.enums[0];
    try std.testing.expectEqualStrings("QueueState", state.name);
    try std.testing.expectEqualStrings("zg_queue_state", state.c_name);
    try std.testing.expectEqual(@as(u16, 16), state.tag.unsigned_int);
    try std.testing.expectEqual(@as(usize, 2), state.constants.len);
    try std.testing.expectEqualStrings("ZG_QUEUE_STATE_IDLE", state.constants[0].c_name);
    try std.testing.expectEqualStrings("ZG_QUEUE_STATE_IN_FLIGHT", state.constants[1].c_name);
    try std.testing.expectEqual(@as(i64, 1), state.constants[1].value);
}

test "an error-union slice payload lowers to the plain slice return out parameters" {
    var float_node: semantic.TypeNode = .{ .float = .{ .bits = 32 } };
    var slice_payload: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &float_node } };
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "sampleValuesChecked",
            .params = &.{},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Failed"}, .payload = &slice_payload } },
            .symbol = "ignored",
        }},
        .package = "roles",
        .prefix = "zg",
        .types = &.{},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "roles", "zg", &.{.{ .code = 7, .name = "Failed" }});

    const checked = program.functions[0];
    // The code travels in the return value; the payload uses the same names and
    // roles a plain `[]T` return would, so no emitter needs a second shape.
    try std.testing.expect(checked.ret == .signed_int);
    try std.testing.expectEqual(@as(usize, 2), checked.params.len);
    try std.testing.expectEqualStrings("out_result_ptr", checked.params[0].name);
    try std.testing.expectEqual(abi.AbiParam.Role.return_slice_pointer, checked.params[0].role);
    try std.testing.expect(checked.params[0].scalar.pointer.child.pointer.is_many);
    try std.testing.expect(checked.params[0].scalar.pointer.child.pointer.is_const);
    try std.testing.expectEqualStrings("out_result_len", checked.params[1].name);
    try std.testing.expectEqual(abi.AbiParam.Role.return_slice_length, checked.params[1].role);
    try std.testing.expect(checked.params[1].scalar.pointer.child.* == .usize);
    try std.testing.expectEqual(@as(i32, 7), checked.errors[0].code);
}
