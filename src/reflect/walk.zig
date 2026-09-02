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
    // What `.constructs` and `.destroys` claimed, in the order the walk saw
    // it. The pair itself can only be formed once every function is known.
    var pairings: std.ArrayList(Pairing) = .empty;

    if (@hasField(@TypeOf(declaration), "types")) {
        inline for (declaration.types) |entry| {
            const T = entry.type;
            const info = @typeInfo(T);
            const type_name = if (@hasField(@TypeOf(entry), "name")) entry.name else shortTypeName(@typeName(T));
            switch (entry.repr) {
                .@"opaque" => {
                    try types.append(allocator, .{
                        .kind = .@"opaque",
                        .name = type_name,
                        .zig_path = try registeredZigPath(allocator, declaration, T, type_name),
                    });
                    if (@hasField(@TypeOf(entry), "fields")) inline for (entry.fields) |field| {
                        try appendFieldAccessors(allocator, &functions, &types, declaration, prefix, T, type_name, field);
                    };
                },
                .value => switch (info) {
                    .@"struct" => try appendValueStruct(allocator, &types, declaration, T, type_name, try registeredZigPath(allocator, declaration, T, type_name)),
                    else => @compileError("zigo value type entries must name a struct"),
                },
                // An enum registered here is not walked for declarations --
                // like a callback entry, it exists to name a type, not to
                // contribute functions. What it buys is the `.name`: an enum
                // built by a comptime function has a `@typeName` that ends in
                // the expression that built it, and no name of its own.
                .enumeration => switch (info) {
                    .@"enum" => try appendEnum(allocator, &types, declaration, T, type_name, comptime enumOpenOptIn(entry), try registeredZigPath(allocator, declaration, T, type_name)),
                    else => @compileError("zigo enumeration type entries must name an enum"),
                },
                .tagged_union => switch (info) {
                    .@"union" => |union_info| {
                        if (union_info.tag_type == null) @compileError("zigo tagged_union type entries must name a tagged union");
                        try appendTaggedUnion(allocator, &types, declaration, T, type_name, comptime accessStrategy(entry), comptime omittedVariants(entry), try registeredZigPath(allocator, declaration, T, type_name));
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
                        .zig_path = try registeredZigPath(allocator, declaration, T, type_name),
                    });
                },
                else => @compileError("zigo type repr must be .opaque, .value, .enumeration, .tagged_union, or .callback"),
            }
            if (entry.repr != .@"opaque" and @hasField(@TypeOf(entry), "fields"))
                @compileError("zigo `.fields` metadata is supported only on `.repr = .opaque` type entries");
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
                    try discoverContainer(allocator, &functions, &types, &pairings, declaration, prefix, entry.type, comptime typeEntryName(entry), comptime typeEntryName(entry));
            }
        }
        try discoverContainer(allocator, &functions, &types, &pairings, declaration, prefix, declaration.root, null, "root");
    } else {
        inline for (declaration.functions) |entry| {
            try appendSelectedEntry(allocator, &functions, &types, &pairings, declaration, prefix, entry, null, null);
        }
    }

    var constructors: std.ArrayList(semantic.Constructor) = .empty;
    // A binding that said which type a function makes and which unmakes it is
    // paired on that, wherever the two are declared and whatever they are
    // called. The name rule below is what a binding that said nothing gets.
    for (pairings.items) |claim| {
        if (claim.kind != .constructs) continue;
        if (findPairing(pairings.items, .constructs, claim.type).? != claim.index)
            return pairingIssue(allocator, "two functions declare `.constructs = \"{s}\"`", .{claim.type});
        const destructor_index = findPairing(pairings.items, .destroys, claim.type) orelse
            return pairingIssue(allocator, "`.constructs = \"{s}\"` has no function declaring `.destroys = \"{s}\"`", .{ claim.type, claim.type });
        try pair(allocator, &constructors, functions.items, claim.index, destructor_index, claim.type);
    }
    for (pairings.items) |claim| {
        if (claim.kind != .destroys) continue;
        if (findPairing(pairings.items, .destroys, claim.type).? != claim.index)
            return pairingIssue(allocator, "two functions declare `.destroys = \"{s}\"`", .{claim.type});
        if (findPairing(pairings.items, .constructs, claim.type) == null)
            return pairingIssue(allocator, "`.destroys = \"{s}\"` has no function declaring `.constructs = \"{s}\"`", .{ claim.type, claim.type });
    }
    for (functions.items, 0..) |*function, index| {
        if (!isConstructorName(function.name)) continue;
        const type_name = returnedOpaqueName(function.@"return") orelse continue;
        // An explicit claim already settled this type, and settled it against
        // the declarations rather than against their spelling.
        if (findPairing(pairings.items, .constructs, type_name) != null) continue;
        for (functions.items, 0..) |destructor, destructor_index| {
            if (destructor.field_access != null) continue;
            if (destructor.receiver == null or !std.mem.eql(u8, destructor.receiver.?, type_name)) continue;
            if (!isDestructorName(destructor.name)) continue;
            try pair(allocator, &constructors, functions.items, index, destructor_index, type_name);
            break;
        }
    }

    const packages = try reflectPackages(allocator, declaration, types.items, functions.items);

    return .{
        .allocator = comptime injectionExpression(declaration, "allocator"),
        .constructors = try constructors.toOwnedSlice(allocator),
        .functions = try functions.toOwnedSlice(allocator),
        .io = comptime injectionExpression(declaration, "io"),
        .package = package_name,
        .packages = if (packages.len == 0) null else packages,
        .prefix = prefix,
        .types = try types.toOwnedSlice(allocator),
        .zig_version = @import("builtin").zig_version_string,
    };
}

fn appendSelectedEntry(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(semantic.SemanticFn),
    types: *std.ArrayList(semantic.TypeDecl),
    pairings: *std.ArrayList(Pairing),
    comptime declaration: anytype,
    prefix: []const u8,
    comptime entry: anytype,
    comptime inherited_receiver: ?[]const u8,
    comptime inherited_prefix: ?[]const u8,
) !void {
    if (comptime isStringEntry(@TypeOf(entry))) {
        return appendSelectedPath(allocator, functions, types, pairings, declaration, prefix, entry, .{}, inherited_receiver, inherited_prefix);
    }
    if (@hasField(@TypeOf(entry), "functions")) {
        inline for (entry.functions) |nested| {
            try appendSelectedEntry(allocator, functions, types, pairings, declaration, prefix, nested, entry.receiver, entry.strip_prefix);
        }
        return;
    }
    try appendSelectedPath(allocator, functions, types, pairings, declaration, prefix, entry.path, entry, inherited_receiver, inherited_prefix);
}

fn appendSelectedPath(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(semantic.SemanticFn),
    types: *std.ArrayList(semantic.TypeDecl),
    pairings: *std.ArrayList(Pairing),
    comptime declaration: anytype,
    prefix: []const u8,
    comptime path: []const u8,
    comptime metadata: anytype,
    comptime inherited_receiver: ?[]const u8,
    comptime inherited_prefix: ?[]const u8,
) !void {
    const owner = comptime pathOwner(path);
    const member = comptime pathMember(path);
    try appendFunction(
        allocator,
        functions,
        types,
        pairings,
        declaration,
        prefix,
        member,
        @field(comptime pathContainer(declaration, owner), member),
        metadata,
        owner,
        comptime if (@hasField(@TypeOf(metadata), "receiver")) metadata.receiver else inherited_receiver,
        inherited_prefix,
    );
}

fn appendFieldAccessors(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(semantic.SemanticFn),
    types: *std.ArrayList(semantic.TypeDecl),
    comptime declaration: anytype,
    prefix: []const u8,
    comptime Owner: type,
    owner_name: []const u8,
    comptime metadata: anytype,
) !void {
    if (!@hasField(@TypeOf(metadata), "path"))
        @compileError("zigo field entries require `.path`");
    const path = metadata.path;
    const resolved = comptime fieldPathType(Owner, path);
    if (resolved == null) return fieldAccessIssue(allocator, path, comptime fieldPathOffendingType(Owner, path));
    const Leaf = resolved.?;
    if (!comptime supportedFieldLeaf(declaration, Leaf))
        return fieldAccessIssue(allocator, path, Leaf);
    if (@hasField(@TypeOf(metadata), "set") and metadata.set and !comptime fieldPathWritable(Owner, path))
        return fieldAccessIssue(allocator, path, comptime fieldPathConstPointerType(Owner, path));

    const name = if (@hasField(@TypeOf(metadata), "name")) metadata.name else fieldPathMember(path);
    const field_type = try typeNode(
        allocator,
        declaration,
        Leaf,
        types,
        comptime "field `" ++ path ++ "`",
    );
    try functions.append(allocator, .{
        .doc = if (@hasField(@TypeOf(metadata), "doc")) metadata.doc else null,
        .field_access = .{ .path = path },
        .name = name,
        .params = &.{},
        .receiver = owner_name,
        .@"return" = field_type,
        .symbol = try naming.functionSymbolAlloc(allocator, prefix, owner_name, name),
    });

    if (@hasField(@TypeOf(metadata), "set") and metadata.set) {
        const setter_name = try setterNameAlloc(allocator, name);
        const params = try allocator.alloc(semantic.Parameter, 1);
        params[0] = .{ .name = "v", .name_source = .sidecar, .type = field_type };
        try functions.append(allocator, .{
            .doc = if (@hasField(@TypeOf(metadata), "doc")) metadata.doc else null,
            .field_access = .{ .path = path, .setter = true },
            .name = setter_name,
            .params = params,
            .receiver = owner_name,
            .@"return" = .{ .void = {} },
            .symbol = try naming.functionSymbolAlloc(allocator, prefix, owner_name, setter_name),
        });
    }
}

fn setterNameAlloc(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    if (name.len == 0) return allocator.dupe(u8, "set");
    const result = try allocator.alloc(u8, name.len + 3);
    @memcpy(result[0..3], "set");
    result[3] = std.ascii.toUpper(name[0]);
    @memcpy(result[4..], name[1..]);
    return result;
}

