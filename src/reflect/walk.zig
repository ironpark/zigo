const std = @import("std");
const semantic = @import("semantic");

pub fn reflect(
    allocator: std.mem.Allocator,
    comptime declaration: anytype,
    package_name: []const u8,
    prefix: []const u8,
) !semantic.Semantic {
    // Reflection deliberately unrolls binding and parameter metadata so invalid
    // declarations fail at compile time. Broad APIs can legitimately exceed
    // Zig's default quota of 1,000 branches while doing that work.
    @setEvalBranchQuota(100_000);
    if (!@hasField(@TypeOf(declaration), "functions") and !comptime discoveryEnabled(declaration)) {
        @compileError("zigo declarations require `.functions` or opt-in `.discover = .public`");
    }
    comptime validateSelectors(declaration);

    var functions: std.ArrayList(semantic.SemanticFn) = .empty;
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
                    .@"struct" => try appendValueStruct(allocator, &types, T, type_name),
                    else => @compileError("zigo value type entries must name a struct"),
                },
                .tagged_union, .tagged_union_value => switch (info) {
                    .@"union" => |union_info| {
                        if (union_info.tag_type == null) @compileError("zigo tagged_union type entries must name a tagged union");
                        try appendTaggedUnion(allocator, &types, T, type_name, if (entry.repr == .tagged_union_value) .value_snapshot else .projection);
                    },
                    else => @compileError("zigo tagged_union type entries must name a tagged union"),
                },
                else => @compileError("zigo type repr must be .opaque, .value, .tagged_union, or .tagged_union_value"),
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

    if (@hasField(@TypeOf(declaration), "functions")) {
        inline for (declaration.functions) |entry| {
            try appendFunction(allocator, &functions, &types, declaration, prefix, entry.name, entry.@"fn", entry, null);
        }
    }
    if (comptime discoveryEnabled(declaration)) {
        if (@hasField(@TypeOf(declaration), "types")) {
            inline for (declaration.types) |entry| {
                const owner = comptime if (@hasField(@TypeOf(entry), "name")) entry.name else shortTypeName(@typeName(entry.type));
                try discoverContainer(allocator, &functions, &types, declaration, prefix, entry.type, owner);
            }
        }
        if (@hasField(@TypeOf(declaration), "specializations")) {
            inline for (declaration.specializations) |entry| {
                try discoverContainer(allocator, &functions, &types, declaration, prefix, entry.type, entry.name);
            }
        }
        try discoverContainer(allocator, &functions, &types, declaration, prefix, declaration.root, null);
    }

    var constructors: std.ArrayList(semantic.Constructor) = .empty;
    for (functions.items) |*function| {
        if (!isConstructorName(function.name)) continue;
        const type_name = returnedOpaqueName(function.@"return") orelse continue;
        for (functions.items) |destructor| {
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
        .functions = try functions.toOwnedSlice(allocator),
        .package = package_name,
        .prefix = prefix,
        .types = try types.toOwnedSlice(allocator),
        .zig_version = @import("builtin").zig_version_string,
    };
}

