const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming.zig");

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
    document: semantic.Semantic,
    package: []const u8,
    prefix: []const u8,
    error_codes: []const abi.ErrorCode,
    backend: abi.Program.Backend,
) !abi.Program {
    const functions = try allocator.alloc(abi.AbiFn, document.functions.len);
    for (document.functions, 0..) |*function, function_index| {
        var params: std.ArrayList(abi.AbiParam) = .empty;
        if (function.receiver) |receiver| {
            const child = try allocator.create(abi.AbiScalar);
            child.* = .{ .@"opaque" = receiver };
            try params.append(allocator, .{
                .name = "self",
                .role = .receiver,
                .scalar = .{ .pointer = .{ .child = child, .is_const = false } },
            });
        }
        for (function.params, 0..) |parameter, parameter_index| {
            switch (parameter.type) {
                .callback => |callback| {
                    if (backend == .cgo) continue;
                    const callback_params = try allocator.alloc(abi.AbiScalar, callback.params.len);
                    for (callback.params, 0..) |callback_parameter, callback_index|
                        callback_params[callback_index] = try lowerValue(allocator, document, prefix, callback_parameter);
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
                    if (parameter.direction == .out) {
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
                .value_struct => {
                    const child = try allocator.create(abi.AbiScalar);
                    child.* = try lowerValue(allocator, document, prefix, parameter.type);
                    try params.append(allocator, .{
                        .name = parameter.name,
                        .role = .struct_in,
                        .scalar = .{ .pointer = .{ .child = child, .is_const = true } },
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
        const return_scalar = switch (function.@"return") {
            .slice => |slice| result: {
                const element = try allocator.create(abi.AbiScalar);
                element.* = try lowerValue(allocator, document, prefix, slice.element.*);
                const many = try allocator.create(abi.AbiScalar);
                many.* = .{ .pointer = .{ .child = element, .is_const = slice.@"const", .is_many = true } };
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
                break :result abi.AbiScalar.void;
            },
            .error_union => |error_union| result: {
                function_errors = try codesFor(allocator, error_union.error_set, error_codes);
                if (error_union.payload.* != .void) {
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
            else => try lowerValue(allocator, document, prefix, function.@"return"),
        };
        const function_name = try naming.snakeAlloc(allocator, function.name);
        defer allocator.free(function_name);
        const symbol_owner = function.receiver orelse function.namespace;
        const legacy_symbol = if (symbol_owner) |owner| blk: {
            const receiver_name = try naming.snakeAlloc(allocator, owner);
            defer allocator.free(receiver_name);
            break :blk try std.fmt.allocPrint(allocator, "{s}_{s}_{s}", .{ prefix, receiver_name, function_name });
        } else try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, function_name });
        const symbol = if (backend == .purego and functionHasCallback(function.*))
            try std.fmt.allocPrint(allocator, "{s}_purego_v1", .{legacy_symbol})
        else
            legacy_symbol;
        functions[function_index] = .{
            .symbol = symbol,
            .params = try params.toOwnedSlice(allocator),
            .ret = return_scalar,
            .errors = function_errors,
            .origin = function,
        };
    }
    const projections = try lowerTaggedUnionProjections(allocator, document, prefix);
    const snapshots = try lowerTaggedUnionSnapshots(allocator, document, prefix);
    const structs = try lowerValueStructs(allocator, document, prefix);
    return .{
        .backend = backend,
        .callback_convention = if (backend == .purego) .function_pointer_userdata_v1 else .fixed_go_export,
        .constructors = document.constructors,
        .error_codes = error_codes,
        .functions = functions,
        .package = package,
        .prefix = prefix,
        .projections = projections,
        .snapshots = snapshots,
        .structs = structs,
        .types = document.types,
    };
}

fn functionHasCallback(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| if (parameter.type == .callback) return true;
    return false;
}

fn lowerTaggedUnionProjections(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) ![]const abi.AbiProjection {
    var projections: std.ArrayList(abi.AbiProjection) = .empty;
    for (document.types) |*declaration| {
        if (declaration.kind != .tagged_union) continue;
        const tag_params = try allocator.alloc(abi.AbiParam, 2);
        tag_params[0] = try projectionReceiver(allocator, declaration.name);
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
            try params.append(allocator, try projectionReceiver(allocator, declaration.name));
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
        if (declaration.kind != .tagged_union or declaration.unionRepr() != .value_snapshot) continue;
        const type_name = try snapshotTypeNameAlloc(allocator, prefix, declaration.name);
        const layout = try snapshotLayout(allocator, document, prefix, declaration.*);

        const receiver = try projectionReceiver(allocator, declaration.name);
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
fn lowerValueStructs(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) ![]const abi.AbiStruct {
    var structs: std.ArrayList(abi.AbiStruct) = .empty;
    for (document.types) |*declaration| {
        if (declaration.kind != .value_struct or declaration.layout != .@"extern") continue;
        if (!valueStructUsed(document, declaration.name)) continue;
        const fields = try allocator.alloc(abi.AbiStruct.Field, declaration.fields.len);
        var offset: usize = 0;
        var alignment: usize = 1;
        for (declaration.fields, 0..) |field, index| {
            const node = field.type.?;
            const scalar = try lowerValue(allocator, document, prefix, node);
            const bytes = try memberBytes(document, prefix, node, scalar);
            const member_alignment = try memberAlignment(document, prefix, node, scalar);
            offset += padding(offset, member_alignment);
            fields[index] = .{
                .name = field.name,
                .scalar = scalar,
                .node = node,
                .offset = offset,
                .bytes = bytes,
            };
            offset += bytes;
            alignment = @max(alignment, member_alignment);
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
        .error_union => |value| mentionsValueStruct(document, value.payload.*, name),
        else => false,
    };
}

fn memberBytes(document: semantic.Semantic, prefix: []const u8, node: semantic.TypeNode, scalar: abi.AbiScalar) !usize {
    if (node != .value_struct) return scalarBytes(scalar);
    const nested = valueStructDeclaration(document, node.value_struct.ref);
    var offset: usize = 0;
    var alignment: usize = 1;
    for (nested.fields) |field| {
        const child = field.type.?;
        const child_scalar = try lowerValueNoAlloc(document, prefix, child);
        const bytes = try memberBytes(document, prefix, child, child_scalar);
        const child_alignment = try memberAlignment(document, prefix, child, child_scalar);
        offset += padding(offset, child_alignment);
        offset += bytes;
        alignment = @max(alignment, child_alignment);
    }
    return offset + padding(offset, alignment);
}

fn memberAlignment(document: semantic.Semantic, prefix: []const u8, node: semantic.TypeNode, scalar: abi.AbiScalar) !usize {
    if (node != .value_struct) return scalarBytes(scalar);
    const nested = valueStructDeclaration(document, node.value_struct.ref);
    var alignment: usize = 1;
    for (nested.fields) |field| {
        const child = field.type.?;
        const child_scalar = try lowerValueNoAlloc(document, prefix, child);
        alignment = @max(alignment, try memberAlignment(document, prefix, child, child_scalar));
    }
    return alignment;
}

/// Layout only needs the scalar's width, and a nested struct never consults
/// the returned name, so the sizing walk avoids allocating C names.
fn lowerValueNoAlloc(document: semantic.Semantic, prefix: []const u8, node: semantic.TypeNode) !abi.AbiScalar {
    return switch (node) {
        .value_struct => |value| .{ .value_struct = .{ .name = value.ref, .c_name = value.ref } },
        .@"enum" => |value| lowerValueNoAlloc(document, prefix, enumDeclaration(document, value.ref).tag_type.?),
        .bool => .bool_u8,
        .int => |value| if (value.is_usize)
            (if (value.signed) .isize else .usize)
        else if (value.signed)
            .{ .signed_int = value.bits }
        else
            .{ .unsigned_int = value.bits },
        .float => |value| .{ .float = value.bits },
        else => error.UnsupportedType,
    };
}

fn valueStructDeclaration(document: semantic.Semantic, name: []const u8) semantic.TypeDecl {
    for (document.types) |declaration| if (std.mem.eql(u8, declaration.name, name)) return declaration;
    unreachable;
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

fn projectionReceiver(allocator: std.mem.Allocator, owner: []const u8) !abi.AbiParam {
    const child = try allocator.create(abi.AbiScalar);
    child.* = .{ .@"opaque" = owner };
    return .{
        .name = "self",
        .role = .receiver,
        .scalar = .{ .pointer = .{ .child = child, .is_const = true } },
    };
}

fn lowerValue(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8, node: semantic.TypeNode) !abi.AbiScalar {
    return switch (node) {
        .void => .void,
        .bool => .bool_u8,
        .int => |value| if (value.is_usize)
            (if (value.signed) .isize else .usize)
        else if (value.signed)
            .{ .signed_int = value.bits }
        else
            .{ .unsigned_int = value.bits },
        .float => |value| .{ .float = value.bits },
        .@"enum" => |value| lowerValue(allocator, document, prefix, enumDeclaration(document, value.ref).tag_type.?),
        .opaque_ptr => |value| blk: {
            const child = try allocator.create(abi.AbiScalar);
            child.* = .{ .@"opaque" = value.ref };
            break :blk .{ .pointer = .{ .child = child, .is_const = value.@"const" } };
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

fn enumDeclaration(document: semantic.Semantic, name: []const u8) semantic.TypeDecl {
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
    try std.testing.expectEqualStrings("Value", tag.params[0].scalar.pointer.child.@"opaque");
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
    try std.testing.expectEqualStrings("Child", child_pointer.child.@"opaque");
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
                .union_repr = .value_snapshot,
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

    // The mirror keeps the user's field order and the C compiler's offsets.
    try std.testing.expectEqual(@as(usize, 2), program.structs.len);
    const config = program.structs[0];
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

    const point = program.structs[1];
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