fn fieldPathMember(comptime path: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, path, '.')) |index| path[index + 1 ..] else path;
}

/// Resolve one field segment at a time. A pointer is accepted only between
/// segments, and only when it is a non-optional single pointer to a struct.
fn fieldPathType(comptime Current: type, comptime path: []const u8) ?type {
    if (path.len == 0) return null;
    const Container = switch (@typeInfo(Current)) {
        .pointer => |pointer| if (pointer.size == .one and @typeInfo(pointer.child) == .@"struct") pointer.child else return null,
        .@"struct" => Current,
        else => return null,
    };
    const dot = std.mem.indexOfScalar(u8, path, '.');
    const segment = if (dot) |index| path[0..index] else path;
    if (segment.len == 0 or !@hasField(Container, segment)) return null;
    const Field = @FieldType(Container, segment);
    if (dot) |index| return fieldPathType(Field, path[index + 1 ..]);
    return Field;
}

fn fieldPathOffendingType(comptime Current: type, comptime path: []const u8) ?type {
    const Container = switch (@typeInfo(Current)) {
        .pointer => |pointer| if (pointer.size == .one and @typeInfo(pointer.child) == .@"struct") pointer.child else return Current,
        .@"struct" => Current,
        else => return Current,
    };
    const dot = std.mem.indexOfScalar(u8, path, '.');
    const segment = if (dot) |index| path[0..index] else path;
    if (segment.len == 0 or !@hasField(Container, segment)) return null;
    if (dot) |index| return fieldPathOffendingType(@FieldType(Container, segment), path[index + 1 ..]);
    return null;
}

fn fieldPathConstPointerType(comptime Current: type, comptime path: []const u8) ?type {
    const Container = switch (@typeInfo(Current)) {
        .pointer => |pointer| if (pointer.size == .one and @typeInfo(pointer.child) == .@"struct") blk: {
            if (pointer.is_const) return Current;
            break :blk pointer.child;
        } else return Current,
        .@"struct" => Current,
        else => return Current,
    };
    const dot = std.mem.indexOfScalar(u8, path, '.');
    const segment = if (dot) |index| path[0..index] else path;
    if (segment.len == 0 or !@hasField(Container, segment)) return null;
    if (dot) |index| return fieldPathConstPointerType(@FieldType(Container, segment), path[index + 1 ..]);
    return null;
}

fn fieldPathWritable(comptime Current: type, comptime path: []const u8) bool {
    const Container = switch (@typeInfo(Current)) {
        .pointer => |pointer| if (pointer.size == .one and !pointer.is_const and @typeInfo(pointer.child) == .@"struct") pointer.child else return false,
        .@"struct" => Current,
        else => return false,
    };
    const dot = std.mem.indexOfScalar(u8, path, '.');
    const segment = if (dot) |index| path[0..index] else path;
    if (segment.len == 0 or !@hasField(Container, segment)) return false;
    if (dot) |index| return fieldPathWritable(@FieldType(Container, segment), path[index + 1 ..]);
    return true;
}

fn supportedFieldLeaf(comptime declaration: anytype, comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .bool, .int, .float => true,
        .@"enum" => registeredTypeName(declaration, T, .enumeration) != null,
        else => false,
    };
}

fn fieldAccessIssue(allocator: std.mem.Allocator, comptime path: []const u8, comptime T: ?type) error{ FieldAccess, OutOfMemory } {
    const message = try fieldAccessMessageAlloc(allocator, path, T);
    defer allocator.free(message);
    if (!@import("builtin").is_test) std.debug.print("{s}", .{message});
    return error.FieldAccess;
}

fn fieldAccessMessageAlloc(allocator: std.mem.Allocator, comptime path: []const u8, comptime T: ?type) ![]u8 {
    const detail = if (T) |Field|
        comptime " encounters unsupported type `" ++ @typeName(Field) ++ "`"
    else
        " is unknown or crosses something other than a plain struct or non-optional single pointer";
    return std.fmt.allocPrint(
        allocator,
        "error[ZIGO037]: field path `{s}`{s}\n" ++
            "  hint: paths may cross struct values or non-optional single pointers and must end at a bool, integer, float, or registered enum\n",
        .{ path, detail },
    );
}

test "packages assign explicit functions owning types and longest namespaces" {
    const Api = struct {
        pub const Handle = struct {
            pub fn touch(self: *Handle) void {
                _ = self;
            }
        };
        pub const text = struct {
            pub fn simple() void {}
            pub const unicode = struct {
                pub fn width() void {}
            };
        };
        pub fn rootFn() void {}
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Api,
        .discover = .recursive,
        .types = .{.{ .type = Api.Handle, .repr = .@"opaque" }},
        .packages = .{
            .{ .path = "objects", .types = .{"Handle"} },
            .{ .path = "text", .name = "textual", .namespaces = .{"text"} },
            .{ .path = "unicode", .namespaces = .{"text.unicode"}, .functions = .{"root.rootFn"} },
        },
    }, "sample", "zg");
    try std.testing.expectEqual(@as(usize, 3), document.packages.?.len);
    try std.testing.expectEqualStrings("objects", document.types[0].package.?);
    for (document.functions) |function| {
        if (std.mem.eql(u8, function.name, "touch")) try std.testing.expectEqualStrings("objects", function.package.?);
        if (std.mem.eql(u8, function.name, "simple")) try std.testing.expectEqualStrings("textual", function.package.?);
        if (std.mem.eql(u8, function.name, "width")) try std.testing.expectEqualStrings("unicode", function.package.?);
        if (std.mem.eql(u8, function.name, "rootFn")) try std.testing.expectEqualStrings("unicode", function.package.?);
    }
}

test "packages reject invalid paths and missing selectors" {
    const Api = struct {
        pub fn ping() void {}
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.PackageDeclaration, reflect(arena.allocator(), .{
        .root = Api,
        .functions = .{.{ .path = "root.ping" }},
        .packages = .{.{ .path = "../bad" }},
    }, "sample", "zg"));
    try std.testing.expectError(error.PackageDeclaration, reflect(arena.allocator(), .{
        .root = Api,
        .functions = .{.{ .path = "root.ping" }},
        .packages = .{.{ .path = "tools", .types = .{"Missing"} }},
    }, "sample", "zg"));
}

fn reflectPackages(
    allocator: std.mem.Allocator,
    comptime declaration: anytype,
    types: []semantic.TypeDecl,
    functions: []semantic.SemanticFn,
) ![]const semantic.Package {
    if (!@hasField(@TypeOf(declaration), "packages")) return &.{};
    var packages: std.ArrayList(semantic.Package) = .empty;
    inline for (declaration.packages) |entry| {
        const name = if (@hasField(@TypeOf(entry), "name")) entry.name else blk: {
            const base = std.fs.path.basename(entry.path);
            break :blk try naming.snakeAlloc(allocator, base);
        };
        if (!semantic.validPackagePath(entry.path)) return packageIssue("invalid package path `{s}`", .{entry.path});
        if (!naming.isGoIdentifier(name)) return packageIssue("package name `{s}` is not a valid Go identifier", .{name});
        for (packages.items) |previous| {
            if (std.mem.eql(u8, previous.path, entry.path)) return packageIssue("duplicate package path `{s}`", .{entry.path});
            if (std.mem.eql(u8, previous.name, name)) return packageIssue("duplicate package name `{s}`", .{name});
        }
        try packages.append(allocator, .{
            .doc = if (@hasField(@TypeOf(entry), "doc")) entry.doc else null,
            .name = name,
            .path = entry.path,
        });
    }

    inline for (declaration.packages, 0..) |entry, package_index| {
        if (@hasField(@TypeOf(entry), "types")) inline for (entry.types) |selector| {
            var found = false;
            for (types) |*type_decl| if (std.mem.eql(u8, type_decl.name, selector)) {
                if (type_decl.package != null) return packageIssue("type `{s}` is assigned to more than one package", .{selector});
                type_decl.package = packages.items[package_index].name;
                found = true;
            };
            if (!found) return packageIssue("package type selector `{s}` names no declaration", .{selector});
        };
    }

    inline for (declaration.packages, 0..) |entry, package_index| {
        if (@hasField(@TypeOf(entry), "functions")) inline for (entry.functions) |selector| {
            var found = false;
            for (functions) |*function| if (functionMatchesSelector(function.*, selector)) {
                const owned = function.receiver orelse function.goOwner();
                if (owned) |owner| if (typePackage(types, owner)) |owner_package| {
                    if (!std.mem.eql(u8, owner_package, packages.items[package_index].name))
                        return packageIssue("function `{s}` cannot be split from owning type `{s}`", .{ selector, owner });
                };
                if (function.package != null) return packageIssue("function `{s}` is assigned to more than one package", .{selector});
                function.package = packages.items[package_index].name;
                found = true;
            };
            if (!found) return packageIssue("package function selector `{s}` names no declaration", .{selector});
        };
    }

    for (functions) |*function| {
        if (function.receiver orelse function.goOwner()) |owner| if (typePackage(types, owner)) |owner_package| {
            if (function.package) |explicit| if (!std.mem.eql(u8, explicit, owner_package))
                return packageIssue("function `{s}` cannot be split from owning type `{s}`", .{ function.name, owner });
            function.package = owner_package;
            continue;
        };
        if (function.package != null) continue;
        var best_name: ?[]const u8 = null;
        var best_length: usize = 0;
        inline for (declaration.packages, 0..) |entry, package_index| {
            if (@hasField(@TypeOf(entry), "namespaces")) inline for (entry.namespaces) |prefix| {
                if (function.namespace) |namespace| if (namespaceMatches(namespace, prefix) and prefix.len > best_length) {
                    best_length = prefix.len;
                    best_name = packages.items[package_index].name;
                };
            };
        }
        function.package = best_name;
    }
    return packages.toOwnedSlice(allocator);
}