fn appendFunction(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(semantic.SemanticFn),
    types: *std.ArrayList(semantic.TypeDecl),
    comptime declaration: anytype,
    prefix: []const u8,
    comptime source_name: []const u8,
    comptime function_value: anytype,
    comptime metadata: anytype,
    comptime discovered_owner: ?[]const u8,
) !void {
    const info = switch (@typeInfo(@TypeOf(function_value))) {
        .@"fn" => |info| info,
        else => @compileError("zigo function entry must contain a function"),
    };
    const function_name = if (@hasField(@TypeOf(metadata), "name")) metadata.name else source_name;
    const receiver = comptime receiverName(info, declaration);
    const first_param: usize = if (receiver != null) 1 else 0;
    const params = try allocator.alloc(semantic.Parameter, comptime concreteParamCount(info, first_param));
    inline for (info.params, 0..) |param, param_index| {
        if (param_index < first_param) continue;
        if (info.is_generic) continue;
        if (param.is_generic or param.type == null) continue;
        const output_index = comptime concreteParamIndex(info, first_param, param_index);
        const has_sidecar = @hasField(@TypeOf(metadata), "params");
        const parameter_name = if (has_sidecar)
            metadata.params[output_index]
        else
            try std.fmt.allocPrint(allocator, "p{d}", .{output_index});
        var reflected: semantic.Parameter = .{
            .name = parameter_name,
            .name_source = if (has_sidecar) .sidecar else .fallback,
            .type = try typeNode(allocator, param.type.?, types),
        };
        if (has_sidecar and @hasField(@TypeOf(metadata), "param_meta")) {
            const meta = metadata.param_meta;
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
        .name = function_name,
        .namespace = if (receiver == null) discovered_owner else null,
        .params = params,
        .receiver = receiver,
        .@"return" = if (info.return_type) |return_type| try typeNode(allocator, return_type, types) else .{ .void = {} },
        .symbol = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, function_name }),
    };
    if (@hasField(@TypeOf(metadata), "semantic")) reflected_function.return_semantic = metadata.semantic;
    if (@hasField(@TypeOf(metadata), "returns")) reflected_function.ownership = metadata.returns;
    try functions.append(allocator, reflected_function);
}

fn discoverContainer(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(semantic.SemanticFn),
    types: *std.ArrayList(semantic.TypeDecl),
    comptime declaration: anytype,
    prefix: []const u8,
    comptime Container: type,
    comptime owner: ?[]const u8,
) !void {
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@typeInfo(@TypeOf(value)) != .@"fn") continue;
        const path = comptime declarationPath(owner, candidate.name);
        if (comptime selectorContains(declaration, "exclude", path)) continue;
        comptime var overridden = false;
        if (@hasField(@TypeOf(declaration), "overrides")) {
            inline for (declaration.overrides) |override| {
                if (comptime std.mem.eql(u8, override.path, path)) {
                    overridden = true;
                    try appendFunction(allocator, functions, types, declaration, prefix, candidate.name, value, override, owner);
                }
            }
        }
        if (!overridden) try appendFunction(allocator, functions, types, declaration, prefix, candidate.name, value, .{}, owner);
    }
}

fn discoveryEnabled(comptime declaration: anytype) bool {
    if (!@hasField(@TypeOf(declaration), "discover")) return false;
    if (declaration.discover != .public) @compileError("zigo `.discover` must be `.public`");
    if (!@hasField(@TypeOf(declaration), "root")) @compileError("zigo `.discover = .public` requires `.root`");
    if (@TypeOf(declaration.root) != type) @compileError("zigo `.root` must be a module or container type");
    return true;
}

fn validateSelectors(comptime declaration: anytype) void {
    if (!discoveryEnabled(declaration)) {
        if (@hasField(@TypeOf(declaration), "overrides") or @hasField(@TypeOf(declaration), "exclude")) {
            @compileError("zigo `.overrides` and `.exclude` require `.discover = .public`");
        }
        return;
    }
    if (@hasField(@TypeOf(declaration), "overrides")) {
        inline for (declaration.overrides, 0..) |override, index| {
            if (!@hasField(@TypeOf(override), "path")) @compileError("zigo override entries require `.path`");
            if (!discoveredPathExists(declaration, override.path)) {
                @compileError("zigo override path does not name a discovered public function: " ++ override.path);
            }
            inline for (declaration.overrides, 0..) |previous, previous_index| {
                if (previous_index < index and std.mem.eql(u8, previous.path, override.path)) @compileError("duplicate zigo override path: " ++ override.path);
            }
            if (selectorContains(declaration, "exclude", override.path)) {
                @compileError("zigo path cannot be both overridden and excluded: " ++ override.path);
            }
        }
    }
    if (@hasField(@TypeOf(declaration), "exclude")) {
        inline for (declaration.exclude, 0..) |path, index| {
            if (!discoveredPathExists(declaration, path)) {
                @compileError("zigo exclusion path does not name a discovered public function: " ++ path);
            }
            inline for (declaration.exclude, 0..) |previous, previous_index| {
                if (previous_index < index and std.mem.eql(u8, previous, path)) @compileError("duplicate zigo exclusion path: " ++ path);
            }
        }
    }
}

