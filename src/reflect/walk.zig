const std = @import("std");
const naming = @import("naming");
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
                // An enum registered here is not walked for declarations --
                // like a callback entry, it exists to name a type, not to
                // contribute functions. What it buys is the `.name`: an enum
                // built by a comptime function has a `@typeName` that ends in
                // the expression that built it, and no name of its own.
                .enumeration => switch (info) {
                    .@"enum" => try appendEnum(allocator, &types, T, type_name),
                    else => @compileError("zigo enumeration type entries must name an enum"),
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
                else => @compileError("zigo type repr must be .opaque, .value, .enumeration, .tagged_union, or .callback"),
            }
        }
    }
    if (comptime discoveryEnabled(declaration)) {
        // Discovery walks every registered container plus the root; entries in
        // `functions` attach metadata to what it finds.
        if (@hasField(@TypeOf(declaration), "types")) {
            inline for (declaration.types) |entry| {
                // A callback type is a signature and an enum is a name, not
                // containers to walk.
                if (comptime entry.repr != .callback and entry.repr != .enumeration)
                    try discoverContainer(allocator, &functions, &types, declaration, prefix, entry.type, comptime typeEntryName(entry), comptime typeEntryName(entry));
            }
        }
        try discoverContainer(allocator, &functions, &types, declaration, prefix, declaration.root, null, "root");
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
            // The storage the shim allocated is the shim's to free, so the
            // paired destructor runs the Zig `deinit` and then destroys it.
            if (function.boxed == .create) {
                for (functions.items) |*candidate| {
                    if (candidate.receiver != null and std.mem.eql(u8, candidate.receiver.?, type_name) and
                        std.mem.eql(u8, candidate.name, destructor.name)) candidate.boxed = .destroy;
                }
            }
            break;
        }
    }

    return .{
        .allocator = comptime injectionExpression(declaration, "allocator"),
        .constructors = try constructors.toOwnedSlice(allocator),
        .functions = try functions.toOwnedSlice(allocator),
        .io = comptime injectionExpression(declaration, "io"),
        .package = package_name,
        .prefix = prefix,
        .types = try types.toOwnedSlice(allocator),
        .zig_version = @import("builtin").zig_version_string,
    };
}

/// The Zig expression the shim writes for an injected argument. `.allocator`
/// takes one of the three std allocators by name or a path into the bound
/// module; `.io` takes a path only, because `std` has no default `Io`. There
/// is no default for either: an allocator nobody chose is a lifetime decision
/// zigo has no business making.
fn injectionExpression(comptime declaration: anytype, comptime field: []const u8) ?[]const u8 {
    if (!@hasField(@TypeOf(declaration), field)) return null;
    const value = @field(declaration, field);
    if (@TypeOf(value) == @TypeOf(.enum_literal)) {
        if (!std.mem.eql(u8, field, "allocator"))
            @compileError("zigo `." ++ field ++ "` must be a declaration path string");
        return switch (value) {
            .c_allocator => "std.heap.c_allocator",
            .page_allocator => "std.heap.page_allocator",
            .smp_allocator => "std.heap.smp_allocator",
            else => @compileError("zigo `.allocator` must be .c_allocator, .page_allocator, .smp_allocator, or a declaration path string"),
        };
    }
    // A path is resolved against the bound module, the same root every
    // `.functions` path resolves against.
    return "target." ++ value;
}

