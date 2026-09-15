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

/// How a plugin option names an interface: the `Entry` `zigo.interface(...)`
/// returned, or the name the binding gave it. An interface has no Zig
/// declaration behind it, so the name is the whole reference.
pub const InterfaceRef = union(enum) {
    entry: Entry,
    name: []const u8,
};

/// The authoring spelling of one plugin option type. Every field whose type
/// is a `plugin.ref.*` reference is written with the authoring value that
/// names the declaration -- a `TypeRef`, a `FunctionRef`, an `InterfaceRef`
/// -- and `use` turns it into the path the document carries. Optionals,
/// slices and nested option structs map element by element; a plugin that
/// declares no reference gets its own option type back, unchanged.
pub fn Authored(comptime Options: type) type {
    if (Options == plugin.ref.Type) return TypeRef;
    if (Options == plugin.ref.Function) return FunctionRef;
    if (Options == plugin.ref.Interface) return InterfaceRef;
    return switch (@typeInfo(Options)) {
        .optional => |optional| blk: {
            const Child = Authored(optional.child);
            break :blk if (Child == optional.child) Options else ?Child;
        },
        .pointer => |pointer| blk: {
            if (pointer.size != .slice or pointer.child == u8) break :blk Options;
            const Child = Authored(pointer.child);
            break :blk if (Child == pointer.child) Options else []const Child;
        },
        .@"struct" => AuthoredStruct(Options),
        else => Options,
    };
}

fn AuthoredStruct(comptime Options: type) type {
    const info = @typeInfo(Options).@"struct";
    if (info.layout != .auto) return Options;
    comptime var mapped = false;
    comptime var names: [info.fields.len][:0]const u8 = undefined;
    comptime var types: [info.fields.len]type = undefined;
    comptime var attributes: [info.fields.len]std.builtin.Type.StructField.Attributes = undefined;
    inline for (info.fields, 0..) |field, index| {
        const Mapped = Authored(field.type);
        names[index] = field.name;
        types[index] = Mapped;
        attributes[index] = if (Mapped == field.type)
            .{ .default_value_ptr = field.default_value_ptr }
        else
            .{ .default_value_ptr = authoredDefault(Mapped) };
        if (Mapped != field.type) mapped = true;
    }
    if (!mapped) return Options;
    const frozen_names = names;
    const frozen_types = types;
    const frozen_attributes = attributes;
    return @Struct(.auto, null, &frozen_names, &frozen_types, &frozen_attributes);
}

/// What a mapped field defaults to: nothing to reference, or no default at
/// all when the plugin asked for a reference outright.
fn authoredDefault(comptime Mapped: type) ?*const anyopaque {
    return switch (@typeInfo(Mapped)) {
        .optional => @ptrCast(&@as(Mapped, null)),
        .pointer => @ptrCast(&@as(Mapped, &.{})),
        else => null,
    };
}

/// One reference an option value named, kept for the root check the
/// attachment site could not make itself. A field or a tag literal is written
/// before the `api.value(...)` call that knows the binding, so `normalize`
/// makes the check there.
pub const RootRef = struct { root: type, path: []const u8 };

/// One authoring option value as the document carries it, for an attachment
/// that knows the binding it belongs to: a reference into another
/// `zigo.define` is refused here rather than resolving to nothing at
/// generation time.
fn checkedOptions(comptime Options: type, comptime value: Authored(Options), comptime root: ?type) Options {
    comptime var named: []const RootRef = &.{};
    return authoredOptions(Options, value, root, &named);
}

