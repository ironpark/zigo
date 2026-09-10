//! Public binding authoring: scoped references and typed declaration contracts.
const std = @import("std");
const ir = @import("declare.zig");

pub const SemanticHint = ir.SemanticHint;
pub const GoAdapter = ir.GoAdapter;
pub const Injection = ir.Injection;
pub const Defaults = struct {
    codepoints: ?ir.Codepoints = null,
    strings: ?ir.Strings = null,
};

pub const FunctionRef = struct {
    root: type,
    container: type,
    path: []const u8,
    name: []const u8,

    pub fn signature(comptime self: FunctionRef) std.builtin.Type.Fn {
        return @typeInfo(@TypeOf(@field(self.container, self.name))).@"fn";
    }
};
pub const TypeRef = struct {
    root: type,
    type: type,
    path: []const u8,
};

/// A constructor is static unless it explicitly selects a receiver.
pub const Receiver = union(enum) {
    none,
    member,
    type: TypeRef,
};
pub const Role = union(enum) {
    auto,
    free,
    method: TypeRef,
    constructor: struct { type: TypeRef, receiver: Receiver = .none, parent: enum { none, receiver } = .none },
    destructor: TypeRef,
};
pub const Lifetime = union(enum) {
    inferred,
    owned: struct { release: ?FunctionRef = null },
    borrowed: enum { receiver },
    library,
};
pub const Returns = struct {
    lifetime: Lifetime = .inferred,
    semantic: ?SemanticHint = null,
    go: ?GoAdapter = null,
};
pub const Buffer = union(enum) {
    input,
    output: struct { written: ?ir.Written = null },
    inout: struct { written: ?ir.Written = null },
};
pub const CallbackContract = struct {
    retention: ?ir.Retention = null,
    reentrancy: ?ir.Reentrancy = null,
    thread: ?ir.Thread = null,
    go_error: bool = false,
    on_failure: ?ir.CallbackFailure = null,
    /// Original Zig argument index carrying the token.
    userdata: ?usize = null,
};
pub const ParamContract = union(enum) {
    value,
    buffer: Buffer,
    stream: struct { buffer: ?u32 = null },
    callback: CallbackContract,
    cancel: struct { canceled: ?[]const u8 = null },
    flatten: []const []const u8,
};
pub const Param = struct {
    /// Original Zig argument index, including receiver, injection and userdata.
    index: usize,
    go_name: ?[]const u8 = null,
    semantic: ?SemanticHint = null,
    go: ?GoAdapter = null,
    contract: ParamContract = .value,

    pub fn named(comptime self: Param, comptime name: ?[]const u8) Param {
        var copy = self;
        copy.go_name = name;
        return copy;
    }
};
pub const FunctionOptions = struct {
    name: ?[]const u8 = null,
    doc: ?[]const u8 = null,
    role: Role = .auto,
    params: []const Param = &.{},
    returns: Returns = .{},
    covers: []const FunctionRef = &.{},
    /// The exported C symbol, written as is. Absent derives it from the
    /// prefix, the owner and the Go name.
    symbol: ?[]const u8 = null,
};
pub const Function = struct { ref: FunctionRef, options: FunctionOptions = .{}, extensions: []const ir.Extension = &.{} };

pub const HandleOptions = struct { fields: []const ir.HandleField = &.{} };
pub const ValueOptions = struct { fields: []const ir.ValueField = &.{}, go: ?GoAdapter = null };
pub const MaterializedOptions = struct { fields: []const ir.ValueField = &.{} };
pub const EnumOptions = struct { exhaustive: bool = true, go: ?GoAdapter = null, covers: []const FunctionRef = &.{} };
pub const UnionOptions = struct { access: ir.Access = .projection, omit: []const []const u8 = &.{} };
/// Sparse hints indexed by the original native callback signature.
pub const CallbackParam = struct { index: usize, semantic: ?SemanticHint = null };
pub const CallbackOptions = struct {
    params: []const CallbackParam = &.{},
    returns: struct { semantic: ?SemanticHint = null } = .{},
    userdata: ?ir.Userdata = null,
    retention: ?ir.Retention = null,
    reentrancy: ?ir.Reentrancy = null,
    thread: ?ir.Thread = null,
    on_failure: ?ir.CallbackFailure = null,
};
pub const Representation = union(enum) {
    handle: HandleOptions,
    value: ValueOptions,
    materialized: MaterializedOptions,
    enumeration: EnumOptions,
    tagged_union: UnionOptions,
    callback: CallbackOptions,
};
pub const TypeOptions = struct {
    name: ?[]const u8 = null,
    doc: ?[]const u8 = null,
    members: []const Entry = &.{},
};
pub const Type = struct {
    ref: TypeRef,
    representation: Representation,
    options: TypeOptions = .{},
    extensions: []const ir.Extension = &.{},
};
pub const Package = struct {
    path: []const u8,
    name: ?[]const u8 = null,
    doc: ?[]const u8 = null,
    defaults: Defaults = .{},
    declarations: []const Entry,
};
pub const Interface = struct {
    name: []const u8,
    methods: []const []const u8,
    types: []const TypeRef,
    closer: bool = true,
    doc: ?[]const u8 = null,
};