/// The parameters zigo fills in rather than exposing. Zig spells them as
/// ordinary arguments, but neither has a C representation, so a binding that
/// wants them names the value once instead of per call.
fn injectionFor(comptime T: type) ?semantic.Injection {
    if (T == std.mem.Allocator) return .allocator;
    if (T == std.Io) return .io;
    return null;
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
    // What the message calls the declaration: the owner it was reached through
    // plus the source name, which is the spelling the binding's `.path` uses.
    const owner_label = comptime if (receiver) |value|
        value ++ "."
    else if (discovered_owner) |value| value ++ "." else "";
    const function_label = source_name;
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
        const injection = comptime injectionFor(param.type.?);
        // An injected parameter never reaches C, so it is not walked as a
        // type: `std.mem.Allocator` is a struct with a vtable pointer, and
        // reflecting it would fail long before validation could explain why.
        const parameter_type = if (injection != null) semantic.TypeNode{ .void = {} } else try typeNode(allocator, param.type.?, types, comptime std.fmt.comptimePrint(
            "`{s}{s}` parameter `{s}`",
            .{ owner_label, function_label, if (has_sidecar) metadata.params[output_index] else std.fmt.comptimePrint("p{d}", .{output_index}) },
        ));
        var reflected: semantic.Parameter = .{
            .injected = injection,
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
                if (@hasField(@TypeOf(value), "written")) reflected.written = value.written;
                if (@hasField(@TypeOf(value), "buffer")) reflected.buffer = value.buffer;
                if (@hasField(@TypeOf(value), "go_error")) reflected.go_error = value.go_error;
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
    // A Zig `init` that returns its value has no C representation, so with an
    // allocator to hand zigo boxes it: the shim allocates the storage and the
    // binding hands Go a handle. The decision is made before the return type
    // is walked, because walking it would register a value struct C cannot
    // carry and reject the whole binding instead.
    const boxed_type = comptime boxedConstructorName(declaration, info, function_name);
    const reflected_return = if (boxed_type) |type_name| blk: {
        const payload = try allocator.create(semantic.TypeNode);
        payload.* = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = type_name } };
        break :blk semantic.TypeNode{ .error_union = .{
            .error_set = comptime boxedErrorNames(info),
            .payload = payload,
        } };
    } else if (info.return_type) |return_type|
        try typeNode(allocator, return_type, types, comptime std.fmt.comptimePrint("`{s}{s}` return value", .{ owner_label, function_label }))
    else
        semantic.TypeNode{ .void = {} };
    var reflected_function: semantic.SemanticFn = .{
        .boxed = if (boxed_type != null) .create else null,
        .has_comptime_params = if (info.is_generic) true else null,
        .name = function_name,
        .namespace = if (receiver == null) discovered_owner else null,
        .params = params,
        .receiver = receiver,
        .@"return" = reflected_return,
        .symbol = try naming.functionSymbolAlloc(allocator, prefix, receiver orelse discovered_owner, function_name),
    };
    if (boxed_type != null) reflected_function.ownership = .caller;
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

/// The registered handle name a value-returning constructor is boxed into,
/// or null when this is not one. Boxing needs three things at once: a
/// constructor name, a return of the registered type by value, and an
/// allocator the binding chose to own the storage. Without the allocator the
/// function is left alone, so the rejection the author sees still names the
/// struct rather than a decision zigo made for them.
fn boxedConstructorName(comptime declaration: anytype, comptime info: std.builtin.Type.Fn, comptime function_name: []const u8) ?[]const u8 {
    if (injectionExpression(declaration, "allocator") == null) return null;
    if (!isConstructorName(function_name)) return null;
    const return_type = info.return_type orelse return null;
    const value_type = switch (@typeInfo(return_type)) {
        .error_union => |error_union| error_union.payload,
        else => return_type,
    };
    if (@typeInfo(value_type) != .@"struct") return null;
    if (!@hasField(@TypeOf(declaration), "types")) return null;
    inline for (declaration.types) |entry| {
        if (entry.repr == .@"opaque" and entry.type == value_type) return typeEntryName(entry);
    }
    return null;
}

/// The Zig error names a boxed constructor can fail with. Running out of
/// memory is not among them: the allocation the shim adds is zigo's own, and
/// it reports that as a panic rather than inventing an error the Zig function
/// never declared.
fn boxedErrorNames(comptime info: std.builtin.Type.Fn) []const []const u8 {
    const return_type = info.return_type orelse return &.{};
    const error_union = switch (@typeInfo(return_type)) {
        .error_union => |value| value,
        else => return &.{},
    };
    const errors = @typeInfo(error_union.error_set).error_set orelse return &.{};
    comptime var names: [errors.len][]const u8 = undefined;
    inline for (errors, 0..) |entry, index| names[index] = entry.name;
    const frozen = names;
    return &frozen;
}

fn discoverContainer(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(semantic.SemanticFn),
    types: *std.ArrayList(semantic.TypeDecl),
    comptime declaration: anytype,
    prefix: []const u8,
    comptime Container: type,
    comptime owner: ?[]const u8,
    /// How a binding spells this container in `.functions` and `.exclude`:
    /// `root` for the module itself, the entry name for a registered type,
    /// and those plus every namespace segment below them.
    comptime path_prefix: []const u8,
) !void {
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@typeInfo(@TypeOf(value)) != .@"fn") continue;
        const path = path_prefix ++ "." ++ candidate.name;
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
    if (comptime !discoveryRecursive(declaration)) return;
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@TypeOf(value) != type or comptime !isNestedContainer(Container, value)) continue;
        try discoverContainer(
            allocator,
            functions,
            types,
            declaration,
            prefix,
            value,
            comptime if (owner) |parent| parent ++ "." ++ candidate.name else candidate.name,
            path_prefix ++ "." ++ candidate.name,
        );
    }
}