fn discoveredPathExists(comptime declaration: anytype, comptime wanted: []const u8) bool {
    if (@hasField(@TypeOf(declaration), "types")) {
        inline for (declaration.types) |entry| {
            const owner = if (@hasField(@TypeOf(entry), "name")) entry.name else shortTypeName(@typeName(entry.type));
            if (containerHasPath(entry.type, owner, wanted)) return true;
        }
    }
    if (@hasField(@TypeOf(declaration), "specializations")) {
        inline for (declaration.specializations) |entry| {
            if (containerHasPath(entry.type, entry.name, wanted)) return true;
        }
    }
    return containerHasPath(declaration.root, null, wanted);
}

fn containerHasPath(comptime Container: type, comptime owner: ?[]const u8, comptime wanted: []const u8) bool {
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        if (@typeInfo(@TypeOf(@field(Container, candidate.name))) != .@"fn") continue;
        if (std.mem.eql(u8, declarationPath(owner, candidate.name), wanted)) return true;
    }
    return false;
}

fn selectorContains(comptime declaration: anytype, comptime field_name: []const u8, comptime path: []const u8) bool {
    if (!@hasField(@TypeOf(declaration), field_name)) return false;
    inline for (@field(declaration, field_name)) |candidate| {
        if (std.mem.eql(u8, candidate, path)) return true;
    }
    return false;
}

