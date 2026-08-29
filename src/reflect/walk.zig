const std = @import("std");
const semantic = @import("semantic");

pub fn reflect(
    allocator: std.mem.Allocator,
    comptime declaration: anytype,
    package_name: []const u8,
    prefix: []const u8,
) !semantic.Semantic {
    const entries = declaration.functions;
    const functions = try allocator.alloc(semantic.SemanticFn, entries.len);

    inline for (entries, 0..) |entry, function_index| {
        const info = switch (@typeInfo(@TypeOf(entry.@"fn"))) {
            .@"fn" => |info| info,
            else => @compileError("zigo function entry must contain a function"),
        };
        const params = try allocator.alloc(semantic.Parameter, info.params.len);
        inline for (info.params, 0..) |param, param_index| {
            if (param.is_generic or param.type == null) @compileError("generic parameters require an explicit specialization");
            params[param_index] = .{
                .name = try std.fmt.allocPrint(allocator, "p{d}", .{param_index}),
                .name_source = .fallback,
                .type = scalarType(param.type.?),
            };
        }
        const return_type = info.return_type orelse @compileError("generic return types require an explicit specialization");
        functions[function_index] = .{
            .name = entry.name,
            .params = params,
            .@"return" = scalarType(return_type),
            .symbol = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, entry.name }),
        };
    }

    return .{
        .functions = functions,
        .package = package_name,
        .prefix = prefix,
        .zig_version = @import("builtin").zig_version_string,
    };
}

fn scalarType(comptime T: type) semantic.TypeNode {
    return switch (@typeInfo(T)) {
        .void => .{ .void = {} },
        .bool => .{ .bool = {} },
        .int => |info| .{ .int = .{
            .bits = info.bits,
            .is_usize = T == usize or T == isize,
            .signed = info.signedness == .signed,
        } },
        .float => |info| .{ .float = .{ .bits = info.bits } },
        else => @compileError("Phase 2 reflector supports only scalar types"),
    };
}

test "scalar reflection matches the semantic JSON golden" {
    const add = struct {
        fn call(a: i32, b: i32) i32 {
            return a + b;
        }
    }.call;
    const declaration = .{ .functions = .{.{ .name = "add", .@"fn" = add }} };
    const document = try reflect(std.testing.allocator, declaration, "scalar", "zg");
    const json = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(json);
    defer {
        for (document.functions) |function| {
            for (function.params) |param| std.testing.allocator.free(param.name);
            std.testing.allocator.free(function.params);
            std.testing.allocator.free(function.symbol);
        }
        std.testing.allocator.free(document.functions);
    }
    const golden =
        \\{
        \\  "constructors": [],
        \\  "functions": [
        \\    {
        \\      "name": "add",
        \\      "ownership": "borrowed",
        \\      "params": [
        \\        {
        \\          "direction": "in",
        \\          "name": "p0",
        \\          "name_source": "fallback",
        \\          "retention": "borrowed",
        \\          "type": {
        \\            "bits": 32,
        \\            "is_usize": false,
        \\            "kind": "int",
        \\            "signed": true
        \\          }
        \\        },
        \\        {
        \\          "direction": "in",
        \\          "name": "p1",
        \\          "name_source": "fallback",
        \\          "retention": "borrowed",
        \\          "type": {
        \\            "bits": 32,
        \\            "is_usize": false,
        \\            "kind": "int",
        \\            "signed": true
        \\          }
        \\        }
        \\      ],
        \\      "return": {
        \\        "bits": 32,
        \\        "is_usize": false,
        \\        "kind": "int",
        \\        "signed": true
        \\      },
        \\      "symbol": "zg_add"
        \\    }
        \\  ],
        \\  "ir_version": 1,
        \\  "package": "scalar",
        \\  "prefix": "zg",
        \\  "types": [],
        \\  "zig_version": "0.16.0"
        \\}
        \\
    ;
    try std.testing.expectEqualStrings(golden, json);
}