/// A declaration is a namespace of its container only when it was written
/// inside it. Comparing the mangled type names is what tells that apart from
/// an `@This()` alias, a re-export, or an imported module -- all of which
/// would otherwise make discovery walk in circles or leave the binding.
fn isNestedContainer(comptime Container: type, comptime Child: type) bool {
    if (!isContainer(Child)) return false;
    const parent = @typeName(Container);
    const child = @typeName(Child);
    return child.len > parent.len + 1 and
        std.mem.startsWith(u8, child, parent) and child[parent.len] == '.' and
        std.mem.indexOfScalar(u8, child[parent.len + 1 ..], '.') == null;
}

fn discoveryEnabled(comptime declaration: anytype) bool {
    if (!@hasField(@TypeOf(declaration), "discover")) return false;
    if (declaration.discover != .public and declaration.discover != .recursive)
        @compileError("zigo `.discover` must be `.public` or `.recursive`");
    if (@TypeOf(declaration.root) != type) @compileError("zigo `.root` must be a module or container type");
    return true;
}

/// `.public` finds the functions declared directly in the root and in each
/// registered type. `.recursive` also descends into the namespace structs
/// those containers declare. It stays opt-in because turning it on would
/// otherwise silently widen an existing binding's exported surface.
fn discoveryRecursive(comptime declaration: anytype) bool {
    if (!@hasField(@TypeOf(declaration), "discover")) return false;
    return declaration.discover == .recursive;
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
/// registered type, and any number of container segments in between:
/// `root.unicode.codepointWidth` names a function in the `unicode` namespace
/// struct. The same grammar addresses a declaration whether the binding lists
/// functions explicitly or discovers them. The owner keeps its dots, which is
/// what makes the namespace, the C symbol and the ABI identity agree without
/// any of them learning a second spelling.
fn pathOwner(comptime path: []const u8) ?[]const u8 {
    const index = comptime std.mem.lastIndexOfScalar(u8, path, '.') orelse
        @compileError("zigo path must be `root.<name>` or `<Type>.<name>`: " ++ path);
    const owner = path[0..index];
    if (std.mem.eql(u8, owner, "root")) return null;
    if (std.mem.startsWith(u8, owner, "root.")) return owner["root.".len..];
    return owner;
}

fn pathMember(comptime path: []const u8) []const u8 {
    const index = comptime std.mem.lastIndexOfScalar(u8, path, '.') orelse
        @compileError("zigo path must be `root.<name>` or `<Type>.<name>`: " ++ path);
    return path[index + 1 ..];
}

fn pathContainer(comptime declaration: anytype, comptime owner: ?[]const u8) type {
    const path = owner orelse return declaration.root;
    comptime {
        var iterator = std.mem.splitScalar(u8, path, '.');
        const head = iterator.first();
        var Container: type = registeredContainer(declaration, head) orelse
            rootContainerChild(declaration.root, head, path);
        while (iterator.next()) |segment| Container = rootContainerChild(Container, segment, path);
        return Container;
    }
}

/// The first segment of an owner may name a registered `types` entry, which is
/// how `<Type>.<name>` has always addressed a method. Everything after it is
/// an ordinary public container declaration.
fn registeredContainer(comptime declaration: anytype, comptime name: []const u8) ?type {
    if (@hasField(@TypeOf(declaration), "types")) {
        inline for (declaration.types) |entry| {
            if (comptime entry.repr != .callback and entry.repr != .enumeration and std.mem.eql(u8, typeEntryName(entry), name)) return entry.type;
        }
    }
    return null;
}

fn rootContainerChild(comptime Container: type, comptime name: []const u8, comptime path: []const u8) type {
    if (!isContainer(Container) or !@hasDecl(Container, name) or @TypeOf(@field(Container, name)) != type)
        @compileError("zigo path segment `" ++ name ++ "` does not name a public container type or a registered `.types` entry: " ++ path);
    return @field(Container, name);
}

fn isContainer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => true,
        else => false,
    };
}

fn declarationPathExists(comptime declaration: anytype, comptime wanted: []const u8) bool {
    comptime {
        const dot = std.mem.indexOfScalar(u8, wanted, '.') orelse return false;
        const head = wanted[0..dot];
        const rest = wanted[dot + 1 ..];
        if (std.mem.eql(u8, head, "root")) return containerHasPath(declaration.root, rest);
        if (registeredContainer(declaration, head)) |Container| return containerHasPath(Container, rest);
        return false;
    }
}