fn declarationPath(comptime owner: ?[]const u8, comptime name: []const u8) []const u8 {
    return if (owner) |value| value ++ "." ++ name else "root." ++ name;
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
        .@"struct" => blk: {
            const name = shortTypeName(@typeName(T));
            var exists = false;
            for (types.items) |declaration| {
                if (std.mem.eql(u8, declaration.zig_path orelse "", @typeName(T))) {
                    exists = true;
                    break;
                }
            }
            if (!exists) try appendValueStruct(allocator, types, T, name);
            break :blk .{ .value_struct = .{ .ref = name } };
        },
        .@"union" => blk: {
            const name = shortTypeName(@typeName(T));
            for (types.items) |declaration| {
                if (declaration.kind == .tagged_union and std.mem.eql(u8, declaration.zig_path orelse "", @typeName(T))) {
                    break :blk .{ .value_struct = .{ .ref = declaration.name } };
                }
            }
            if (@typeInfo(T).@"union".tag_type == null) @compileError("zigo cannot reflect an untagged union");
            try appendTaggedUnion(allocator, types, T, name, .projection);
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
            if (isHandleRepr(entry.repr) and entry.type == pointer.child) {
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
        if ((declaration.kind == .@"opaque" or declaration.kind == .tagged_union) and
            (std.mem.eql(u8, declaration.zig_path orelse "", path) or
                std.mem.eql(u8, declaration.name, shortTypeName(path)))) return declaration.name;
    }
    return null;
}

fn isHandleRepr(comptime repr: anytype) bool {
    return repr == .@"opaque" or repr == .tagged_union or repr == .tagged_union_value;
}

/// A value struct carries its field types into the IR. Validation needs them
/// to decide whether the struct can cross the C ABI, and lowering needs them
/// to mirror the struct in the C header.
fn appendValueStruct(
    allocator: std.mem.Allocator,
    types: *std.ArrayList(semantic.TypeDecl),
    comptime T: type,
    name: []const u8,
) !void {
    const info = @typeInfo(T).@"struct";
    const index = types.items.len;
    try types.append(allocator, .{
        .kind = .value_struct,
        .layout = switch (info.layout) {
            .@"extern" => .@"extern",
            .@"packed" => .@"packed",
            .auto => null,
        },
        .name = name,
        .zig_path = @typeName(T),
    });
    // Reflecting a field can append further types, so the declaration is
    // updated by index rather than through a held pointer.
    const fields = try allocator.alloc(semantic.TypeField, info.fields.len);
    inline for (info.fields, 0..) |field, field_index| {
        fields[field_index] = .{
            .name = field.name,
            .type = try typeNode(allocator, field.type, types),
        };
    }
    types.items[index].fields = fields;
}

fn appendTaggedUnion(
    allocator: std.mem.Allocator,
    types: *std.ArrayList(semantic.TypeDecl),
    comptime T: type,
    name: []const u8,
    repr: semantic.UnionRepr,
) !void {
    const info = @typeInfo(T).@"union";
    const Tag = info.tag_type orelse @compileError("zigo cannot reflect an untagged union");
    const tag_info = @typeInfo(Tag).@"enum";
    const tag_name = try std.fmt.allocPrint(allocator, "{s}Tag", .{name});

    const union_index = types.items.len;
    try types.append(allocator, .{
        .kind = .tagged_union,
        .name = name,
        // The projection default stays absent from semantic.json so opting out
        // of the snapshot leaves existing documents byte-identical.
        .union_repr = if (repr == .projection) null else repr,
        .zig_path = @typeName(T),
    });

    const fields = try allocator.alloc(semantic.TypeField, info.fields.len);
    inline for (info.fields, 0..) |field, index| {
        fields[index] = .{
            .name = field.name,
            .type = try typeNode(allocator, field.type, types),
            .value = @intCast(@intFromEnum(@field(Tag, field.name))),
        };
    }
    types.items[union_index].fields = fields;
    types.items[union_index].tag_type = .{ .@"enum" = .{ .ref = tag_name } };

    const tag_fields = try allocator.alloc(semantic.TypeField, tag_info.fields.len);
    inline for (tag_info.fields, 0..) |field, index| {
        tag_fields[index] = .{ .name = field.name, .value = @intCast(field.value) };
    }
    const integer_tag = try typeNode(allocator, tag_info.tag_type, types);
    try types.append(allocator, .{
        .exhaustive = tag_info.is_exhaustive,
        .fields = tag_fields,
        .kind = .@"enum",
        .name = tag_name,
        .tag_type = integer_tag,
        .zig_path = @typeName(Tag),
    });
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

test "the value snapshot repr is recorded only when it is opted into" {
    const Signal = union(enum(u8)) {
        idle,
        ticks: u32,
    };
    const Fixture = struct {
        fn current() *const Signal {
            unreachable;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const snapshot = try reflect(arena.allocator(), .{
        .types = .{.{ .type = Signal, .repr = .tagged_union_value }},
        .functions = .{.{ .name = "current", .@"fn" = Fixture.current }},
    }, "variant", "zg");
    try std.testing.expectEqual(semantic.UnionRepr.value_snapshot, snapshot.types[0].unionRepr());
    const snapshot_json = try snapshot.serialize(std.testing.allocator);
    defer std.testing.allocator.free(snapshot_json);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_json, "\"union_repr\": \"value_snapshot\"") != null);

    const projection = try reflect(arena.allocator(), .{
        .types = .{.{ .type = Signal, .repr = .tagged_union }},
        .functions = .{.{ .name = "current", .@"fn" = Fixture.current }},
    }, "variant", "zg");
    try std.testing.expectEqual(semantic.UnionRepr.projection, projection.types[0].unionRepr());
    const projection_json = try projection.serialize(std.testing.allocator);
    defer std.testing.allocator.free(projection_json);
    try std.testing.expect(std.mem.indexOf(u8, projection_json, "union_repr") == null);
}

test "tagged union representation reflects discriminants and payloads" {
    const Value = union(enum(u8)) {
        none,
        integer: i32,
        flag: bool,
    };
    const Fixture = struct {
        fn current() *const Value {
            unreachable;
        }
    };
    const declaration = .{
        .types = .{.{ .type = Value, .repr = .tagged_union }},
        .functions = .{.{ .name = "current", .@"fn" = Fixture.current }},
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), declaration, "variant", "zg");

    try std.testing.expectEqual(@as(usize, 2), document.types.len);
    const union_decl = document.types[0];
    try std.testing.expectEqual(semantic.TypeKind.tagged_union, union_decl.kind);
    try std.testing.expectEqualStrings("Value", union_decl.name);
    try std.testing.expectEqualStrings("ValueTag", union_decl.tag_type.?.@"enum".ref);
    try std.testing.expectEqual(@as(usize, 3), union_decl.fields.len);
    try std.testing.expect(union_decl.fields[0].type.? == .void);
    try std.testing.expectEqual(@as(i64, 1), union_decl.fields[1].value.?);
    try std.testing.expect(union_decl.fields[1].type.? == .int);

    const tag_decl = document.types[1];
    try std.testing.expectEqual(semantic.TypeKind.@"enum", tag_decl.kind);
    try std.testing.expectEqualStrings("ValueTag", tag_decl.name);
    try std.testing.expectEqual(@as(u16, 8), tag_decl.tag_type.?.int.bits);
    try std.testing.expectEqualStrings("Value", document.functions[0].@"return".opaque_ptr.ref);
    try std.testing.expect(document.functions[0].@"return".opaque_ptr.@"const");

    const json = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\": \"tagged_union\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\": \"integer\"") != null);
    var parsed = try semantic.Semantic.parse(std.testing.allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqual(semantic.TypeKind.tagged_union, parsed.value.types[0].kind);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.types[0].fields[1].value.?);
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

