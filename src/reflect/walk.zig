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
    if (!@hasField(@TypeOf(declaration), "root")) {
        @compileError("zigo declarations require `.root`; paths in `.functions` resolve against it");
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
                .tagged_union => switch (info) {
                    .@"union" => |union_info| {
                        if (union_info.tag_type == null) @compileError("zigo tagged_union type entries must name a tagged union");
                        try appendTaggedUnion(allocator, &types, T, type_name, comptime accessStrategy(entry));
                    },
                    else => @compileError("zigo tagged_union type entries must name a tagged union"),
                },
                // A function pointer alias is not a distinct type, so its
                // name cannot be reflected: the entry supplies it, and every
                // parameter of the same signature is matched to it by the
                // structural type name.
                .callback => {
                    if (!@hasField(@TypeOf(entry), "name")) @compileError("zigo callback type entries need an explicit `.name`: a `pub const` alias of a function pointer type carries no name of its own");
                    if (info != .pointer or @typeInfo(info.pointer.child) != .@"fn") @compileError("zigo callback type entries must name a `*const fn` type");
                    try types.append(allocator, .{
                        .kind = .callback,
                        .name = entry.name,
                        .zig_path = @typeName(T),
                    });
                },
                else => @compileError("zigo type repr must be .opaque, .value, .tagged_union, or .callback"),
            }
        }
    }
    if (comptime discoveryEnabled(declaration)) {
        // Discovery walks every registered container plus the root; entries in
        // `functions` attach metadata to what it finds.
        if (@hasField(@TypeOf(declaration), "types")) {
            inline for (declaration.types) |entry| {
                // A callback type is a signature, not a container to walk.
                if (comptime entry.repr != .callback)
                    try discoverContainer(allocator, &functions, &types, declaration, prefix, entry.type, comptime typeEntryName(entry));
            }
        }
        try discoverContainer(allocator, &functions, &types, declaration, prefix, declaration.root, null);
    } else {
        inline for (declaration.functions) |entry| {
            const owner = comptime pathOwner(entry.path);
            const member = comptime pathMember(entry.path);
            try appendFunction(
                allocator,
                &functions,
                &types,
                declaration,
                prefix,
                member,
                @field(comptime pathContainer(declaration, owner), member),
                entry,
                owner,
            );
        }
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
    // `.path` addresses the declaration; `.name` only renames it on the Go
    // side, so there is still exactly one way to say which function is meant.
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
        const parameter_type = try typeNode(allocator, param.type.?, types);
        var reflected: semantic.Parameter = .{
            .name = parameter_name,
            .name_source = if (has_sidecar) .sidecar else .fallback,
            .type = parameter_type,
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
        // The sentinel is part of the Zig type, so it remains a C string even
        // when a declaration sidecar omits a semantic hint.
        if (isSentinelBytePointer(param.type.?)) reflected.semantic = .c_string;
        // A collection of sentinel strings is still a string collection even
        // without sidecar metadata. The unsentinel `[][]const u8` spelling is
        // intentionally opt-in through `.semantic = .utf8_string`.
        if (isSentinelStringSlice(param.type.?)) reflected.semantic = .utf8_string;
        params[output_index] = reflected;
    }
    const reflected_return = if (info.return_type) |return_type|
        try typeNode(allocator, return_type, types)
    else
        semantic.TypeNode{ .void = {} };
    var reflected_function: semantic.SemanticFn = .{
        .has_comptime_params = if (info.is_generic) true else null,
        .name = function_name,
        .namespace = if (receiver == null) discovered_owner else null,
        .params = params,
        .receiver = receiver,
        .@"return" = reflected_return,
        .symbol = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, function_name }),
    };
    if (@hasField(@TypeOf(metadata), "semantic")) reflected_function.return_semantic = metadata.semantic;
    if (@hasField(@TypeOf(metadata), "returns")) reflected_function.ownership = metadata.returns;
    // `.release` addresses the freeing function the same way `.path` does, so
    // the last segment names it inside the generated document.
    if (@hasField(@TypeOf(metadata), "release")) reflected_function.release = comptime pathMember(metadata.release);
    if (info.return_type) |return_type| {
        if (isSentinelBytePointer(return_type)) reflected_function.return_semantic = .c_string;
    }
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
        comptime var adjusted = false;
        if (@hasField(@TypeOf(declaration), "functions")) {
            inline for (declaration.functions) |entry| {
                if (comptime std.mem.eql(u8, entry.path, path)) {
                    adjusted = true;
                    try appendFunction(allocator, functions, types, declaration, prefix, candidate.name, value, entry, owner);
                }
            }
        }
        if (!adjusted) try appendFunction(allocator, functions, types, declaration, prefix, candidate.name, value, .{}, owner);
    }
}