/// Follows the remaining segments through public container declarations and
/// reports whether the last one names a public function. Resolving the path
/// the caller asked for, rather than enumerating everything reachable, is what
/// keeps a container that refers back to itself from unrolling forever.
fn containerHasPath(comptime Container: type, comptime rest: []const u8) bool {
    comptime {
        if (!isContainer(Container)) return false;
        const dot = std.mem.indexOfScalar(u8, rest, '.') orelse
            return @hasDecl(Container, rest) and @typeInfo(@TypeOf(@field(Container, rest))) == .@"fn";
        const head = rest[0..dot];
        if (!@hasDecl(Container, head) or @TypeOf(@field(Container, head)) != type) return false;
        return containerHasPath(@field(Container, head), rest[dot + 1 ..]);
    }
}

fn selectorContains(comptime declaration: anytype, comptime field_name: []const u8, comptime path: []const u8) bool {
    if (!@hasField(@TypeOf(declaration), field_name)) return false;
    inline for (@field(declaration, field_name)) |candidate| {
        if (std.mem.eql(u8, candidate, path)) return true;
    }
    return false;
}

/// `context` names the parameter, return value, or field the type was reached
/// through. Reflection rejections are compile errors in the binding author's
/// build, and without it they only name the constraint, never where it broke.
fn typeNode(
    allocator: std.mem.Allocator,
    comptime T: type,
    types: *std.ArrayList(semantic.TypeDecl),
    comptime context: []const u8,
) !semantic.TypeNode {
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
                element.* = try typeNode(allocator, info.child, types, context ++ " (slice element)");
                break :blk .{ .slice = .{
                    .@"const" = info.is_const,
                    .element = element,
                    .sentinel = if (info.child == u8) info.sentinel() else null,
                } };
            },
            .one => blk: {
                // `*std.Io.Writer` and `*std.Io.Reader` are concrete structs in
                // Zig 0.16, so type identity settles it. They are matched ahead
                // of the opaque-handle rule: neither is a registered type, and
                // without this the author would be told to register a std type
                // rather than that the position is the problem.
                if (info.child == std.Io.Writer) break :blk .{ .io_stream = .{ .direction = .writer } };
                if (info.child == std.Io.Reader) break :blk .{ .io_stream = .{ .direction = .reader } };
                if (@typeInfo(info.child) == .@"fn") {
                    const function_info = @typeInfo(info.child).@"fn";
                    const callback_params = try allocator.alloc(semantic.TypeNode, function_info.params.len);
                    inline for (function_info.params, 0..) |parameter, index| {
                        const parameter_type = parameter.type orelse
                            @compileError("zigo cannot reflect a generic callback parameter, at " ++ context);
                        callback_params[index] = try typeNode(
                            allocator,
                            parameter_type,
                            types,
                            context ++ std.fmt.comptimePrint(" (callback parameter {d})", .{index}),
                        );
                    }
                    const callback_return = try allocator.create(semantic.TypeNode);
                    const callback_return_type = function_info.return_type orelse
                        @compileError("zigo cannot reflect a generic callback return type, at " ++ context);
                    callback_return.* = try typeNode(allocator, callback_return_type, types, context ++ " (callback return value)");
                    break :blk .{ .callback = .{
                        .c_callconv = std.meta.eql(function_info.calling_convention, std.builtin.CallingConvention.c),
                        .has_userdata = function_info.params.len != 0 and
                            function_info.params[function_info.params.len - 1].type == usize,
                        .params = callback_params,
                        .ref = callbackNameForPath(types.items, @typeName(T)),
                        .@"return" = callback_return,
                    } };
                }
                const name = opaqueNameForPath(types.items, @typeName(info.child)) orelse
                    return missingOpaqueType(@typeName(info.child), context);
                break :blk .{ .opaque_ptr = .{
                    .@"const" = info.is_const,
                    .nullable = false,
                    .ref = name,
                } };
            },
            .many => blk: {
                const sentinel = info.sentinel() orelse @compileError(
                    "zigo supports slices, pointers to declared opaque types, and `[*:0]const u8` sentinel strings; mutable or non-zero-sentinel many pointers are unsupported, at " ++ context,
                );
                if (info.child != u8 or !info.is_const or sentinel != 0) @compileError(
                    "zigo supports slices, pointers to declared opaque types, and `[*:0]const u8` sentinel strings; mutable or non-zero-sentinel many pointers are unsupported, at " ++ context,
                );
                const element = try allocator.create(semantic.TypeNode);
                element.* = try typeNode(allocator, info.child, types, context ++ " (slice element)");
                break :blk .{ .slice = .{
                    .@"const" = true,
                    .element = element,
                    .sentinel = sentinel,
                    .sentinel_many = true,
                } };
            },
            else => @compileError(
                "zigo supports slices, pointers to declared opaque types, and `[*:0]const u8` sentinel strings; mutable or non-zero-sentinel many pointers are unsupported, at " ++ context,
            ),
        },
        // A pointer to a declared opaque type has a null representation Go can
        // express directly: the handle argument is already a pointer, so a nil
        // one crosses as NULL. It keeps reflecting straight to `opaque_ptr`
        // rather than through the `optional` node below, unchanged from before
        // this type was extended.
        //
        // Every other optional (bool, integer, float, enum, or an `extern
        // struct`) reflects to the `optional` node instead: presence and value
        // travel together, either as a single nullable pointer parameter or as
        // a `bool` plus an out parameter on return -- lowering and generation
        // decide which. A slice, callback, tagged union, or another optional
        // has no such shape yet, so it stays a compile error until zigo grows
        // one (planned separately from this phase).
        .optional => |info| blk: {
            const child = @typeInfo(info.child);
            if (child == .pointer and child.pointer.size == .one and @typeInfo(child.pointer.child) != .@"fn") {
                const name = opaqueNameForPath(types.items, @typeName(child.pointer.child)) orelse
                    return missingOpaqueType(@typeName(child.pointer.child), context);
                break :blk .{ .opaque_ptr = .{
                    .@"const" = child.pointer.is_const,
                    .nullable = true,
                    .ref = name,
                } };
            }
            const allowed = switch (child) {
                .bool, .int, .float, .@"enum" => true,
                .@"struct" => |value| value.layout == .@"extern",
                // A slice already carries a pointer, so absence rides on that
                // pointer being NULL -- which is why an empty slice and an
                // absent one stay different. A sentinel many pointer reflects
                // to the same `slice` node and works the same way.
                .pointer => |value| value.size == .slice or
                    (value.size == .many and value.is_const and value.sentinel() != null),
                else => false,
            };
            if (!allowed) @compileError(
                "zigo supports optionals on pointers to declared opaque types, bool, integers, floats, enums, extern structs, and slices, at " ++ context,
            );
            const child_node = try allocator.create(semantic.TypeNode);
            child_node.* = try typeNode(allocator, info.child, types, context ++ " (optional child)");
            break :blk .{ .optional = .{ .child = child_node } };
        },
        .error_union => |info| blk: {
            const payload = try allocator.create(semantic.TypeNode);
            payload.* = try typeNode(allocator, info.payload, types, context ++ " (error payload)");
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
        .@"enum" => blk: {
            // A registered entry is found by Zig path, so an enum the binding
            // named keeps that name wherever a signature reaches it. Only a
            // type nobody registered is named from `@typeName`.
            for (types.items) |declaration| {
                if (declaration.kind == .@"enum" and std.mem.eql(u8, declaration.zig_path orelse "", @typeName(T))) {
                    break :blk .{ .@"enum" = .{ .ref = declaration.name } };
                }
            }
            const name = shortTypeName(@typeName(T));
            var exists = false;
            for (types.items) |declaration| {
                if (std.mem.eql(u8, declaration.name, name)) exists = true;
            }
            if (!exists) try appendEnum(allocator, types, T, name);
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
            if (@typeInfo(T).@"union".tag_type == null) @compileError("zigo cannot reflect an untagged union, at " ++ context);
            try appendTaggedUnion(allocator, types, T, name, .projection);
            break :blk .{ .value_struct = .{ .ref = name } };
        },
        else => @compileError("zigo supports scalars, enums, slices, opaque pointers, structs, and error unions, at " ++ context),
    };
}

