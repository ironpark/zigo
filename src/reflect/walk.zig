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

    if (@hasField(@TypeOf(declaration), "types")) {
        inline for (declaration.types) |entry| {
            const T = entry.type;
            const info = @typeInfo(T);
            const type_name = if (@hasField(@TypeOf(entry), "name")) entry.name else shortTypeName(@typeName(T));
            switch (entry.repr) {
                .@"opaque" => try types.append(allocator, .{
                    .kind = .@"opaque",
                    .name = type_name,
                    .zig_path = @typeName(T),
                }),
                .value => switch (info) {
                    .@"struct" => |struct_info| try types.append(allocator, .{
                        .kind = .value_struct,
                        .layout = switch (struct_info.layout) {
                            .@"extern" => .@"extern",
                            .@"packed" => .@"packed",
                            .auto => null,
                        },
                        .name = type_name,
                        .zig_path = @typeName(T),
                    }),
                    else => @compileError("zigo value type entries must name a struct"),
                },
                else => @compileError("zigo type repr must be .opaque or .value"),
            }
        }
    }
    if (@hasField(@TypeOf(declaration), "specializations")) {
        inline for (declaration.specializations) |entry| {
            try types.append(allocator, .{
                .kind = .@"opaque",
                .name = entry.name,
                .zig_path = @typeName(entry.type),
            });
        }
    }

    inline for (entries, 0..) |entry, function_index| {
        const info = switch (@typeInfo(@TypeOf(entry.@"fn"))) {
            .@"fn" => |info| info,
            else => @compileError("zigo function entry must contain a function"),
        };
        const receiver = comptime receiverName(info, declaration);
        const first_param: usize = if (receiver != null) 1 else 0;
        const params = try allocator.alloc(semantic.Parameter, comptime concreteParamCount(info, first_param));
        inline for (info.params, 0..) |param, param_index| {
            if (param_index < first_param) continue;
            if (info.is_generic) continue;
            if (param.is_generic or param.type == null) continue;
            const output_index = comptime concreteParamIndex(info, first_param, param_index);
            const has_sidecar = @hasField(@TypeOf(entry), "params");
            const parameter_name = if (has_sidecar)
                entry.params[output_index]
            else
                try std.fmt.allocPrint(allocator, "p{d}", .{output_index});
            var reflected: semantic.Parameter = .{
                .name = parameter_name,
                .name_source = if (has_sidecar) .sidecar else .fallback,
                .type = try typeNode(allocator, param.type.?, &types),
            };
            if (has_sidecar and @hasField(@TypeOf(entry), "param_meta")) {
                const meta = entry.param_meta;
                if (@hasField(@TypeOf(meta), parameter_name)) {
                    const value = @field(meta, parameter_name);
                    if (@hasField(@TypeOf(value), "direction")) reflected.direction = value.direction;
                    if (@hasField(@TypeOf(value), "retention")) reflected.retention = value.retention;
                    if (@hasField(@TypeOf(value), "semantic")) reflected.semantic = value.semantic;
                }
            }
            params[output_index] = reflected;
        }
        var reflected_function: semantic.SemanticFn = .{
            .has_comptime_params = if (info.is_generic) true else null,
            .name = entry.name,
            .params = params,
            .receiver = receiver,
            .@"return" = if (info.return_type) |return_type| try typeNode(allocator, return_type, &types) else .{ .void = {} },
            .symbol = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, entry.name }),
        };
        if (@hasField(@TypeOf(entry), "semantic")) reflected_function.return_semantic = entry.semantic;
        if (@hasField(@TypeOf(entry), "returns")) reflected_function.ownership = entry.returns;
        functions[function_index] = reflected_function;
    }

    var constructors: std.ArrayList(semantic.Constructor) = .empty;
    for (functions) |*function| {
        if (!isConstructorName(function.name)) continue;
        const type_name = returnedOpaqueName(function.@"return") orelse continue;
        for (functions) |destructor| {
            if (destructor.receiver == null or !std.mem.eql(u8, destructor.receiver.?, type_name)) continue;
            if (!isDestructorName(destructor.name)) continue;
            try constructors.append(allocator, .{
                .deinit = destructor.name,
                .init = function.name,
                .type = type_name,
            });
            function.namespace = type_name;
            function.ownership = .caller;
            break;
        }
    }

    return .{
        .constructors = try constructors.toOwnedSlice(allocator),
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
            .one => blk: {
                if (@typeInfo(info.child) == .@"fn") {
                    const function_info = @typeInfo(info.child).@"fn";
                    const callback_params = try allocator.alloc(semantic.TypeNode, function_info.params.len);
                    inline for (function_info.params, 0..) |parameter, index| {
                        const parameter_type = parameter.type orelse return error.GenericCallback;
                        callback_params[index] = try typeNode(allocator, parameter_type, types);
                    }
                    const callback_return = try allocator.create(semantic.TypeNode);
                    callback_return.* = try typeNode(allocator, function_info.return_type orelse return error.GenericCallback, types);
                    break :blk .{ .callback = .{
                        .c_callconv = std.meta.eql(function_info.calling_convention, std.builtin.CallingConvention.c),
                        .has_userdata = function_info.params.len != 0 and
                            function_info.params[function_info.params.len - 1].type == usize,
                        .params = callback_params,
                        .@"return" = callback_return,
                    } };
                }
                const name = opaqueNameForPath(types.items, @typeName(info.child)) orelse return error.MissingOpaqueType;
                break :blk .{ .opaque_ptr = .{
                    .@"const" = info.is_const,
                    .nullable = false,
                    .ref = name,
                } };
            },
            else => @compileError("zigo supports slices and pointers to declared opaque types"),
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
        .@"struct" => |info| blk: {
            const name = shortTypeName(@typeName(T));
            var exists = false;
            for (types.items) |declaration| {
                if (std.mem.eql(u8, declaration.zig_path orelse "", @typeName(T))) {
                    exists = true;
                    break;
                }
            }
            if (!exists) try types.append(allocator, .{
                .kind = .value_struct,
                .layout = switch (info.layout) {
                    .@"extern" => .@"extern",
                    .@"packed" => .@"packed",
                    .auto => null,
                },
                .name = name,
                .zig_path = @typeName(T),
            });
            break :blk .{ .value_struct = .{ .ref = name } };
        },
        .@"union" => blk: {
            const name = shortTypeName(@typeName(T));
            try types.append(allocator, .{
                .kind = .tagged_union,
                .name = name,
                .zig_path = @typeName(T),
            });
            break :blk .{ .value_struct = .{ .ref = name } };
        },
        else => @compileError("zigo supports scalars, enums, slices, opaque pointers, structs, and error unions"),
    };
}