/// The authoring tree contains actual declarations, not package membership paths.
pub const Entry = union(enum) {
    function: Function,
    type: Type,
    package: Package,
    interface: Interface,

    /// Only explicitly supplied fields are replaced. Null clears a nullable field.
    /// Nested contracts are replaced as a whole; there is no implicit deep merge.
    pub fn with(comptime self: Entry, comptime values: anytype) Entry {
        var result = self;
        switch (result) {
            .function => |*f| f.options = replace(f.options, values),
            .type => |*t| t.options = replace(t.options, values),
            else => @compileError("zigo with requires a function or type declaration"),
        }
        return result;
    }
    /// Capture this type declaration and its source scope in a generic context.
    pub fn context(comptime self: Entry) type {
        return Context(self);
    }

    /// Replace the type's complete member list, retaining its options and plugins.
    pub fn members(comptime self: Entry, comptime entries: []const Entry) Entry {
        if (self != .type) @compileError("zigo members requires a type declaration");
        return self.with(.{ .members = entries });
    }
    pub fn named(comptime self: Entry, comptime name: ?[]const u8) Entry {
        return self.with(.{ .name = name });
    }
    pub fn documented(comptime self: Entry, comptime doc: ?[]const u8) Entry {
        return self.with(.{ .doc = doc });
    }
    pub fn functionRef(comptime self: Entry) FunctionRef {
        if (self != .function) @compileError("zigo functionRef requires a function");
        return self.function.ref;
    }
    pub fn typeRef(comptime self: Entry) TypeRef {
        if (self != .type) @compileError("zigo typeRef requires a type");
        return self.type.ref;
    }
    pub fn use(comptime self: Entry, comptime P: anytype, comptime options: pluginOptions(P, self)) Entry {
        comptime checkPluginSubject(P, self);
        var result = self;
        const extensions = switch (self) {
            .function => self.function.extensions,
            .type => self.type.extensions,
            else => @compileError("zigo plugins attach to functions or types"),
        };
        inline for (extensions) |existing| {
            if (std.mem.eql(u8, existing.plugin, P.name)) @compileError("zigo duplicate plugin attachment: " ++ P.name);
        }
        const Captured = struct {
            pub const name = P.name;
            pub const Options = pluginOptions(P, self);
        };
        var captured = ir.extension(Captured, options);
        if (@hasField(@TypeOf(P), "builtin")) {
            captured.builtin = switch (P.builtin) {
                .iterator => .{ .iterator = options },
                .implements => .{ .implements = options.kind },
                .text => .text,
            };
        }
        const extended = extensions ++ [_]ir.Extension{captured};
        switch (result) {
            .function => |*f| f.extensions = extended,
            .type => |*t| t.extensions = extended,
            else => unreachable,
        }
        return result;
    }
    /// Explicit replacement, separate from duplicate-rejecting use().
    pub fn replacePlugin(comptime self: Entry, comptime P: anytype, comptime options: pluginOptions(P, self)) Entry {
        var result = self;
        const existing = switch (self) {
            .function => self.function.extensions,
            .type => self.type.extensions,
            else => @compileError("zigo plugins attach to functions or types"),
        };
        comptime var kept: []const ir.Extension = &.{};
        inline for (existing) |e| if (!std.mem.eql(u8, e.plugin, P.name)) {
            kept = kept ++ [_]ir.Extension{e};
        };
        switch (result) {
            .function => |*f| f.extensions = kept,
            .type => |*t| t.extensions = kept,
            else => unreachable,
        }
        return result.use(P, options);
    }
};

fn pluginOptions(comptime P: anytype, comptime entry: Entry) type {
    return if (entry == .function) P.FunctionOptions else P.TypeOptions;
}
fn checkPluginSubject(comptime P: anytype, comptime entry: Entry) void {
    if (@hasField(@TypeOf(P), "subjects")) {
        const subject = switch (entry) {
            .function => "function",
            .type => @tagName(entry.type.representation),
            else => @compileError("zigo plugins attach to functions or types"),
        };
        inline for (P.subjects) |candidate| if (std.mem.eql(u8, @tagName(candidate), subject)) return;
        @compileError("zigo plugin " ++ P.name ++ " does not support " ++ subject);
    }
}
fn replace(comptime original: anytype, comptime values: anytype) @TypeOf(original) {
    if (@typeInfo(@TypeOf(values)) != .@"struct") @compileError("zigo with expects named option fields");
    var result = original;
    inline for (std.meta.fields(@TypeOf(values))) |field| {
        if (!@hasField(@TypeOf(original), field.name)) @compileError("zigo unknown option: " ++ field.name);
        @field(result, field.name) = @field(values, field.name);
    }
    return result;
}

