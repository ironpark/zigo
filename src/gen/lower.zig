const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");
const materialized_lowering = @import("lower/materialized.zig");
const appendMaterializedReturnOuts = materialized_lowering.appendMaterializedReturnOuts;
const lowerMaterializedLayouts = materialized_lowering.lowerMaterializedLayouts;
const materializedLayoutIndex = materialized_lowering.materializedLayoutIndex;
const ownership_rules = @import("lower/ownership.zig");
pub const constructorForDeinit = ownership_rules.constructorForDeinit;
pub const constructorForType = ownership_rules.constructorForType;
pub const ownedOpaqueReturn = ownership_rules.ownedOpaqueReturn;
pub const releaseTarget = ownership_rules.releaseTarget;
pub const releasableSliceReturnElement = ownership_rules.releasableSliceReturnElement;
pub const ownershipOf = ownership_rules.ownershipOf;
pub const paramOwnershipOf = ownership_rules.paramOwnershipOf;
pub const isReleaseTarget = ownership_rules.isReleaseTarget;
const recordOwnership = ownership_rules.recordOwnership;

pub fn semanticDocument(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    package: []const u8,
    prefix: []const u8,
    error_codes: []const abi.ErrorCode,
) !abi.Program {
    return semanticDocumentForBackend(allocator, document, package, prefix, error_codes, .cgo);
}

/// Every error-set name the document's functions can fail with, in first-use
/// order and without repeats. This is the order the errors lock numbers them.
pub fn distinctErrorNamesAlloc(allocator: std.mem.Allocator, document: semantic.Semantic) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    errdefer names.deinit(allocator);
    for (document.functions) |function| {
        if (function.@"return" != .error_union) continue;
        next: for (function.@"return".error_union.error_set) |name| {
            for (names.items) |existing| if (std.mem.eql(u8, existing, name)) continue :next;
            try names.append(allocator, name);
        }
    }
    return names.toOwnedSlice(allocator);
}