/// The same mapping, collecting every reference into `named`. `root` is the
/// binding the attachment belongs to when the attachment site knows it, and
/// null when the check is left to whoever reads `named`.
fn authoredOptions(comptime Options: type, comptime value: Authored(Options), comptime root: ?type, comptime named: *[]const RootRef) Options {
    if (Options == plugin.ref.Type) {
        comptime checkReferenceRoot(value.root, root, value.path);
        named.* = named.* ++ [_]RootRef{.{ .root = value.root, .path = value.path }};
        return .{ .path = @typeName(value.type) };
    }
    if (Options == plugin.ref.Function) {
        comptime checkReferenceRoot(value.root, root, value.path);
        named.* = named.* ++ [_]RootRef{.{ .root = value.root, .path = value.path }};
        return .{ .path = if (value.container == value.root) value.name else @typeName(value.container) ++ "." ++ value.name };
    }
    if (Options == plugin.ref.Interface) return .{ .name = switch (value) {
        .entry => |entry| if (entry == .interface) entry.interface.name else @compileError("zigo an interface reference requires a zigo.interface declaration"),
        .name => |name| name,
    } };
    if (Authored(Options) == Options) return value;
    return switch (@typeInfo(Options)) {
        .optional => |optional| if (value) |inner| authoredOptions(optional.child, inner, root, named) else null,
        .pointer => |pointer| blk: {
            comptime var mapped: [value.len]pointer.child = undefined;
            inline for (value, 0..) |item, index| mapped[index] = authoredOptions(pointer.child, item, root, named);
            const frozen = mapped;
            break :blk &frozen;
        },
        .@"struct" => |info| blk: {
            var result: Options = undefined;
            inline for (info.fields) |field| {
                @field(result, field.name) = authoredOptions(field.type, @field(value, field.name), root, named);
            }
            break :blk result;
        },
        else => value,
    };
}

fn checkReferenceRoot(comptime actual: type, comptime expected: ?type, comptime path: []const u8) void {
    const binding = expected orelse return;
    if (actual != binding) @compileError("zigo plugin option references a type outside this binding: " ++ path);
}

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
    pub fn use(comptime self: Returns, comptime P: plugin.Plugin, comptime options: Authored(P.ResultOptions)) Returns {
        comptime checkNodeSubject(P, .result);
        comptime checkDuplicateAttachment(self.extensions, P.name);
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.ResultOptions;
        };
        const written = comptime checkedOptions(P.ResultOptions, options, null);
        var result = self;
        result.extensions = self.extensions ++ [_]ir.Extension{ir.extension(Captured, written)};
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
    pub fn use(comptime self: Param, comptime P: plugin.Plugin, comptime options: Authored(P.ParamOptions)) Param {
        comptime checkNodeSubject(P, .param);
        comptime checkDuplicateAttachment(self.extensions, P.name);
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.ParamOptions;
        };
        // A parameter names no binding of its own, so a reference here is
        // checked only where every reference is: against the document.
        const written = comptime checkedOptions(P.ParamOptions, options, null);
        var copy = self;
        copy.extensions = self.extensions ++ [_]ir.Extension{ir.extension(Captured, written)};
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

/// A getter (and optionally setter) on a handle, reached by a dotted field
/// path.
pub const HandleField = struct {
    path: []const u8,
    name: ?[]const u8 = null,
    set: bool = false,
    doc: ?[]const u8 = null,
    /// Plugin options, one entry per plugin. Written by `extend`. The getter
    /// and the setter both carry them, the way they share `doc`.
    ext: []const ir.Extension = &.{},
    /// The references those options named, checked in `normalize` against the
    /// binding the owning handle belongs to.
    refs: []const RootRef = &.{},

    /// Attach `options` as plugin `P`'s function options for the accessors
    /// this field synthesizes. A plugin whose `subjects` exclude `.function`
    /// is refused here, where the declaration is written.
    pub fn extend(comptime self: HandleField, comptime P: plugin.Plugin, comptime options: Authored(P.FunctionOptions)) HandleField {
        comptime checkNodeSubject(P, .function);
        comptime checkDuplicateAttachment(self.ext, P.name);
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.FunctionOptions;
        };
        comptime var named: []const RootRef = &.{};
        const written = comptime authoredOptions(P.FunctionOptions, options, null, &named);
        var result = self;
        result.ext = self.ext ++ [_]ir.Extension{ir.extension(Captured, written)};
        result.refs = self.refs ++ named;
        return result;
    }
};