fn discoveryEnabled(comptime declaration: anytype) bool {
    if (!@hasField(@TypeOf(declaration), "discover")) return false;
    if (declaration.discover != .public) @compileError("zigo `.discover` must be `.public`");
    if (@TypeOf(declaration.root) != type) @compileError("zigo `.root` must be a module or container type");
    return true;
}

/// The access strategy a `types` entry chose. Defaults keep the axis out of
/// declarations that do not need it; new strategies add a value here rather
/// than a new `repr` name.
fn accessStrategy(comptime entry: anytype) semantic.Access {
    if (!@hasField(@TypeOf(entry), "access")) return .projection;
    return switch (entry.access) {
        .projection => .projection,
        .snapshot => .snapshot,
        else => @compileError("zigo `.access` must be `.projection` or `.snapshot`"),
    };
}

/// The display name of a `types` entry: the explicit `.name` when given, and
/// otherwise the short Zig type name. Generic instantiations need the explicit
/// form, which is why registering one is an ordinary `types` entry.
fn typeEntryName(comptime entry: anytype) []const u8 {
    return if (@hasField(@TypeOf(entry), "name")) entry.name else shortTypeName(@typeName(entry.type));
}

fn validateSelectors(comptime declaration: anytype) void {
    if (@TypeOf(declaration.root) != type) @compileError("zigo `.root` must be a module or container type");
    if (@hasField(@TypeOf(declaration), "functions")) {
        inline for (declaration.functions, 0..) |entry, index| {
            if (!@hasField(@TypeOf(entry), "path")) @compileError("zigo function entries require `.path`");
            if (!declarationPathExists(declaration, entry.path)) {
                @compileError("zigo path does not name a public function: " ++ entry.path ++
                    " (use `root.<name>` for a function in `.root`, or `<Type>.<name>` for one in a registered type)");
            }
            inline for (declaration.functions, 0..) |previous, previous_index| {
                if (previous_index < index and std.mem.eql(u8, previous.path, entry.path)) @compileError("duplicate zigo function path: " ++ entry.path);
            }
            if (selectorContains(declaration, "exclude", entry.path)) {
                @compileError("zigo path cannot be both listed and excluded: " ++ entry.path);
            }
        }
    }
    if (!discoveryEnabled(declaration)) {
        if (@hasField(@TypeOf(declaration), "exclude")) {
            @compileError("zigo `.exclude` requires `.discover = .public`; an explicit list simply omits the function");
        }
        return;
    }
    if (@hasField(@TypeOf(declaration), "exclude")) {
        inline for (declaration.exclude, 0..) |path, index| {
            if (!declarationPathExists(declaration, path)) {
                @compileError("zigo exclusion path does not name a discovered public function: " ++ path);
            }
            inline for (declaration.exclude, 0..) |previous, previous_index| {
                if (previous_index < index and std.mem.eql(u8, previous, path)) @compileError("duplicate zigo exclusion path: " ++ path);
            }
        }
    }
}

/// `root.<name>` for a function in `.root`, `<Type>.<name>` for one in a
/// registered type. The same grammar addresses a declaration whether the
/// binding lists functions explicitly or discovers them.
fn pathOwner(comptime path: []const u8) ?[]const u8 {
    const index = comptime std.mem.lastIndexOfScalar(u8, path, '.') orelse
        @compileError("zigo path must be `root.<name>` or `<Type>.<name>`: " ++ path);
    const owner = path[0..index];
    return if (std.mem.eql(u8, owner, "root")) null else owner;
}