/// Error codes numbered 1..n over `distinctErrorNamesAlloc`, for renderings
/// that need every error to have a code without consulting the errors lock:
/// the report, `abi-diff`, and the interface signature check.
pub fn provisionalErrorCodesAlloc(allocator: std.mem.Allocator, document: semantic.Semantic) ![]const abi.ErrorCode {
    const names = try distinctErrorNamesAlloc(allocator, document);
    defer allocator.free(names);
    const codes = try allocator.alloc(abi.ErrorCode, names.len);
    for (names, codes, 1..) |name, *code, number| code.* = .{ .code = @intCast(number), .name = name };
    return codes;
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
    document.functions = try promoteCheckedFunctions(allocator, source_document, document.functions);
    // Lowered ahead of the functions, so a function can point at the mirror it
    // fills rather than making a backend find it again by name.
    const structs = try lowerValueStructs(allocator, document, prefix);
    const materialized_layouts = try lowerMaterializedLayouts(allocator, document);
    const functions = try allocator.alloc(abi.AbiFn, document.functions.len);
    for (document.functions, 0..) |*function, function_index| {
        var params: std.ArrayList(abi.AbiParam) = .empty;
        // Where each flattened parameter's fields begin, so no emitter has to
        // search `params` for the field it is rendering.
        const flatten_start = try allocator.alloc(?usize, function.params.len);
        @memset(flatten_start, null);
        if (function.receiver) |receiver| {
            const child = try allocator.create(abi.AbiScalar);
            child.* = .{ .@"opaque" = try lowerOpaque(allocator, prefix, receiver) };
            const receiver_const = function.receiverByValue() or if (function.field_access) |access| !access.setter else false;
            try params.append(allocator, .{
                .name = "self",
                .role = .receiver,
                .scalar = .{ .pointer = .{ .child = child, .is_const = receiver_const } },
            });
        }
        for (function.params, 0..) |parameter, parameter_index| {
            // The shim writes the value itself, so the parameter is absent
            // from the C signature and from everything derived from it.
            if (parameter.injected != null) continue;
            if (abi.materializedOutParameter(parameter) != null) {
                try params.append(allocator, .{
                    .name = try std.fmt.allocPrint(allocator, "{s}_len", .{parameter.name}),
                    .role = .slice_length,
                    .scalar = .usize,
                    .source_index = parameter_index,
                });
                continue;
            }
            if (parameter.flatten) |fields| {
                flatten_start[parameter_index] = params.items.len;
                for (fields, 0..) |field, field_index| {
                    const name = try flattenedFieldNameAlloc(allocator, function.*, parameter_index, field.name);
                    const scalar = if (field.type == .optional) blk: {
                        const child = try allocator.create(abi.AbiScalar);
                        child.* = try lowerValue(allocator, document, prefix, field.type.optional.child.*);
                        break :blk abi.AbiScalar{ .pointer = .{ .child = child, .is_const = true, .is_optional = true } };
                    } else try lowerValue(allocator, document, prefix, field.type);
                    try params.append(allocator, .{
                        .field_index = field_index,
                        .name = name,
                        .role = .flattened_field,
                        .scalar = scalar,
                        .source_index = parameter_index,
                    });
                }
                continue;
            }
            // `?[]T` reuses the slice lowering whole: the same pointer and
            // length cross, and absence rides on the pointer being NULL, so
            // an absent slice and an empty one stay different.
            if (parameter.type == .optional and parameter.type.optional.child.* == .slice) {
                const slice_node = parameter.type.optional.child.*;
                const element = try allocator.create(abi.AbiScalar);
                element.* = try lowerValue(allocator, document, prefix, slice_node.slice.element.*);
                if (semantic.isCStringSlice(slice_node, parameter.semantic)) {
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
            if (semantic.isStringSliceParameter(parameter)) {
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
            if (semantic.isCStringSlice(parameter.type, parameter.semantic)) {
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
            if (parameter.type == .atomic_ptr) {
                const atomic = parameter.type.atomic_ptr;
                const child = try allocator.create(abi.AbiScalar);
                child.* = try lowerValue(allocator, document, prefix, atomic.child.*);
                try params.append(allocator, .{
                    .name = parameter.name,
                    .role = .atomic_ptr,
                    .scalar = .{ .pointer = .{ .child = child, .is_const = atomic.@"const" } },
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
                    const declaration = typeDeclaration(document, value.ref);
                    if (declaration.kind == .tagged_union) {
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
                    if (declaration.layout == .@"packed") {
                        try params.append(allocator, .{
                            .name = parameter.name,
                            .scalar = try lowerValue(allocator, document, prefix, parameter.type),
                            .source_index = parameter_index,
                        });
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
        var materialized_return = abi.materializedReturn(function.@"return");
        if (materialized_return) |*result| result.layout = materializedLayoutIndex(materialized_layouts, result.root);
        var materialized_out = abi.materializedOut(function.*);
        if (materialized_out) |*output| output.layout = materializedLayoutIndex(materialized_layouts, output.root);
        const caller_owned_c_string = function.ownership == .caller and function.release != null and
            returnContainsCStringSlice(function.@"return", function.return_semantic);
        const return_scalar = if (materialized_return) |materialized| result: {
            try appendMaterializedReturnOuts(allocator, &params);
            if (materialized.fallible) {
                function_errors = try codesFor(allocator, function.@"return".error_union.error_set, error_codes);
                break :result abi.AbiScalar{ .signed_int = 32 };
            }
            break :result abi.AbiScalar.void;
        } else if (materialized_out) |output| result: {
            if (output.fallible) {
                const count = try allocator.create(abi.AbiScalar);
                count.* = .usize;
                try params.append(allocator, .{
                    .name = "out_written",
                    .role = .payload_out,
                    .scalar = .{ .pointer = .{ .child = count, .is_const = false } },
                });
            }
            try appendMaterializedReturnOuts(allocator, &params);
            if (output.fallible) {
                function_errors = try codesFor(allocator, function.@"return".error_union.error_set, error_codes);
                break :result abi.AbiScalar{ .signed_int = 32 };
            }
            break :result abi.AbiScalar.usize;
        } else if (semantic.isCStringSlice(function.@"return", function.return_semantic) and !caller_owned_c_string) blk: {
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
                    (!semantic.isCStringSlice(error_union.payload.*, function.return_semantic) or caller_owned_c_string))
                {
                    try appendSliceReturnOuts(allocator, document, prefix, &params, error_union.payload.slice, false);
                } else if (error_union.payload.* == .optional and
                    error_union.payload.optional.child.* == .slice and
                    (!semantic.isCStringSlice(error_union.payload.optional.child.*, function.return_semantic) or caller_owned_c_string))
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
                        .role = if (optional.child.* == .value_struct and !semantic.isPackedValue(document.types, optional.child.*)) .struct_out else .payload_out,
                        .scalar = .{ .pointer = .{ .child = payload, .is_const = false } },
                        .source_index = function.params.len,
                    });
                } else if (error_union.payload.* != .void) {
                    const payload = try allocator.create(abi.AbiScalar);
                    if (taggedUnionValueDeclaration(document, error_union.payload.*)) |declaration| {
                        const record = structRecord(structs, declaration.name);
                        payload.* = .{ .snapshot = record.c_name };
                    } else {
                        payload.* = try lowerValue(allocator, document, prefix, error_union.payload.*);
                    }
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
                if (semantic.isPackedValue(document.types, function.@"return"))
                    break :result try lowerValue(allocator, document, prefix, function.@"return");
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
                    (!semantic.isCStringSlice(optional.child.*, function.return_semantic) or caller_owned_c_string))
                {
                    try appendSliceReturnOuts(allocator, document, prefix, &params, optional.child.slice, true);
                    break :result abi.AbiScalar{ .void = {} };
                }
                const child = try allocator.create(abi.AbiScalar);
                child.* = try lowerValue(allocator, document, prefix, optional.child.*);
                try params.append(allocator, .{
                    .name = "out_result",
                    .role = if (optional.child.* == .value_struct and !semantic.isPackedValue(document.types, optional.child.*)) .struct_out else .payload_out,
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
        const symbol = if (backend == .purego and semantic.functionHasCallback(function.*))
            try std.fmt.allocPrint(allocator, "{s}_purego_v2", .{base_symbol})
        else
            base_symbol;
        functions[function_index] = .{
            .flatten_start = flatten_start,
            .symbol = symbol,
            .params = try params.toOwnedSlice(allocator),
            .ret = return_scalar,
            .errors = function_errors,
            .origin = function,
            .materialized_return = materialized_return,
            .materialized_out = materialized_out,
            .must_variant = try mustVariant(allocator, document, function.*),
            .reaches_callback_errors = functionReachesCallbackErrors(document.functions, document.constructors, function.*),
            .ret_struct = if (function.@"return" == .value_struct and !semantic.isPackedValue(document.types, function.@"return"))
                structRecord(structs, function.@"return".value_struct.ref)
            else if (function.@"return" == .optional and function.@"return".optional.child.* == .value_struct and
                !semantic.isPackedValue(document.types, function.@"return".optional.child.*))
                structRecord(structs, function.@"return".optional.child.value_struct.ref)
            else
                null,
            // A slice optional carries absence in its own pointer, so it
            // takes none of the presence machinery a scalar one needs.
            .ret_optional = function.@"return" == .optional and function.@"return".optional.child.* != .slice,
            .payload_struct = if (function.@"return" == .error_union and
                function.@"return".error_union.payload.* == .value_struct and
                !semantic.isPackedValue(document.types, function.@"return".error_union.payload.*))
                structRecord(structs, function.@"return".error_union.payload.value_struct.ref)
            else if (function.@"return" == .error_union and
                function.@"return".error_union.payload.* == .optional and
                function.@"return".error_union.payload.optional.child.* == .value_struct and
                !semantic.isPackedValue(document.types, function.@"return".error_union.payload.optional.child.*))
                structRecord(structs, function.@"return".error_union.payload.optional.child.value_struct.ref)
            else
                null,
            .value_union_return = taggedUnionValueDeclaration(source_document, source_document.functions[function_index].@"return") != null,
            .param_strings = try classifyParamStrings(allocator, function.*),
            .ret_string = returnStringRole(function.*),
            .slice_return_element = if (materialized_return != null)
                semantic.TypeNode{ .int = .{ .bits = 8, .signed = false } }
            else
                sliceReturnElement(function.*),
            .userdata_for = try pairUserdataParams(allocator, function.*),
        };
    }
    // A callback's Go type name is chosen against every other callback in the
    // program, so it can only be settled once every function is lowered.
    try nameCallbackTypes(allocator, document, functions);
    const handles = try lowerHandles(allocator, document, prefix);
    try numberRetainedCallbackSlots(allocator, document, functions, handles);
    // The ownership record indexes other functions and reads handle slot
    // counts, so it is the last thing settled.
    try recordOwnership(allocator, document, source_document.functions, functions, handles);
    const interfaces = try lowerInterfaces(allocator, document, functions);
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
        .handles = handles,
        .functions = functions,
        .interfaces = interfaces,
        .origins = document.functions,
        .live_fields = try lowerLiveFields(allocator, document),
        .materialized_layouts = materialized_layouts,
        .packed_structs = try lowerPackedStructs(allocator, document),
        .package = package,
        .packages = document.packages,
        .prefix = prefix,
        .projections = projections,
        .snapshots = snapshots,
        .structs = structs,
        .types = document.types,
    };
}

// ---------------------------------------------------------------------------
// Function-shape rules. Emit and validate both ask these questions, so they
// are answered here once, on the semantic document lowering works from, and
// recorded on the lowered function where the answer is per function.
// ---------------------------------------------------------------------------

/// The single rule for whether the public package emits a `Must<Name>`
/// wrapper: the function is public, its Go name is not `Close`, and its
/// signature carries an error -- a constructor, an error-union return, or any
/// of the checks that grow a signature by `error`.
pub fn mustVariant(allocator: std.mem.Allocator, document: semantic.Semantic, function: semantic.SemanticFn) !bool {
    const constructor = semantic.constructorForInit(document.constructors, function);
    if (constructor == null and constructorForDeinit(document.constructors, function) != null) return false;
    if (isReleaseTarget(document.functions, function)) return false;
    const public_name = try semantic.publicFunctionNameAlloc(allocator, document, function);
    defer allocator.free(public_name);
    if (std.mem.eql(u8, public_name, "Close")) return false;
    return constructor != null or function.@"return" == .error_union or needsCheck(document, function);
}

/// Whether the public wrapper returns an `error` the Zig signature does not
/// declare: a handle that can be nil or closed, a narrow integer that can be
/// out of range, a stream that can fail, or a callback that can return a Go
/// error.
pub fn needsCheck(document: semantic.Semantic, function: semantic.SemanticFn) bool {
    return function.receiver != null or hasOpaqueParameter(function) or hasNarrowIntParameter(function) or
        functionHasStream(function) or functionReachesCallbackErrors(document.functions, document.constructors, function);
}

pub fn hasOpaqueParameter(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| if (parameter.type == .opaque_ptr) return true;
    return false;
}

pub fn functionHasStream(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| if (parameter.type == .io_stream) return true;
    return false;
}

/// Whether any parameter is declared narrower than the C integer that carries
/// it, which is what makes the Go signature grow an `error`.
pub fn hasNarrowIntParameter(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| {
        if (abi.narrowInt(parameter.type) != null) return true;
        if (parameter.direction == .in and abi.narrowSliceElement(parameter.type) != null) return true;
        if (parameter.flatten) |fields| for (fields) |field| {
            const node = if (field.type == .optional) field.type.optional.child.* else field.type;
            if (abi.narrowInt(node) != null) return true;
        };
    }
    return false;
}

pub fn hasRetainedCallback(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| if (parameter.type == .callback and parameter.retention == .retained) return true;
    return false;
}

/// True for a callback whose Go type returns an `error` alongside its value,
/// from `param_meta.<name>.go_error`.
pub fn isErrorCallback(parameter: semantic.Parameter) bool {
    return parameter.type == .callback and parameter.goError();
}

/// `go_error` is a property of the callback *signature*, not of one
/// parameter. One Go type is generated per ABI signature and shared by every
/// parameter that has it, and on purego one dispatcher is too, so the answer
/// has to be the same everywhere the signature appears: one `.go_error = true`
/// makes the whole signature carry an error.
pub fn callbackSignatureHasGoError(functions: []const semantic.SemanticFn, wanted: semantic.Callback) bool {
    for (functions) |function| {
        for (function.params) |parameter| {
            if (!isErrorCallback(parameter)) continue;
            if (callbackSignatureEqual(parameter.type.callback, wanted)) return true;
        }
    }
    return false;
}

/// The effective answer for one parameter: the signature's, not the
/// parameter's own flag.
pub fn callbackHasGoError(functions: []const semantic.SemanticFn, parameter: semantic.Parameter) bool {
    return parameter.type == .callback and callbackSignatureHasGoError(functions, parameter.type.callback);
}

pub fn callbackSignatureEqual(lhs: semantic.Callback, rhs: semantic.Callback) bool {
    if (lhs.params.len != rhs.params.len or !semanticTypeEqual(lhs.@"return".*, rhs.@"return".*)) return false;
    for (lhs.params, rhs.params) |a, b| if (!semanticTypeEqual(a, b)) return false;
    return true;
}

fn semanticTypeEqual(lhs: semantic.TypeNode, rhs: semantic.TypeNode) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .void, .bool => true,
        .int => |value| value.bits == rhs.int.bits and value.signed == rhs.int.signed and value.is_usize == rhs.int.is_usize,
        .float => |value| value.bits == rhs.float.bits,
        .@"enum" => |value| std.mem.eql(u8, value.ref, rhs.@"enum".ref),
        .value_struct => |value| std.mem.eql(u8, value.ref, rhs.value_struct.ref),
        .opaque_ptr => |value| value.by_value == rhs.opaque_ptr.by_value and value.@"const" == rhs.opaque_ptr.@"const" and value.nullable == rhs.opaque_ptr.nullable and std.mem.eql(u8, value.ref, rhs.opaque_ptr.ref),
        .slice => |value| value.@"const" == rhs.slice.@"const" and value.sentinel == rhs.slice.sentinel and
            value.sentinel_many == rhs.slice.sentinel_many and semanticTypeEqual(value.element.*, rhs.slice.element.*),
        else => false,
    };
}

/// The handle type that keeps a function's retained callbacks alive: the
/// constructed type, the owned return, or the receiver.
pub fn retainedCallbackOwner(constructors: []const semantic.Constructor, function: semantic.SemanticFn) ?[]const u8 {
    if (!hasRetainedCallback(function)) return null;
    if (semantic.constructorForInit(constructors, function)) |constructor| return constructor.type;
    if (ownedOpaqueReturn(constructors, function)) |owned| return owned;
    return function.receiver;
}

/// True when a handle of this type retains a callback that can report a Go
/// error. Such an error has nowhere to go at the moment it happens -- native
/// code is running -- so it surfaces on the next call that touches the handle,
/// exactly as a retained callback's panic does.
pub fn typeOwnsErrorCallbacks(functions: []const semantic.SemanticFn, constructors: []const semantic.Constructor, type_name: []const u8) bool {
    for (functions) |function| {
        const owner = retainedCallbackOwner(constructors, function) orelse continue;
        if (!std.mem.eql(u8, owner, type_name)) continue;
        for (function.params) |parameter| {
            if (parameter.retention == .retained and callbackHasGoError(functions, parameter)) return true;
        }
    }
    return false;
}

/// True when native code running under this call can reach a Go callback that
/// returns an `error`: one passed to the call, or one a touched handle retains.
pub fn functionReachesCallbackErrors(functions: []const semantic.SemanticFn, constructors: []const semantic.Constructor, function: semantic.SemanticFn) bool {
    if (function.receiver) |receiver| {
        if (typeOwnsErrorCallbacks(functions, constructors, receiver)) return true;
    }
    for (function.params) |parameter| {
        if (callbackHasGoError(functions, parameter)) return true;
        if (parameter.type == .opaque_ptr and typeOwnsErrorCallbacks(functions, constructors, parameter.type.opaque_ptr.ref)) return true;
    }
    return false;
}

fn flattenedFieldNameAlloc(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    source_index: usize,
    field_name: []const u8,
) ![]u8 {
    var collisions: usize = 0;
    for (function.params) |parameter| {
        if (parameter.injected == null and parameter.flatten == null and std.mem.eql(u8, parameter.name, field_name)) collisions += 1;
        if (parameter.flatten) |fields| for (fields) |field| if (std.mem.eql(u8, field.name, field_name)) {
            collisions += 1;
        };
    }
    if (collisions <= 1) return allocator.dupe(u8, field_name);
    return std.fmt.allocPrint(allocator, "{s}_{s}", .{ function.params[source_index].name, field_name });
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
        if (declaration.variantOmitted(field.name)) continue;
        const payload = field.type.?;
        if (payload == .void) continue;
        const slot_name = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ parameter.name, field.name });
        try appendTaggedUnionPayloadParams(allocator, document, prefix, params, payload, slot_name, parameter_index);
    }
}

fn appendTaggedUnionPayloadParams(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    prefix: []const u8,
    params: *std.ArrayList(abi.AbiParam),
    node: semantic.TypeNode,
    slot_name: []const u8,
    source_index: usize,
) !void {
    if (node == .value_struct) {
        const declaration = typeDeclaration(document, node.value_struct.ref);
        if (declaration.layout == .@"packed") {
            try params.append(allocator, .{
                .name = slot_name,
                .role = .union_payload,
                .scalar = try lowerValue(allocator, document, prefix, declaration.backing_type.?),
                .source_index = source_index,
            });
            return;
        }
        for (declaration.fields) |field| {
            const child_name = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ slot_name, field.name });
            try appendTaggedUnionPayloadParams(allocator, document, prefix, params, field.type.?, child_name, source_index);
        }
        return;
    }
    try params.append(allocator, .{
        .name = slot_name,
        .role = .union_payload,
        .scalar = try lowerValue(allocator, document, prefix, node),
        .source_index = source_index,
    });
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
        if (document.isValueOnlyTaggedUnion(declaration.name)) continue;
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
pub fn promoteCheckedFunctions(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    functions: []const semantic.SemanticFn,
) ![]const semantic.SemanticFn {
    const promoted = try allocator.alloc(semantic.SemanticFn, functions.len);
    for (functions, 0..) |function, index| {
        promoted[index] = function;
        const value_union_return = taggedUnionValueDeclaration(document, function.@"return") != null;
        if (function.@"return" == .error_union or (!reportsPanics(function) and !value_union_return)) continue;
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
        if (!document.valueStructUsed(declaration.name)) continue;
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
                .atomic = field.atomic orelse false,
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
            .c_name = try naming.cTypeNameAlloc(allocator, prefix, declaration.name),
            .fields = fields,
            .size = offset + padding(offset, alignment),
            .alignment = alignment,
        });
    }
    for (document.types) |*declaration| {
        if (declaration.kind != .tagged_union or !taggedUnionReturnedByValue(document, declaration.name)) continue;
        var fields: std.ArrayList(abi.AbiStruct.Field) = .empty;
        var offset: usize = 0;
        var alignment: usize = 1;
        try appendValueUnionReturnField(
            allocator,
            document,
            prefix,
            &fields,
            declaration.tag_type.?,
            "tag",
            &offset,
            &alignment,
        );
        for (declaration.fields) |field| {
            if (declaration.variantOmitted(field.name) or field.type.? == .void) continue;
            try appendValueUnionReturnField(
                allocator,
                document,
                prefix,
                &fields,
                field.type.?,
                field.name,
                &offset,
                &alignment,
            );
        }
        try structs.append(allocator, .{
            .owner = declaration,
            .name = declaration.name,
            .c_name = try snapshotTypeNameAlloc(allocator, prefix, declaration.name),
            .fields = try fields.toOwnedSlice(allocator),
            .size = offset + padding(offset, alignment),
            .alignment = alignment,
        });
    }
    const result = try structs.toOwnedSlice(allocator);
    // Castability is a whole-record answer that depends on the members'
    // records, so it is settled after every record exists.
    for (result) |*record| record.castable = structCastable(result, record.*);
    return result;
}