/// A hint for one field of a value or materialized struct.
pub const ValueField = struct {
    name: []const u8,
    semantic: ?SemanticHint = null,
    /// Go doc for this field. Absent takes the Zig source's `///`, and
    /// failing that the generated description.
    doc: ?[]const u8 = null,
    /// Plugin options, one entry per plugin. Written by `use`.
    ext: []const ir.Extension = &.{},
    /// The references those options named, checked in `normalize` against the
    /// binding the owning type belongs to.
    refs: []const RootRef = &.{},

    /// Attach `options` as plugin `P`'s field options for this member. A
    /// plugin whose `subjects` exclude `.field` is refused here, where the
    /// declaration is written.
    pub fn use(comptime self: ValueField, comptime P: plugin.Plugin, comptime options: Authored(P.FieldOptions)) ValueField {
        comptime checkNodeSubject(P, .field);
        comptime checkDuplicateAttachment(self.ext, P.name);
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.FieldOptions;
        };
        comptime var named: []const RootRef = &.{};
        const written = comptime authoredOptions(P.FieldOptions, options, null, &named);
        var result = self;
        result.ext = self.ext ++ [_]ir.Extension{ir.extension(Captured, written)};
        result.refs = self.refs ++ named;
        return result;
    }
};

/// Go doc for one member of a registered enum, by its Zig tag name.
pub const EnumField = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
    /// Plugin options, one entry per plugin. Written by `use`.
    ext: []const ir.Extension = &.{},
    /// The references those options named, checked in `normalize` against the
    /// binding the owning enum belongs to.
    refs: []const RootRef = &.{},

    /// Attach `options` as plugin `P`'s tag options for this member. A plugin
    /// whose `subjects` exclude `.enum_tag` is refused here.
    pub fn use(comptime self: EnumField, comptime P: plugin.Plugin, comptime options: Authored(P.TagOptions)) EnumField {
        comptime checkNodeSubject(P, .enum_tag);
        comptime checkDuplicateAttachment(self.ext, P.name);
        const Captured = struct {
            pub const name = P.name;
            pub const Options = P.TagOptions;
        };
        comptime var named: []const RootRef = &.{};
        const written = comptime authoredOptions(P.TagOptions, options, null, &named);
        var result = self;
        result.ext = self.ext ++ [_]ir.Extension{ir.extension(Captured, written)};
        result.refs = self.refs ++ named;
        return result;
    }
};