fn packageIssue(comptime detail: []const u8, args: anytype) error{PackageDeclaration} {
    if (!@import("builtin").is_test) std.debug.print("error[ZIGO031]: " ++ detail ++ "\n  hint: each `.packages` entry must uniquely select existing declarations and keep owned functions with their type\n", args);
    return error.PackageDeclaration;
}

fn typePackage(types: []const semantic.TypeDecl, name: []const u8) ?[]const u8 {
    for (types) |type_decl| if (std.mem.eql(u8, type_decl.name, name)) return type_decl.package;
    return null;
}

fn namespaceMatches(namespace: []const u8, prefix: []const u8) bool {
    return std.mem.eql(u8, namespace, prefix) or (std.mem.startsWith(u8, namespace, prefix) and namespace.len > prefix.len and namespace[prefix.len] == '.');
}

fn functionMatchesSelector(function: semantic.SemanticFn, selector: []const u8) bool {
    if (function.zig_path) |path| if (std.mem.eql(u8, path, selector)) return true;
    if (function.receiver orelse function.namespace) |owner| {
        if (selector.len == owner.len + function.name.len + 1 and std.mem.startsWith(u8, selector, owner) and selector[owner.len] == '.' and std.mem.endsWith(u8, selector, function.name)) return true;
        if (selector.len == owner.len + function.name.len + 6 and std.mem.startsWith(u8, selector, "root.") and std.mem.endsWith(u8, selector, function.name)) return true;
        return false;
    }
    return (std.mem.eql(u8, selector, function.name) or (std.mem.startsWith(u8, selector, "root.") and std.mem.eql(u8, selector[5..], function.name)));
}

/// Records one constructor pair: the document gains the pairing, Go groups the
/// constructor under the type it makes, and the storage a boxed constructor
/// allocated becomes the destructor's to free.
fn pair(
    allocator: std.mem.Allocator,
    constructors: *std.ArrayList(semantic.Constructor),
    functions: []semantic.SemanticFn,
    init_index: usize,
    deinit_index: usize,
    type_name: []const u8,
) !void {
    const constructor = &functions[init_index];
    try constructors.append(allocator, .{
        .deinit = functions[deinit_index].name,
        .init = constructor.name,
        .type = type_name,
    });
    // Go groups the constructor under the type it makes; the Zig call path
    // stays where the function is actually declared, so a root-level
    // `newTerminal` is still called as `target.newTerminal`.
    if (!std.mem.eql(u8, constructor.namespace orelse "", type_name)) constructor.go_owner = type_name;
    constructor.ownership = .caller;
    // The storage the shim allocated is the shim's to free, so the paired
    // destructor runs the Zig `deinit` and then destroys it.
    if (constructor.boxed == .create) functions[deinit_index].boxed = .destroy;
}

/// The index of the function that claimed this half of a type's pairing.
fn findPairing(pairings: []const Pairing, kind: @FieldType(Pairing, "kind"), type_name: []const u8) ?usize {
    for (pairings) |claim| {
        if (claim.kind == kind and std.mem.eql(u8, claim.type, type_name)) return claim.index;
    }
    return null;
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
    pairings: *std.ArrayList(Pairing),
    comptime declaration: anytype,
    prefix: []const u8,
    comptime source_name: []const u8,
    comptime function_value: anytype,
    comptime metadata: anytype,
    comptime discovered_owner: ?[]const u8,
    comptime explicit_receiver: ?[]const u8,
    comptime strip_prefix: ?[]const u8,
) !void {
    const info = switch (@typeInfo(@TypeOf(function_value))) {
        .@"fn" => |info| info,
        else => @compileError("zigo function entry must contain a function"),
    };
    // `.path` addresses the declaration; `.name` only renames it on the Go
    // side, so there is still exactly one way to say which function is meant.
    const stripped_name: ?[]const u8 = comptime if (strip_prefix) |value| naming.stripFunctionPrefix(source_name, value) else source_name;
    if (strip_prefix != null and stripped_name == null)
        return receiverIssue(allocator, "function `{s}` does not begin with group prefix `{s}`", .{ source_name, strip_prefix.? });
    const function_name = if (@hasField(@TypeOf(metadata), "name")) metadata.name else stripped_name orelse unreachable;
    // The receiver is the first parameter Go would see: an injected
    // `std.mem.Allocator` or `std.Io` ahead of the handle never reaches the
    // C signature, so it does not stop the function from being a method.
    const inferred_receiver_index = comptime receiverIndex(info, declaration);
    const receiver_index = comptime if (explicit_receiver != null) firstNonInjectedIndex(info) else inferred_receiver_index;
    if (explicit_receiver) |expected| {
        const actual = comptime if (receiver_index) |index| receiverNameAt(info, declaration, index) else null;
        if (actual == null or !std.mem.eql(u8, actual.?, expected))
            return receiverIssue(allocator, "function `{s}` declares `.receiver = \"{s}\"` but its first non-injected parameter is not `*{s}` or `*const {s}`", .{ source_name, expected, expected, expected });
    }
    const receiver: ?[]const u8 = comptime explicit_receiver orelse if (receiver_index) |index| receiverNameAt(info, declaration, index) else null;
    // What the message calls the declaration: the owner it was reached through
    // plus the source name, which is the spelling the binding's `.path` uses.
    const owner_label = comptime if (receiver) |value|
        value ++ "."
    else if (discovered_owner) |value| value ++ "." else "";
    const function_label = source_name;
    const has_sidecar = @hasField(@TypeOf(metadata), "params");
    // `.params` names what Go sees, so the count it has to match leaves out
    // the receiver and every injected argument. Saying so here, before the
    // names are indexed, is what keeps a short list from failing as a
    // comptime tuple index inside zigo instead of as a binding error.
    if (comptime has_sidecar and metadata.params.len != exposedParamCount(info, receiver_index)) {
        return paramNameCountMismatch(comptime paramNameCountMessage(
            owner_label ++ function_label,
            metadata.params.len,
            exposedParamCount(info, receiver_index),
        ));
    }
    const params = try allocator.alloc(semantic.Parameter, comptime concreteParamCount(info, receiver_index));
    inline for (info.params, 0..) |param, param_index| {
        if (receiver_index != null and param_index == receiver_index.?) continue;
        if (info.is_generic) continue;
        if (param.is_generic or param.type == null) continue;
        const output_index = comptime concreteParamIndex(info, receiver_index, param_index);
        const injection = comptime injectionFor(param.type.?);
        // Where this parameter falls in `.params`, which counts only the
        // parameters Go is given.
        const sidecar_index = comptime exposedParamIndex(info, receiver_index, param_index);
        const named_by_sidecar = comptime injection == null and has_sidecar and sidecar_index < metadata.params.len;
        // An injected parameter is never named by the binding -- it has no
        // C parameter to name -- so it carries the name of what fills it,
        // which is what a diagnostic about it has to say anyway.
        const parameter_name = if (comptime injection) |value|
            @tagName(value)
        else if (named_by_sidecar)
            metadata.params[sidecar_index]
        else
            try std.fmt.allocPrint(allocator, "p{d}", .{output_index});
        // The same name as a comptime string, for the messages `typeNode`
        // builds while walking this parameter.
        const parameter_label = comptime if (named_by_sidecar)
            metadata.params[sidecar_index]
        else
            std.fmt.comptimePrint("p{d}", .{output_index});
        // The cancellation flag is opt-in by name rather than by type: the
        // meta is what says "give Go a `ctx` and poll this", and the type
        // check below is what makes it sound. Recognising it here keeps
        // `typeNode` from rejecting `*const std.atomic.Value(u32)` as an
        // unregistered struct pointer and reporting the wrong thing.
        const names_cancel = comptime named_by_sidecar and @hasField(@TypeOf(metadata), "cancel") and
            std.mem.eql(u8, metadata.cancel.param, metadata.params[sidecar_index]);
        const is_cancel_flag = comptime names_cancel and isCancelFlag(param.type.?);
        // An injected parameter never reaches C, so it is not walked as a
        // type: `std.mem.Allocator` is a struct with a vtable pointer, and
        // reflecting it would fail long before validation could explain why.
        const parameter_type = if (injection != null or names_cancel) semantic.TypeNode{
            .void = {},
        } else try typeNode(allocator, declaration, param.type.?, types, comptime std.fmt.comptimePrint(
            "`{s}{s}` parameter `{s}`",
            .{ owner_label, function_label, parameter_label },
        ));
        var reflected: semantic.Parameter = .{
            .cancel = if (names_cancel) true else null,
            .injected = injection,
            .name = parameter_name,
            .name_source = if (named_by_sidecar) .sidecar else .fallback,
            .type = parameter_type,
        };
        if (named_by_sidecar and @hasField(@TypeOf(metadata), "param_meta")) {
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
        // A cancel parameter whose spelling did not match keeps the `void`
        // above, and validation names it. One that did becomes its own node.
        if (is_cancel_flag) reflected.type = .{ .cancel_flag = {} };
        // The sentinel is part of the Zig type, so it remains a C string even
        // when a declaration sidecar omits a semantic hint.
        if (!names_cancel and isSentinelBytePointer(param.type.?)) reflected.semantic = .c_string;
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
    const boxed_type = comptime boxedConstructorName(
        declaration,
        info,
        function_name,
        if (@hasField(@TypeOf(metadata), "constructs")) metadata.constructs else null,
    );
    const reflected_return = if (boxed_type) |type_name| blk: {
        const payload = try allocator.create(semantic.TypeNode);
        payload.* = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = type_name } };
        break :blk semantic.TypeNode{ .error_union = .{
            .error_set = comptime boxedErrorNames(info),
            .payload = payload,
        } };
    } else if (info.return_type) |return_type|
        try typeNode(allocator, declaration, return_type, types, comptime std.fmt.comptimePrint("`{s}{s}` return value", .{ owner_label, function_label }))
    else
        semantic.TypeNode{ .void = {} };
    var reflected_function: semantic.SemanticFn = .{
        .boxed = if (boxed_type != null) .create else null,
        .has_comptime_params = if (info.is_generic) true else null,
        .name = function_name,
        .namespace = if (receiver == null) discovered_owner else null,
        .params = params,
        .receiver = receiver,
        // The shim passes `self` where Zig declared it; only injected
        // arguments can sit ahead of it, and they are counted here.
        .receiver_at = comptime if (receiver_index != null and receiver_index.? != 0) receiver_index.? else null,
        .@"return" = reflected_return,
        .symbol = try naming.functionSymbolAlloc(allocator, prefix, receiver orelse discovered_owner, function_name),
        .zig_path = comptime zigCallPath(receiver, discovered_owner, source_name, function_name),
    };
    if (@hasField(@TypeOf(metadata), "child_of_receiver") and metadata.child_of_receiver)
        reflected_function.child_of_receiver = true;
    if (boxed_type != null) reflected_function.ownership = .caller;
    if (@hasField(@TypeOf(metadata), "semantic")) reflected_function.return_semantic = metadata.semantic;
    if (@hasField(@TypeOf(metadata), "returns")) {
        reflected_function.ownership = metadata.returns;
        if (metadata.returns == .borrowed) reflected_function.borrowed_return = true;
    }
    // `.release` addresses the freeing function the same way `.path` does, so
    // the last segment names it inside the generated document.
    if (@hasField(@TypeOf(metadata), "release")) reflected_function.release = comptime pathMember(metadata.release);
    if (@hasField(@TypeOf(metadata), "cancel")) reflected_function.cancel = metadata.cancel.param;
    if (info.return_type) |return_type| {
        if (isSentinelBytePointer(return_type)) reflected_function.return_semantic = .c_string;
    }
    // A binding pairs a constructor with a destructor by naming the type they
    // make and unmake. The claim is checked against the signature here, where
    // the declaration is still in hand; the pair is formed once the walk ends.
    if (@hasField(@TypeOf(metadata), "constructs")) {
        const type_name = metadata.constructs;
        if (!comptime isRegisteredHandle(declaration, type_name))
            return pairingIssue(allocator, "`{s}{s}` declares `.constructs = \"{s}\"`, which is not a registered opaque type", .{ owner_label, function_label, type_name });
        const returned = returnedOpaqueName(reflected_function.@"return") orelse "";
        if (!std.mem.eql(u8, returned, type_name))
            return pairingIssue(allocator, "`{s}{s}` declares `.constructs = \"{s}\"` but does not return `*{s}`", .{ owner_label, function_label, type_name, type_name });
        try pairings.append(allocator, .{ .index = functions.items.len, .kind = .constructs, .type = type_name });
    }
    if (@hasField(@TypeOf(metadata), "destroys")) {
        const type_name = metadata.destroys;
        if (!comptime isRegisteredHandle(declaration, type_name))
            return pairingIssue(allocator, "`{s}{s}` declares `.destroys = \"{s}\"`, which is not a registered opaque type", .{ owner_label, function_label, type_name });
        if (!std.mem.eql(u8, reflected_function.receiver orelse "", type_name))
            return pairingIssue(allocator, "`{s}{s}` declares `.destroys = \"{s}\"` but does not take `*{s}` as its first parameter after any injected argument", .{ owner_label, function_label, type_name, type_name });
        if (reflected_function.@"return" != .void)
            return pairingIssue(allocator, "`{s}{s}` declares `.destroys = \"{s}\"` but does not return void", .{ owner_label, function_label, type_name });
        try pairings.append(allocator, .{ .index = functions.items.len, .kind = .destroys, .type = type_name });
    }
    try functions.append(allocator, reflected_function);
}