/// True when the Go mirror of `record` may be reinterpreted as the C one. A
/// `bool` member rules it out -- Go does not promise C's representation for
/// it -- and so does a member struct that is itself not castable.
fn structCastable(records: []const abi.AbiStruct, record: abi.AbiStruct) bool {
    for (record.fields) |field| {
        if (field.atomic) return false;
        if (field.node == .bool) return false;
        if (field.node != .value_struct) continue;
        var found = false;
        for (records) |candidate| {
            if (!std.mem.eql(u8, candidate.name, field.node.value_struct.ref)) continue;
            found = true;
            if (!structCastable(records, candidate)) return false;
            break;
        }
        if (!found) return false;
    }
    return true;
}

fn appendValueUnionReturnField(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    prefix: []const u8,
    fields: *std.ArrayList(abi.AbiStruct.Field),
    node: semantic.TypeNode,
    name: []const u8,
    offset: *usize,
    alignment: *usize,
) !void {
    if (node == .value_struct) {
        const declaration = typeDeclaration(document, node.value_struct.ref);
        if (declaration.layout == .@"packed") {
            return appendValueUnionReturnField(allocator, document, prefix, fields, declaration.backing_type.?, name, offset, alignment);
        }
        for (declaration.fields) |field| {
            const child_name = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ name, field.name });
            try appendValueUnionReturnField(allocator, document, prefix, fields, field.type.?, child_name, offset, alignment);
        }
        return;
    }
    const scalar = try lowerValue(allocator, document, prefix, node);
    const bytes = scalarBytes(scalar);
    offset.* += padding(offset.*, bytes);
    try fields.append(allocator, .{
        .name = name,
        .scalar = scalar,
        .node = node,
        .offset = offset.*,
        .bytes = bytes,
    });
    offset.* += bytes;
    alignment.* = @max(alignment.*, bytes);
}