/// A compile-time authoring context; define/select return the existing Entry schema.
fn Context(comptime entry: Entry) type {
    if (entry != .type) @compileError("zigo context requires a type declaration");
    if (entry.type.representation == .callback)
        @compileError("zigo callback declarations have no member context");
    return struct {
        const Self = @This();
        pub const Target = entry.type.ref.type;
        pub const source = Scope(entry.type.ref.root, Target, entry.type.ref.path);
        pub const func = source.func;
        pub const funcs = source.funcs;
        pub const ref = source.ref;

        pub fn typeRef() TypeRef {
            return entry.typeRef();
        }
        /// Replace all members while preserving the captured options and plugins.
        pub fn define(comptime entries: []const Entry) Entry {
            return entry.members(entries);
        }
        pub fn select(comptime selector: Selector) Entry {
            return Self.define(Self.funcs(selector));
        }
    };
}

pub const Selector = union(enum) {
    names: []const []const u8,
    public: struct { prefix: []const u8 = "", exclude: []const []const u8 = &.{} },
};

pub fn scope(comptime Root: type) type {
    return Scope(Root, Root, "root");
}
fn Scope(comptime Root: type, comptime Container: type, comptime path: []const u8) type {
    return struct {
        pub fn in(comptime name: []const u8) type {
            const T = namedType(Container, name);
            return Scope(Root, T, path ++ "." ++ name);
        }
        pub fn ref(comptime name: []const u8) FunctionRef {
            if (!@hasDecl(Container, name) or @typeInfo(@TypeOf(@field(Container, name))) != .@"fn")
                @compileError("zigo reference is not a public function: " ++ path ++ "." ++ name);
            return .{ .root = Root, .container = Container, .path = path ++ "." ++ name, .name = name };
        }
        pub fn typeRef(comptime name: []const u8) TypeRef {
            return .{ .root = Root, .type = namedType(Container, name), .path = path ++ "." ++ name };
        }
        pub fn func(comptime name: []const u8, comptime options: FunctionOptions) Entry {
            return .{ .function = .{ .ref = ref(name), .options = options } };
        }
        pub fn funcs(comptime selector: Selector) []const Entry {
            comptime var entries: []const Entry = &.{};
            switch (selector) {
                .names => |names| {
                    inline for (names, 0..) |name, i| {
                        inline for (names[0..i]) |prior| if (std.mem.eql(u8, prior, name)) @compileError("zigo duplicate function selection: " ++ name);
                        entries = entries ++ [_]Entry{func(name, .{})};
                    }
                },
                .public => |selection| {
                    inline for (selection.exclude, 0..) |name, i| {
                        _ = ref(name);
                        if (!std.mem.startsWith(u8, name, selection.prefix)) @compileError("zigo excluded function is outside the selected prefix: " ++ name);
                        inline for (selection.exclude[0..i]) |prior| if (std.mem.eql(u8, prior, name)) @compileError("zigo duplicate function exclusion: " ++ name);
                    }
                    inline for (std.meta.declarations(Container)) |d| {
                        if (@typeInfo(@TypeOf(@field(Container, d.name))) != .@"fn") continue;
                        if (!std.mem.startsWith(u8, d.name, selection.prefix)) continue;
                        comptime var excluded = false;
                        inline for (selection.exclude) |name| if (std.mem.eql(u8, d.name, name)) {
                            excluded = true;
                        };
                        if (!excluded) entries = entries ++ [_]Entry{func(d.name, .{})};
                    }
                },
            }
            if (entries.len == 0) @compileError("zigo function selection is empty");
            return entries;
        }
        fn typeEntry(comptime name: []const u8, comptime repr: Representation) Entry {
            const reference = typeRef(name);
            const info = @typeInfo(reference.type);
            const valid = switch (repr) {
                .handle => info == .@"struct" or info == .@"opaque" or info == .@"union",
                .value => info == .@"struct" and (info.@"struct".layout == .@"extern" or info.@"struct".layout == .@"packed"),
                .materialized => info == .@"struct",
                .enumeration => info == .@"enum",
                .tagged_union => info == .@"union" and info.@"union".tag_type != null,
                .callback => info == .pointer and @typeInfo(info.pointer.child) == .@"fn",
            };
            if (!valid) @compileError("zigo " ++ @tagName(repr) ++ " representation cannot register " ++ reference.path);
            return .{ .type = .{ .ref = reference, .representation = repr, .options = .{ .name = name } } };
        }
        pub fn handle(comptime name: []const u8, comptime options: HandleOptions) Entry {
            return typeEntry(name, .{ .handle = options });
        }
        pub fn val(comptime name: []const u8, comptime options: ValueOptions) Entry {
            return typeEntry(name, .{ .value = options });
        }
        pub fn materialized(comptime name: []const u8, comptime options: MaterializedOptions) Entry {
            return typeEntry(name, .{ .materialized = options });
        }
        pub fn enumType(comptime name: []const u8, comptime options: EnumOptions) Entry {
            return typeEntry(name, .{ .enumeration = options });
        }
        pub fn taggedUnion(comptime name: []const u8, comptime options: UnionOptions) Entry {
            return typeEntry(name, .{ .tagged_union = options });
        }
        pub fn callback(comptime name: []const u8, comptime options: CallbackOptions) Entry {
            return typeEntry(name, .{ .callback = options });
        }
    };
}
fn namedType(comptime Container: type, comptime name: []const u8) type {
    if (!@hasDecl(Container, name) or @TypeOf(@field(Container, name)) != type)
        @compileError("zigo reference is not a public type: " ++ name);
    return @field(Container, name);
}
pub fn package(comptime options: Package) Entry {
    return .{ .package = options };
}
pub fn interface(comptime options: Interface) Entry {
    return .{ .interface = options };
}