/// One half of a `.constructs`/`.destroys` claim, and the function that made
/// it.
const Pairing = struct {
    index: usize,
    kind: enum { constructs, destroys },
    type: []const u8,
};

/// Whether a `.types` entry registers this name as a handle, which is the only
/// thing a constructor pair can be about.
fn isRegisteredHandle(comptime declaration: anytype, comptime type_name: []const u8) bool {
    if (!@hasField(@TypeOf(declaration), "types")) return false;
    inline for (declaration.types) |entry| {
        if (isHandleRepr(entry.repr) and std.mem.eql(u8, typeEntryName(entry), type_name)) return true;
    }
    return false;
}

/// What a `.constructs`/`.destroys` claim the signatures do not support is
/// told. Like `ZIGO027`, this is raised while reflecting, before there is a
/// `semantic.json` for the generator's own diagnostics to point at.
fn pairingIssue(allocator: std.mem.Allocator, comptime detail: []const u8, args: anytype) error{ ConstructorPairing, OutOfMemory } {
    const message = try pairingMessageAlloc(allocator, detail, args);
    defer allocator.free(message);
    if (!@import("builtin").is_test) std.debug.print("{s}", .{message});
    return error.ConstructorPairing;
}

fn pairingMessageAlloc(allocator: std.mem.Allocator, comptime detail: []const u8, args: anytype) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "error[ZIGO028]: " ++ detail ++ "\n" ++
            "  hint: `.constructs` and `.destroys` name one registered opaque type each, on the function that returns `*T` and the function that takes it\n",
        args,
    );
}

/// Explicit receiver and receiver-group metadata is checked while the Zig
/// signature is still available, before semantic.json exists.
fn receiverIssue(allocator: std.mem.Allocator, comptime detail: []const u8, args: anytype) error{ ReceiverMetadata, OutOfMemory } {
    const message = try receiverMessageAlloc(allocator, detail, args);
    defer allocator.free(message);
    if (!@import("builtin").is_test) std.debug.print("{s}", .{message});
    return error.ReceiverMetadata;
}

fn receiverMessageAlloc(allocator: std.mem.Allocator, comptime detail: []const u8, args: anytype) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "error[ZIGO038]: " ++ detail ++ "\n" ++
            "  hint: name a registered opaque type whose pointer is the function's first parameter after any injected `std.mem.Allocator` or `std.Io`\n",
        args,
    );
}

/// Where the shim has to reach to call this declaration, when the owner and
/// the Go name do not already spell it. A handle first parameter makes a
/// function a method in Go wherever it is declared, and `.name` renames it for
/// Go only, so neither says where the Zig declaration lives.
fn zigCallPath(
    comptime receiver: ?[]const u8,
    comptime discovered_owner: ?[]const u8,
    comptime source_name: []const u8,
    comptime function_name: []const u8,
) ?[]const u8 {
    const declared = if (discovered_owner) |owner| owner ++ "." ++ source_name else source_name;
    const owner: ?[]const u8 = if (receiver) |value| value else discovered_owner;
    const derived = if (owner) |value| value ++ "." ++ function_name else function_name;
    return if (std.mem.eql(u8, declared, derived)) null else declared;
}

/// The registered handle name a value-returning constructor is boxed into,
/// or null when this is not one. Boxing needs three things at once: a
/// constructor name, a return of the registered type by value, and an
/// allocator the binding chose to own the storage. Without the allocator the
/// function is left alone, so the rejection the author sees still names the
/// struct rather than a decision zigo made for them.
fn boxedConstructorName(
    comptime declaration: anytype,
    comptime info: std.builtin.Type.Fn,
    comptime function_name: []const u8,
    /// The type `.constructs` named, which says this is a constructor whatever
    /// it is called.
    comptime constructs: ?[]const u8,
) ?[]const u8 {
    if (injectionExpression(declaration, "allocator") == null) return null;
    if (constructs == null and !isConstructorName(function_name)) return null;
    const return_type = info.return_type orelse return null;
    const value_type = switch (@typeInfo(return_type)) {
        .error_union => |error_union| error_union.payload,
        else => return_type,
    };
    if (@typeInfo(value_type) != .@"struct") return null;
    if (!@hasField(@TypeOf(declaration), "types")) return null;
    inline for (declaration.types) |entry| {
        if (entry.repr == .@"opaque" and entry.type == value_type) {
            // A `.constructs` claim about a different type is left alone here
            // so the mismatch is reported against the declaration rather than
            // silently boxed into the wrong handle.
            if (constructs) |claimed| if (!std.mem.eql(u8, claimed, typeEntryName(entry))) return null;
            return typeEntryName(entry);
        }
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
    pairings: *std.ArrayList(Pairing),
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
                if (comptime functionEntryContainsPath(entry, path)) {
                    adjusted = true;
                    _ = try appendDiscoveredEntry(allocator, functions, types, pairings, declaration, prefix, path, candidate.name, value, owner, entry, null, null);
                }
            }
        }
        if (!adjusted) try appendFunction(allocator, functions, types, pairings, declaration, prefix, candidate.name, value, .{}, owner, null, null);
    }
    if (comptime !discoveryRecursive(declaration)) return;
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@TypeOf(value) != type or comptime !isNestedContainer(Container, value)) continue;
        try discoverContainer(
            allocator,
            functions,
            types,
            pairings,
            declaration,
            prefix,
            value,
            comptime if (owner) |parent| parent ++ "." ++ candidate.name else candidate.name,
            path_prefix ++ "." ++ candidate.name,
        );
    }
}

fn functionEntryContainsPath(comptime entry: anytype, comptime path: []const u8) bool {
    if (comptime isStringEntry(@TypeOf(entry))) return std.mem.eql(u8, entry, path);
    if (@hasField(@TypeOf(entry), "functions")) {
        inline for (entry.functions) |nested| if (functionEntryContainsPath(nested, path)) return true;
        return false;
    }
    return std.mem.eql(u8, entry.path, path);
}

