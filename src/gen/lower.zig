const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming.zig");

pub fn semanticDocument(allocator: std.mem.Allocator, document: semantic.Semantic, package: []const u8, prefix: []const u8) !abi.Program {
    const functions = try allocator.alloc(abi.AbiFn, document.functions.len);
    for (document.functions, 0..) |*function, function_index| {
        const params = try allocator.alloc(abi.AbiParam, function.params.len);
        for (function.params, 0..) |parameter, parameter_index| {
            params[parameter_index] = .{ .name = parameter.name, .scalar = lowerScalar(parameter.type) };
        }
        const function_name = try naming.snakeAlloc(allocator, function.name);
        functions[function_index] = .{
            .symbol = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, function_name }),
            .params = params,
            .ret = lowerScalar(function.@"return"),
            .origin = function,
        };
    }
    return .{ .functions = functions, .package = package, .prefix = prefix };
}

fn lowerScalar(node: semantic.TypeNode) abi.AbiScalar {
    return switch (node) {
        .void => .void,
        .bool => .bool_u8,
        .int => |value| if (value.signed) .{ .signed_int = value.bits } else .{ .unsigned_int = value.bits },
        .float => |value| .{ .float = value.bits },
        else => unreachable,
    };
}
