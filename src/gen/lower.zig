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
                        callback_params[callback_index] = try lowerValue(allocator, document, callback_parameter);
                    const callback_return = try allocator.create(abi.AbiScalar);
                    callback_return.* = try lowerValue(allocator, document, callback.@"return".*);
                    try params.append(allocator, .{
                        .name = parameter.name,
                        .scalar = .{ .callback = .{ .params = callback_params, .ret = callback_return } },
                        .source_index = parameter_index,
                    });
                },
                .slice => |slice| {
                    const child = try allocator.create(abi.AbiScalar);
                    child.* = try lowerValue(allocator, document, slice.element.*);
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
                else => try params.append(allocator, .{
                    .name = parameter.name,
                    .scalar = try lowerValue(allocator, document, parameter.type),
                    .source_index = parameter_index,
                }),
            }
        }

        var function_errors: []const abi.ErrorCode = &.{};
        const return_scalar = switch (function.@"return") {
            .slice => |slice| result: {
                const element = try allocator.create(abi.AbiScalar);
                element.* = try lowerValue(allocator, document, slice.element.*);
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
                    payload.* = try lowerValue(allocator, document, error_union.payload.*);
                    try params.append(allocator, .{
                        .name = "out_result",
                        .role = .payload_out,
                        .scalar = .{ .pointer = .{ .child = payload, .is_const = false } },
                        .source_index = function.params.len,
                    });
                }
                break :result abi.AbiScalar{ .signed_int = 32 };
            },
            else => try lowerValue(allocator, document, function.@"return"),
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
    return .{
        .backend = backend,
        .callback_convention = if (backend == .purego) .function_pointer_userdata_v1 else .fixed_go_export,
        .constructors = document.constructors,
        .error_codes = error_codes,
        .functions = functions,
        .package = package,
        .prefix = prefix,
        .projections = projections,
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
        tag_output.* = try lowerValue(allocator, document, declaration.tag_type.?);
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
                element.* = try lowerValue(allocator, document, payload.slice.element.*);
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
                lowered.* = try lowerValue(allocator, document, payload);
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

fn projectionReceiver(allocator: std.mem.Allocator, owner: []const u8) !abi.AbiParam {
    const child = try allocator.create(abi.AbiScalar);
    child.* = .{ .@"opaque" = owner };
    return .{
        .name = "self",
        .role = .receiver,
        .scalar = .{ .pointer = .{ .child = child, .is_const = true } },
    };
}

fn lowerValue(allocator: std.mem.Allocator, document: semantic.Semantic, node: semantic.TypeNode) !abi.AbiScalar {
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
        .@"enum" => |value| lowerValue(allocator, document, enumDeclaration(document, value.ref).tag_type.?),
        .opaque_ptr => |value| blk: {
            const child = try allocator.create(abi.AbiScalar);
            child.* = .{ .@"opaque" = value.ref };
            break :blk .{ .pointer = .{ .child = child, .is_const = value.@"const" } };
        },
        else => unreachable,
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