/// The opaque registry is filled while walking, so a pointer to an
/// unregistered type is only discovered at run time. Naming the type and the
/// site it was reached through is the whole difference between a usable
/// message and a bare error name.
fn missingOpaqueType(comptime type_name: []const u8, comptime context: []const u8) error{MissingOpaqueType} {
    std.debug.print(
        "zigo: `{s}` is not a registered opaque type, at {s}\n" ++
            "  hint: add it to `.types` with `.repr = .opaque`\n",
        .{ type_name, context },
    );
    return error.MissingOpaqueType;
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
/// One place an enum becomes a `TypeDecl`, whether the binding registered it
/// or a signature reached it.
fn appendEnum(
    allocator: std.mem.Allocator,
    types: *std.ArrayList(semantic.TypeDecl),
    comptime T: type,
    name: []const u8,
) !void {
    const info = @typeInfo(T).@"enum";
    const fields = try allocator.alloc(semantic.TypeField, info.fields.len);
    inline for (info.fields, 0..) |field, index| fields[index] = .{ .name = field.name, .value = @intCast(field.value) };
    const tag_type = try typeNode(allocator, info.tag_type, types, "the tag type of enum `" ++ @typeName(T) ++ "`");
    try types.append(allocator, .{
        .exhaustive = info.is_exhaustive,
        .fields = fields,
        .kind = .@"enum",
        .name = name,
        .tag_type = tag_type,
        .zig_path = @typeName(T),
    });
}

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
            .type = try typeNode(
                allocator,
                field.type,
                types,
                "`" ++ comptime shortTypeName(@typeName(T)) ++ "` field `" ++ field.name ++ "`",
            ),
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
            .type = try typeNode(
                allocator,
                field.type,
                types,
                "`" ++ comptime shortTypeName(@typeName(T)) ++ "` variant `" ++ field.name ++ "`",
            ),
            .value = @intCast(@intFromEnum(@field(Tag, field.name))),
        };
    }
    types.items[union_index].fields = fields;
    types.items[union_index].tag_type = .{ .@"enum" = .{ .ref = tag_name } };

    const tag_fields = try allocator.alloc(semantic.TypeField, tag_info.fields.len);
    inline for (tag_info.fields, 0..) |field, index| {
        tag_fields[index] = .{ .name = field.name, .value = @intCast(field.value) };
    }
    const integer_tag = try typeNode(allocator, tag_info.tag_type, types, "`" ++ comptime shortTypeName(@typeName(Tag)) ++ "` tag type");
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