fn taggedUnionReturnedByValue(document: semantic.Semantic, name: []const u8) bool {
    for (document.functions) |function| if (semantic.typeIsNamedValue(function.@"return", name)) return true;
    return false;
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
            if (nested.layout == .@"packed") continue;
            try appendStructInDependencyOrder(allocator, document, nested, ordered);
        }
    }
    for (ordered.items) |present| if (present == declaration) return;
    try ordered.append(allocator, declaration);
}

/// A nested struct is lowered before the struct that embeds it, so its final
/// size and alignment are already recorded and never recomputed here.
fn memberLayout(lowered: []const abi.AbiStruct, node: semantic.TypeNode, scalar: abi.AbiScalar) struct { bytes: usize, alignment: usize } {
    if (node != .value_struct or scalar != .value_struct) {
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
    return .{ .name = name, .c_name = try naming.cTypeNameAlloc(allocator, prefix, name) };
}

/// The handle typedefs the header declares, in declaration order. A tagged
/// union is a handle too: C only ever holds a pointer to it.
fn lowerHandles(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) ![]abi.AbiOpaque {
    var handles: std.ArrayList(abi.AbiOpaque) = .empty;
    for (document.types) |declaration| {
        if (declaration.kind != .@"opaque" and declaration.kind != .tagged_union) continue;
        try handles.append(allocator, try lowerOpaque(allocator, prefix, declaration.name));
    }
    return handles.toOwnedSlice(allocator);
}

/// Numbers every retained callback slot once. A slot belongs to the handle the
/// call transfers the callback to: the constructed type for an initialiser or
/// a caller-owned handle return, the receiver otherwise. Within one owner the
/// numbering walks the functions in program order and, inside a function, the
/// retained callback parameters in parameter order -- the order generated Go
/// reads its handle array in.
fn numberRetainedCallbackSlots(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    functions: []abi.AbiFn,
    handles: []abi.AbiOpaque,
) !void {
    const tables = try allocator.alloc([]?usize, functions.len);
    for (functions, 0..) |lowered, index| {
        tables[index] = try allocator.alloc(?usize, lowered.origin.params.len);
        @memset(tables[index], null);
    }
    const owners = try allocator.alloc(?[]const u8, functions.len);
    for (functions, 0..) |lowered, index| owners[index] = retainedCallbackOwner(document.constructors, lowered.origin.*);
    for (handles) |*handle| {
        var slot: usize = 0;
        for (functions, 0..) |lowered, index| {
            const owner = owners[index] orelse continue;
            if (!std.mem.eql(u8, owner, handle.name)) continue;
            for (lowered.origin.params, 0..) |parameter, parameter_index| {
                if (parameter.type != .callback or parameter.retention != .retained) continue;
                tables[index][parameter_index] = slot;
                slot += 1;
            }
        }
        handle.retained_callback_slots = slot;
    }
    for (functions, 0..) |*lowered, index| lowered.callback_slots = tables[index];
}

/// Every declared interface with its methods resolved per type. Validation
/// has already required each method to exist, so a missing one here is a
/// document that skipped validation and is treated as such.
fn lowerInterfaces(allocator: std.mem.Allocator, document: semantic.Semantic, functions: []const abi.AbiFn) ![]const abi.AbiInterface {
    const declared = document.interfaces orelse return &.{};
    const interfaces = try allocator.alloc(abi.AbiInterface, declared.len);
    for (declared, interfaces) |interface, *lowered| {
        const methods = try allocator.alloc(abi.AbiInterface.Method, interface.methods.len);
        for (interface.methods, methods) |method, *record| {
            const implementations = try allocator.alloc(*const abi.AbiFn, interface.types.len);
            for (interface.types, implementations) |type_name, *implementation| {
                implementation.* = for (functions) |*candidate| {
                    const receiver = candidate.origin.receiver orelse continue;
                    if (std.mem.eql(u8, receiver, type_name) and std.mem.eql(u8, candidate.origin.name, method)) break candidate;
                } else return error.InvalidSemantic;
            }
            record.* = .{ .name = method, .functions = implementations };
        }
        lowered.* = .{
            .name = interface.name,
            .doc = interface.doc,
            .closer = interface.closer,
            .package = interface.package,
            .types = interface.types,
            .methods = methods,
        };
    }
    return interfaces;
}

/// The members `omit` left standing, per declaration. Applying the rule here
/// keeps every emitter loop a plain walk over what the binding exposes.
fn lowerLiveFields(allocator: std.mem.Allocator, document: semantic.Semantic) ![]const abi.AbiLiveFields {
    const entries = try allocator.alloc(abi.AbiLiveFields, document.types.len);
    for (document.types, 0..) |declaration, index| {
        var fields: std.ArrayList(semantic.TypeField) = .empty;
        for (declaration.fields) |field| {
            if (declaration.variantOmitted(field.name)) continue;
            try fields.append(allocator, field);
        }
        entries[index] = .{ .type_name = declaration.name, .fields = try fields.toOwnedSlice(allocator) };
    }
    return entries;
}

/// The bit layout of every `packed struct`: fields pack from the least
/// significant bit upwards, in declaration order, each taking its declared
/// width.
fn lowerPackedStructs(allocator: std.mem.Allocator, document: semantic.Semantic) ![]const abi.AbiPacked {
    var packed_structs: std.ArrayList(abi.AbiPacked) = .empty;
    for (document.types) |declaration| {
        if (declaration.kind != .value_struct or declaration.layout != .@"packed") continue;
        const fields = try allocator.alloc(abi.AbiPacked.Field, declaration.fields.len);
        var bit_offset: u16 = 0;
        for (declaration.fields, 0..) |field, index| {
            const bits = packedBitWidth(document, field.type.?);
            fields[index] = .{
                .name = field.name,
                .bit_offset = bit_offset,
                .bits = bits,
                .mask = if (bits == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(bits)) - 1,
            };
            bit_offset += bits;
        }
        try packed_structs.append(allocator, .{ .name = declaration.name, .fields = fields });
    }
    return packed_structs.toOwnedSlice(allocator);
}

fn packedBitWidth(document: semantic.Semantic, node: semantic.TypeNode) u16 {
    return switch (node) {
        .bool => 1,
        .int => |value| value.bits,
        .@"enum" => |value| packedBitWidth(document, typeDeclaration(document, value.ref).tag_type.?),
        .value_struct => |value| typeDeclaration(document, value.ref).backing_type.?.int.bits,
        else => unreachable,
    };
}

/// The enum typedefs and their member constants. The constant name is already
/// uppercased here, so no backend re-spells it.
fn lowerEnums(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) ![]const abi.AbiEnum {
    var enums: std.ArrayList(abi.AbiEnum) = .empty;
    for (document.types) |declaration| {
        if (declaration.kind != .@"enum") continue;
        const c_name = try naming.cTypeNameAlloc(allocator, prefix, declaration.name);
        const constants = try allocator.alloc(abi.AbiEnum.Constant, declaration.fields.len);
        var constant_count: usize = 0;
        for (declaration.fields) |field| {
            if (declaration.variantOmitted(field.name)) continue;
            const member = try naming.snakeAlloc(allocator, field.name);
            defer allocator.free(member);
            const combined = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ c_name, member });
            defer allocator.free(combined);
            constants[constant_count] = .{
                .name = field.name,
                .c_name = try std.ascii.allocUpperString(allocator, combined),
                .value = field.value.?,
            };
            constant_count += 1;
        }
        try enums.append(allocator, .{
            .name = declaration.name,
            .c_name = c_name,
            .tag = try lowerValue(allocator, document, prefix, declaration.tag_type.?),
            .constants = constants[0..constant_count],
        });
    }
    return enums.toOwnedSlice(allocator);
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
        .@"enum" => |value| lowerValue(allocator, document, prefix, typeDeclaration(document, value.ref).tag_type.?),
        .opaque_ptr => |value| blk: {
            const child = try allocator.create(abi.AbiScalar);
            child.* = .{ .@"opaque" = try lowerOpaque(allocator, prefix, value.ref) };
            break :blk .{ .pointer = .{ .child = child, .is_const = value.@"const", .is_optional = value.nullable } };
        },
        .value_struct => |value| blk: {
            const declaration = typeDeclaration(document, value.ref);
            if (declaration.layout == .@"packed")
                break :blk try lowerValue(allocator, document, prefix, declaration.backing_type.?);
            break :blk .{ .value_struct = .{
                .name = value.ref,
                .c_name = try naming.cTypeNameAlloc(allocator, prefix, value.ref),
            } };
        },
        // Validation rejects every node that cannot be lowered, so this is a
        // backstop against a malformed document rather than a reachable path.
        else => error.UnsupportedType,
    };
}