fn appendDiscoveredEntry(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(semantic.SemanticFn),
    types: *std.ArrayList(semantic.TypeDecl),
    pairings: *std.ArrayList(Pairing),
    comptime declaration: anytype,
    prefix: []const u8,
    comptime path: []const u8,
    comptime source_name: []const u8,
    comptime function_value: anytype,
    comptime owner: ?[]const u8,
    comptime entry: anytype,
    comptime inherited_receiver: ?[]const u8,
    comptime inherited_prefix: ?[]const u8,
) !bool {
    if (comptime isStringEntry(@TypeOf(entry))) {
        if (!std.mem.eql(u8, entry, path)) return false;
        try appendFunction(allocator, functions, types, pairings, declaration, prefix, source_name, function_value, .{}, owner, inherited_receiver, inherited_prefix);
        return true;
    }
    if (@hasField(@TypeOf(entry), "functions")) {
        var matched = false;
        inline for (entry.functions) |nested| {
            matched = try appendDiscoveredEntry(allocator, functions, types, pairings, declaration, prefix, path, source_name, function_value, owner, nested, entry.receiver, entry.strip_prefix) or matched;
        }
        return matched;
    }
    if (!std.mem.eql(u8, entry.path, path)) return false;
    try appendFunction(allocator, functions, types, pairings, declaration, prefix, source_name, function_value, entry, owner, comptime if (@hasField(@TypeOf(entry), "receiver")) entry.receiver else inherited_receiver, inherited_prefix);
    return true;
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
        inline for (declaration.functions) |entry| validateFunctionEntry(declaration, entry, false);
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

fn validateFunctionEntry(comptime declaration: anytype, comptime entry: anytype, comptime nested: bool) void {
    if (comptime isStringEntry(@TypeOf(entry))) {
        if (!nested) @compileError("zigo function entries require `.path`");
        validateFunctionPath(declaration, entry);
        return;
    }
    if (@hasField(@TypeOf(entry), "functions")) {
        if (nested) @compileError("zigo function groups cannot be nested");
        if (!@hasField(@TypeOf(entry), "receiver") or !@hasField(@TypeOf(entry), "strip_prefix"))
            @compileError("zigo function groups require `.receiver`, `.strip_prefix`, and `.functions`");
        if (@hasField(@TypeOf(entry), "params") or @hasField(@TypeOf(entry), "param_meta"))
            @compileError("zigo function groups put `.params` and `.param_meta` on nested function entries");
        inline for (entry.functions) |child| validateFunctionEntry(declaration, child, true);
        return;
    }
    if (!@hasField(@TypeOf(entry), "path")) @compileError("zigo function entries require `.path`");
    validateFunctionPath(declaration, entry.path);
}

fn validateFunctionPath(comptime declaration: anytype, comptime path: []const u8) void {
    if (!declarationPathExists(declaration, path)) {
        @compileError("zigo path does not name a public function: " ++ path ++
            " (use `root.<name>` for a function in `.root`, or `<Type>.<name>` for one in a registered type)");
    }
    if (countFunctionPath(declaration.functions, path) > 1) @compileError("duplicate zigo function path: " ++ path);
    if (selectorContains(declaration, "exclude", path)) @compileError("zigo path cannot be both listed and excluded: " ++ path);
}

fn countFunctionPath(comptime entries: anytype, comptime path: []const u8) usize {
    var count: usize = 0;
    inline for (entries) |entry| {
        if (comptime isStringEntry(@TypeOf(entry))) {
            if (std.mem.eql(u8, entry, path)) count += 1;
        } else if (@hasField(@TypeOf(entry), "functions")) {
            count += countFunctionPath(entry.functions, path);
        } else if (@hasField(@TypeOf(entry), "path") and std.mem.eql(u8, entry.path, path)) {
            count += 1;
        }
    }
    return count;
}

fn isStringEntry(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .array => |array| array.child == u8,
            else => pointer.size == .slice and pointer.child == u8,
        },
        else => false,
    };
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
    comptime declaration: anytype,
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
                element.* = try typeNode(allocator, declaration, info.child, types, context ++ " (slice element)");
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
                            declaration,
                            parameter_type,
                            types,
                            context ++ std.fmt.comptimePrint(" (callback parameter {d})", .{index}),
                        );
                    }
                    const callback_return = try allocator.create(semantic.TypeNode);
                    const callback_return_type = function_info.return_type orelse
                        @compileError("zigo cannot reflect a generic callback return type, at " ++ context);
                    callback_return.* = try typeNode(allocator, declaration, callback_return_type, types, context ++ " (callback return value)");
                    break :blk .{ .callback = .{
                        .c_callconv = std.meta.eql(function_info.calling_convention, std.builtin.CallingConvention.c),
                        .has_userdata = function_info.params.len != 0 and
                            function_info.params[function_info.params.len - 1].type == usize,
                        .params = callback_params,
                        .ref = registeredTypeName(declaration, T, .callback) orelse callbackNameForPath(types.items, @typeName(T)),
                        .@"return" = callback_return,
                    } };
                }
                const name = registeredTypeName(declaration, info.child, .handle) orelse opaqueNameForPath(types.items, @typeName(info.child)) orelse
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
                element.* = try typeNode(allocator, declaration, info.child, types, context ++ " (slice element)");
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
                const name = registeredTypeName(declaration, child.pointer.child, .handle) orelse opaqueNameForPath(types.items, @typeName(child.pointer.child)) orelse
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
            child_node.* = try typeNode(allocator, declaration, info.child, types, context ++ " (optional child)");
            break :blk .{ .optional = .{ .child = child_node } };
        },
        .error_union => |info| blk: {
            const payload = try allocator.create(semantic.TypeNode);
            payload.* = try typeNode(allocator, declaration, info.payload, types, context ++ " (error payload)");
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
            // Registered identity is the comptime type, not `@typeName`: Zig
            // may truncate generated type names so distinct enums share one.
            if (comptime registeredTypeName(declaration, T, .enumeration)) |name|
                break :blk .{ .@"enum" = .{ .ref = name } };
            const name = shortTypeName(@typeName(T));
            var exists = false;
            for (types.items) |type_declaration| {
                if (std.mem.eql(u8, type_declaration.name, name)) exists = true;
            }
            if (!exists) try appendEnum(allocator, types, declaration, T, name, false, @typeName(T));
            break :blk .{ .@"enum" = .{ .ref = name } };
        },
        .@"struct" => blk: {
            if (comptime registeredTypeName(declaration, T, .value)) |registered_name|
                break :blk .{ .value_struct = .{ .ref = registered_name } };
            const name = shortTypeName(@typeName(T));
            var exists = false;
            for (types.items) |type_declaration| {
                if (std.mem.eql(u8, type_declaration.zig_path orelse "", @typeName(T))) {
                    exists = true;
                    break;
                }
            }
            if (!exists) try appendValueStruct(allocator, types, declaration, T, name, @typeName(T));
            break :blk .{ .value_struct = .{ .ref = name } };
        },
        .@"union" => blk: {
            if (comptime registeredTypeName(declaration, T, .tagged_union)) |registered_name|
                break :blk .{ .value_struct = .{ .ref = registered_name } };
            const name = shortTypeName(@typeName(T));
            for (types.items) |type_declaration| {
                if (type_declaration.kind == .tagged_union and std.mem.eql(u8, type_declaration.zig_path orelse "", @typeName(T))) {
                    break :blk .{ .value_struct = .{ .ref = type_declaration.name } };
                }
            }
            if (@typeInfo(T).@"union".tag_type == null) @compileError("zigo cannot reflect an untagged union, at " ++ context);
            try appendTaggedUnion(allocator, types, declaration, T, name, .projection, &.{}, @typeName(T));
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

/// The two parameter filters the walk needs. `concrete` drops the receiver and
/// anything reflection cannot name a type for; `exposed` additionally drops
/// what zigo injects, because an injected argument has no C parameter and no
/// Go argument, so a binding that had to name it would be naming a value it
/// never passes.
const ParamFilter = enum { concrete, exposed };

/// Counts matching parameters, or -- given a `target_index` -- how many precede
/// it, which is that parameter's slot in the filtered list.
fn paramSlot(
    comptime info: std.builtin.Type.Fn,
    comptime receiver_index: ?usize,
    comptime filter: ParamFilter,
    comptime target_index: ?usize,
) usize {
    if (info.is_generic and target_index == null) return 0;
    var count: usize = 0;
    inline for (info.params, 0..) |parameter, index| {
        if (target_index) |target| if (index == target) return count;
        if (receiver_index == index or parameter.is_generic or parameter.type == null) continue;
        if (filter == .exposed and injectionFor(parameter.type.?) != null) continue;
        count += 1;
    }
    if (target_index != null) unreachable;
    return count;
}

fn concreteParamCount(comptime info: std.builtin.Type.Fn, comptime receiver_index: ?usize) usize {
    return paramSlot(info, receiver_index, .concrete, null);
}

fn concreteParamIndex(comptime info: std.builtin.Type.Fn, comptime receiver_index: ?usize, comptime target_index: usize) usize {
    return paramSlot(info, receiver_index, .concrete, target_index);
}

fn exposedParamCount(comptime info: std.builtin.Type.Fn, comptime receiver_index: ?usize) usize {
    return paramSlot(info, receiver_index, .exposed, null);
}

fn exposedParamIndex(comptime info: std.builtin.Type.Fn, comptime receiver_index: ?usize, comptime target_index: usize) usize {
    return paramSlot(info, receiver_index, .exposed, target_index);
}

/// What a `.params` list of the wrong length is told. Reflection runs before
/// there is a `semantic.json` to point at, so the declaration is named by the
/// path the binding used and the text carries the diagnostic code the rest of
/// the generator reports under.
fn paramNameCountMessage(comptime declaration: []const u8, comptime named: usize, comptime exposed: usize) []const u8 {
    return std.fmt.comptimePrint(
        "error[ZIGO027]: `.params` names {d} parameter{s} but `{s}` exposes {d}\n" ++
            "  --> {s}\n" ++
            "  hint: `.params` names only the parameters Go passes: leave out the receiver and any injected `std.mem.Allocator` or `std.Io`\n",
        .{ named, if (named == 1) "" else "s", declaration, exposed, declaration },
    );
}

fn paramNameCountMismatch(comptime message: []const u8) error{ParamNameCount} {
    // The message is the whole diagnostic, so it goes out the moment it is
    // built -- except under `zig test`, where the case that asserts the error
    // would otherwise leave the report itself on the build's stderr.
    if (!@import("builtin").is_test) std.debug.print("{s}", .{message});
    return error.ParamNameCount;
}

/// The index of the receiver parameter: the first parameter that is not an
/// injected argument, when it is a pointer to a registered handle.
fn receiverIndex(comptime info: std.builtin.Type.Fn, comptime declaration: anytype) ?usize {
    inline for (info.params, 0..) |parameter, index| {
        const T = parameter.type orelse return null;
        if (injectionFor(T) != null) continue;
        return if (receiverNameAt(info, declaration, index) != null) index else null;
    }
    return null;
}

fn firstNonInjectedIndex(comptime info: std.builtin.Type.Fn) ?usize {
    inline for (info.params, 0..) |parameter, index| {
        const T = parameter.type orelse return null;
        if (injectionFor(T) == null) return index;
    }
    return null;
}

fn receiverNameAt(comptime info: std.builtin.Type.Fn, comptime declaration: anytype, comptime index: usize) ?[]const u8 {
    const T = info.params[index].type orelse return null;
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

/// The public name attached to an exact registered type. Type equality is the
/// identity source; `@typeName` is only a display path and can be truncated for
/// comptime-generated types.
const RegisteredUse = enum { callback, enumeration, handle, tagged_union, value };

fn registeredTypeName(comptime declaration: anytype, comptime T: type, comptime use: RegisteredUse) ?[]const u8 {
    if (@hasField(@TypeOf(declaration), "types")) {
        inline for (declaration.types) |entry| {
            const matches_repr = switch (use) {
                .callback => entry.repr == .callback,
                .enumeration => entry.repr == .enumeration,
                .handle => isHandleRepr(entry.repr),
                .tagged_union => entry.repr == .tagged_union,
                .value => entry.repr == .value,
            };
            if (matches_repr and entry.type == T) return typeEntryName(entry);
        }
    }
    return null;
}

/// Preserve the ordinary Zig path until two distinct registered types share
/// it. At that point the registered name makes semantic.json paths unique and
/// keeps reports and ABI comparisons deterministic without making paths the
/// source of type identity again.
fn registeredZigPath(
    allocator: std.mem.Allocator,
    comptime declaration: anytype,
    comptime T: type,
    name: []const u8,
) ![]const u8 {
    if (@hasField(@TypeOf(declaration), "types")) {
        inline for (declaration.types) |entry| {
            if (entry.type != T and std.mem.eql(u8, @typeName(entry.type), @typeName(T)))
                return std.fmt.allocPrint(allocator, "{s}#{s}", .{ @typeName(T), name });
        }
    }
    return @typeName(T);
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

/// `.exhaustive = false` on an enum registration is an assertion that the
/// binding deliberately accepts values outside the named tags. The reflected
/// type still records whether Zig itself is exhaustive; validation compares
/// the assertion with that fact.
fn enumOpenOptIn(comptime entry: anytype) bool {
    if (!@hasField(@TypeOf(entry), "exhaustive")) return false;
    return !entry.exhaustive;
}

/// A value struct carries its field types into the IR. Validation needs them
/// to decide whether the struct can cross the C ABI, and lowering needs them
/// to mirror the struct in the C header.
/// One place an enum becomes a `TypeDecl`, whether the binding registered it
/// or a signature reached it.
fn appendEnum(
    allocator: std.mem.Allocator,
    types: *std.ArrayList(semantic.TypeDecl),
    comptime declaration: anytype,
    comptime T: type,
    name: []const u8,
    open: bool,
    zig_path: []const u8,
) !void {
    const info = @typeInfo(T).@"enum";
    const fields = try allocator.alloc(semantic.TypeField, info.fields.len);
    inline for (info.fields, 0..) |field, index| fields[index] = .{ .name = field.name, .value = @intCast(field.value) };
    const tag_type = try typeNode(allocator, declaration, info.tag_type, types, "the tag type of enum `" ++ @typeName(T) ++ "`");
    try types.append(allocator, .{
        .exhaustive = info.is_exhaustive,
        .fields = fields,
        .kind = .@"enum",
        .name = name,
        .open = if (open) true else null,
        .tag_type = tag_type,
        .zig_path = zig_path,
    });
}

fn appendValueStruct(
    allocator: std.mem.Allocator,
    types: *std.ArrayList(semantic.TypeDecl),
    comptime declaration: anytype,
    comptime T: type,
    name: []const u8,
    zig_path: []const u8,
) !void {
    const info = @typeInfo(T).@"struct";
    const index = types.items.len;
    try types.append(allocator, .{
        .backing_type = if (info.layout == .@"packed")
            try typeNode(allocator, declaration, info.backing_integer.?, types, "packed struct backing integer")
        else
            null,
        .kind = .value_struct,
        .layout = switch (info.layout) {
            .@"extern" => .@"extern",
            .@"packed" => .@"packed",
            .auto => null,
        },
        .name = name,
        .zig_path = zig_path,
    });
    // Reflecting a field can append further types, so the declaration is
    // updated by index rather than through a held pointer.
    const fields = try allocator.alloc(semantic.TypeField, info.fields.len);
    inline for (info.fields, 0..) |field, field_index| {
        fields[field_index] = .{
            .name = field.name,
            .type = try typeNode(
                allocator,
                declaration,
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
    comptime declaration: anytype,
    comptime T: type,
    name: []const u8,
    access: semantic.Access,
    omitted_variants: []const []const u8,
    zig_path: []const u8,
) !void {
    const info = @typeInfo(T).@"union";
    const Tag = info.tag_type orelse @compileError("zigo cannot reflect an untagged union");
    const tag_info = @typeInfo(Tag).@"enum";
    const tag_name = try std.fmt.allocPrint(allocator, "{s}Tag", .{name});

    const union_index = types.items.len;
    try types.append(allocator, .{
        .kind = .tagged_union,
        .name = name,
        .omitted_variants = if (omitted_variants.len == 0) null else omitted_variants,
        // The default strategy stays absent from semantic.json, so a type that
        // does not choose one leaves its document unchanged.
        .access = if (access == .projection) null else access,
        .zig_path = zig_path,
    });

    const fields = try allocator.alloc(semantic.TypeField, info.fields.len);
    inline for (info.fields, 0..) |field, index| {
        fields[index] = .{
            .name = field.name,
            .type = try typeNode(
                allocator,
                declaration,
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
    const integer_tag = try typeNode(allocator, declaration, tag_info.tag_type, types, "`" ++ comptime shortTypeName(@typeName(Tag)) ++ "` tag type");
    try types.append(allocator, .{
        .exhaustive = tag_info.is_exhaustive,
        .fields = tag_fields,
        .kind = .@"enum",
        .name = tag_name,
        .omitted_variants = if (omitted_variants.len == 0) null else omitted_variants,
        .tag_type = integer_tag,
        .zig_path = @typeName(Tag),
    });
}

fn omittedVariants(comptime entry: anytype) []const []const u8 {
    if (!@hasField(@TypeOf(entry), "omit_variants")) return &.{};
    return &entry.omit_variants;
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

/// The one Zig spelling a cancellation flag may have. `std.atomic.Value(u32)`
/// rather than `Value(bool)`: the flag is written from a Go goroutine while
/// native code reads it, and Go has no atomic operation on a single byte --
/// `sync/atomic` starts at 32 bits. An `extern struct { raw: u32 }` and a Go
/// `uint32` are the same four bytes on every supported target, so the two
/// sides can share one word without either of them guessing at a layout.
fn isCancelFlag(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer or info.pointer.size != .one) return false;
    return info.pointer.child == std.atomic.Value(u32);
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
    comptime var values: [names.len]u8 = undefined;
    inline for (&values, 0..) |*value, index| value.* = index;
    return @Enum(u8, .exhaustive, names, &values);
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

test "registered generated enums with the same @typeName keep distinct identity" {
    const first_names = [_][]const u8{ "block", "bar", "underline", "hollow" };
    const second_names = [_][]const u8{ "g0", "g1", "g2", "g3" };
    const CursorStyle = GeneratedEnum(first_names[0..4]);
    const CharsetSlot = GeneratedEnum(second_names[0..4]);
    comptime std.debug.assert(std.mem.eql(u8, @typeName(CursorStyle), @typeName(CharsetSlot)));

    const Fixture = struct {
        pub fn configure(slot: CharsetSlot, style: CursorStyle) void {
            _ = slot;
            _ = style;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{
            .{ .name = "CursorStyle", .type = CursorStyle, .repr = .enumeration },
            .{ .name = "CharsetSlot", .type = CharsetSlot, .repr = .enumeration },
        },
        .functions = .{.{ .path = "root.configure", .params = .{ "slot", "style" } }},
    }, "terminal", "zg");

    try std.testing.expectEqualStrings("CharsetSlot", document.functions[0].params[0].type.@"enum".ref);
    try std.testing.expectEqualStrings("CursorStyle", document.functions[0].params[1].type.@"enum".ref);
    try std.testing.expect(!std.mem.eql(u8, document.types[0].zig_path.?, document.types[1].zig_path.?));
    try std.testing.expect(std.mem.endsWith(u8, document.types[0].zig_path.?, "#CursorStyle"));
    try std.testing.expect(std.mem.endsWith(u8, document.types[1].zig_path.?, "#CharsetSlot"));
}

test "a registered non-exhaustive enum records an explicit open opt-in" {
    const EraseDisplay = enum(u8) { below, above, _ };
    const Fixture = struct {
        pub fn echo(value: EraseDisplay) EraseDisplay {
            return value;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .name = "EraseDisplay", .type = EraseDisplay, .repr = .enumeration, .exhaustive = false }},
        .functions = .{.{ .path = "root.echo", .params = .{"value"} }},
    }, "terminal", "zg");

    try std.testing.expect(!document.types[0].exhaustive);
    try std.testing.expectEqual(@as(?bool, true), document.types[0].open);
    const bytes = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"open\": true") != null);
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
        .functions = .{.{ .path = "root.open", .params = .{"name"} }},
    }, "store", "zg");

    try std.testing.expectEqualStrings("std.heap.smp_allocator", document.allocator.?);
    try std.testing.expectEqual(semantic.Injection.allocator, document.functions[0].params[0].injected.?);
    // Nothing walked the allocator's type: it never reaches C, so it carries
    // the one node that means "no C representation needed".
    try std.testing.expectEqual(semantic.TypeNode.void, document.functions[0].params[0].type);
    try std.testing.expectEqual(@as(?semantic.Injection, null), document.functions[0].params[1].injected);
}

test "`.params` names only what Go passes, and a wrong count is reported" {
    const Fixture = struct {
        pub fn freeString(gpa: std.mem.Allocator, str: []const u8) void {
            _ = gpa;
            _ = str;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .allocator = .smp_allocator,
        .root = Fixture,
        .functions = .{.{ .path = "root.freeString", .params = .{"str"} }},
    }, "text", "zg");

    // The injected parameter keeps its place in the Zig call, and carries the
    // name of what fills it rather than one the binding had to invent.
    const params = document.functions[0].params;
    try std.testing.expectEqual(@as(usize, 2), params.len);
    try std.testing.expectEqual(semantic.Injection.allocator, params[0].injected.?);
    try std.testing.expectEqualStrings("allocator", params[0].name);
    try std.testing.expectEqual(semantic.NameSource.fallback, params[0].name_source);
    try std.testing.expectEqualStrings("str", params[1].name);
    try std.testing.expectEqual(semantic.NameSource.sidecar, params[1].name_source);

    // Naming the injected parameter as well is the mistake ZIGO027 explains,
    // rather than a comptime tuple index inside zigo.
    try std.testing.expectError(error.ParamNameCount, reflect(arena.allocator(), .{
        .allocator = .smp_allocator,
        .root = Fixture,
        .functions = .{.{ .path = "root.freeString", .params = .{ "gpa", "str" } }},
    }, "text", "zg"));
}

test "the parameter count message names the declaration and the code" {
    try std.testing.expectEqualStrings(
        \\error[ZIGO027]: `.params` names 2 parameters but `root.freeString` exposes 1
        \\  --> root.freeString
        \\  hint: `.params` names only the parameters Go passes: leave out the receiver and any injected `std.mem.Allocator` or `std.Io`
        \\
    , comptime paramNameCountMessage("root.freeString", 2, 1));
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
        .functions = .{.{ .path = "root.touch" }},
    }, "store", "zg");

    try std.testing.expectEqualStrings("target.gpa", document.allocator.?);
}

test "a root-level constructor keeps its Zig call path while Go groups it" {
    const Fixture = struct {
        const Terminal = opaque {};

        pub fn new(columns: u32) error{Invalid}!*Terminal {
            _ = columns;
            unreachable;
        }

        pub fn destroy(self: *Terminal) void {
            _ = self;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .name = "Terminal", .type = Fixture.Terminal, .repr = .@"opaque" }},
        .functions = .{
            .{ .path = "root.new", .params = .{"columns"} },
            .{ .path = "root.destroy" },
        },
    }, "terminal", "zg");

    try std.testing.expectEqualStrings("Terminal", document.constructors[0].type);
    const constructor = document.functions[0];
    try std.testing.expectEqual(semantic.Ownership.caller, constructor.ownership);
    // Go sees `Terminal`'s constructor; the shim still calls `target.new`.
    try std.testing.expectEqualStrings("Terminal", constructor.goOwner().?);
    try std.testing.expectEqual(@as(?[]const u8, null), constructor.namespace);
    try std.testing.expectEqualStrings("zg_new", constructor.symbol);
}