test "a nested namespace path reflects with a dotted owner" {
    const Api = struct {
        pub const unicode = struct {
            /// Reports the display width of a codepoint.
            pub fn codepointWidth(cp: u21) u8 {
                return if (cp < 0x1100) 1 else 2;
            }

            pub const grapheme = struct {
                pub fn breaks(before: u21, after: u21) bool {
                    return before != after;
                }
            };
        };
    };
    const declaration = .{
        .root = Api,
        .functions = .{
            .{ .path = "root.unicode.codepointWidth", .params = .{"cp"} },
            .{ .path = "root.unicode.grapheme.breaks" },
        },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), declaration, "text", "zg");

    try std.testing.expectEqualStrings("codepointWidth", document.functions[0].name);
    try std.testing.expectEqualStrings("unicode", document.functions[0].namespace.?);
    try std.testing.expect(document.functions[0].receiver == null);
    try std.testing.expectEqualStrings("zg_unicode_codepoint_width", document.functions[0].symbol);
    try std.testing.expectEqualStrings("cp", document.functions[0].params[0].name);

    try std.testing.expectEqualStrings("breaks", document.functions[1].name);
    try std.testing.expectEqualStrings("unicode.grapheme", document.functions[1].namespace.?);
    try std.testing.expectEqualStrings("zg_unicode_grapheme_breaks", document.functions[1].symbol);
}

test "nested paths resolve only through public container segments" {
    const Api = struct {
        pub const unicode = struct {
            pub fn codepointWidth(cp: u21) u8 {
                return if (cp < 0x1100) 1 else 2;
            }

            pub const grapheme = struct {
                pub fn breaks(before: u21, after: u21) bool {
                    return before != after;
                }
            };
        };

        pub fn topLevel() void {}
    };
    const declaration = .{ .root = Api, .functions = .{.{ .path = "root.topLevel" }} };
    try std.testing.expect(comptime declarationPathExists(declaration, "root.unicode.codepointWidth"));
    try std.testing.expect(comptime declarationPathExists(declaration, "root.unicode.grapheme.breaks"));
    try std.testing.expect(comptime declarationPathExists(declaration, "root.topLevel"));
    try std.testing.expect(!comptime declarationPathExists(declaration, "root.unicode.missing"));
    try std.testing.expect(!comptime declarationPathExists(declaration, "root.missing.codepointWidth"));
    // A function is not a container, so a path cannot continue through one.
    try std.testing.expect(!comptime declarationPathExists(declaration, "root.topLevel.more"));
}