/// How each semantic parameter carries text, indexed by parameter index. The
/// three roles are mutually exclusive: a string slice's elements are slices,
/// so it can never also be a bare byte slice.
fn classifyParamStrings(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]const abi.AbiFn.ParamString {
    const result = try allocator.alloc(abi.AbiFn.ParamString, function.params.len);
    for (function.params, 0..) |parameter, index| {
        result[index] = if (semantic.stringSliceForm(parameter.type, parameter.semantic)) |form|
            .{ .role = if (parameter.direction == .in) .string_slice else .none, .form = if (parameter.direction == .in) form else null }
        else if (semantic.isCStringSliceThroughOptional(parameter.type, parameter.semantic))
            .{ .role = .c_string }
        else if (semantic.isUtf8Slice(parameter.type, parameter.semantic))
            .{ .role = .utf8_slice }
        else
            .{};
    }
    return result;
}

/// How the result carries text. A caller-owned slice return with a release
/// target is deliberately not a C string here: it is handed over as the
/// out-pointer-and-length pair `sliceReturnElement` describes, and generated
/// Go copies it and calls the release function.
fn returnStringRole(function: semantic.SemanticFn) abi.AbiFn.StringRole {
    const payload = if (function.@"return" == .error_union) function.@"return".error_union.payload.* else function.@"return";
    const caller_owned = function.ownership == .caller and function.release != null;
    if (!caller_owned and semantic.isCStringSliceThroughOptional(payload, function.return_semantic)) return .c_string;
    if (semantic.isUtf8Slice(payload, function.return_semantic)) return .utf8_slice;
    return .none;
}

/// The element a slice return crosses with, or null when the result is not
/// one. A C-string return is excluded: it travels as a plain pointer with no
/// length beside it.
fn sliceReturnElement(function: semantic.SemanticFn) ?semantic.TypeNode {
    if (returnStringRole(function) == .c_string) return null;
    return switch (function.@"return") {
        .slice => |value| value.element.*,
        // `?[]T` hands back the same pointer and length; absence is the NULL
        // pointer, so nothing about the shape changes here.
        .optional => |value| if (value.child.* == .slice) value.child.slice.element.* else null,
        .error_union => |value| if (value.payload.* == .slice)
            value.payload.slice.element.*
        else if (semantic.isOptionalSlice(value.payload.*))
            value.payload.optional.child.slice.element.*
        else
            null,
        else => null,
    };
}

test "narrow integer slice elements cross at their promoted width" {
    var narrow: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    const slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &narrow } };
    const params = [_]semantic.Parameter{.{ .name = "values", .type = slice }};
    const functions = [_]semantic.SemanticFn{
        .{ .name = "consume", .params = &params, .@"return" = .{ .void = {} }, .symbol = "zg_consume" },
        .{ .name = "view", .params = &.{}, .@"return" = slice, .symbol = "zg_view" },
    };
    const document: semantic.Semantic = .{
        .functions = &functions,
        .package = "narrow",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "narrow", "zg", &.{});
    try std.testing.expectEqual(@as(u16, 32), program.functions[0].params[0].scalar.pointer.child.unsigned_int);
    try std.testing.expectEqual(@as(u16, 32), program.functions[1].params[0].scalar.pointer.child.pointer.child.unsigned_int);
}

/// The callback each userdata parameter belongs to. A callback that carries
/// userdata is always followed immediately by its token, so the pairing is
/// fixed by position rather than by name.
fn pairUserdataParams(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]const ?usize {
    const result = try allocator.alloc(?usize, function.params.len);
    for (result, 0..) |*entry, index| {
        entry.* = null;
        if (index == 0) continue;
        const callback = function.params[index - 1];
        if (callback.type == .callback and callback.type.callback.has_userdata) entry.* = index - 1;
    }
    return result;
}

/// The public Go type name of every callback parameter, and whether this use
/// is the first in program order to produce that name. A declared callback
/// type names itself; an anonymous signature is named after its owner and
/// parameter, qualified when two of them would otherwise collide, and
/// suffixed with `Callback` when the name is already a public type.
fn nameCallbackTypes(allocator: std.mem.Allocator, document: semantic.Semantic, functions: []abi.AbiFn) !void {
    for (functions) |*lowered| {
        const entries = try allocator.alloc(?abi.AbiFn.CallbackType, lowered.origin.params.len);
        for (entries) |*entry| entry.* = null;
        lowered.callback_types = entries;
    }
    var seen: std.ArrayList([]const u8) = .empty;
    defer seen.deinit(allocator);
    for (functions) |*lowered| {
        const entries = @constCast(lowered.callback_types);
        for (lowered.origin.params, 0..) |parameter, index| {
            if (parameter.type != .callback) continue;
            const name = try callbackTypeNameAlloc(allocator, document, functions, lowered.*, index);
            var first_use = true;
            for (seen.items) |taken| if (std.mem.eql(u8, taken, name)) {
                first_use = false;
                break;
            };
            if (first_use) try seen.append(allocator, name);
            entries[index] = .{ .name = name, .first_use = first_use };
        }
    }
}

fn callbackTypeNameAlloc(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    functions: []const abi.AbiFn,
    function: abi.AbiFn,
    parameter_index: usize,
) ![]u8 {
    // A declared callback type names itself; the derived name is for the
    // signatures the binding left anonymous.
    if (function.origin.params[parameter_index].type.callback.ref) |ref| return allocator.dupe(u8, ref);
    const base = try callbackTypeBaseNameAlloc(allocator, function.origin.*, parameter_index);
    defer allocator.free(base);
    var duplicate_base = false;
    for (functions) |candidate| {
        for (candidate.origin.params, 0..) |parameter, candidate_index| {
            if (parameter.type != .callback) continue;
            if (candidate.origin == function.origin and candidate_index == parameter_index) continue;
            const candidate_base = try callbackTypeBaseNameAlloc(allocator, candidate.origin.*, candidate_index);
            defer allocator.free(candidate_base);
            if (std.mem.eql(u8, base, candidate_base)) duplicate_base = true;
        }
    }

    const owner = function.origin.receiver orelse function.origin.namespace;
    const qualified = if (duplicate_base and owner != null) blk: {
        const owner_name = try naming.ownerPascalAlloc(allocator, owner.?);
        defer allocator.free(owner_name);
        const function_name = try naming.pascalAlloc(allocator, function.origin.name);
        defer allocator.free(function_name);
        const parameter_name = try naming.pascalAlloc(allocator, function.origin.params[parameter_index].name);
        defer allocator.free(parameter_name);
        break :blk try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ owner_name, function_name, parameter_name });
    } else try allocator.dupe(u8, base);
    defer allocator.free(qualified);

    for (document.types) |declaration| {
        if (std.mem.eql(u8, declaration.name, qualified))
            return std.fmt.allocPrint(allocator, "{s}Callback", .{qualified});
    }
    return allocator.dupe(u8, qualified);
}