test "public discovery combines methods root functions exclusions and overrides" {
    const Api = struct {
        pub const Handle = struct {
            pub fn create() *Handle {
                unreachable;
            }

            pub fn set(self: *Handle, value: i32) void {
                _ = self;
                _ = value;
            }

            pub fn internal(self: *Handle, secret: i32) void {
                _ = self;
                _ = secret;
            }

            pub fn deinit(self: *Handle) void {
                _ = self;
            }
        };

        pub fn ping(value: i32) i32 {
            return value;
        }

        fn privateHelper() void {}
    };
    const declaration = .{
        .root = Api,
        .discover = .public,
        .types = .{.{ .type = Api.Handle, .repr = .@"opaque" }},
        .overrides = .{
            .{ .path = "Handle.set", .name = "put", .params = .{"value"} },
            .{ .path = "root.ping", .name = "health" },
        },
        .exclude = .{"Handle.internal"},
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), declaration, "auto", "zg");
    try std.testing.expectEqual(@as(usize, 4), document.functions.len);
    try std.testing.expectEqualStrings("create", document.functions[0].name);
    try std.testing.expectEqualStrings("Handle", document.functions[0].namespace.?);
    try std.testing.expectEqual(.caller, document.functions[0].ownership);
    try std.testing.expectEqualStrings("put", document.functions[1].name);
    try std.testing.expectEqualStrings("value", document.functions[1].params[0].name);
    try std.testing.expectEqual(.sidecar, document.functions[1].params[0].name_source);
    try std.testing.expectEqualStrings("deinit", document.functions[2].name);
    try std.testing.expectEqualStrings("health", document.functions[3].name);
    try std.testing.expect(document.functions[3].receiver == null);
    try std.testing.expect(document.functions[3].namespace == null);
    try std.testing.expectEqual(@as(usize, 1), document.constructors.len);
}

test "discovery selectors use stable owner-qualified paths" {
    const Api = struct {
        pub const Handle = struct {
            pub fn update(self: *Handle) void {
                _ = self;
            }
        };

        pub fn update() void {}
    };
    const declaration = .{
        .root = Api,
        .discover = .public,
        .types = .{.{ .type = Api.Handle, .repr = .@"opaque" }},
    };
    try std.testing.expect(comptime discoveredPathExists(declaration, "Handle.update"));
    try std.testing.expect(comptime discoveredPathExists(declaration, "root.update"));
    try std.testing.expect(!comptime discoveredPathExists(declaration, "Missing.update"));
    try std.testing.expect(!comptime discoveredPathExists(declaration, "root.privateHelper"));
}