test "recursive discovery is opt-in and stops at the module boundary" {
    const Api = struct {
        pub const osc = struct {
            pub fn parse(byte: u8) u8 {
                return byte;
            }

            /// An alias back to its own container would make an exhaustive
            /// walk loop; discovery only follows declarations written inside.
            pub const Self = @This();
        };

        pub fn topLevel() void {}
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const shallow = try reflect(arena.allocator(), .{ .root = Api, .discover = .public }, "term", "zg");
    try std.testing.expectEqual(@as(usize, 1), shallow.functions.len);
    try std.testing.expectEqualStrings("topLevel", shallow.functions[0].name);

    const deep = try reflect(arena.allocator(), .{ .root = Api, .discover = .recursive }, "term", "zg");
    try std.testing.expectEqual(@as(usize, 2), deep.functions.len);
    try std.testing.expectEqualStrings("topLevel", deep.functions[0].name);
    try std.testing.expectEqualStrings("parse", deep.functions[1].name);
    try std.testing.expectEqualStrings("osc", deep.functions[1].namespace.?);
    try std.testing.expectEqualStrings("zg_osc_parse", deep.functions[1].symbol);
}

test "recursive discovery honours an exclusion on a nested path" {
    const Api = struct {
        pub const osc = struct {
            pub fn parse(byte: u8) u8 {
                return byte;
            }

            pub fn internalHelper() void {}
        };
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Api,
        .discover = .recursive,
        .exclude = .{"root.osc.internalHelper"},
    }, "term", "zg");
    try std.testing.expectEqual(@as(usize, 1), document.functions.len);
    try std.testing.expectEqualStrings("parse", document.functions[0].name);
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

/// An enum a comptime function built: `@typeName` ends in the expression that
/// produced it, so its last dotted segment is not a name at all. This is the
/// shape `lib.Enum(...)` has in real third-party Zig libraries.
fn GeneratedEnum(comptime names: []const []const u8) type {
    _ = names;
    return enum(u8) { block, bar };
}

const generated_enum_names = [_][]const u8{ "block", "bar", "underline", "hollow" };

test "a registered enum keeps its name wherever a signature reaches it" {
    const Style = GeneratedEnum(generated_enum_names[0..2]);
    const Fixture = struct {
        pub fn current() Style {
            unreachable;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .name = "CursorStyle", .type = Style, .repr = .enumeration }},
        .functions = .{.{ .path = "root.current" }},
    }, "cursor", "zg");

    try std.testing.expectEqual(@as(usize, 1), document.types.len);
    try std.testing.expectEqual(semantic.TypeKind.@"enum", document.types[0].kind);
    try std.testing.expectEqualStrings("CursorStyle", document.types[0].name);
    try std.testing.expectEqualStrings("block", document.types[0].fields[0].name);
    // The signature must reach the registered declaration by Zig path rather
    // than appending a second one named from `@typeName`.
    try std.testing.expectEqualStrings("CursorStyle", document.functions[0].@"return".@"enum".ref);
}

test "an unregistered generated enum is named from @typeName and rejected downstream" {
    const Style = GeneratedEnum(generated_enum_names[0..2]);
    const Fixture = struct {
        pub fn current() Style {
            unreachable;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .functions = .{.{ .path = "root.current" }},
    }, "cursor", "zg");

    // Reflection still records what it saw; `ZIGO021` is what refuses it, and
    // its message points at the Zig path recorded here.
    try std.testing.expect(!naming.isGoIdentifier(document.types[0].name));
    try std.testing.expect(std.mem.endsWith(u8, document.types[0].zig_path.?, "[0..2])"));
}

test "an allocator parameter is injected rather than exposed" {
    const Fixture = struct {
        const Store = opaque {};
        pub fn open(gpa: std.mem.Allocator, name: []const u8) error{OutOfMemory}!*Store {
            _ = gpa;
            _ = name;
            unreachable;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .allocator = .smp_allocator,
        .root = Fixture,
        .types = .{.{ .name = "Store", .type = Fixture.Store, .repr = .@"opaque" }},
        .functions = .{.{ .path = "root.open", .params = .{ "gpa", "name" } }},
    }, "store", "zg");

    try std.testing.expectEqualStrings("std.heap.smp_allocator", document.allocator.?);
    try std.testing.expectEqual(semantic.Injection.allocator, document.functions[0].params[0].injected.?);
    // Nothing walked the allocator's type: it never reaches C, so it carries
    // the one node that means "no C representation needed".
    try std.testing.expectEqual(semantic.TypeNode.void, document.functions[0].params[0].type);
    try std.testing.expectEqual(@as(?semantic.Injection, null), document.functions[0].params[1].injected);
}