fn callbackTypeBaseNameAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn, parameter_index: usize) ![]u8 {
    const parameter_name = try naming.pascalAlloc(allocator, function.params[parameter_index].name);
    defer allocator.free(parameter_name);
    if (function.receiver orelse function.namespace) |owner| {
        const owner_name = try naming.ownerPascalAlloc(allocator, owner);
        defer allocator.free(owner_name);
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ owner_name, parameter_name });
    }
    const function_name = try naming.pascalAlloc(allocator, function.name);
    defer allocator.free(function_name);
    // A parameter already called `callback` would otherwise stutter into
    // `ApplyCallbackCallback`.
    if (std.mem.eql(u8, parameter_name, "Callback"))
        return std.fmt.allocPrint(allocator, "{s}Callback", .{function_name});
    return std.fmt.allocPrint(allocator, "{s}{s}Callback", .{ function_name, parameter_name });
}

fn returnContainsCStringSlice(node: semantic.TypeNode, hint: ?semantic.SemanticHint) bool {
    const payload = if (node == .error_union) node.error_union.payload.* else node;
    const child = if (payload == .optional) payload.optional.child.* else payload;
    return semantic.isCStringSlice(child, hint);
}

fn typeDeclaration(document: semantic.Semantic, name: []const u8) semantic.TypeDecl {
    return semantic.typeDecl(document.types, name) orelse unreachable;
}

fn taggedUnionValueDeclaration(document: semantic.Semantic, node: semantic.TypeNode) ?semantic.TypeDecl {
    if (node != .value_struct) return null;
    const declaration = typeDeclaration(document, node.value_struct.ref);
    return if (declaration.kind == .tagged_union) declaration else null;
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

test "retained callback slots are numbered per owning handle in declaration order" {
    var callback_result: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const callback: semantic.TypeNode = .{ .callback = .{
        .has_userdata = false,
        .params = &.{},
        .@"return" = &callback_result,
    } };
    const handle: semantic.TypeNode = .{ .opaque_ptr = .{ .ref = "Watcher", .nullable = false, .@"const" = false } };
    const document: semantic.Semantic = .{
        .constructors = &.{.{ .deinit = "deinit", .init = "init", .type = "Watcher" }},
        .functions = &.{
            .{
                .name = "init",
                .namespace = "Watcher",
                .ownership = .caller,
                .params = &.{
                    .{ .name = "onStart", .retention = .retained, .type = callback },
                    .{ .name = "onStop", .retention = .retained, .type = callback },
                },
                .@"return" = handle,
                .symbol = "ignored",
            },
            .{
                .name = "onTick",
                .params = &.{.{ .name = "handler", .retention = .retained, .type = callback }},
                .receiver = "Watcher",
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            },
            // Borrowed callbacks take no slot, so they do not shift the
            // numbering of the retained ones that follow.
            .{
                .name = "each",
                .params = &.{.{ .name = "visit", .type = callback }},
                .receiver = "Watcher",
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            },
        },
        .package = "watch",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Watcher" }},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "watch", "zg", &.{});

    try std.testing.expectEqual(@as(usize, 3), program.retainedCallbackSlotCount("Watcher"));
    try std.testing.expectEqual(@as(?usize, 0), program.functions[0].callbackSlot(0));
    try std.testing.expectEqual(@as(?usize, 1), program.functions[0].callbackSlot(1));
    try std.testing.expectEqual(@as(?usize, 2), program.functions[1].callbackSlot(0));
    try std.testing.expectEqual(@as(?usize, null), program.functions[2].callbackSlot(0));
    try std.testing.expectEqual(@as(usize, 0), program.retainedCallbackSlotCount("Missing"));
}

test "flattened fields are reachable by parameter and field index" {
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "resize",
            .params = &.{
                .{ .name = "scale", .type = .{ .float = .{ .bits = 32 } } },
                .{
                    .flatten = &.{
                        .{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                        .{ .name = "height", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                    },
                    .name = "size",
                    .type = .{ .value_struct = .{ .ref = "Size" } },
                },
            },
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "layout",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{
                .{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                .{ .name = "height", .type = .{ .int = .{ .bits = 32, .signed = true } } },
            },
            .kind = .value_struct,
            .layout = .@"extern",
            .name = "Size",
        }},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "layout", "zg", &.{});

    const resize = program.functions[0];
    try std.testing.expectEqual(@as(?usize, null), resize.flatten_start[0]);
    try std.testing.expectEqualStrings("width", resize.flattenedParam(1, 0).name);
    try std.testing.expectEqualStrings("height", resize.flattenedParam(1, 1).name);
    try std.testing.expectEqual(abi.AbiParam.Role.flattened_field, resize.flattenedParam(1, 1).role);
}

test "lowering drops omitted members and lays packed fields out from the low bit" {
    const document: semantic.Semantic = .{
        .package = "flags",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "idle", .value = 0 },
                    .{ .name = "draining", .value = 1 },
                    .{ .name = "closed", .value = 2 },
                },
                .kind = .@"enum",
                .name = "State",
                .omitted_variants = &.{"draining"},
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{
                .backing_type = .{ .int = .{ .bits = 16, .signed = false } },
                .fields = &.{
                    .{ .name = "enabled", .type = .{ .bool = {} } },
                    .{ .name = "level", .type = .{ .int = .{ .bits = 4, .signed = false } } },
                    .{ .name = "state", .type = .{ .@"enum" = .{ .ref = "State" } } },
                },
                .kind = .value_struct,
                .layout = .@"packed",
                .name = "Flags",
            },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "flags", "zg", &.{});

    const live = program.liveFields("State");
    try std.testing.expectEqual(@as(usize, 2), live.len);
    try std.testing.expectEqualStrings("idle", live[0].name);
    try std.testing.expectEqualStrings("closed", live[1].name);

    const layout = program.packedLayout("Flags");
    try std.testing.expectEqual(@as(usize, 3), layout.len);
    try std.testing.expectEqual(@as(u16, 0), layout[0].bit_offset);
    try std.testing.expectEqual(@as(u64, 0x1), layout[0].mask);
    try std.testing.expectEqual(@as(u16, 1), layout[1].bit_offset);
    try std.testing.expectEqual(@as(u64, 0xf), layout[1].mask);
    // An enum member takes its tag type's width, not the width of its values.
    try std.testing.expectEqual(@as(u16, 5), layout[2].bit_offset);
    try std.testing.expectEqual(@as(u16, 8), layout[2].bits);
}