test "a receiver constructor reflects its dependent lifetime opt-in" {
    const Fixture = struct {
        const Parent = opaque {};
        const Child = opaque {};

        pub fn newChild(parent: *Parent) *Child {
            _ = parent;
            unreachable;
        }

        pub fn freeChild(child: *Child) void {
            _ = child;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{
            .{ .name = "Parent", .type = Fixture.Parent, .repr = .@"opaque" },
            .{ .name = "Child", .type = Fixture.Child, .repr = .@"opaque" },
        },
        .functions = .{
            .{ .path = "root.newChild", .constructs = "Child", .child_of_receiver = true },
            .{ .path = "root.freeChild", .destroys = "Child" },
        },
    }, "handles", "zg");

    try std.testing.expect(document.functions[0].childOfReceiver());
    const json = try document.serialize(arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, json, "\"child_of_receiver\": true") != null);
}

test "`.constructs` and `.destroys` pair functions the name rule never would" {
    const Fixture = struct {
        const Terminal = opaque {};

        pub fn makeTerminal(columns: u32) error{Invalid}!*Terminal {
            _ = columns;
            unreachable;
        }

        pub fn releaseTerminal(self: *Terminal) void {
            _ = self;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .name = "Terminal", .type = Fixture.Terminal, .repr = .@"opaque" }},
        .functions = .{
            .{ .path = "root.makeTerminal", .params = .{"columns"}, .constructs = "Terminal" },
            .{ .path = "root.releaseTerminal", .destroys = "Terminal" },
        },
    }, "terminal", "zg");

    try std.testing.expectEqual(@as(usize, 1), document.constructors.len);
    try std.testing.expectEqualStrings("makeTerminal", document.constructors[0].init);
    try std.testing.expectEqualStrings("releaseTerminal", document.constructors[0].deinit);
    try std.testing.expectEqualStrings("Terminal", document.constructors[0].type);
    try std.testing.expectEqualStrings("Terminal", document.functions[0].goOwner().?);
    try std.testing.expectEqual(semantic.Ownership.caller, document.functions[0].ownership);
    // The shim still reaches the declaration where it lives: no owner, so
    // the name alone spells the call and no override is recorded.
    try std.testing.expectEqual(@as(?[]const u8, null), document.functions[0].namespace);
    try std.testing.expectEqual(@as(?[]const u8, null), document.functions[0].zig_path);
    // The destructor is a method in Go, so its path is the one that moved.
    try std.testing.expectEqualStrings("Terminal", document.functions[1].receiver.?);
    try std.testing.expectEqualStrings("releaseTerminal", document.functions[1].zig_path.?);
}