test "a declaration path becomes an expression against the bound module" {
    const Fixture = struct {
        pub const gpa: std.mem.Allocator = undefined;
        pub fn touch(allocator: std.mem.Allocator) void {
            _ = allocator;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .allocator = "gpa",
        .root = Fixture,
        .functions = .{.{ .path = "root.touch", .params = .{"allocator"} }},
    }, "store", "zg");

    try std.testing.expectEqualStrings("target.gpa", document.allocator.?);
}

test "a value-returning init is boxed into a caller-owned handle" {
    const Fixture = struct {
        const Terminal = struct {
            columns: u32,

            pub fn init(gpa: std.mem.Allocator, columns: u32) error{Invalid}!Terminal {
                _ = gpa;
                return .{ .columns = columns };
            }

            pub fn deinit(self: *Terminal) void {
                _ = self;
            }
        };
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .allocator = .smp_allocator,
        .root = Fixture,
        .types = .{.{ .type = Fixture.Terminal, .repr = .@"opaque" }},
        .functions = .{
            .{ .path = "Terminal.init", .params = .{ "gpa", "columns" } },
            .{ .path = "Terminal.deinit" },
        },
    }, "terminal", "zg");

    // `Terminal.init` returns a `Terminal`, which has no C representation. It
    // reaches the IR as `!*Terminal` because the shim owns the storage.
    const init_fn = document.functions[0];
    try std.testing.expectEqual(semantic.Boxed.create, init_fn.boxed.?);
    try std.testing.expectEqual(semantic.Ownership.caller, init_fn.ownership);
    try std.testing.expectEqualStrings("Terminal", init_fn.@"return".error_union.payload.opaque_ptr.ref);
    try std.testing.expectEqualStrings("Invalid", init_fn.@"return".error_union.error_set[0]);
    // The allocator parameter still disappears from every generated signature.
    try std.testing.expectEqual(semantic.Injection.allocator, init_fn.params[0].injected.?);
    try std.testing.expectEqual(semantic.Boxed.destroy, document.functions[1].boxed.?);
    try std.testing.expectEqualStrings("Terminal", document.constructors[0].type);
}

test "without an allocator a value-returning init is left alone" {
    const Fixture = struct {
        const Terminal = struct {
            columns: u32,

            pub fn init(columns: u32) Terminal {
                return .{ .columns = columns };
            }
        };
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .type = Fixture.Terminal, .repr = .@"opaque" }},
        .functions = .{.{ .path = "Terminal.init", .params = .{"columns"} }},
    }, "terminal", "zg");

    // Left as the value struct it is, so the diagnostic the author sees names
    // the struct rather than a lifetime decision zigo made for them.
    try std.testing.expectEqual(@as(?semantic.Boxed, null), document.functions[0].boxed);
    try std.testing.expectEqualStrings("Terminal", document.functions[0].@"return".value_struct.ref);
}

test "std.Io.Writer and std.Io.Reader parameters reflect as stream nodes" {
    const Fixture = struct {
        pub fn dump(w: *std.Io.Writer) error{WriteFailed}!void {
            try w.writeAll("x");
        }
        pub fn load(r: *std.Io.Reader) error{ReadFailed}!usize {
            return r.discardRemaining() catch error.ReadFailed;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .functions = .{
            .{ .path = "root.dump", .params = .{"w"} },
            .{ .path = "root.load", .params = .{"r"}, .param_meta = .{ .r = .{ .buffer = 8192 } } },
        },
    }, "stream", "zg");

    try std.testing.expectEqual(
        semantic.StreamDirection.writer,
        document.functions[0].params[0].type.io_stream.direction,
    );
    // An unset buffer stays absent from the document; the default lives in one
    // place rather than being baked into every reflection.
    try std.testing.expectEqual(@as(?u32, null), document.functions[0].params[0].buffer);
    try std.testing.expectEqual(semantic.default_stream_buffer, document.functions[0].params[0].bufferSize());
    try std.testing.expectEqual(
        semantic.StreamDirection.reader,
        document.functions[1].params[0].type.io_stream.direction,
    );
    try std.testing.expectEqual(@as(u32, 8192), document.functions[1].params[0].bufferSize());
}