pub const DiscoverySelection = struct { exclude: []const FunctionRef = &.{} };
pub const Discovery = union(enum) {
    explicit,
    public: DiscoverySelection,
    recursive: DiscoverySelection,
};
pub const Binding = struct {
    root: type,
    allocator: ?Injection = null,
    io: ?Injection = null,
    defaults: Defaults = .{},
    discovery: Discovery = .explicit,
    string_release: ?FunctionRef = null,
    declarations: []const Entry = &.{},
};

test "scoped references and explicit selection preserve source identity" {
    const Lib = struct {
        pub const Item = opaque {};
        pub fn a() void {}
        pub fn b() void {}
    };
    const api = scope(Lib);
    const entries = comptime api.funcs(.{ .names = &.{ "b", "a" } });
    try std.testing.expectEqualStrings("root.b", comptime entries[0].functionRef().path);
    try std.testing.expect(api.typeRef("Item").type == Lib.Item);
    const original = comptime api.handle("Item", .{}).members(entries);
    const replaced = comptime original.members(&.{api.func("a", .{})});
    try std.testing.expectEqual(@as(usize, 1), replaced.type.options.members.len);
    try std.testing.expectEqualStrings("root.a", replaced.type.options.members[0].function.ref.path);
    const param = comptime (Param{ .index = 1 }).named("alias").named(null);
    try std.testing.expect(param.go_name == null);
    const renamed = api.func("a", .{}).named("Other");
    try std.testing.expectEqualStrings("root.a", renamed.functionRef().path);
}
test "contract replacement clears stale lifetime and explicit null clears names" {
    const Lib = struct {
        pub fn take() void {}
        pub fn free() void {}
    };
    const api = scope(Lib);
    const owned = api.func("take", .{ .name = "Take", .returns = .{ .lifetime = .{ .owned = .{ .release = api.ref("free") } } } });
    const borrowed = owned.with(.{ .name = null, .returns = Returns{ .lifetime = .{ .borrowed = .receiver } } });
    try std.testing.expect(borrowed.function.options.name == null);
    try std.testing.expect(borrowed.function.options.returns.lifetime == .borrowed);
}

test "type plugins and explicit replacement keep one typed option payload" {
    const Lib = struct {
        pub const Record = extern struct { value: u32 };
    };
    const P = .{ .name = "TEST", .FunctionOptions = struct {}, .TypeOptions = struct { limit: ?u32 = 10 }, .subjects = [_]enum { value }{.value} };
    const entry = comptime scope(Lib).val("Record", .{}).use(P, .{ .limit = 5 }).replacePlugin(P, .{ .limit = null });
    try std.testing.expectEqual(@as(usize, 1), entry.type.extensions.len);
    const bytes = try entry.type.extensions[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("{\"limit\":null}", bytes);
}

test "plugin options are selected by attachment target" {
    const Lib = struct {
        pub const Record = extern struct { value: u32 };
        pub fn f() void {}
    };
    const P = .{ .name = "DUAL", .FunctionOptions = struct { checked: bool }, .TypeOptions = struct { key: []const u8 }, .subjects = [_]enum { function, value }{ .function, .value } };
    const api = scope(Lib);
    const f = comptime api.func("f", .{}).use(P, .{ .checked = true });
    const t = comptime api.val("Record", .{}).use(P, .{ .key = "value" });
    const f_json = try f.function.extensions[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(f_json);
    const t_json = try t.type.extensions[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(t_json);
    try std.testing.expectEqualStrings("{\"checked\":true}", f_json);
    try std.testing.expectEqualStrings("{\"key\":\"value\"}", t_json);
}