pub const HandleOptions = struct { fields: []const HandleField = &.{} };
pub const ValueOptions = struct { fields: []const ValueField = &.{}, go: ?GoAdapter = null };
pub const MaterializedOptions = struct { fields: []const ValueField = &.{} };
pub const EnumOptions = struct {
    exhaustive: bool = true,
    /// Generate `Parse<Enum>`, `MarshalText` and `UnmarshalText`.
    text: bool = false,
    go: ?GoAdapter = null,
    covers: []const FunctionRef = &.{},
    fields: []const EnumField = &.{},
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
            pub const Options = pluginWireOptions(P, self);
        };
        const written = comptime checkedOptions(Captured.Options, options, entryRoot(self));
        var captured = ir.extension(Captured, written);
        // The two built-ins whose options the reflector resolves before it
        // writes them -- an iterator name derived from the method it advances,
        // the interface list checked for emptiness here rather than a
        // declaration later. Both attach to a function; `.implements` also
        // names `.handle` as a subject, for the assertions its plugin writes
        // after the type, and a type carries no options of its own.
        const on_function = switch (self) {
            .function => true,
            else => false,
        };
        if (on_function) {
            if (std.mem.eql(u8, P.name, features.iterator.name)) {
                captured.builtin = .{ .iterator = written };
            } else if (std.mem.eql(u8, P.name, features.implements.name)) {
                if (written.kinds.len == 0) @compileError("zigo implements needs a non-empty `.kinds`");
                captured.builtin = .{ .implements = written };
            }
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

/// What a declaration writes when it attaches `P`: the plugin's own option
/// type, with every reference field spelled the way a binding names a
/// declaration.
fn pluginOptions(comptime P: plugin.Plugin, comptime entry: Entry) type {
    return Authored(pluginWireOptions(P, entry));
}
/// The same options as the document carries them.
fn pluginWireOptions(comptime P: plugin.Plugin, comptime entry: Entry) type {
    return if (entry == .function) P.FunctionOptions else P.TypeOptions;
}
/// The binding a declaration belongs to, which is the root every reference in
/// its options has to resolve against.
fn entryRoot(comptime entry: Entry) type {
    return switch (entry) {
        .function => |f| f.ref.root,
        .type => |t| t.ref.root,
        else => @compileError("zigo plugins attach to functions or types"),
    };
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

test "reference options travel as the native path a reflector writes" {
    const Lib = struct {
        pub const Context = opaque {
            pub fn close(_: *@This()) void {}
        };
        pub fn open() void {}
    };
    const P: plugin.Plugin = .{
        .name = "REF",
        .TypeOptions = struct {
            target: ?plugin.ref.Type = null,
            satisfies: []const plugin.ref.Interface = &.{},
        },
        .FunctionOptions = struct { helper: ?plugin.ref.Function = null },
        .subjects = &.{ .handle, .function },
    };
    const api = scope(Lib);
    const readable = comptime interface(.{ .name = "Readable", .methods = &.{"close"}, .types = &.{api.typeRef("Context")} });
    const Holder = comptime api.handle("Context", .{}).context();
    const declared = comptime Holder.members(&.{}).use(P, .{
        .target = api.typeRef("Context"),
        .satisfies = &.{ .{ .entry = readable }, .{ .name = "Closer" } },
    });
    const type_json = try declared.type.extensions[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(type_json);
    var parsed = try std.json.parseFromSlice(struct { target: []const u8, satisfies: []const []const u8 }, std.testing.allocator, type_json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(@typeName(Lib.Context), parsed.value.target);
    try std.testing.expect(std.mem.endsWith(u8, parsed.value.target, ".Context"));
    try std.testing.expectEqualStrings("Readable", parsed.value.satisfies[0]);
    try std.testing.expectEqualStrings("Closer", parsed.value.satisfies[1]);

    // A function declared at the binding root is its own path; one reached
    // through a type carries the container the method is declared in.
    const free = comptime api.func("open", .{}).use(P, .{ .helper = api.ref("open") });
    const free_json = try free.function.extensions[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(free_json);
    try std.testing.expectEqualStrings("{\"helper\":\"open\"}", free_json);
    const method = comptime api.func("open", .{}).use(P, .{ .helper = Holder.ref("close") });
    const method_json = try method.function.extensions[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(method_json);
    try std.testing.expect(std.mem.indexOf(u8, method_json, ".Context.close\"}") != null);
}

test "field and tag options name declarations the way a declaration's do" {
    const Lib = struct {
        pub const Context = opaque {};
        pub const Point = extern struct { x: i32 };
        pub const Mode = enum(u8) { idle };
    };
    const P: plugin.Plugin = .{
        .name = "REF",
        .FieldOptions = struct { target: ?plugin.ref.Type = null },
        .TagOptions = struct { target: ?plugin.ref.Type = null },
        .FunctionOptions = struct { helper: ?plugin.ref.Function = null },
        .subjects = &.{ .value, .enumeration, .handle, .function, .field, .enum_tag },
    };
    const api = scope(Lib);
    const field = comptime (ValueField{ .name = "x" }).use(P, .{ .target = api.typeRef("Context") });
    const field_json = try field.ext[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(field_json);
    try std.testing.expectEqualStrings("{\"target\":\"" ++ @typeName(Lib.Context) ++ "\"}", field_json);
    // The reference is kept for the root check `normalize` makes: a field
    // literal is written before the declaration that names the binding.
    try std.testing.expectEqual(@as(usize, 1), field.refs.len);
    try std.testing.expect(field.refs[0].root == Lib);

    const tag = comptime (EnumField{ .name = "idle" }).use(P, .{ .target = api.typeRef("Point") });
    const tag_json = try tag.ext[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(tag_json);
    try std.testing.expectEqualStrings("{\"target\":\"" ++ @typeName(Lib.Point) ++ "\"}", tag_json);
    try std.testing.expectEqual(@as(usize, 1), tag.refs.len);

    // A handle field carries the accessors' function options, references and all.
    const accessor = comptime (HandleField{ .path = "x" }).extend(P, .{});
    try std.testing.expectEqual(@as(usize, 0), accessor.refs.len);
    const accessor_json = try accessor.ext[0].jsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(accessor_json);
    try std.testing.expectEqualStrings("{\"helper\":null}", accessor_json);
}