fn pathMember(comptime path: []const u8) []const u8 {
    const index = comptime std.mem.lastIndexOfScalar(u8, path, '.') orelse
        @compileError("zigo path must be `root.<name>` or `<Type>.<name>`: " ++ path);
    return path[index + 1 ..];
}

fn pathContainer(comptime declaration: anytype, comptime owner: ?[]const u8) type {
    const name = owner orelse return declaration.root;
    if (@hasField(@TypeOf(declaration), "types")) {
        inline for (declaration.types) |entry| {
            if (comptime entry.repr != .callback and std.mem.eql(u8, typeEntryName(entry), name)) return entry.type;
        }
    }
    @compileError("zigo path names a type that is not registered in `.types`: " ++ name);
}

fn declarationPathExists(comptime declaration: anytype, comptime wanted: []const u8) bool {
    if (@hasField(@TypeOf(declaration), "types")) {
        inline for (declaration.types) |entry| {
            if (comptime entry.repr == .callback) continue;
            if (containerHasPath(entry.type, comptime typeEntryName(entry), wanted)) return true;
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
                break :blk .{ .slice = .{
                    .@"const" = info.is_const,
                    .element = element,
                    .sentinel = if (info.child == u8) info.sentinel() else null,
                } };
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
                        .ref = callbackNameForPath(types.items, @typeName(T)),
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
            .many => blk: {
                const sentinel = info.sentinel() orelse @compileError(
                    "zigo supports slices, pointers to declared opaque types, and `[*:0]const u8` sentinel strings; mutable or non-zero-sentinel many pointers are unsupported",
                );
                if (info.child != u8 or !info.is_const or sentinel != 0) @compileError(
                    "zigo supports slices, pointers to declared opaque types, and `[*:0]const u8` sentinel strings; mutable or non-zero-sentinel many pointers are unsupported",
                );
                const element = try allocator.create(semantic.TypeNode);
                element.* = try typeNode(allocator, info.child, types);
                break :blk .{ .slice = .{
                    .@"const" = true,
                    .element = element,
                    .sentinel = sentinel,
                    .sentinel_many = true,
                } };
            },
            else => @compileError(
                "zigo supports slices, pointers to declared opaque types, and `[*:0]const u8` sentinel strings; mutable or non-zero-sentinel many pointers are unsupported",
            ),
        },
        // Only a pointer to a declared opaque type has a null representation Go
        // can express: the handle argument is already a pointer, so a nil one
        // crosses as NULL. Every other optional would need a separate presence
        // flag in the ABI, which zigo does not generate.
        .optional => |info| blk: {
            const child = @typeInfo(info.child);
            if (child != .pointer or child.pointer.size != .one or @typeInfo(child.pointer.child) == .@"fn")
                @compileError("zigo supports optionals only on pointers to declared opaque types");
            const name = opaqueNameForPath(types.items, @typeName(child.pointer.child)) orelse return error.MissingOpaqueType;
            break :blk .{ .opaque_ptr = .{
                .@"const" = child.pointer.is_const,
                .nullable = true,
                .ref = name,
            } };
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
            if (isHandleRepr(entry.repr) and entry.type == pointer.child) return typeEntryName(entry);
        }
    }
    return null;
}

