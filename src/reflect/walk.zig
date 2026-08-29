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
    var types: std.ArrayList(semantic.TypeDecl) = .empty;

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
                .type = try typeNode(allocator, param.type.?, &types),
            };
        }
        const return_type = info.return_type orelse @compileError("generic return types require an explicit specialization");
        functions[function_index] = .{
            .name = entry.name,
            .params = params,
            .@"return" = try typeNode(allocator, return_type, &types),
            .symbol = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, entry.name }),
        };
    }

    return .{
        .functions = functions,
        .package = package_name,
        .prefix = prefix,
        .types = try types.toOwnedSlice(allocator),
        .zig_version = @import("builtin").zig_version_string,
    };
}

fn typeNode(allocator: std.mem.Allocator, comptime T: type, types: *std.ArrayList(semantic.TypeDecl)) !semantic.TypeNode {
    return switch (@typeInfo(T)) {
        .void => .{ .void = {} },
        .bool => .{ .bool = {} },
        .int => |info| .{ .int = .{
            .bits = info.bits,
            .is_usize = T == usize or T == isize,
            .signed = info.signedness == .signed,
        } },
        .float => |info| .{ .float = .{ .bits = info.bits } },
        .pointer => |info| switch (info.size) {
            .slice => blk: {
                const element = try allocator.create(semantic.TypeNode);
                element.* = try typeNode(allocator, info.child, types);
                break :blk .{ .slice = .{ .@"const" = info.is_const, .element = element } };
            },
            else => @compileError("Phase 5 reflector supports only slices and scalar types"),
        },
        .error_union => |info| blk: {
            const payload = try allocator.create(semantic.TypeNode);
            payload.* = try typeNode(allocator, info.payload, types);
            const reflected_errors = @typeInfo(info.error_set).error_set;
            const names = if (reflected_errors) |errors| names: {
                const result = try allocator.alloc([]const u8, errors.len);
                inline for (errors, 0..) |entry, index| result[index] = entry.name;
                break :names result;
            } else &.{};
            break :blk .{ .error_union = .{
                .anyerror = reflected_errors == null,
                .error_set = names,
                .payload = payload,
            } };
        },
        .@"enum" => |info| blk: {
            const name = shortTypeName(@typeName(T));
            var exists = false;
            for (types.items) |declaration| {
                if (std.mem.eql(u8, declaration.name, name)) exists = true;
            }
            if (!exists) {
                const fields = try allocator.alloc(semantic.TypeField, info.fields.len);
                inline for (info.fields, 0..) |field, index| fields[index] = .{ .name = field.name, .value = @intCast(field.value) };
                const tag_type = try allocator.create(semantic.TypeNode);
                tag_type.* = try typeNode(allocator, info.tag_type, types);
                try types.append(allocator, .{
                    .exhaustive = info.is_exhaustive,
                    .fields = fields,
                    .kind = .@"enum",
                    .name = name,
                    .tag_type = tag_type.*,
                    .zig_path = @typeName(T),
                });
            }
            break :blk .{ .@"enum" = .{ .ref = name } };
        },
        else => @compileError("Phase 5 reflector supports only scalars, enums, slices, and error unions"),
    };
}

fn shortTypeName(comptime full_name: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, full_name, '.')) |index| full_name[index + 1 ..] else full_name;
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
        std.testing.allocator.free(document.types);
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
