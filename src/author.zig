//! Public binding authoring: scoped references and typed declaration contracts.
const std = @import("std");
const ir = @import("declare.zig");
const features = @import("features.zig");
const plugin = @import("plugin");

pub const SemanticHint = ir.SemanticHint;
pub const GoAdapter = ir.GoAdapter;
pub const OptionsSpec = ir.OptionsSpec;
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
/// Who owns a result. Spelled through `zigo.result.*`; the literal form is
/// not part of the authoring surface.
const Ownership = union(enum) {
    inferred,
    owned: struct { release: ?FunctionRef = null },
    /// Owned by the receiver, and unusable once the receiver is closed.
    borrowed,
    library,
};
pub const Returns = struct {
    /// Set by `zigo.result.owned()`, `releasedBy()`, `borrowed()`.
    ownership: Ownership = .inferred,
    semantic: ?SemanticHint = null,
    go: ?GoAdapter = null,
    /// Plugin options, one entry per plugin. Written by `use`.
    extensions: []const ir.Extension = &.{},

    /// Attach plugin `P` with its `ResultOptions` to this function's result.
    /// A plugin whose `subjects` exclude `.result` is refused here, at the
    /// declaration, rather than as a diagnostic long afterwards.
    pub fn use(comptime self: Returns, comptime P: plugin.Plugin, comptime options: P.ResultOptions) Returns {
        comptime checkNodeSubject(P, .result);
        comptime checkDuplicateAttachment(self.extensions, P.name);
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.ResultOptions;
        };
        var result = self;
        result.extensions = self.extensions ++ [_]ir.Extension{ir.extension(Captured, options)};
        return result;
    }
};
const Buffer = union(enum) {
    input,
    output: struct { written: ?ir.Written = null },
    inout: struct { written: ?ir.Written = null },
};
/// The contract a callback type and each call site of it share. A callback
/// declaration states the defaults; `zigo.param.callback` overrides them
/// field by field, and a field left null inherits the declaration's value.
pub const CallbackContract = struct {
    retention: ?ir.Retention = null,
    reentrancy: ?ir.Reentrancy = null,
    thread: ?ir.Thread = null,
    on_failure: ?ir.CallbackFailure = null,
};
/// What one call site adds to the shared contract.
pub const CallbackSite = struct {
    contract: CallbackContract = .{},
    /// The Go callback returns an `error` (its Zig result is `i32`).
    go_error: bool = false,
    /// Original Zig argument index carrying the token.
    userdata: ?usize = null,
};
const ParamContract = union(enum) {
    value,
    buffer: Buffer,
    stream: struct { buffer: ?u32 = null },
    callback: CallbackSite,
    cancel: struct { canceled: ?[]const u8 = null },
    flatten: []const []const u8,
    options: struct {
        fields: []const []const u8,
        options: ir.OptionsSpec = .{},
    },
};
pub const Param = struct {
    /// Original Zig argument index, including receiver, injection and userdata.
    index: usize,
    go_name: ?[]const u8 = null,
    semantic: ?SemanticHint = null,
    go: ?GoAdapter = null,
    /// Set by `zigo.param.*`; a plain `.{ .index = n }` carries a value.
    contract: ParamContract = .value,
    /// Plugin options, one entry per plugin. Written by `use`.
    extensions: []const ir.Extension = &.{},

    pub fn named(comptime self: Param, comptime name: ?[]const u8) Param {
        var copy = self;
        copy.go_name = name;
        return copy;
    }

    /// Attach plugin `P` with its `ParamOptions` to this parameter. A plugin
    /// whose `subjects` exclude `.param` is refused here, at the declaration.
    pub fn use(comptime self: Param, comptime P: plugin.Plugin, comptime options: P.ParamOptions) Param {
        comptime checkNodeSubject(P, .param);
        comptime checkDuplicateAttachment(self.extensions, P.name);
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.ParamOptions;
        };
        var copy = self;
        copy.extensions = self.extensions ++ [_]ir.Extension{ir.extension(Captured, options)};
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
pub const EnumOptions = struct {
    exhaustive: bool = true,
    /// Generate `Parse<Enum>`, `MarshalText` and `UnmarshalText`.
    text: bool = false,
    go: ?GoAdapter = null,
    covers: []const FunctionRef = &.{},
    fields: []const ir.EnumField = &.{},
};
pub const UnionOptions = struct { access: ir.Access = .projection, omit: []const []const u8 = &.{} };
/// Sparse hints indexed by the original native callback signature.
pub const CallbackParam = struct { index: usize, semantic: ?SemanticHint = null };
pub const CallbackOptions = struct {
    params: []const CallbackParam = &.{},
    returns: struct { semantic: ?SemanticHint = null } = .{},
    userdata: ?ir.Userdata = null,
    /// Defaults every call site of this type inherits.
    contract: CallbackContract = .{},
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
    /// Written by `.context().members(...)` and `.select(...)`.
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
/// One dependent child a session adopts. The adopt method is `Add<Type>` and
/// the accessor is `<Type>s` unless `accessor` spells the whole accessor name:
/// a `Search` handle reads as `Searches` only because it is said here.
pub const SessionChild = struct {
    type: TypeRef,
    accessor: ?[]const u8 = null,
};

/// A Go type that adopts one handle and the dependent children it handed out,
/// and closes them in that order. The primary is closed last, and every child
/// must be a dependent child of it.
pub const Session = struct {
    name: []const u8,
    primary: TypeRef,
    children: []const SessionChild,
    doc: ?[]const u8 = null,
};

/// The declaration kinds a plugin attaches to. The DSL's spelling of
/// `plugin.Subject`; the two are compared by tag name, so a `plugin.Plugin`
/// value and one of `zigo.features` pass the same check.
pub const Subject = enum { function, handle, value, enumeration, tagged_union, callback, materialized, error_set, param, result, field, enum_tag };

/// The authoring tree contains actual declarations, not package membership paths.
pub const Entry = union(enum) {
    function: Function,
    type: Type,
    package: Package,
    interface: Interface,
    session: Session,

    /// Only explicitly supplied fields are replaced. Null clears a nullable field.
    /// Nested contracts are replaced as a whole; there is no implicit deep merge.
    pub fn with(comptime self: Entry, comptime values: anytype) Entry {
        var result = self;
        switch (result) {
            .function => |*f| f.options = replace(f.options, values),
            .type => |*t| {
                if (@hasField(@TypeOf(values), "members")) @compileError("zigo members are declared through .context().members(...)");
                t.options = replace(t.options, values);
            },
            else => @compileError("zigo with requires a function or type declaration"),
        }
        return result;
    }
    /// Capture this type declaration and its source scope in a generic context.
    pub fn context(comptime self: Entry) type {
        return Context(self);
    }

    pub fn functionRef(comptime self: Entry) FunctionRef {
        if (self != .function) @compileError("zigo functionRef requires a function");
        return self.function.ref;
    }
    pub fn typeRef(comptime self: Entry) TypeRef {
        if (self != .type) @compileError("zigo typeRef requires a type");
        return self.type.ref;
    }
    /// Attach plugin `P` with its typed options. `P` is the `plugin.Plugin`
    /// value a plugin package exports, or one of `zigo.features`; the same
    /// declaration cannot attach the same plugin twice.
    pub fn use(comptime self: Entry, comptime P: plugin.Plugin, comptime options: pluginOptions(P, self)) Entry {
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
        if (std.mem.eql(u8, P.name, features.iterator.name)) {
            captured.builtin = .{ .iterator = options };
        } else if (std.mem.eql(u8, P.name, features.implements.name)) {
            if (options.kinds.len == 0) @compileError("zigo implements needs a non-empty `.kinds`");
            captured.builtin = .{ .implements = .{ .kinds = options.kinds, .keep_original = options.keep_original } };
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
    pub fn replacePlugin(comptime self: Entry, comptime P: plugin.Plugin, comptime options: pluginOptions(P, self)) Entry {
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

fn pluginOptions(comptime P: plugin.Plugin, comptime entry: Entry) type {
    return if (entry == .function) P.FunctionOptions else P.TypeOptions;
}
/// The subject check the node-level `use` methods share: a parameter, a
/// result, a field or an enum tag is a node kind the plugin has to declare,
/// exactly as a declaration kind is. Tags are compared by name so this
/// module's `Subject` and `plugin.Subject` pass the same check.
fn checkNodeSubject(comptime P: plugin.Plugin, comptime subject: Subject) void {
    inline for (P.subjects) |candidate| if (std.mem.eql(u8, @tagName(candidate), @tagName(subject))) return;
    @compileError("zigo plugin " ++ P.name ++ " does not support " ++ @tagName(subject));
}

fn checkDuplicateAttachment(comptime entries: []const ir.Extension, comptime name: []const u8) void {
    inline for (entries) |existing| if (std.mem.eql(u8, existing.plugin, name))
        @compileError("zigo duplicate plugin attachment: " ++ name);
}

fn checkPluginSubject(comptime P: plugin.Plugin, comptime entry: Entry) void {
    const subject = switch (entry) {
        .function => "function",
        .type => @tagName(entry.type.representation),
        else => @compileError("zigo plugins attach to functions or types"),
    };
    inline for (P.subjects) |candidate| if (std.mem.eql(u8, @tagName(candidate), subject)) return;
    @compileError("zigo plugin " ++ P.name ++ " does not support " ++ subject);
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

/// A compile-time authoring context; members/select return the existing Entry schema.
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
        pub fn members(comptime entries: []const Entry) Entry {
            var result = entry;
            result.type.options.members = entries;
            return result;
        }
        pub fn select(comptime selector: Selector) Entry {
            return Self.members(Self.funcs(selector));
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
        /// The module every reference resolves against; `zigo.define` reads it.
        pub const root = Root;

        /// A nested namespace container. A registered type's members are not
        /// reached this way: its `.context()` is.
        pub fn namespace(comptime name: []const u8) type {
            const T = namedType(Container, name);
            if (@typeInfo(T) != .@"struct") @compileError("zigo namespace requires a struct container: " ++ path ++ "." ++ name);
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
        pub fn value(comptime name: []const u8, comptime options: ValueOptions) Entry {
            return typeEntry(name, .{ .value = options });
        }
        pub fn materialized(comptime name: []const u8, comptime options: MaterializedOptions) Entry {
            return typeEntry(name, .{ .materialized = options });
        }
        pub fn enumeration(comptime name: []const u8, comptime options: EnumOptions) Entry {
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
pub fn session(comptime options: Session) Entry {
    return .{ .session = options };
}

pub const DiscoverySelection = struct { exclude: []const FunctionRef = &.{} };
pub const Discovery = union(enum) {
    explicit,
    public: DiscoverySelection,
    recursive: DiscoverySelection,
};
/// Everything a binding says besides its root, which `zigo.scope(library)`
/// already states: `zigo.define(api, .{ ... })` takes the scope.
pub const Binding = struct {
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
    const Item = api.handle("Item", .{}).context();
    const original = comptime Item.members(entries);
    const replaced = comptime original.context().members(&.{api.func("a", .{})});
    try std.testing.expectEqual(@as(usize, 1), replaced.type.options.members.len);
    try std.testing.expectEqualStrings("root.a", replaced.type.options.members[0].function.ref.path);
    const param = comptime (Param{ .index = 1 }).named("alias").named(null);
    try std.testing.expect(param.go_name == null);
    const renamed = api.func("a", .{}).with(.{ .name = "Other" });
    try std.testing.expectEqualStrings("root.a", renamed.functionRef().path);
}
test "contract replacement clears stale ownership and explicit null clears names" {
    const Lib = struct {
        pub fn take() void {}
        pub fn free() void {}
    };
    const result = @import("result.zig");
    const api = scope(Lib);
    const owned = api.func("take", .{ .name = "Take", .returns = result.releasedBy(api.ref("free")) });
    const borrowed = owned.with(.{ .name = null, .returns = result.borrowed() });
    try std.testing.expect(borrowed.function.options.name == null);
    try std.testing.expect(borrowed.function.options.returns.ownership == .borrowed);
}

test "type plugins and explicit replacement keep one typed option payload" {
    const Lib = struct {
        pub const Record = extern struct { value: u32 };
    };
    const P: plugin.Plugin = .{ .name = "TEST", .TypeOptions = struct { limit: ?u32 = 10 }, .subjects = &.{.value} };
    const entry = comptime scope(Lib).value("Record", .{}).use(P, .{ .limit = 5 }).replacePlugin(P, .{ .limit = null });
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
    const P: plugin.Plugin = .{ .name = "DUAL", .FunctionOptions = struct { checked: bool }, .TypeOptions = struct { key: []const u8 }, .subjects = &.{ .function, .value } };
    const api = scope(Lib);
    const f = comptime api.func("f", .{}).use(P, .{ .checked = true });
    const t = comptime api.value("Record", .{}).use(P, .{ .key = "value" });
    const f_json = try f.function.extensions[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(f_json);
    const t_json = try t.type.extensions[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(t_json);
    try std.testing.expectEqualStrings("{\"checked\":true}", f_json);
    try std.testing.expectEqualStrings("{\"key\":\"value\"}", t_json);
}