/// The declared callback type whose structural name matches `path`. Two
/// aliases of one signature are the same type to Zig, so the first declared
/// one wins for both.
fn callbackNameForPath(types: []const semantic.TypeDecl, path: []const u8) ?[]const u8 {
    for (types) |declaration| {
        if (declaration.kind == .callback and std.mem.eql(u8, declaration.zig_path orelse "", path)) return declaration.name;
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
    return repr == .@"opaque" or repr == .tagged_union;
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
    access: semantic.Access,
) !void {
    const info = @typeInfo(T).@"union";
    const Tag = info.tag_type orelse @compileError("zigo cannot reflect an untagged union");
    const tag_info = @typeInfo(Tag).@"enum";
    const tag_name = try std.fmt.allocPrint(allocator, "{s}Tag", .{name});

    const union_index = types.items.len;
    try types.append(allocator, .{
        .kind = .tagged_union,
        .name = name,
        // The default strategy stays absent from semantic.json, so a type that
        // does not choose one leaves its document unchanged.
        .access = if (access == .projection) null else access,
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

fn isSentinelBytePointer(comptime T: type) bool {
    const info = switch (@typeInfo(T)) {
        .pointer => |value| value,
        else => return false,
    };
    if (info.size != .many or info.child != u8 or !info.is_const) return false;
    return (info.sentinel() orelse return false) == 0;
}

fn isSentinelStringSlice(comptime T: type) bool {
    const outer = switch (@typeInfo(T)) {
        .pointer => |value| value,
        else => return false,
    };
    if (outer.size != .slice or !outer.is_const) return false;
    const inner = switch (@typeInfo(outer.child)) {
        .pointer => |value| value,
        else => return false,
    };
    if (!inner.is_const or inner.child != u8) return false;
    const sentinel = inner.sentinel() orelse return false;
    return sentinel == 0;
}

test "scalar reflection matches the semantic JSON golden" {
    const Api = struct {
        pub fn add(a: i32, b: i32) i32 {
            return a + b;
        }
    };
    const declaration = .{ .root = Api, .functions = .{.{ .path = "root.add" }} };
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

        pub fn generic(comptime T: type, value: T) T {
            return value;
        }

        pub fn callback(value: *const fn (i32) void) void {
            _ = value;
        }

        pub fn tagged(value: Value) void {
            _ = value;
        }
    };
    const declaration = .{ .root = Fixture, .functions = .{
        .{ .path = "root.generic" },
        .{ .path = "root.callback" },
        .{ .path = "root.tagged" },
    } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), declaration, "invalid", "zg");
    try std.testing.expectEqual(true, document.functions[0].has_comptime_params.?);
    try std.testing.expect(!document.functions[1].params[0].type.callback.c_callconv);
    try std.testing.expectEqual(semantic.TypeKind.tagged_union, document.types[0].kind);
}

test "sentinel byte pointers reflect as c strings" {
    const Fixture = struct {
        pub fn echo(text: [*:0]const u8) [*:0]const u8 {
            return text;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .functions = .{.{ .path = "root.echo", .params = .{"text"} }},
    }, "sentinel", "zg");

    try std.testing.expectEqual(@as(u16, 8), document.functions[0].params[0].type.slice.element.*.int.bits);
    try std.testing.expectEqual(semantic.SemanticHint.c_string, document.functions[0].params[0].semantic.?);
    try std.testing.expectEqual(semantic.SemanticHint.c_string, document.functions[0].return_semantic.?);
    const json = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"semantic\": \"c_string\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"return_semantic\": \"c_string\"") != null);
}

test "string slice element spellings survive reflection" {
    const Fixture = struct {
        pub fn plain(paths: []const []const u8) usize {
            return paths.len;
        }

        pub fn sentinelSlice(paths: []const [:0]const u8) usize {
            return paths.len;
        }

        pub fn sentinelMany(paths: []const [*:0]const u8) usize {
            return paths.len;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .functions = .{
            .{ .path = "root.plain", .params = .{"paths"}, .param_meta = .{ .paths = .{ .semantic = .utf8_string } } },
            .{ .path = "root.sentinelSlice", .params = .{"paths"} },
            .{ .path = "root.sentinelMany", .params = .{"paths"} },
        },
    }, "strings", "zg");

    const plain = document.functions[0].params[0].type.slice.element.*.slice;
    try std.testing.expect(plain.sentinel == null);
    try std.testing.expectEqual(semantic.SemanticHint.utf8_string, document.functions[0].params[0].semantic.?);
    const sentinel_slice = document.functions[1].params[0].type.slice.element.*.slice;
    try std.testing.expectEqual(@as(?u8, 0), sentinel_slice.sentinel);
    try std.testing.expect(!sentinel_slice.sentinel_many);
    try std.testing.expectEqual(semantic.SemanticHint.utf8_string, document.functions[1].params[0].semantic.?);
    const sentinel_many = document.functions[2].params[0].type.slice.element.*.slice;
    try std.testing.expectEqual(@as(?u8, 0), sentinel_many.sentinel);
    try std.testing.expect(sentinel_many.sentinel_many);
    try std.testing.expectEqual(semantic.SemanticHint.utf8_string, document.functions[2].params[0].semantic.?);
}