test "explicit borrowed return is recorded without changing ownership defaults" {
    const Fixture = struct {
        const Parent = opaque {};
        const View = opaque {};

        pub fn view(self: *Parent) ?*View {
            _ = self;
            return null;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{
            .{ .name = "Parent", .type = Fixture.Parent, .repr = .@"opaque" },
            .{ .name = "View", .type = Fixture.View, .repr = .@"opaque" },
        },
        .functions = .{.{ .path = "root.view", .returns = .borrowed }},
    }, "borrowed", "zg");

    try std.testing.expect(document.functions[0].returnsBorrowedHandle());
    try std.testing.expectEqual(semantic.Ownership.borrowed, document.functions[0].ownership);
    const json = try document.serialize(arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, json, "\"borrowed_return\": true") != null);

    const implicit = semantic.SemanticFn{
        .name = "implicit",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "zg_implicit",
    };
    const implicit_json = try std.json.Stringify.valueAlloc(arena.allocator(), implicit, .{ .whitespace = .indent_2, .emit_null_optional_fields = false });
    try std.testing.expect(std.mem.indexOf(u8, implicit_json, "borrowed_return") == null);
}

test "function groups attach free functions and strip their shared prefix" {
    const Fixture = struct {
        const Screen = opaque {};

        pub fn screenSelectAll(screen: *Screen) void {
            _ = screen;
        }

        pub fn screenClearSelection(screen: *const Screen) void {
            _ = screen;
        }

        pub fn screenMove(gpa: std.mem.Allocator, screen: *Screen, count: u32) void {
            _ = gpa;
            _ = screen;
            _ = count;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .allocator = .smp_allocator,
        .root = Fixture,
        .types = .{.{ .type = Fixture.Screen, .repr = .@"opaque" }},
        .functions = .{.{
            .receiver = "Screen",
            .strip_prefix = "screen",
            .functions = .{
                "root.screenSelectAll",
                .{ .path = "root.screenClearSelection", .name = "wipe" },
                .{ .path = "root.screenMove", .params = .{"count"} },
            },
        }},
    }, "display", "zg");

    try std.testing.expectEqual(@as(usize, 3), document.functions.len);
    try std.testing.expectEqualStrings("selectAll", document.functions[0].name);
    try std.testing.expectEqualStrings("wipe", document.functions[1].name);
    try std.testing.expectEqualStrings("move", document.functions[2].name);
    for (document.functions) |function| try std.testing.expectEqualStrings("Screen", function.receiver.?);
    try std.testing.expectEqualStrings("screenSelectAll", document.functions[0].zig_path.?);
    try std.testing.expectEqualStrings("zg_screen_select_all", document.functions[0].symbol);
    try std.testing.expectEqual(@as(?usize, 1), document.functions[2].receiver_at);
    try std.testing.expectEqual(semantic.Injection.allocator, document.functions[2].params[0].injected.?);
    try std.testing.expectEqualStrings("count", document.functions[2].params[1].name);
}