fn concreteParamCount(comptime info: std.builtin.Type.Fn, comptime first_param: usize) usize {
    if (info.is_generic) return 0;
    var count: usize = 0;
    inline for (info.params, 0..) |parameter, index| {
        if (index >= first_param and !parameter.is_generic and parameter.type != null) count += 1;
    }
    return count;
}

fn concreteParamIndex(comptime info: std.builtin.Type.Fn, comptime first_param: usize, comptime target_index: usize) usize {
    var count: usize = 0;
    inline for (info.params, 0..) |parameter, index| {
        if (index == target_index) return count;
        if (index >= first_param and !parameter.is_generic and parameter.type != null) count += 1;
    }
    unreachable;
}

fn receiverName(comptime info: std.builtin.Type.Fn, comptime declaration: anytype) ?[]const u8 {
    if (info.params.len == 0) return null;
    const T = info.params[0].type orelse return null;
    const pointer = switch (@typeInfo(T)) {
        .pointer => |pointer| pointer,
        else => return null,
    };
    if (pointer.size != .one) return null;
    if (@hasField(@TypeOf(declaration), "types")) {
        inline for (declaration.types) |entry| {
            if (entry.repr == .@"opaque" and entry.type == pointer.child) {
                return if (@hasField(@TypeOf(entry), "name")) entry.name else shortTypeName(@typeName(entry.type));
            }
        }
    }
    if (@hasField(@TypeOf(declaration), "specializations")) {
        inline for (declaration.specializations) |entry| {
            if (entry.type == pointer.child) return entry.name;
        }
    }
    return null;
}

fn opaqueNameForPath(types: []const semantic.TypeDecl, path: []const u8) ?[]const u8 {
    for (types) |declaration| {
        if (declaration.kind == .@"opaque" and
            (std.mem.eql(u8, declaration.zig_path orelse "", path) or
                std.mem.eql(u8, declaration.name, shortTypeName(path)))) return declaration.name;
    }
    return null;
}

fn returnedOpaqueName(node: semantic.TypeNode) ?[]const u8 {
    return switch (node) {
        .opaque_ptr => |pointer| pointer.ref,
        .error_union => |result| returnedOpaqueName(result.payload.*),
        else => null,
    };
}

fn isConstructorName(name: []const u8) bool {
    return std.mem.eql(u8, name, "init") or std.mem.eql(u8, name, "create") or
        std.mem.eql(u8, name, "new") or std.mem.eql(u8, name, "open");
}

fn isDestructorName(name: []const u8) bool {
    return std.mem.eql(u8, name, "deinit") or std.mem.eql(u8, name, "destroy") or
        std.mem.eql(u8, name, "close");
}

fn shortTypeName(full_name: []const u8) []const u8 {
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

test "reflection preserves invalid declarations for generator diagnostics" {
    const Fixture = struct {
        const Value = union(enum) { integer: i32, flag: bool };

        fn generic(comptime T: type, value: T) T {
            return value;
        }

        fn callback(value: *const fn (i32) void) void {
            _ = value;
        }

        fn tagged(value: Value) void {
            _ = value;
        }
    };
    const declaration = .{ .functions = .{
        .{ .name = "generic", .@"fn" = Fixture.generic },
        .{ .name = "callback", .@"fn" = Fixture.callback },
        .{ .name = "tagged", .@"fn" = Fixture.tagged },
    } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), declaration, "invalid", "zg");
    try std.testing.expectEqual(true, document.functions[0].has_comptime_params.?);
    try std.testing.expect(!document.functions[1].params[0].type.callback.c_callconv);
    try std.testing.expectEqual(semantic.TypeKind.tagged_union, document.types[0].kind);
}

test "named generic specializations become distinct opaque types" {
    const Generic = struct {
        fn Buffer(comptime T: type) type {
            return struct { value: T };
        }
    };
    const FloatBuffer = Generic.Buffer(f32);
    const IntBuffer = Generic.Buffer(i32);
    const declaration = .{
        .specializations = .{
            .{ .name = "FloatBuffer", .type = FloatBuffer },
            .{ .name = "IntBuffer", .type = IntBuffer },
        },
        .functions = .{},
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), declaration, "generic", "zg");
    try std.testing.expectEqual(@as(usize, 2), document.types.len);
    try std.testing.expectEqualStrings("FloatBuffer", document.types[0].name);
    try std.testing.expectEqualStrings("IntBuffer", document.types[1].name);
}