test "the snapshot access strategy is recorded only when it is opted into" {
    const Signal = union(enum(u8)) {
        idle,
        ticks: u32,
    };
    const Fixture = struct {
        pub fn current() *const Signal {
            unreachable;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const snapshot = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .type = Signal, .repr = .tagged_union, .access = .snapshot }},
        .functions = .{.{ .path = "root.current" }},
    }, "variant", "zg");
    try std.testing.expectEqual(semantic.Access.snapshot, snapshot.types[0].accessStrategy());
    const snapshot_json = try snapshot.serialize(std.testing.allocator);
    defer std.testing.allocator.free(snapshot_json);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_json, "\"access\": \"snapshot\"") != null);

    const projection = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .type = Signal, .repr = .tagged_union }},
        .functions = .{.{ .path = "root.current" }},
    }, "variant", "zg");
    try std.testing.expectEqual(semantic.Access.projection, projection.types[0].accessStrategy());
    const projection_json = try projection.serialize(std.testing.allocator);
    defer std.testing.allocator.free(projection_json);
    try std.testing.expect(std.mem.indexOf(u8, projection_json, "\"access\":") == null);
}

test "tagged union representation reflects discriminants and payloads" {
    const Value = union(enum(u8)) {
        none,
        integer: i32,
        flag: bool,
    };
    const Fixture = struct {
        pub fn current() *const Value {
            unreachable;
        }
    };
    const declaration = .{
        .root = Fixture,
        .types = .{.{ .type = Value, .repr = .tagged_union }},
        .functions = .{.{ .path = "root.current" }},
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

test "named generic instantiations are ordinary registered types" {
    const Generic = struct {
        fn Buffer(comptime T: type) type {
            return struct { value: T };
        }
    };
    const FloatBuffer = Generic.Buffer(f32);
    const IntBuffer = Generic.Buffer(i32);
    const declaration = .{
        .root = Generic,
        .types = .{
            .{ .name = "FloatBuffer", .type = FloatBuffer, .repr = .@"opaque" },
            .{ .name = "IntBuffer", .type = IntBuffer, .repr = .@"opaque" },
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

test "public discovery combines methods root functions exclusions and entries" {
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
        .functions = .{
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
    try std.testing.expect(comptime declarationPathExists(declaration, "Handle.update"));
    try std.testing.expect(comptime declarationPathExists(declaration, "root.update"));
    try std.testing.expect(!comptime declarationPathExists(declaration, "Missing.update"));
    try std.testing.expect(!comptime declarationPathExists(declaration, "root.privateHelper"));
}

test "an optional opaque pointer parameter reflects as a nullable handle" {
    const Api = struct {
        pub const Handle = struct {
            pub fn create() error{OutOfMemory}!*Handle {
                return error.OutOfMemory;
            }

            pub fn deinit(self: *Handle) void {
                _ = self;
            }

            pub fn adopt(self: *Handle, other: ?*const Handle, owner: *Handle) void {
                _ = self;
                _ = other;
                _ = owner;
            }
        };
    };
    const declaration = .{
        .root = Api,
        .types = .{.{ .type = Api.Handle, .repr = .@"opaque" }},
        .functions = .{
            .{ .path = "Handle.create" },
            .{ .path = "Handle.deinit" },
            .{ .path = "Handle.adopt", .params = .{ "other", "owner" } },
        },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), declaration, "optional", "zg");
    const adopt = document.functions[2];
    try std.testing.expectEqualStrings("adopt", adopt.name);
    const optional = adopt.params[0].type.opaque_ptr;
    try std.testing.expect(optional.nullable);
    try std.testing.expect(optional.@"const");
    try std.testing.expectEqualStrings("Handle", optional.ref);
    // The neighbouring non-optional pointer keeps the checked-handle contract.
    try std.testing.expect(!adopt.params[1].type.opaque_ptr.nullable);
}