test "per-function explicit receivers validate the first non-injected parameter" {
    const Fixture = struct {
        const Screen = opaque {};
        const Search = opaque {};

        pub fn matchCount(gpa: std.mem.Allocator, search: *Search) u32 {
            _ = gpa;
            _ = search;
            return 0;
        }
    };
    const types = .{
        .{ .type = Fixture.Screen, .repr = .@"opaque" },
        .{ .type = Fixture.Search, .repr = .@"opaque" },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .allocator = .smp_allocator,
        .root = Fixture,
        .types = types,
        .functions = .{.{ .path = "root.matchCount", .receiver = "Search" }},
    }, "search", "zg");
    try std.testing.expectEqualStrings("Search", document.functions[0].receiver.?);
    try std.testing.expectEqual(@as(?usize, 1), document.functions[0].receiver_at);

    try std.testing.expectError(error.ReceiverMetadata, reflect(arena.allocator(), .{
        .allocator = .smp_allocator,
        .root = Fixture,
        .types = types,
        .functions = .{.{ .path = "root.matchCount", .receiver = "Screen" }},
    }, "search", "zg"));
}

test "receiver metadata diagnostics use ZIGO038" {
    const mismatch = try receiverMessageAlloc(
        std.testing.allocator,
        "function `{s}` declares `.receiver = \"{s}\"` but its first non-injected parameter is not `*{s}` or `*const {s}`",
        .{ "screenSelectAll", "Screen", "Screen", "Screen" },
    );
    defer std.testing.allocator.free(mismatch);
    try std.testing.expectEqualStrings(
        "error[ZIGO038]: function `screenSelectAll` declares `.receiver = \"Screen\"` but its first non-injected parameter is not `*Screen` or `*const Screen`\n" ++
            "  hint: name a registered opaque type whose pointer is the function's first parameter after any injected `std.mem.Allocator` or `std.Io`\n",
        mismatch,
    );
}

test "function groups reject paths without their prefix" {
    const Fixture = struct {
        const Screen = opaque {};
        pub fn selectAll(screen: *Screen) void {
            _ = screen;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.ReceiverMetadata, reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .type = Fixture.Screen, .repr = .@"opaque" }},
        .functions = .{.{
            .receiver = "Screen",
            .strip_prefix = "screen",
            .functions = .{"root.selectAll"},
        }},
    }, "display", "zg"));
}

test "an injected argument ahead of the handle does not stop a function being a method" {
    const Fixture = struct {
        const Terminal = opaque {};

        pub fn makeTerminal(columns: u32) error{Invalid}!*Terminal {
            _ = columns;
            unreachable;
        }

        pub fn releaseTerminal(gpa: std.mem.Allocator, self: *Terminal) void {
            _ = gpa;
            _ = self;
        }

        pub fn resize(gpa: std.mem.Allocator, self: *Terminal, columns: u32) void {
            _ = gpa;
            _ = self;
            _ = columns;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .name = "Terminal", .type = Fixture.Terminal, .repr = .@"opaque" }},
        .functions = .{
            .{ .path = "root.makeTerminal", .params = .{"columns"}, .constructs = "Terminal" },
            .{ .path = "root.releaseTerminal", .destroys = "Terminal" },
            .{ .path = "root.resize", .params = .{"columns"} },
        },
    }, "terminal", "zg");

    try std.testing.expectEqual(@as(usize, 1), document.constructors.len);
    try std.testing.expectEqualStrings("releaseTerminal", document.constructors[0].deinit);
    // The destructor: one injected entry ahead of the receiver, nothing exposed.
    try std.testing.expectEqualStrings("Terminal", document.functions[1].receiver.?);
    try std.testing.expectEqual(@as(?usize, 1), document.functions[1].receiver_at);
    try std.testing.expectEqual(@as(usize, 1), document.functions[1].params.len);
    try std.testing.expectEqual(semantic.Injection.allocator, document.functions[1].params[0].injected.?);
    // The method: `.params` still names only what Go passes.
    try std.testing.expectEqualStrings("Terminal", document.functions[2].receiver.?);
    try std.testing.expectEqual(@as(?usize, 1), document.functions[2].receiver_at);
    try std.testing.expectEqual(@as(usize, 2), document.functions[2].params.len);
    try std.testing.expectEqualStrings("columns", document.functions[2].params[1].name);
}

test "a `.constructs` claim the signatures do not support is refused" {
    const Fixture = struct {
        const Terminal = opaque {};
        const Cursor = opaque {};

        pub fn makeTerminal(columns: u32) error{Invalid}!*Terminal {
            _ = columns;
            unreachable;
        }

        pub fn releaseTerminal(self: *Terminal) void {
            _ = self;
        }
    };
    const types = .{
        .{ .name = "Terminal", .type = Fixture.Terminal, .repr = .@"opaque" },
        .{ .name = "Cursor", .type = Fixture.Cursor, .repr = .@"opaque" },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // A constructor of a type it does not return.
    try std.testing.expectError(error.ConstructorPairing, reflect(arena.allocator(), .{
        .root = Fixture,
        .types = types,
        .functions = .{
            .{ .path = "root.makeTerminal", .params = .{"columns"}, .constructs = "Cursor" },
            .{ .path = "root.releaseTerminal", .destroys = "Cursor" },
        },
    }, "terminal", "zg"));

    // A destructor of a type it does not take.
    try std.testing.expectError(error.ConstructorPairing, reflect(arena.allocator(), .{
        .root = Fixture,
        .types = types,
        .functions = .{
            .{ .path = "root.makeTerminal", .params = .{"columns"}, .constructs = "Terminal" },
            .{ .path = "root.releaseTerminal", .destroys = "Cursor" },
        },
    }, "terminal", "zg"));

    // A type nothing else was registered under.
    try std.testing.expectError(error.ConstructorPairing, reflect(arena.allocator(), .{
        .root = Fixture,
        .types = types,
        .functions = .{.{ .path = "root.makeTerminal", .params = .{"columns"}, .constructs = "Screen" }},
    }, "terminal", "zg"));

    // One half on its own.
    try std.testing.expectError(error.ConstructorPairing, reflect(arena.allocator(), .{
        .root = Fixture,
        .types = types,
        .functions = .{.{ .path = "root.makeTerminal", .params = .{"columns"}, .constructs = "Terminal" }},
    }, "terminal", "zg"));
    try std.testing.expectError(error.ConstructorPairing, reflect(arena.allocator(), .{
        .root = Fixture,
        .types = types,
        .functions = .{.{ .path = "root.releaseTerminal", .destroys = "Terminal" }},
    }, "terminal", "zg"));
}

test "the pairing message names the declaration and the code" {
    const message = try pairingMessageAlloc(
        std.testing.allocator,
        "`{s}` declares `.constructs = \"{s}\"` but does not return `*{s}`",
        .{ "makeTerminal", "Cursor", "Cursor" },
    );
    defer std.testing.allocator.free(message);
    try std.testing.expectEqualStrings(
        \\error[ZIGO028]: `makeTerminal` declares `.constructs = "Cursor"` but does not return `*Cursor`
        \\  hint: `.constructs` and `.destroys` name one registered opaque type each, on the function that returns `*T` and the function that takes it
        \\
    , message);
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
            .{ .path = "Terminal.init", .params = .{"columns"} },
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

test "opaque fields reflect nested value and pointer accessors" {
    const Style = enum(u8) { block, bar };
    const Cursor = struct { x: u16, style: Style };
    const Screen = struct { cursor: *Cursor };
    const Terminal = struct { enabled: bool, screen: Screen };
    const Fixture = struct {};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const document = try reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{
            .{ .type = Style, .repr = .enumeration },
            .{ .type = Terminal, .repr = .@"opaque", .fields = .{
                .{ .path = "enabled" },
                .{ .path = "screen.cursor.x", .name = "cursorX" },
                .{ .path = "screen.cursor.style", .name = "cursorStyle", .set = true, .doc = "Current cursor style." },
            } },
        },
        .functions = .{},
    }, "terminal", "zg");

    try std.testing.expectEqual(@as(usize, 4), document.functions.len);
    try std.testing.expectEqualStrings("enabled", document.functions[0].name);
    try std.testing.expectEqualStrings("Terminal", document.functions[0].receiver.?);
    try std.testing.expectEqualStrings("screen.cursor.x", document.functions[1].field_access.?.path);
    try std.testing.expectEqual(semantic.TypeNode{ .int = .{ .signed = false, .bits = 16 } }, document.functions[1].@"return");
    try std.testing.expectEqualStrings("cursorStyle", document.functions[2].name);
    try std.testing.expectEqualStrings("Style", document.functions[2].@"return".@"enum".ref);
    try std.testing.expectEqualStrings("setCursorStyle", document.functions[3].name);
    try std.testing.expect(document.functions[3].field_access.?.setter);
    try std.testing.expectEqualStrings("v", document.functions[3].params[0].name);
    try std.testing.expectEqualStrings("Current cursor style.", document.functions[3].doc.?);
}

test "invalid opaque field paths and leaf types use ZIGO037" {
    const Terminal = struct { label: []const u8 };
    const Fixture = struct {};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.FieldAccess, reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .type = Terminal, .repr = .@"opaque", .fields = .{.{ .path = "missing" }} }},
        .functions = .{},
    }, "terminal", "zg"));
    try std.testing.expectError(error.FieldAccess, reflect(arena.allocator(), .{
        .root = Fixture,
        .types = .{.{ .type = Terminal, .repr = .@"opaque", .fields = .{.{ .path = "label" }} }},
        .functions = .{},
    }, "terminal", "zg"));

    const unknown = try fieldAccessMessageAlloc(std.testing.allocator, "screen.cursor.x", null);
    defer std.testing.allocator.free(unknown);
    try std.testing.expectEqualStrings(
        "error[ZIGO037]: field path `screen.cursor.x` is unknown or crosses something other than a plain struct or non-optional single pointer\n" ++
            "  hint: paths may cross struct values or non-optional single pointers and must end at a bool, integer, float, or registered enum\n",
        unknown,
    );
    const unsupported = try fieldAccessMessageAlloc(std.testing.allocator, "label", []const u8);
    defer std.testing.allocator.free(unsupported);
    try std.testing.expectEqualStrings(
        "error[ZIGO037]: field path `label` encounters unsupported type `[]const u8`\n" ++
            "  hint: paths may cross struct values or non-optional single pointers and must end at a bool, integer, float, or registered enum\n",
        unsupported,
    );
}
