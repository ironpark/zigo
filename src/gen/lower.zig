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
                .callback => continue,
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
        const symbol = if (symbol_owner) |owner| blk: {
            const receiver_name = try naming.snakeAlloc(allocator, owner);
            defer allocator.free(receiver_name);
            break :blk try std.fmt.allocPrint(allocator, "{s}_{s}_{s}", .{ prefix, receiver_name, function_name });
        } else try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, function_name });
        functions[function_index] = .{
            .symbol = symbol,
            .params = try params.toOwnedSlice(allocator),
            .ret = return_scalar,
            .errors = function_errors,
            .origin = function,
        };
    }
    return .{
        .constructors = document.constructors,
        .error_codes = error_codes,
        .functions = functions,
        .package = package,
        .prefix = prefix,
        .types = document.types,
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
