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
        for (function.params, 0..) |parameter, parameter_index| {
            switch (parameter.type) {
                .slice => |slice| {
                    const child = try allocator.create(abi.AbiScalar);
                    child.* = lowerValue(document, slice.element.*);
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
                    .scalar = lowerValue(document, parameter.type),
                    .source_index = parameter_index,
                }),
            }
        }

        var function_errors: []const abi.ErrorCode = &.{};
        const return_scalar = switch (function.@"return") {
            .error_union => |error_union| result: {
                function_errors = try codesFor(allocator, error_union.error_set, error_codes);
                if (error_union.payload.* != .void) {
                    const payload = try allocator.create(abi.AbiScalar);
                    payload.* = lowerValue(document, error_union.payload.*);
                    try params.append(allocator, .{
                        .name = "out_result",
                        .role = .payload_out,
                        .scalar = .{ .pointer = .{ .child = payload, .is_const = false } },
                        .source_index = function.params.len,
                    });
                }
                break :result abi.AbiScalar{ .signed_int = 32 };
            },
            else => lowerValue(document, function.@"return"),
        };
        const function_name = try naming.snakeAlloc(allocator, function.name);
        functions[function_index] = .{
            .symbol = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, function_name }),
            .params = try params.toOwnedSlice(allocator),
            .ret = return_scalar,
            .errors = function_errors,
            .origin = function,
        };
    }
    return .{
        .error_codes = error_codes,
        .functions = functions,
        .package = package,
        .prefix = prefix,
        .types = document.types,
    };
}

fn lowerValue(document: semantic.Semantic, node: semantic.TypeNode) abi.AbiScalar {
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
        .@"enum" => |value| lowerValue(document, enumDeclaration(document, value.ref).tag_type.?),
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