test "lowering records how every parameter and return carries text" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var sentinel_element: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte, .sentinel = 0, .sentinel_many = true } };
    var payload: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "apply",
                .params = &.{
                    .{ .name = "names", .type = .{ .slice = .{ .@"const" = true, .element = &sentinel_element } } },
                    .{ .name = "path", .semantic = .c_string, .type = .{ .slice = .{ .@"const" = true, .element = &byte } } },
                    .{ .name = "text", .semantic = .utf8_string, .type = .{ .slice = .{ .@"const" = true, .element = &byte } } },
                    .{ .name = "raw", .type = .{ .slice = .{ .@"const" = true, .element = &byte } } },
                },
                .@"return" = .{ .void = {} },
                .symbol = "zg_apply",
            },
            // A caller-owned C string is handed over as a slice with a
            // release target, not as a bare `const char *`.
            .{ .name = "owned", .ownership = .caller, .release = "free", .return_semantic = .c_string, .params = &.{}, .@"return" = .{ .slice = .{ .@"const" = true, .element = &byte } }, .symbol = "zg_owned" },
            .{ .name = "borrowed", .return_semantic = .c_string, .params = &.{}, .@"return" = .{ .slice = .{ .@"const" = true, .element = &byte } }, .symbol = "zg_borrowed" },
            .{ .name = "free", .params = &.{.{ .name = "value", .type = .{ .slice = .{ .@"const" = true, .element = &byte } } }}, .@"return" = .{ .void = {} }, .symbol = "zg_free" },
            .{ .name = "words", .ownership = .caller, .release = "free", .params = &.{}, .@"return" = .{ .error_union = .{ .payload = &payload, .error_set = &.{} } }, .symbol = "zg_words" },
        },
        .package = "text",
        .prefix = "zg",
        .types = &.{},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "text", "zg", &.{});

    const apply = program.functions[0];
    try std.testing.expectEqual(abi.AbiFn.StringRole.string_slice, apply.paramString(0).role);
    // `[*:0]const u8` elements are accepted like `[:0]const u8` ones; only the
    // element spelling the shim rebuilds differs.
    try std.testing.expectEqual(@as(?semantic.StringSliceForm, .sentinel_many), apply.paramString(0).form);
    try std.testing.expectEqual(abi.AbiFn.StringRole.c_string, apply.paramString(1).role);
    try std.testing.expectEqual(abi.AbiFn.StringRole.utf8_slice, apply.paramString(2).role);
    try std.testing.expectEqual(abi.AbiFn.StringRole.none, apply.paramString(3).role);

    try std.testing.expectEqual(abi.AbiFn.StringRole.none, program.functions[1].ret_string);
    try std.testing.expect(program.functions[1].slice_return_element != null);
    try std.testing.expectEqual(abi.AbiFn.StringRole.c_string, program.functions[2].ret_string);
    // A C-string return crosses as a plain pointer, so it has no length to
    // write into `out_result_len`.
    try std.testing.expect(program.functions[2].slice_return_element == null);
    try std.testing.expect(program.functions[4].slice_return_element != null);
}

test "lowering pairs userdata with its callback and names the callback type" {
    var callback_return: semantic.TypeNode = .{ .void = {} };
    var token: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = true, .ref = "Token" } };
    const callback: semantic.TypeNode = .{ .callback = .{ .params = &.{}, .@"return" = &callback_return, .has_userdata = true } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "watch",
                .namespace = "Queue",
                .params = &.{
                    .{ .name = "onEvent", .type = callback },
                    .{ .name = "userdata", .type = .{ .optional = .{ .child = &token } } },
                },
                .@"return" = .{ .void = {} },
                .symbol = "zg_queue_watch",
            },
        },
        .package = "queue",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Token" }},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "queue", "zg", &.{});
    const watch = program.functions[0];
    // The token sits directly after the callback that owns it.
    try std.testing.expectEqual(@as(?usize, null), watch.userdataFor(0));
    try std.testing.expectEqual(@as(?usize, 0), watch.userdataFor(1));
    try std.testing.expectEqualStrings("QueueOnEvent", watch.callbackType(0).?.name);
    try std.testing.expect(watch.callbackType(0).?.first_use);
    try std.testing.expect(watch.callbackType(1) == null);
}

test "struct castability follows the members, nested structs included" {
    const document: semantic.Semantic = .{
        .functions = &.{
            .{ .name = "take", .params = &.{
                .{ .name = "plain", .type = .{ .value_struct = .{ .ref = "Plain" } } },
                .{ .name = "flagged", .type = .{ .value_struct = .{ .ref = "Flagged" } } },
                .{ .name = "nested", .type = .{ .value_struct = .{ .ref = "Nested" } } },
            }, .@"return" = .{ .void = {} }, .symbol = "zg_take" },
        },
        .package = "shapes",
        .prefix = "zg",
        .types = &.{
            .{ .kind = .value_struct, .layout = .@"extern", .name = "Plain", .fields = &.{.{ .name = "count", .type = .{ .int = .{ .bits = 32, .signed = true } } }} },
            .{ .kind = .value_struct, .layout = .@"extern", .name = "Flagged", .fields = &.{.{ .name = "on", .type = .{ .bool = {} } }} },
            .{ .kind = .value_struct, .layout = .@"extern", .name = "Nested", .fields = &.{.{ .name = "inner", .type = .{ .value_struct = .{ .ref = "Flagged" } } }} },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "shapes", "zg", &.{});
    try std.testing.expect(program.structCastable("Plain"));
    // Go does not promise C's `bool` representation, and a struct that
    // embeds one inherits the answer.
    try std.testing.expect(!program.structCastable("Flagged"));
    try std.testing.expect(!program.structCastable("Nested"));
}

test "lowering records who owns every result" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var narrow: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    var bytes: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    const narrow_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &narrow } };
    var optional_bytes: semantic.TypeNode = .{ .optional = .{ .child = &bytes } };
    var store: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Store" } };
    var cursor: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Cursor" } };
    const view: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = true, .ref = "View" } };
    var node: semantic.TypeNode = .{ .materialized = .{ .ref = "Node" } };
    const fields = [_]semantic.TypeField{.{ .name = "value", .type = .{ .int = .{ .bits = 32, .signed = true } } }};
    const document: semantic.Semantic = .{
        .allocator = "std.heap.smp_allocator",
        .constructors = &.{
            .{ .deinit = "close", .init = "open", .type = "Store" },
            .{ .deinit = "destroy", .init = "create", .type = "Cursor" },
        },
        .functions = &.{
            // 1. A constructed handle.
            .{ .name = "open", .namespace = "Store", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{}, .payload = &store } }, .symbol = "zg_store_open" },
            .{ .name = "close", .receiver = "Store", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_store_close" },
            // 2. A boxed value constructor, created as a child of the store.
            .{ .name = "create", .boxed = .create, .child_of_receiver = true, .receiver = "Store", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{}, .payload = &cursor } }, .symbol = "zg_store_create" },
            .{ .name = "destroy", .boxed = .destroy, .receiver = "Cursor", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_cursor_destroy" },
            // 4. A borrowed view into the receiver.
            .{ .name = "view", .borrowed_return = true, .receiver = "Store", .params = &.{}, .@"return" = view, .symbol = "zg_store_view" },
            // 5. A borrowed slice, copied and never released.
            .{ .name = "peek", .receiver = "Store", .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{}, .payload = &optional_bytes } }, .symbol = "zg_store_peek" },
            // 6. A caller-owned slice with a release method on the receiver.
            .{ .name = "take", .receiver = "Store", .ownership = .caller, .release = "give", .params = &.{}, .@"return" = optional_bytes, .symbol = "zg_store_take" },
            .{ .name = "give", .receiver = "Store", .params = &.{.{ .name = "buffer", .type = bytes }}, .@"return" = .{ .void = {} }, .symbol = "zg_store_give" },
            // 7. Strings: borrowed crosses as a C pointer, caller-owned as a buffer.
            .{ .name = "name", .return_semantic = .c_string, .params = &.{}, .@"return" = bytes, .symbol = "zg_name" },
            .{ .name = "render", .ownership = .caller, .release = "free", .return_semantic = .c_string, .params = &.{}, .@"return" = bytes, .symbol = "zg_render" },
            .{ .name = "free", .params = &.{.{ .name = "buffer", .type = bytes }}, .@"return" = .{ .void = {} }, .symbol = "zg_free" },
            // 8. A narrow element the shim widens in place.
            .{ .name = "codepoints", .ownership = .caller, .release = "freeCodepoints", .params = &.{}, .@"return" = narrow_slice, .symbol = "zg_codepoints" },
            .{ .name = "freeCodepoints", .params = &.{.{ .name = "values", .type = narrow_slice }}, .@"return" = .{ .void = {} }, .symbol = "zg_free_codepoints" },
            // 10. A materialized tree, returned and staged out.
            .{ .name = "snapshot", .ownership = .caller, .release = "free", .params = &.{}, .@"return" = node, .symbol = "zg_snapshot" },
            .{ .name = "fill", .ownership = .caller, .release = "free", .params = &.{.{ .direction = .out, .name = "output", .type = .{ .slice = .{ .@"const" = false, .element = &node } }, .written = .@"return" }}, .@"return" = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } }, .symbol = "zg_fill" },
            // 13. A value.
            .{ .name = "count", .params = &.{}, .@"return" = .{ .int = .{ .bits = 32, .signed = true } }, .symbol = "zg_count" },
        },
        .package = "owners",
        .prefix = "zg",
        .types = &.{
            .{ .kind = .@"opaque", .name = "Store" },
            .{ .kind = .@"opaque", .name = "Cursor" },
            .{ .kind = .@"opaque", .name = "View" },
            .{ .fields = &fields, .kind = .materialized, .materialized_version = 1, .name = "Node", .zig_path = "Node" },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "owners", "zg", &.{});
    const functions = program.functions;

    const open = functions[0].ownership.handle;
    try std.testing.expectEqualStrings("Store", open.type_name);
    try std.testing.expectEqualStrings("zg_store_close", open.destructor.?);
    try std.testing.expect(!open.boxed and !open.child_of_receiver);
    try std.testing.expectEqual(abi.Ownership.none, functions[1].ownership);

    const create = functions[2].ownership.handle;
    try std.testing.expectEqualStrings("Cursor", create.type_name);
    try std.testing.expectEqualStrings("zg_cursor_destroy", create.destructor.?);
    try std.testing.expect(create.boxed and create.child_of_receiver);

    try std.testing.expectEqualStrings("View", functions[4].ownership.borrowed_view.type_name);

    const peek = functions[5].ownership.borrowed_copy;
    try std.testing.expect(peek.element == .int and peek.absent and peek.fallible);
    try std.testing.expectEqual(abi.AbiFn.StringRole.none, peek.text);

    const take = functions[6].ownership.buffer;
    try std.testing.expectEqual(@as(usize, 7), take.release);
    try std.testing.expectEqualStrings("zg_store_give", functions[take.release].symbol);
    try std.testing.expectEqualStrings("zg_store", take.release_receiver_c_name.?);
    // A method reports panics, so its promoted return is an error union.
    try std.testing.expect(take.absent and take.fallible and !take.narrow and take.materialized == null);
    // The release target itself owns nothing.
    try std.testing.expectEqual(abi.Ownership.none, functions[7].ownership);

    const name = functions[8].ownership.borrowed_copy;
    try std.testing.expectEqual(abi.AbiFn.StringRole.c_string, name.text);
    try std.testing.expect(semantic.isByte(name.element));
    // A caller-owned C string is a byte buffer with a release, not a C pointer.
    const render = functions[9].ownership.buffer;
    try std.testing.expect(semantic.isByte(render.element));
    try std.testing.expectEqual(@as(usize, 10), render.release);
    try std.testing.expect(render.release_receiver_c_name == null);

    const codepoints = functions[11].ownership.buffer;
    try std.testing.expect(codepoints.narrow);
    try std.testing.expectEqual(@as(u16, 21), codepoints.element.int.bits);

    const snapshot = functions[13].ownership.buffer;
    try std.testing.expect(semantic.isByte(snapshot.element));
    try std.testing.expectEqual(@as(?usize, 0), snapshot.materialized);
    const fill = functions[14].ownership.buffer;
    try std.testing.expectEqual(@as(?usize, 0), fill.materialized);
    try std.testing.expectEqual(@as(usize, 10), fill.release);

    try std.testing.expectEqual(abi.Ownership.none, functions[15].ownership);
}

test "lowering records what every parameter does with memory" {
    var callback_result: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const callback: semantic.TypeNode = .{ .callback = .{ .has_userdata = false, .params = &.{}, .@"return" = &callback_result } };
    var hub: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Hub" } };
    var narrow: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    var node: semantic.TypeNode = .{ .materialized = .{ .ref = "Node" } };
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const narrow_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &narrow } };
    const fields = [_]semantic.TypeField{.{ .name = "value", .type = .{ .int = .{ .bits = 32, .signed = true } } }};
    const document: semantic.Semantic = .{
        .allocator = "std.heap.smp_allocator",
        .constructors = &.{.{ .deinit = "deinit", .init = "create", .type = "Hub" }},
        .functions = &.{
            // 11. Retained callbacks become tokens the handle stores.
            .{ .name = "create", .namespace = "Hub", .ownership = .caller, .params = &.{
                .{ .name = "observer", .retention = .retained, .type = callback },
                .{ .name = "userdata", .type = .{ .int = .{ .bits = 64, .signed = false } } },
            }, .@"return" = .{ .error_union = .{ .error_set = &.{}, .payload = &hub } }, .symbol = "zg_hub_create" },
            .{ .name = "deinit", .receiver = "Hub", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_hub_deinit" },
            .{ .name = "watch", .receiver = "Hub", .params = &.{
                .{ .name = "handler", .retention = .retained, .type = callback },
                .{ .name = "once", .type = callback },
            }, .@"return" = .{ .void = {} }, .symbol = "zg_hub_watch" },
            // 12. A stream lives for the call.
            .{ .name = "dump", .receiver = "Hub", .params = &.{.{ .name = "w", .type = .{ .io_stream = .{ .direction = .writer } } }}, .@"return" = .{ .void = {} }, .symbol = "zg_hub_dump" },
            // 9. Narrow slices are staged, in either direction, except in the
            // release target that must see the buffer as it was handed out.
            .{ .name = "sum", .params = &.{
                .{ .name = "values", .type = narrow_slice },
                .{ .direction = .out, .name = "filled", .type = .{ .slice = .{ .@"const" = false, .element = &narrow } } },
            }, .@"return" = .{ .void = {} }, .symbol = "zg_sum" },
            .{ .name = "take", .ownership = .caller, .release = "freeCodepoints", .params = &.{}, .@"return" = narrow_slice, .symbol = "zg_take" },
            .{ .name = "freeCodepoints", .params = &.{.{ .name = "values", .type = narrow_slice }}, .@"return" = .{ .void = {} }, .symbol = "zg_free_codepoints" },
            // 10. A materialized out slice is staged in Zig too.
            .{ .name = "fill", .ownership = .caller, .release = "free", .params = &.{.{ .direction = .out, .name = "output", .type = .{ .slice = .{ .@"const" = false, .element = &node } }, .written = .@"return" }}, .@"return" = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } }, .symbol = "zg_fill" },
            .{ .name = "free", .params = &.{.{ .name = "buffer", .type = .{ .slice = .{ .@"const" = true, .element = &byte } } }}, .@"return" = .{ .void = {} }, .symbol = "zg_free" },
        },
        .package = "params",
        .prefix = "zg",
        .types = &.{
            .{ .kind = .@"opaque", .name = "Hub" },
            .{ .fields = &fields, .kind = .materialized, .materialized_version = 1, .name = "Node", .zig_path = "Node" },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try semanticDocument(arena.allocator(), document, "params", "zg", &.{});
    const functions = program.functions;

    try std.testing.expectEqual(abi.ParamOwnership.retained_token, functions[0].paramOwnership(0));
    try std.testing.expectEqual(abi.ParamOwnership.transient, functions[0].paramOwnership(1));
    // The handle counts the tokens stored by its constructor and its methods.
    try std.testing.expectEqual(@as(usize, 2), functions[0].ownership.handle.retained_slots);
    try std.testing.expectEqual(abi.ParamOwnership.retained_token, functions[2].paramOwnership(0));
    try std.testing.expectEqual(abi.ParamOwnership.transient, functions[2].paramOwnership(1));
    try std.testing.expectEqual(abi.ParamOwnership.stream, functions[3].paramOwnership(0));
    try std.testing.expectEqual(abi.ParamOwnership.staged_copy, functions[4].paramOwnership(0));
    try std.testing.expectEqual(abi.ParamOwnership.staged_copy, functions[4].paramOwnership(1));
    try std.testing.expectEqual(abi.ParamOwnership.transient, functions[6].paramOwnership(0));
    try std.testing.expectEqual(abi.ParamOwnership.staged_copy, functions[7].paramOwnership(0));
    // An index past the parameters answers the same as any plain argument.
    try std.testing.expectEqual(abi.ParamOwnership.transient, functions[8].paramOwnership(3));
}
