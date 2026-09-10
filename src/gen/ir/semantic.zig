const std = @import("std");
const naming = @import("naming");

pub const Int = struct {
    bits: u16,
    is_usize: bool = false,
    signed: bool,
};

pub const Float = struct { bits: u16 };
pub const Ref = struct { ref: []const u8 };
/// A struct whose complete pointer-bearing result tree is serialized by the
/// shim. `pointer` distinguishes an embedded value from a referenced node;
/// `nullable` is meaningful only for referenced nodes.
pub const Materialized = struct {
    ref: []const u8,
    pointer: bool = false,
    nullable: bool = false,
};
pub const OpaquePtr = struct {
    /// The Zig declaration takes the registered opaque type by value. C and
    /// Go still pass its handle pointer; only the shim dereferences it to make
    /// the copy the Zig call expects. Omitted for ordinary pointer handles so
    /// existing semantic documents stay byte-identical.
    by_value: bool = false,
    @"const": bool,
    nullable: bool,
    ref: []const u8,
};
pub const Slice = struct {
    @"const": bool,
    element: *TypeNode,
    /// A sentinel on the Zig slice or many-pointer spelling. The semantic
    /// shape stays a slice so older IR readers can still parse ordinary byte
    /// slices, while string-slice lowering can reproduce the declared element.
    sentinel: ?u8 = null,
    /// True when `sentinel` came from a many pointer (`[*:0]T`) rather than a
    /// sentinel slice (`[:0]T`). Meaningful only when `sentinel` is present.
    sentinel_many: bool = false,
};
pub const Optional = struct { child: *TypeNode };
/// Which direction a `*std.Io.Writer` / `*std.Io.Reader` parameter streams.
/// The two lower to different fixed callback signatures, so the direction is
/// the whole of the type: neither side carries a payload type.
pub const StreamDirection = enum { writer, reader };
pub const IoStream = struct { direction: StreamDirection };
/// A call-scoped pointer to `std.atomic.Value(T)`. The wrapper is erased from
/// the C shape, while this node keeps enough information to spell Go's typed
/// `sync/atomic` pointer and rebuild the Zig pointer in the shim.
pub const AtomicPtr = struct {
    child: *TypeNode,
    @"const": bool,
};
pub const ErrorUnion = struct {
    anyerror: bool = false,
    error_set: []const []const u8,
    payload: *TypeNode,
};
/// Domain value returned to native code when a Go callback cannot produce its
/// ordinary result. The failure is still recorded for the public wrapper.
pub const CallbackFailure = struct { result: i128 };
pub const Callback = struct {
    c_callconv: bool = true,
    has_userdata: bool,
    /// `params` lists the value parameters in native order with the userdata
    /// slot last, which is the order Go dispatches in. When the native
    /// signature declares userdata elsewhere this is its native position and
    /// the shim thunk reorders the arguments; absent means it is last there too.
    userdata_at: ?usize = null,
    params: []const TypeNode,
    /// One hint per entry of `params` (the userdata slot is always null).
    /// Only `codepoint` on a `u32` is meaningful; absent when no parameter
    /// carries a hint.
    param_semantics: ?[]const ?SemanticHint = null,
    /// The hint on the callback's result.
    return_semantic: ?SemanticHint = null,
    /// The declared callback type this signature was registered under, when
    /// the binding registered one (`.callback`). It names the Go
    /// type; the signature alone still decides the ABI.
    ref: ?[]const u8 = null,
    @"return": *TypeNode,

    pub fn paramHint(self: Callback, index: usize) ?SemanticHint {
        const hints = self.param_semantics orelse return null;
        return if (index < hints.len) hints[index] else null;
    }

    /// How many of `params` carry a value; the userdata slot is not one.
    pub fn valueCount(self: Callback) usize {
        return if (self.has_userdata and self.params.len != 0) self.params.len - 1 else self.params.len;
    }

    /// Where the userdata slot sits in the native signature.
    pub fn nativeUserdataIndex(self: Callback) ?usize {
        if (!self.has_userdata or self.params.len == 0) return null;
        return self.userdata_at orelse self.nativeParamCount() - 1;
    }

    /// The `params` index of the parameter at native position `native`.
    /// Positions count native parameters, so a byte pair (`[*]const u8`,
    /// `usize`) takes two of them; `slotAtNative` tells the halves apart.
    pub fn goIndexOfNative(self: Callback, native: usize) usize {
        return self.slotAtNative(native).index;
    }

    /// How many native parameters the callback declares: one per value, two
    /// for a byte pair, and the userdata slot.
    pub fn nativeParamCount(self: Callback) usize {
        var count: usize = 0;
        for (self.params) |node| count += nativeSlots(node);
        return count;
    }

    /// Where native parameter `native` lands in `params`, and which half of a
    /// byte pair it is when the parameter is one.
    pub fn slotAtNative(self: Callback, native: usize) NativeSlot {
        const userdata = self.nativeUserdataIndex();
        if (userdata != null and native == userdata.?) return .{ .index = self.params.len - 1, .part = .value };
        var position: usize = 0;
        const value_count = self.valueCount();
        for (self.params[0..value_count], 0..) |node, index| {
            const slots = nativeSlots(node);
            // The userdata slot sits between value parameters; skip over it.
            if (userdata != null and position <= userdata.? and userdata.? < position + slots) position += 1;
            if (native < position + slots) return .{
                .index = index,
                .part = if (slots == 1) .value else if (native == position) .pointer else .length,
            };
            position += slots;
        }
        unreachable;
    }

    /// Whether a value position carries a byte pair or a sentinel string,
    /// which Go receives as a copied `string` or `[]byte`.
    pub fn hasBytePayload(self: Callback) bool {
        for (self.params[0..self.valueCount()]) |node| if (isBytePayload(node)) return true;
        return false;
    }

    /// Whether any position of the signature is spelled differently in Go
    /// than in the raw closure, so the handle constructor needs an adapter.
    pub fn hasCodepoints(self: Callback) bool {
        if (self.param_semantics) |hints| for (hints, self.params) |hint, node| if (isCodepoint(node, hint)) return true;
        return isCodepoint(self.@"return".*, self.return_semantic);
    }
};

/// One native parameter of a callback, located in the Go-order `params`.
pub const NativeSlot = struct {
    index: usize,
    part: enum { value, pointer, length },
};

/// A callback value Go receives as text or bytes: a const byte slice, which
/// the native signature spells as a `[*]const u8` + `usize` pair, or a
/// `[*:0]const u8` sentinel string. Either is copied into Go memory before
/// the callback runs, so it may be kept after the callback returns.
pub fn isBytePayload(node: TypeNode) bool {
    return node == .slice and node.slice.@"const" and isByte(node.slice.element.*);
}

/// Whether a byte payload's hint makes it Go text (`string`) rather than
/// `[]byte`.
pub fn isTextHint(hint: ?SemanticHint) bool {
    return hint == .utf8_string or hint == .c_string;
}

/// A byte payload the native signature spells as two parameters.
pub fn isBytePair(node: TypeNode) bool {
    return isBytePayload(node) and node.slice.sentinel == null;
}

/// How many native parameters one callback value occupies.
pub fn nativeSlots(node: TypeNode) usize {
    return if (isBytePair(node)) 2 else 1;
}

pub const TypeNode = union(enum) {
    atomic_ptr: AtomicPtr,
    bool: void,
    callback: Callback,
    /// The cancellation flag a `.cancel` function polls. Its Zig spelling is
    /// `*const std.atomic.Value(u32)` and it crosses as `const uint32_t *`;
    /// it is its own node because neither the pointer nor the atomic wrapper
    /// is a shape the generic lowering can carry, and because Go builds the
    /// flag itself rather than being handed one.
    cancel_flag: void,
    @"enum": Ref,
    error_union: ErrorUnion,
    float: Float,
    int: Int,
    io_stream: IoStream,
    materialized: Materialized,
    opaque_ptr: OpaquePtr,
    optional: Optional,
    slice: Slice,
    value_struct: Ref,
    void: void,

    /// The node behind an error union, or the node itself.
    pub fn errorPayload(self: TypeNode) TypeNode {
        return if (self == .error_union) self.error_union.payload.* else self;
    }

    pub fn jsonStringify(self: TypeNode, jw: anytype) !void {
        try jw.beginObject();
        switch (self) {
            .atomic_ptr => |value| {
                try jw.objectField("child");
                try jw.write(value.child.*);
                try jw.objectField("const");
                try jw.write(value.@"const");
                try writeKind(jw, "atomic_ptr");
            },
            .bool => try writeKind(jw, "bool"),
            .cancel_flag => try writeKind(jw, "cancel_flag"),
            .callback => |value| {
                try jw.objectField("c_callconv");
                try jw.write(value.c_callconv);
                try jw.objectField("has_userdata");
                try jw.write(value.has_userdata);
                try writeKind(jw, "callback");
                if (value.userdata_at) |at| {
                    try jw.objectField("userdata_at");
                    try jw.write(at);
                }
                if (value.param_semantics) |hints| {
                    try jw.objectField("param_semantics");
                    try jw.write(hints);
                }
                try jw.objectField("params");
                try jw.write(value.params);
                if (value.ref) |ref| {
                    try jw.objectField("ref");
                    try jw.write(ref);
                }
                try jw.objectField("return");
                try jw.write(value.@"return".*);
                if (value.return_semantic) |hint| {
                    try jw.objectField("return_semantic");
                    try jw.write(hint);
                }
            },
            .@"enum" => |value| {
                try writeKind(jw, "enum");
                try jw.objectField("ref");
                try jw.write(value.ref);
            },
            .error_union => |value| {
                if (value.anyerror) {
                    try jw.objectField("anyerror");
                    try jw.write(true);
                }
                try jw.objectField("error_set");
                try jw.write(value.error_set);
                try writeKind(jw, "error_union");
                try jw.objectField("payload");
                try jw.write(value.payload.*);
            },
            .float => |value| {
                try jw.objectField("bits");
                try jw.write(value.bits);
                try writeKind(jw, "float");
            },
            .int => |value| {
                try jw.objectField("bits");
                try jw.write(value.bits);
                try jw.objectField("is_usize");
                try jw.write(value.is_usize);
                try writeKind(jw, "int");
                try jw.objectField("signed");
                try jw.write(value.signed);
            },
            .io_stream => |value| try writeKind(jw, switch (value.direction) {
                .writer => "io_writer",
                .reader => "io_reader",
            }),
            .materialized => |value| {
                try writeKind(jw, "materialized");
                if (value.pointer) {
                    try jw.objectField("pointer");
                    try jw.write(true);
                }
                if (value.nullable) {
                    try jw.objectField("nullable");
                    try jw.write(true);
                }
                try jw.objectField("ref");
                try jw.write(value.ref);
            },
            .opaque_ptr => |value| {
                if (value.by_value) {
                    try jw.objectField("by_value");
                    try jw.write(true);
                }
                try jw.objectField("const");
                try jw.write(value.@"const");
                try writeKind(jw, "opaque_ptr");
                try jw.objectField("nullable");
                try jw.write(value.nullable);
                try jw.objectField("ref");
                try jw.write(value.ref);
            },
            .optional => |value| {
                try jw.objectField("child");
                try jw.write(value.child.*);
                try writeKind(jw, "optional");
            },
            .slice => |value| {
                try jw.objectField("const");
                try jw.write(value.@"const");
                try jw.objectField("element");
                try jw.write(value.element.*);
                if (value.sentinel) |sentinel| {
                    try jw.objectField("sentinel");
                    try jw.write(sentinel);
                    if (value.sentinel_many) {
                        try jw.objectField("sentinel_many");
                        try jw.write(true);
                    }
                }
                try writeKind(jw, "slice");
            },
            .value_struct => |value| {
                try writeKind(jw, "value_struct");
                try jw.objectField("ref");
                try jw.write(value.ref);
            },
            .void => try writeKind(jw, "void"),
        }
        try jw.endObject();
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!TypeNode {
        const object = switch (source) {
            .object => |object| object,
            else => return error.UnexpectedToken,
        };
        const kind_value = object.get("kind") orelse return error.MissingField;
        const kind = switch (kind_value) {
            .string => |string| string,
            else => return error.UnexpectedToken,
        };
        if (std.mem.eql(u8, kind, "void")) return .{ .void = {} };
        if (std.mem.eql(u8, kind, "atomic_ptr")) return .{ .atomic_ptr = .{
            .child = try parseTypePointer(allocator, object, "child", options),
            .@"const" = try parseField(bool, allocator, object, "const", options),
        } };
        if (std.mem.eql(u8, kind, "bool")) return .{ .bool = {} };
        if (std.mem.eql(u8, kind, "cancel_flag")) return .{ .cancel_flag = {} };
        if (std.mem.eql(u8, kind, "int")) return .{ .int = .{
            .bits = try parseField(u16, allocator, object, "bits", options),
            .is_usize = try parseOptionalField(bool, allocator, object, "is_usize", false, options),
            .signed = try parseField(bool, allocator, object, "signed", options),
        } };
        if (std.mem.eql(u8, kind, "float")) return .{ .float = .{
            .bits = try parseField(u16, allocator, object, "bits", options),
        } };
        if (std.mem.eql(u8, kind, "enum")) return .{ .@"enum" = .{
            .ref = try parseField([]const u8, allocator, object, "ref", options),
        } };
        if (std.mem.eql(u8, kind, "value_struct")) return .{ .value_struct = .{
            .ref = try parseField([]const u8, allocator, object, "ref", options),
        } };
        if (std.mem.eql(u8, kind, "materialized")) return .{ .materialized = .{
            .ref = try parseField([]const u8, allocator, object, "ref", options),
            .pointer = try parseOptionalField(bool, allocator, object, "pointer", false, options),
            .nullable = try parseOptionalField(bool, allocator, object, "nullable", false, options),
        } };
        if (std.mem.eql(u8, kind, "io_writer")) return .{ .io_stream = .{ .direction = .writer } };
        if (std.mem.eql(u8, kind, "io_reader")) return .{ .io_stream = .{ .direction = .reader } };
        if (std.mem.eql(u8, kind, "opaque_ptr")) return .{ .opaque_ptr = .{
            .by_value = try parseOptionalField(bool, allocator, object, "by_value", false, options),
            .@"const" = try parseField(bool, allocator, object, "const", options),
            .nullable = try parseField(bool, allocator, object, "nullable", options),
            .ref = try parseField([]const u8, allocator, object, "ref", options),
        } };
        if (std.mem.eql(u8, kind, "slice")) return .{ .slice = .{
            .@"const" = try parseField(bool, allocator, object, "const", options),
            .element = try parseTypePointer(allocator, object, "element", options),
            .sentinel = if (object.get("sentinel")) |value|
                try std.json.parseFromValueLeaky(u8, allocator, value, options)
            else
                null,
            .sentinel_many = try parseOptionalField(bool, allocator, object, "sentinel_many", false, options),
        } };
        if (std.mem.eql(u8, kind, "optional")) return .{ .optional = .{
            .child = try parseTypePointer(allocator, object, "child", options),
        } };
        if (std.mem.eql(u8, kind, "error_union")) return .{ .error_union = .{
            .anyerror = try parseOptionalField(bool, allocator, object, "anyerror", false, options),
            .error_set = try parseField([]const []const u8, allocator, object, "error_set", options),
            .payload = try parseTypePointer(allocator, object, "payload", options),
        } };
        if (std.mem.eql(u8, kind, "callback")) return .{ .callback = .{
            .c_callconv = try parseOptionalField(bool, allocator, object, "c_callconv", true, options),
            .has_userdata = try parseField(bool, allocator, object, "has_userdata", options),
            .userdata_at = try parseOptionalField(?usize, allocator, object, "userdata_at", null, options),
            .param_semantics = try parseOptionalField(?[]const ?SemanticHint, allocator, object, "param_semantics", null, options),
            .params = try parseField([]const TypeNode, allocator, object, "params", options),
            .ref = try parseOptionalField(?[]const u8, allocator, object, "ref", null, options),
            .@"return" = try parseTypePointer(allocator, object, "return", options),
            .return_semantic = try parseOptionalField(?SemanticHint, allocator, object, "return_semantic", null, options),
        } };
        return error.InvalidEnumTag;
    }
};

fn writeKind(jw: anytype, kind: []const u8) !void {
    try jw.objectField("kind");
    try jw.write(kind);
}

fn parseField(comptime T: type, allocator: std.mem.Allocator, object: std.json.ObjectMap, name: []const u8, options: std.json.ParseOptions) !T {
    return std.json.parseFromValueLeaky(T, allocator, object.get(name) orelse return error.MissingField, options);
}

fn parseOptionalField(comptime T: type, allocator: std.mem.Allocator, object: std.json.ObjectMap, name: []const u8, default: T, options: std.json.ParseOptions) !T {
    const value = object.get(name) orelse return default;
    return std.json.parseFromValueLeaky(T, allocator, value, options);
}

fn parseTypePointer(allocator: std.mem.Allocator, object: std.json.ObjectMap, name: []const u8, options: std.json.ParseOptions) std.json.ParseFromValueError!*TypeNode {
    const pointer = try allocator.create(TypeNode);
    errdefer allocator.destroy(pointer);
    pointer.* = try TypeNode.jsonParseFromValue(allocator, object.get(name) orelse return error.MissingField, options);
    return pointer;
}

pub const NameSource = enum { ast, fallback, sidecar };
/// A parameter the shim fills in rather than one the caller passes. Zig types
/// like `std.mem.Allocator` have no C representation, so the binding names the
/// value once and every generated signature drops the parameter.
pub const Injection = enum { allocator, io };
pub const Direction = enum { in, inout, out };
pub const Retention = enum { borrowed, retained };
pub const CallbackReentrancy = enum { allowed, forbidden };
pub const CallbackThread = enum { caller, any };
/// `codepoint` marks a `u21`/`u32` (or a plain slice of one) as a Unicode
/// scalar value: the raw carrier stays `uint32`, and the public Go API spells
/// it `rune`. `integer` is the opposite claim, for a `u21` a binding with
/// `.codepoints = .infer_u21` would otherwise infer; reflection records it as
/// no hint at all, so a document never carries it.
pub const SemanticHint = enum { c_string, opaque_bytes, utf8_string, codepoint, integer };

/// The largest Unicode scalar value. A codepoint position is checked against
/// this rather than against the Zig integer's own range.
pub const max_codepoint: u32 = 0x10FFFF;
/// Who owns a function's result. `library` is reserved: no generator rule
/// reads it, and it stays only so documents that spelled it still parse.
pub const Ownership = enum { borrowed, caller, library };
/// How much of an `.out` slice the shim reports back as written. `.all` keeps
/// the whole buffer, `.return` trusts the function's `usize` result.
pub const Written = enum { all, @"return" };

/// A parameter's location in the source that declared it, from
/// `names.zig`'s AST scan. Unlike `SourceLocation` this carries no path: a
/// parameter's path is always its owning function's.
pub const ParamSourceLocation = struct {
    line: u32,
    column: u32,
};

/// One scalar field selected from a struct parameter by
/// `Param.flatten`. The original parameter type remains on
/// `Parameter.type`; this list describes the Go/C arguments that replace it.
pub const FlattenedField = struct {
    /// The Zig field is `std.atomic.Value(T)` while the public/ABI type is T.
    atomic: ?bool = null,
    name: []const u8,
    type: TypeNode,
};

pub const Parameter = struct {
    /// Native position among parameters, excluding the receiver. If any entry
    /// sets this, every entry must form a permutation of 0..params.len.
    native_index: ?usize = null,
    /// The Zig parameter is `std.atomic.Value(T)` while Go and C pass T.
    atomic: ?bool = null,
    /// Bytes of shim-side staging buffer behind an `*std.Io.Writer` or
    /// `*std.Io.Reader` parameter, from `Param.buffer`. Only the
    /// buffer size changes; the C signature does not, so this is an ABI
    /// compatible knob rather than part of the shape.
    buffer: ?u32 = null,
    direction: Direction = .in,
    /// Selected fields of a plain struct parameter, in metadata order.
    /// Absent means the parameter crosses in its ordinary shape.
    flatten: ?[]const FlattenedField = null,
    /// Set on the parameter `.cancel = .{ .param = "..." }` named. The type
    /// node says whether the Zig spelling was the one the contract requires;
    /// this says the binding asked for it, so a mismatch can be reported
    /// against the parameter the author meant rather than passed over.
    cancel: ?bool = null,
    /// What only the Go backend reads about this parameter.
    go: ?ParamGo = null,
    /// Parameter-level override for the result a failed callback returns.
    /// Absent preserves the historical in-band sentinel behavior.
    on_callback_failure: ?CallbackFailure = null,
    /// Whether the native side may invoke this callback while a call into the
    /// binding is still active. Documentation only; zigo does not enforce it.
    reentrancy: ?CallbackReentrancy = null,
    /// Which native thread may invoke this callback. Documentation only;
    /// zigo deliberately does not add thread pinning for this contract.
    thread: ?CallbackThread = null,
    /// `Param.userdata`: the parameter of the same function that
    /// carries this callback's Go token. Absent means the one right after
    /// the callback.
    userdata: ?[]const u8 = null,
    /// Set when the shim supplies this argument. An injected parameter is
    /// absent from the C and Go signatures, so adding or removing one is a
    /// breaking change even though nothing about the Zig type moved.
    injected: ?Injection = null,
    name: []const u8,
    name_source: NameSource = .fallback,
    retention: Retention = .borrowed,
    semantic: ?SemanticHint = null,
    /// Where the parameter's name token sits in the source `names.zig`
    /// scanned it from. A diagnostic without this falls back to
    /// `semantic.json` for its location, just like a function without
    /// `SemanticFn.source`.
    source: ?ParamSourceLocation = null,
    type: TypeNode,
    written: ?Written = null,

    /// The staging buffer a stream parameter was declared with, or the
    /// default when it kept it.
    pub fn bufferSize(self: Parameter) u32 {
        return self.buffer orelse default_stream_buffer;
    }

    /// Whether the Go callback behind this parameter may return an `error`.
    /// Parameters that never asked never carry the field.
    pub fn goError(self: Parameter) bool {
        return (self.go orelse ParamGo{}).callback_error orelse false;
    }

    /// Record whether the Go callback behind this parameter returns an error.
    pub fn setGoError(self: *Parameter, value: bool) void {
        var go = self.go orelse ParamGo{};
        go.callback_error = if (value) true else null;
        self.go = go.compact();
    }

    /// The Go type a parameter's scalar is spelled as, with the conversions
    /// either side of the raw call. Reads go through here so the Go
    /// projection can move without touching every caller.
    pub fn goAdapter(self: Parameter) ?GoAdapter {
        return (self.go orelse ParamGo{}).adapter;
    }

    /// Record the Go type this parameter's scalar is spelled as.
    pub fn setGoAdapter(self: *Parameter, value: ?GoAdapter) void {
        var go = self.go orelse ParamGo{};
        go.adapter = value;
        self.go = go.compact();
    }

    /// The written hint a parameter was declared with. Parameters that keep
    /// the default never carry the field.
    pub fn writtenHint(self: Parameter) Written {
        return self.written orelse .all;
    }
};

/// Which half of a boxed constructor pair a function is. A Zig `init` that
/// returns its value has no C representation, so the shim allocates storage
/// with the binding's allocator and hands Go a pointer; the paired `deinit`
/// frees that storage after running the Zig destructor.
pub const Boxed = enum { create, destroy };

/// The staging buffer a stream parameter gets without asking. 64 KiB is large
/// enough that a Go `Write` costs one boundary crossing per 64 KiB of payload
/// and small enough to sit on the shim's stack.
pub const default_stream_buffer: u32 = 65536;
/// Below this a buffer stops amortizing the boundary crossing; above it the
/// staging array stops being a plausible object at all.
pub const min_stream_buffer: u32 = 4096;
pub const max_stream_buffer: u32 = 16 * 1024 * 1024;
/// Above this the staging buffer is heap allocated rather than declared as a
/// stack array, because a shim frame that large is a stack overflow waiting
/// for a deep call.
pub const stream_heap_threshold: u32 = 256 * 1024;

/// Where a function's name token sits in the source `names.zig` scanned it
/// from. Set at most once per function, the same way `doc` is: the first
/// source file that resolves the declaration wins. A diagnostic sourced from
/// a `SemanticFn` without this field still renders against `semantic.json`,
/// exactly as it did before this field existed.
pub const SourceLocation = struct {
    path: []const u8,
    line: u32,
    column: u32,
};

/// One operation of a stream a Zig method hands out. A `fn writer(self)
/// *std.Io.Writer` has no C representation of its own -- the pointer belongs
/// to the object and outliving it is undefined -- so it is expanded into the
/// operations Go needs to satisfy `io.Writer`/`io.Reader`, each of which asks
/// the object for the stream again rather than storing what it got.
pub const StreamAccessor = struct {
    zig_path: ?[]const u8 = null,
    /// The Zig method that hands the stream over, called afresh every time.
    accessor: []const u8,
    direction: StreamDirection,
    op: Op,

    pub const Op = enum { write, flush, read };
};

/// A function synthesized from an opaque type's `.fields` metadata. It is an
/// ordinary method everywhere except the Zig shim: there is no declaration to
/// call, so the shim reads or writes this path on the receiver instead.
pub const FieldAccess = struct {
    /// Read/write through `load`/`store` instead of copying the wrapper.
    atomic: ?bool = null,
    path: []const u8,
    setter: bool = false,
};

/// The `.iterator` opt-in: a method returning `?T` or `!?T` also gets a Go
/// range-over-func wrapper of this name on its receiver.
pub const Iterator = struct {
    name: []const u8,
};

/// The `.implements` opt-in: a handle method also gets the method of one Go
/// standard interface, which calls it and adapts the result.
pub const Implements = enum {
    writer,
    reader,
    writer_to,
    reader_from,

    /// The Go interface the wrapper satisfies.
    pub fn interfaceName(self: Implements) []const u8 {
        return switch (self) {
            .writer => "io.Writer",
            .reader => "io.Reader",
            .writer_to => "io.WriterTo",
            .reader_from => "io.ReaderFrom",
        };
    }

    /// The method the interface requires, which is also the wrapper's name.
    pub fn methodName(self: Implements) []const u8 {
        return switch (self) {
            .writer => "Write",
            .reader => "Read",
            .writer_to => "WriteTo",
            .reader_from => "ReadFrom",
        };
    }

    /// The Go signature the wrapper has, for diagnostics and docs.
    pub fn signature(self: Implements) []const u8 {
        return switch (self) {
            .writer => "Write(p []byte) (int, error)",
            .reader => "Read(p []byte) (int, error)",
            .writer_to => "WriteTo(w io.Writer) (int64, error)",
            .reader_from => "ReadFrom(r io.Reader) (int64, error)",
        };
    }
};

/// The `.go` opt-in on a value struct: the public API spells the user's Go
/// type instead of a generated mirror, and the conversions to and from the
/// raw mirror are two functions the user writes in the public package.
pub const GoAdapter = struct {
    /// Function taking the raw mirror and returning `type`.
    from_raw: []const u8,
    /// Import path of the qualifier `type` uses; absent for a same-package type.
    import: ?[]const u8 = null,
    /// Function taking `type` and returning the raw mirror.
    to_raw: []const u8,
    /// Go spelling of the type, such as `image.Point` or `Timestamp`.
    type: []const u8,

    /// The package qualifier `type` is written with, or null for a bare name.
    pub fn qualifier(self: GoAdapter) ?[]const u8 {
        const dot = std.mem.indexOfScalar(u8, self.type, '.') orelse return null;
        return self.type[0..dot];
    }
};

/// What only the Go backend reads about a parameter. The IR describes the
/// bound Zig API; anything that describes the projection instead lives in a
/// namespace, so a second output language adds a sibling rather than more
/// fields next to the language-neutral ones.
///
/// Absent whenever every member is, so a binding that asks for no Go-specific
/// knob writes no `go` object at all and its document is as small as before
/// the namespace existed. Reads and writes go through `Parameter`'s accessors.
pub const ParamGo = struct {
    /// `Param.go`: the public parameter is spelled as the user's Go type and
    /// converted with `to_raw` before the raw call. Scalars only.
    adapter: ?GoAdapter = null,
    /// Opt-in from `Param.go_error`: the Go callback type behind this
    /// parameter returns `(i32, error)` rather than `i32`, and an error it
    /// returns is stored and handed back by the public wrapper. Optional
    /// rather than a plain `bool` so a binding that never asks for it keeps
    /// the field out of `semantic.json` entirely.
    callback_error: ?bool = null,

    fn compact(self: ParamGo) ?ParamGo {
        return if (self.adapter == null and self.callback_error == null) null else self;
    }
};

/// What only the Go backend reads about a function. See `ParamGo`.
pub const FnGo = struct {
    /// Exact public Go spelling, independent of native and raw identities.
    name: ?[]const u8 = null,
    /// The type a paired constructor is grouped under in Go, when that is not
    /// where the function is declared. `SemanticFn.namespace` stays the Zig
    /// container the shim calls through, so a root-level `newTerminal` can be
    /// `Terminal`'s constructor in Go and still be called as
    /// `target.newTerminal(...)`.
    owner: ?[]const u8 = null,
    /// Function-level `.go`: the scalar result is converted with `from_raw`
    /// and the public signature spells the user's Go type.
    return_adapter: ?GoAdapter = null,
    /// Set by `.iterator`: the method is a `next()` and Go also gets an
    /// `iter.Seq` wrapper. Go surface only; the C symbol is unchanged.
    iterator: ?Iterator = null,
    /// Set by `.implements`: Go also gets the named `io` interface's method,
    /// calling this one. Go surface only; the C symbol is unchanged.
    implements: ?Implements = null,

    fn compact(self: FnGo) ?FnGo {
        return if (self.name == null and self.owner == null and self.return_adapter == null and
            self.iterator == null and self.implements == null) null else self;
    }
};

/// What only the Rust backend reads about this function.
///
/// A sibling of `FnGo`, not a subset of it: the two namespaces answer the same
/// kind of question for different languages and neither reinterprets the
/// other's fields. It holds one member today because a minimal Rust backend
/// binds free functions and needs no more; the point is that the place to add
/// the next one already exists and is not inside `FnGo`.
pub const FnRust = struct {
    /// Exact public Rust spelling, independent of native and raw identities.
    name: ?[]const u8 = null,

    fn compact(self: FnRust) ?FnRust {
        return if (self.name == null) null else self;
    }
};

/// What only the Go backend reads about a registered type. See `ParamGo`.
pub const TypeGo = struct {
    /// Present only when the binding registered the type with `.go`.
    adapter: ?GoAdapter = null,

    fn compact(self: TypeGo) ?TypeGo {
        return if (self.adapter == null) null else self;
    }

    /// The namespace a declaration needs when an adapter is the only
    /// Go-specific thing about it, which is every registration site today.
    pub fn withAdapter(value: ?GoAdapter) ?TypeGo {
        return (TypeGo{ .adapter = value }).compact();
    }
};

/// Plugin options as they travel through the document: one JSON object per
/// plugin, kept verbatim so the generator can hand each plugin exactly what
/// its own declaration wrote. The generator never reads inside an entry; the
/// plugin that owns the key parses it into its own `Options` type.
pub const Extensions = struct {
    /// In the order the declaration wrote them, which is also the order they
    /// are serialized in, so a document round-trips byte-identically.
    entries: []const Entry = &.{},

    pub const Entry = struct {
        /// The owning plugin's name.
        plugin: []const u8,
        options: std.json.Value,
    };

    pub fn get(self: Extensions, plugin: []const u8) ?std.json.Value {
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.plugin, plugin)) return entry.options;
        }
        return null;
    }

    pub fn jsonStringify(self: Extensions, jw: anytype) !void {
        try jw.beginObject();
        for (self.entries) |entry| {
            try jw.objectField(entry.plugin);
            try jw.write(entry.options);
        }
        try jw.endObject();
    }

    /// The value tree the caller parsed is freed right after `parseFromValue`
    /// returns, so every entry is copied into the parse arena here.
    pub fn jsonParseFromValue(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        _: std.json.ParseOptions,
    ) std.json.ParseFromValueError!Extensions {
        const object = switch (source) {
            .object => |value| value,
            else => return error.UnexpectedToken,
        };
        const entries = try allocator.alloc(Entry, object.count());
        var index: usize = 0;
        var iterator = object.iterator();
        while (iterator.next()) |entry| : (index += 1) {
            entries[index] = .{
                .plugin = try allocator.dupe(u8, entry.key_ptr.*),
                .options = try cloneJsonValue(allocator, entry.value_ptr.*),
            };
        }
        return .{ .entries = entries };
    }
};

fn cloneJsonValue(allocator: std.mem.Allocator, source: std.json.Value) std.mem.Allocator.Error!std.json.Value {
    return switch (source) {
        .null, .bool, .integer, .float => source,
        .number_string => |text| .{ .number_string = try allocator.dupe(u8, text) },
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .array => |items| blk: {
            var copy: std.json.Array = .init(allocator);
            try copy.ensureTotalCapacityPrecise(items.items.len);
            for (items.items) |item| copy.appendAssumeCapacity(try cloneJsonValue(allocator, item));
            break :blk .{ .array = copy };
        },
        .object => |fields| blk: {
            var copy: std.json.ObjectMap = .{};
            try copy.ensureTotalCapacity(allocator, fields.count());
            var iterator = fields.iterator();
            while (iterator.next()) |entry| {
                copy.putAssumeCapacity(try allocator.dupe(u8, entry.key_ptr.*), try cloneJsonValue(allocator, entry.value_ptr.*));
            }
            break :blk .{ .object = copy };
        },
    };
}

pub const SemanticFn = struct {
    /// Set on the two halves of a boxed constructor pair.
    boxed: ?Boxed = null,
    /// Set only when function metadata explicitly says
    /// `.returns.ownership = .borrowed`.
    /// `ownership` defaults to borrowed for historical documents, so this
    /// separate bit distinguishes a deliberate borrowed-handle contract from
    /// metadata that made no lifetime choice.
    borrowed_return: ?bool = null,
    /// Set only when a receiver constructor returns a handle whose lifetime
    /// must end before the receiver's. Omitted when false so old semantic
    /// documents remain byte-identical.
    child_of_receiver: ?bool = null,
    /// The parameter `.cancel = .{ .param = "..." }` named, verbatim. Kept on
    /// the function so a name that matches nothing can still be reported, and
    /// so `abi-diff` sees the Go signature gain or lose its `ctx`.
    cancel: ?[]const u8 = null,
    /// Zig error name that means cancellation. Omitted for the historical
    /// `Canceled` default so existing semantic documents stay byte-identical.
    cancel_error: ?[]const u8 = null,
    /// Public Zig declarations this function deliberately wraps. Coverage
    /// metadata only: generation and ABI comparison do not consume it.
    covers: ?[]const []const u8 = null,
    field_access: ?FieldAccess = null,
    /// Set on a function synthesized from a stream-returning method. Never
    /// present in a `semantic.json` on disk: the document records the Zig
    /// method, and the expansion happens between parsing and lowering.
    stream_accessor: ?StreamAccessor = null,
    doc: ?[]const u8 = null,
    /// Plugin options, keyed by plugin name. Absent when no plugin extended
    /// this function, so a document without plugins is unchanged.
    ext: ?Extensions = null,
    has_comptime_params: ?bool = null,
    /// What only the Go backend reads about this function.
    go: ?FnGo = null,
    /// What only the Rust backend reads about this function. Optional and
    /// omitted when empty, so a document that predates the namespace
    /// round-trips byte-identically and no `ir_version` migration is needed.
    rust: ?FnRust = null,
    name: []const u8,
    /// Public sub-package name. Absent means the binding's default package.
    package: ?[]const u8 = null,
    /// The Zig container the function is declared in, and the owner its C
    /// symbol is built from. Go grouping goes through `goOwner`.
    namespace: ?[]const u8 = null,
    /// Set when the receiver or namespace is an instantiation of a generic
    /// type factory (`Stream(Handler)`), whose methods sit in an anonymous
    /// container no source-level owner names. Source enrichment then accepts
    /// a prototype from such a container; a plainly declared owner never
    /// does, so an unrelated `update(self, cell)` elsewhere cannot lend its
    /// parameter names to `RenderState.update`. Omitted otherwise.
    owner_generic: ?bool = null,
    ownership: Ownership = .borrowed,
    params: []const Parameter,
    receiver: ?[]const u8 = null,
    /// The Zig receiver is a registered opaque type by value. Go still sees
    /// an ordinary handle method and the C ABI still receives a const handle
    /// pointer; the shim alone dereferences it before calling Zig.
    receiver_by_value: ?bool = null,
    /// What the receiver is. Absent means `handle`, which is what every
    /// receiver was before registered enums could own methods. A `value`
    /// receiver crosses as its own value rather than as a handle pointer, so
    /// none of the handle bookkeeping -- acquire, parent, `ErrInvalidHandle`,
    /// the retained-callback sweep -- applies to it.
    receiver_kind: ?ReceiverKind = null,
    /// How many entries of `params` Zig declared ahead of the receiver. Only
    /// injected arguments can precede it, so this is absent (zero) unless an
    /// allocator or io comes before the handle, as in
    /// `fn free(gpa: Allocator, self: *T) void`. The shim passes `self` at
    /// this position; C and Go never see the difference.
    receiver_at: ?usize = null,
    /// Name of the function that frees a `.returns.ownership = .caller` slice result.
    /// Generated Go copies the payload and then calls this symbol, so the
    /// public API never hands native memory to the caller.
    release: ?[]const u8 = null,
    @"return": TypeNode,
    /// The Zig result is `std.atomic.Value(T)` while Go and C receive T.
    return_atomic: ?bool = null,
    return_semantic: ?SemanticHint = null,
    /// The function declaration's source location, from `names.zig`. Purely
    /// diagnostic: it has no bearing on the generated ABI, so `abi_diff`
    /// ignores it.
    source: ?SourceLocation = null,
    /// The Zig declaration the shim calls, relative to the bound module, when
    /// it is not `<receiver or namespace>.<name>`: a function declared beside
    /// a type rather than inside it, or one `.name` renamed for Go. Absent
    /// whenever the owner and the name already spell the declaration.
    zig_path: ?[]const u8 = null,
    symbol: []const u8,
    /// Set when the binding wrote `symbol` itself with `.symbol`. Lowering
    /// and validation then use it as written instead of deriving it from the
    /// owner and the name. Omitted otherwise, so existing documents are
    /// byte-identical.
    custom_symbol: ?bool = null,

    /// The type Go groups this function under: the one a binding paired it
    /// with, or the container it was declared in.
    pub fn goOwner(self: SemanticFn) ?[]const u8 {
        return self.goOwnerOverride() orelse self.namespace;
    }

    /// The `.constructs` grouping override alone, without the `namespace`
    /// fallback `goOwner` applies. Only a caller asking whether the binding
    /// stated an owner wants this one.
    pub fn goOwnerOverride(self: SemanticFn) ?[]const u8 {
        return (self.go orelse FnGo{}).owner;
    }

    /// Record the type Go groups this function under.
    pub fn setGoOwner(self: *SemanticFn, value: ?[]const u8) void {
        var go = self.go orelse FnGo{};
        go.owner = value;
        self.go = go.compact();
    }

    /// The exact public Go spelling a binding asked for, if it asked. Callers
    /// wanting the name a function is actually published under want
    /// `Target.publicFunctionNameAlloc`, which resolves constructors too and
    /// reads this override through the target's own namespace.
    pub fn goName(self: SemanticFn) ?[]const u8 {
        return (self.go orelse FnGo{}).name;
    }

    /// Record the exact public Go spelling.
    pub fn setGoName(self: *SemanticFn, value: ?[]const u8) void {
        var go = self.go orelse FnGo{};
        go.name = value;
        self.go = go.compact();
    }

    /// The exact public Rust spelling a binding asked for, if it asked. This
    /// is what the Rust target's `nameOverride` reads, exactly as Go's reads
    /// `goName`. Callers wanting the name a function is actually published
    /// under want `Target.publicFunctionNameAlloc`.
    pub fn rustName(self: SemanticFn) ?[]const u8 {
        return (self.rust orelse FnRust{}).name;
    }

    /// Record the exact public Rust spelling.
    pub fn setRustName(self: *SemanticFn, value: ?[]const u8) void {
        var rust = self.rust orelse FnRust{};
        rust.name = value;
        self.rust = rust.compact();
    }

    /// The Go type the scalar result is spelled as, with its conversion.
    pub fn returnGoAdapter(self: SemanticFn) ?GoAdapter {
        return (self.go orelse FnGo{}).return_adapter;
    }

    /// Record the Go type the scalar result is spelled as.
    pub fn setReturnGoAdapter(self: *SemanticFn, value: ?GoAdapter) void {
        var go = self.go orelse FnGo{};
        go.return_adapter = value;
        self.go = go.compact();
    }

    /// The range-over-func wrapper this method also gets, if any.
    pub fn goIterator(self: SemanticFn) ?Iterator {
        return (self.go orelse FnGo{}).iterator;
    }

    /// Record the range-over-func wrapper this method also gets.
    pub fn setGoIterator(self: *SemanticFn, value: ?Iterator) void {
        var go = self.go orelse FnGo{};
        go.iterator = value;
        self.go = go.compact();
    }

    /// The Go standard interface this method also satisfies, if any.
    pub fn goImplements(self: SemanticFn) ?Implements {
        return (self.go orelse FnGo{}).implements;
    }

    /// Record the Go standard interface this method also satisfies.
    pub fn setGoImplements(self: *SemanticFn, value: ?Implements) void {
        var go = self.go orelse FnGo{};
        go.implements = value;
        self.go = go.compact();
    }

    pub fn childOfReceiver(self: SemanticFn) bool {
        return self.child_of_receiver orelse false;
    }

    pub fn cancelError(self: SemanticFn) []const u8 {
        return self.cancel_error orelse "Canceled";
    }

    pub fn returnsBorrowedHandle(self: SemanticFn) bool {
        return self.borrowed_return orelse false;
    }

    pub fn receiverByValue(self: SemanticFn) bool {
        return self.receiver_by_value orelse false;
    }

    /// Whether the receiver, if there is one, is a handle. Every site that
    /// reads a receiver to mean "there is an object with a lifetime" asks
    /// this rather than testing `receiver` for null.
    pub fn receiverIsHandle(self: SemanticFn) bool {
        if (self.receiver == null) return false;
        return (self.receiver_kind orelse .handle) == .handle;
    }

    /// Whether the receiver is a registered value type passed by its own
    /// value: an enum today.
    pub fn receiverIsValue(self: SemanticFn) bool {
        return self.receiver != null and (self.receiver_kind orelse .handle) == .value;
    }
};

/// A receiver is either an object with a lifetime or a plain value.
pub const ReceiverKind = enum { handle, value };

pub const TypeKind = enum { callback, @"enum", error_set, materialized, @"opaque", tagged_union, value_struct };
pub const Layout = enum { @"extern", @"packed" };
/// How Go reaches a type's contents. This is a separate axis from the type's
/// kind: a tagged union is a tagged union either way, and adding a strategy
/// adds one value here rather than multiplying the kind names.
pub const Access = enum {
    /// Per-variant FFI accessors that check the tag on every read.
    projection,
    /// A zigo-owned snapshot struct carrying the tag and every scalar payload
    /// back in one call, alongside the projections.
    snapshot,
};
pub const TypeField = struct {
    /// The Zig member is `std.atomic.Value(T)` while its mirror contains T.
    atomic: ?bool = null,
    name: []const u8,
    /// Only `codepoint`, and only on a `u32` member of an `extern struct`:
    /// the mirror spells it `rune` over the same four bytes.
    semantic: ?SemanticHint = null,
    type: ?TypeNode = null,
    value: ?i64 = null,
};
/// Numeric extent of the exported enum tags, independent of declaration order.
/// Widen before subtracting so even the full i64 domain is representable.
pub fn enumValueRange(fields: []const TypeField) ?struct { min: i64, max: i64, span: u128 } {
    if (fields.len == 0) return null;
    var min = fields[0].value.?;
    var max = min;
    for (fields[1..]) |field| {
        min = @min(min, field.value.?);
        max = @max(max, field.value.?);
    }
    return .{ .min = min, .max = max, .span = @intCast(@as(i128, max) - min + 1) };
}

pub const TypeDecl = struct {
    /// Root-export fallback retained when a plugin renames the registered type.
    native_name: ?[]const u8 = null,
    access: ?Access = null,
    /// Integer storage used by a packed struct. Absent for every other type.
    backing_type: ?TypeNode = null,
    /// Go doc override supplied by an explicit type registration.
    doc: ?[]const u8 = null,
    exhaustive: bool = true,
    /// Plugin options, keyed by plugin name. Absent when no plugin extended
    /// this type.
    ext: ?Extensions = null,
    fields: []const TypeField = &.{},
    /// What only the Go backend reads about this declaration.
    go: ?TypeGo = null,
    kind: TypeKind,
    layout: ?Layout = null,
    /// Serialized tree layout version. Present only for materialized structs.
    materialized_version: ?u16 = null,
    name: []const u8,
    /// Default failure result for callbacks registered under this type name.
    on_callback_failure: ?CallbackFailure = null,
    /// The packed struct was explicitly registered with `.value`, not
    /// merely discovered as a tagged-union payload.
    registered_value: ?bool = null,
    /// Union variants deliberately excluded from the generated boundary.
    omitted_variants: ?[]const []const u8 = null,
    /// Public sub-package name. Absent means the binding's default package.
    package: ?[]const u8 = null,
    /// Present only when the binding explicitly opts a non-exhaustive Zig
    /// enum into the public surface with `.exhaustive = false`.
    open: ?bool = null,
    tag_type: ?TypeNode = null,
    /// Present only when the binding registered the enum with `.text = true`,
    /// asking for `Parse<Enum>`, `MarshalText` and `UnmarshalText` in Go.
    text: ?bool = null,
    zig_path: ?[]const u8 = null,

    /// The access strategy a type was registered with. Types that only have
    /// one never carry the field.
    pub fn accessStrategy(self: TypeDecl) Access {
        return self.access orelse .projection;
    }

    /// The Go type this declaration's public surface is spelled as, replacing
    /// the generated mirror, when the binding registered one.
    pub fn goAdapter(self: TypeDecl) ?GoAdapter {
        return (self.go orelse TypeGo{}).adapter;
    }

    /// C only ever holds a pointer to these, so a tagged union is a handle too.
    pub fn isHandle(self: TypeDecl) bool {
        return self.kind == .@"opaque" or self.kind == .tagged_union;
    }

    pub fn variantOmitted(self: TypeDecl, name: []const u8) bool {
        for (self.omitted_variants orelse &.{}) |candidate| {
            if (std.mem.eql(u8, candidate, name)) return true;
        }
        return false;
    }
};
pub const Constructor = struct {
    deinit: []const u8,
    init: []const u8,
    /// Explicit public wrapper name from function metadata. Absent keeps the
    /// historical `New<Type>` constructor spelling.
    name: ?[]const u8 = null,
    type: []const u8,
};

/// A `packed struct` value type, which crosses the boundary as its backing
/// integer rather than as an aggregate. Lowering and validation both gate the
/// whole packed-value feature on this, so they read one rule.
pub fn isPackedValue(types: []const TypeDecl, node: TypeNode) bool {
    if (node != .value_struct) return false;
    const declaration = typeDecl(types, node.value_struct.ref) orelse return false;
    return declaration.kind == .value_struct and declaration.layout == .@"packed";
}

/// The registered declaration of this name, if the document has one.
pub fn typeDecl(types: []const TypeDecl, name: []const u8) ?TypeDecl {
    for (types) |declaration| if (std.mem.eql(u8, declaration.name, name)) return declaration;
    return null;
}

/// The failure result a callback parameter reports with: the parameter's own
/// override first, else the default registered on its callback type. Emit,
/// validation and `abi-diff` all resolve it through here.
pub fn callbackFailure(types: []const TypeDecl, parameter: Parameter) ?CallbackFailure {
    if (parameter.on_callback_failure) |value| return value;
    if (parameter.type != .callback) return null;
    const ref = parameter.type.callback.ref orelse return null;
    const declaration = typeDecl(types, ref) orelse return null;
    return if (declaration.kind == .callback) declaration.on_callback_failure else null;
}

/// The Zig declaration a shim calls, relative to the bound module. A document
/// spells it out only when the owner and the name do not: the shim's call has
/// to reach where the function is declared, not where Go presents it.
pub fn zigCallPathAlloc(allocator: std.mem.Allocator, function: SemanticFn) ![]u8 {
    if (function.zig_path) |path| return allocator.dupe(u8, path);
    if (function.receiver orelse function.namespace) |owner|
        return std.fmt.allocPrint(allocator, "{s}.{s}", .{ owner, function.name });
    return allocator.dupe(u8, function.name);
}

/// The constructor whose `init` this function is, if any. Matched on the Zig
/// function name plus the owning type, which is how every consumer -- emit,
/// validate, the report and `abi-diff` -- has to match it: a method
/// constructor carries a receiver, so screening receivers out here reports
/// `(*T).Init` for a function the generator publishes as `NewT`.
pub fn constructorForInit(constructors: []const Constructor, function: SemanticFn) ?Constructor {
    for (constructors) |constructor| {
        if (std.mem.eql(u8, constructor.init, function.name) and
            std.mem.eql(u8, constructor.type, function.goOwner() orelse "")) return constructor;
    }
    return null;
}

/// The document shape `serialize` writes.
pub const current_ir_version: u32 = 2;

/// Lift an older document into the current shape, in place, before it is
/// parsed into `Semantic`. Version 1 spelled the Go-specific fields as
/// siblings of the language-neutral ones; each moves into the `go` object its
/// owner now carries.
///
/// The move is keyed on the old spellings being present rather than on the
/// version number. Two things follow. It is idempotent, so a document already
/// in the current shape passes through untouched. And it does not care which
/// version a document claims, which matters because the fields moved across
/// two commits: a document written between them says version 2 while still
/// spelling `iterator` and `implements` at the top level, and gating on the
/// version would leave exactly those unreadable. `ir_version` is still
/// advanced, but only upward, so a document from a future version keeps its
/// own number and is refused by the `ZIGO020` check rather than quietly
/// rewritten.
///
/// The generator cases check in their `semantic.json` inputs at version 1, so
/// this path is exercised by the ordinary test run rather than by a fixture
/// alone.
fn migrate(allocator: std.mem.Allocator, root: *std.json.Value) !void {
    if (root.* != .object) return;

    if (root.object.getPtr("functions")) |functions| if (functions.* == .array) {
        for (functions.array.items) |*function| {
            if (function.* != .object) continue;
            try nestGo(allocator, &function.object, &.{
                .{ "go_name", "name" },
                .{ "go_owner", "owner" },
                .{ "return_go_adapter", "return_adapter" },
                .{ "iterator", "iterator" },
                .{ "implements", "implements" },
            });
            if (function.object.getPtr("params")) |params| if (params.* == .array) {
                for (params.array.items) |*param| {
                    if (param.* != .object) continue;
                    try nestGo(allocator, &param.object, &.{
                        .{ "go_adapter", "adapter" },
                        .{ "go_error", "callback_error" },
                    });
                }
            };
        }
    };
    if (root.object.getPtr("types")) |types| if (types.* == .array) {
        for (types.array.items) |*declaration| {
            if (declaration.* != .object) continue;
            try nestGo(allocator, &declaration.object, &.{.{ "go_adapter", "adapter" }});
        }
    };
    const declared = root.object.get("ir_version") orelse std.json.Value{ .integer = 1 };
    if (declared != .integer or declared.integer < current_ir_version)
        try root.object.put(allocator, "ir_version", .{ .integer = current_ir_version });
}

/// Move each present `from` key of `object` into its `go` object under `to`.
/// Nothing is added when the owner carried none of them, which is what keeps
/// a migrated document identical to one the current generator would write.
///
/// An existing `go` object is added to, not replaced: a document written
/// between the two commits that moved these fields carries both spellings at
/// once, and overwriting would drop whichever fields had already moved.
fn nestGo(allocator: std.mem.Allocator, object: *std.json.ObjectMap, mapping: []const [2][]const u8) !void {
    var go: std.json.ObjectMap = if (object.get("go")) |existing|
        (if (existing == .object) existing.object else return)
    else
        .{};
    var moved = false;
    for (mapping) |pair| {
        const entry = object.fetchOrderedRemove(pair[0]) orelse continue;
        try go.put(allocator, pair[1], entry.value);
        moved = true;
    }
    if (!moved) return;
    try object.put(allocator, "go", .{ .object = go });
}

pub const Package = struct {
    doc: ?[]const u8 = null,
    name: []const u8,
    path: []const u8,
};

/// A Go interface the binding declares over a chosen set of registered opaque
/// handles. The reflector records only what the binding said; that every
/// listed type has every method with one Go signature is checked by
/// validation and generation, which also spell the interface out.
pub const Interface = struct {
    /// Whether `io.Closer` is part of the interface. Every constructed handle
    /// has `Close`, so this defaults on.
    closer: bool = true,
    doc: ?[]const u8 = null,
    /// Zig declaration names, in the order the interface lists them.
    methods: []const []const u8,
    name: []const u8,
    /// Public sub-package name, following the types. Absent means the
    /// binding's default package.
    package: ?[]const u8 = null,
    /// Registered opaque type names, in the order the binding listed them.
    types: []const []const u8,
};

pub const Semantic = struct {
    /// The Zig expression the shim passes for `std.mem.Allocator` parameters.
    /// Set by the binding's `.allocator`; without it, a function that takes an
    /// allocator is refused rather than guessed at.
    allocator: ?[]const u8 = null,
    constructors: []const Constructor = &.{},
    /// The `//!` container doc of the bindings file, if it has one. It becomes
    /// the generated Go package doc unless `go_package_doc` overrides it.
    doc: ?[]const u8 = null,
    functions: []const SemanticFn = &.{},
    /// Declared Go interfaces. Absent when the binding declares none, so
    /// every document written before the field existed serializes the same.
    interfaces: ?[]const Interface = null,
    /// The Zig expression the shim passes for `std.Io` parameters, from the
    /// binding's `.io`.
    io: ?[]const u8 = null,
    /// 1 spelled the Go-specific fields as siblings of the language-neutral
    /// ones; 2 nests them under `go`. `parse` accepts both and `serialize`
    /// only ever writes the current one, so a checked-in document written
    /// before the move still loads without being regenerated.
    ir_version: u32 = current_ir_version,
    package: []const u8,
    /// Declared public sub-packages. Empty is omitted so legacy documents are unchanged.
    packages: ?[]const Package = null,
    prefix: []const u8,
    types: []const TypeDecl = &.{},
    zig_version: []const u8,

    pub fn serialize(self: Semantic, allocator: std.mem.Allocator) ![]u8 {
        const body = try std.json.Stringify.valueAlloc(allocator, self, .{
            .emit_null_optional_fields = false,
            .whitespace = .indent_2,
        });
        defer allocator.free(body);
        return std.fmt.allocPrint(allocator, "{s}\n", .{body});
    }

    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(Semantic) {
        var dynamic = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
        defer dynamic.deinit();
        try migrate(dynamic.arena.allocator(), &dynamic.value);
        return std.json.parseFromValue(Semantic, allocator, dynamic.value, .{});
    }

    /// A tagged union crosses the boundary by value when a function takes it as
    /// a snapshot parameter.
    pub fn taggedUnionUsedByValue(self: Semantic, name: []const u8) bool {
        for (self.functions) |function| {
            if (functionPassesByValue(function, name) or typeIsNamedValue(function.@"return", name)) return true;
        }
        return false;
    }

    /// ...and as a handle when it is constructed, received, or reachable from
    /// any parameter or return type. Both can be true at once.
    pub fn taggedUnionUsedAsHandle(self: Semantic, name: []const u8) bool {
        for (self.constructors) |constructor| if (std.mem.eql(u8, constructor.type, name)) return true;
        for (self.functions) |function| if (functionUsesAsHandle(function, name)) return true;
        return false;
    }

    /// Value-only unions get a snapshot struct instead of an opaque handle.
    pub fn isValueOnlyTaggedUnion(self: Semantic, name: []const u8) bool {
        return self.taggedUnionUsedByValue(name) and !self.taggedUnionUsedAsHandle(name);
    }

    /// Only structs a function actually mentions reach the header, so registering
    /// a type without using it adds nothing to the generated surface.
    pub fn valueStructUsed(self: Semantic, name: []const u8) bool {
        for (self.functions) |function| {
            for (function.params) |parameter| if (self.mentionsValueStruct(parameter.type, name)) return true;
            if (self.mentionsValueStruct(function.@"return", name)) return true;
        }
        return false;
    }

    pub fn mentionsValueStruct(self: Semantic, node: TypeNode, name: []const u8) bool {
        return switch (node) {
            .value_struct => |value| blk: {
                if (std.mem.eql(u8, value.ref, name)) break :blk true;
                for (self.types) |declaration| {
                    if ((declaration.kind != .value_struct and declaration.kind != .tagged_union) or
                        !std.mem.eql(u8, declaration.name, value.ref)) continue;
                    for (declaration.fields) |field| if (field.type) |child| {
                        if (self.mentionsValueStruct(child, name)) break :blk true;
                    };
                }
                break :blk false;
            },
            .slice => |value| self.mentionsValueStruct(value.element.*, name),
            .error_union => |value| self.mentionsValueStruct(value.payload.*, name),
            .optional => |value| self.mentionsValueStruct(value.child.*, name),
            // A materialized tree stores an extern struct inline, so the
            // struct's Go mirror is needed wherever the tree is decoded.
            .materialized => |value| self.materializedMentionsValueStruct(value.ref, name, 0),
            else => false,
        };
    }

    /// Validation rejects cyclic trees, but this can run before it does, so
    /// the walk is bounded rather than trusting the document.
    fn materializedMentionsValueStruct(self: Semantic, tree: []const u8, name: []const u8, depth: usize) bool {
        if (depth == 64) return false;
        const declaration = typeDecl(self.types, tree) orelse return false;
        if (declaration.kind != .materialized) return false;
        for (declaration.fields) |field| {
            const node = field.type orelse continue;
            if (node == .materialized) {
                if (self.materializedMentionsValueStruct(node.materialized.ref, name, depth + 1)) return true;
            } else if (node == .optional and node.optional.child.* == .materialized) {
                if (self.materializedMentionsValueStruct(node.optional.child.materialized.ref, name, depth + 1)) return true;
            } else if (node == .slice and node.slice.element.* == .materialized) {
                if (self.materializedMentionsValueStruct(node.slice.element.materialized.ref, name, depth + 1)) return true;
            } else if (self.mentionsValueStruct(node, name)) return true;
        }
        return false;
    }
};

pub fn optionalStringEqual(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if (lhs == null or rhs == null) return lhs == null and rhs == null;
    return std.mem.eql(u8, lhs.?, rhs.?);
}

/// The grammar a `.packages` entry's import path must follow: relative, `/`
/// separated, and made of identifier-safe components.
pub fn validPackagePath(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, '\\') != null) return false;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return false;
        for (component) |character| if (!(std.ascii.isAlphanumeric(character) or character == '_' or character == '-' or character == '.')) return false;
    }
    return true;
}

/// The undecorated C symbol of a function: the one the binding wrote, or the
/// one the shared naming rule derives from the prefix, the owner and the
/// name. Lowering, validation and `semantic.json` all go through here, so
/// none of them can spell the symbol differently.
pub fn functionSymbolAlloc(allocator: std.mem.Allocator, prefix: []const u8, function: SemanticFn) ![]u8 {
    if (function.custom_symbol orelse false) return allocator.dupe(u8, function.symbol);
    return naming.functionSymbolAlloc(allocator, prefix, function.receiver orelse function.namespace, function.name);
}

/// True when the function carries a Go-side dispatcher pointer: a user
/// callback, or a stream parameter, which under purego answers to the same
/// versioned symbol a callback does. Lowering picks the symbol from this and
/// validation names the symbol it checks from the same rule, so the two must
/// never drift apart.
pub fn functionHasCallback(function: SemanticFn) bool {
    for (function.params) |parameter| {
        if (parameter.type == .callback or parameter.type == .io_stream) return true;
    }
    return false;
}

/// How the elements of a string slice are spelled in Zig. The three forms
/// cross the boundary identically -- flattened bytes plus lengths -- and
/// differ only in the element type the shim rebuilds.
pub const StringSliceForm = enum { unsentinel, sentinel_slice, sentinel_many };

/// The string-slice form of `node`, or null when it is not one. A sentinel
/// element (`[:0]const u8` or `[*:0]const u8`) is a string slice on its
/// spelling alone; an unsentinelled `[]const u8` element needs the
/// `utf8_string` hint to say the bytes are text. `[]const [*:0]const u8` is
/// accepted on the same terms as `[]const [:0]const u8`: reflection records a
/// many pointer as a slice with `sentinel_many`, and only the rebuilt element
/// type differs.
pub fn stringSliceForm(node: TypeNode, hint: ?SemanticHint) ?StringSliceForm {
    if (node != .slice or !node.slice.@"const") return null;
    const element = node.slice.element.*;
    if (element != .slice or !element.slice.@"const" or !isByte(element.slice.element.*)) return null;
    if (element.slice.sentinel) |sentinel| {
        if (sentinel != 0) return null;
        return if (element.slice.sentinel_many) .sentinel_many else .sentinel_slice;
    }
    return if (hint == .utf8_string) .unsentinel else null;
}

/// A string slice is the only pointer-bearing slice that may cross the Go
/// boundary. It is flattened into bytes plus lengths before the native call;
/// every other pointer-bearing element keeps the ZIGO005 rejection.
pub fn isStringSliceParameter(parameter: Parameter) bool {
    return parameter.direction == .in and stringSliceForm(parameter.type, parameter.semantic) != null;
}

pub fn isByte(node: TypeNode) bool {
    return node == .int and !node.int.signed and node.int.bits == 8;
}

/// The slice inside a `?[]T`, or the node itself. An optional slice reuses the
/// whole slice lowering -- the same pointer and length cross -- and spends the
/// pointer's NULL on absence, so every helper that describes a slice describes
/// the optional one identically.
pub fn sliceThroughOptional(node: TypeNode) TypeNode {
    if (node == .optional and node.optional.child.* == .slice) return node.optional.child.*;
    return node;
}

pub fn isOptionalSlice(node: TypeNode) bool {
    return node == .optional and node.optional.child.* == .slice;
}

/// A byte slice the binding marked as text: it crosses as pointer plus length
/// and Go sees a `string`.
pub fn isUtf8Slice(node: TypeNode, hint: ?SemanticHint) bool {
    const value = sliceThroughOptional(node);
    return hint == .utf8_string and value == .slice and isByte(value.slice.element.*);
}

/// A byte slice the binding marked as NUL-terminated: it crosses as one
/// `const char *` with no length beside it. This is the exact spelling, with
/// no look-through: lowering answers the optional case in its own `?[]T`
/// branch, which lowers the same pointer with `is_optional` set, so looking
/// through here would classify that parameter twice.
pub fn isCStringSlice(node: TypeNode, hint: ?SemanticHint) bool {
    return hint == .c_string and node == .slice and node.slice.@"const" and isByte(node.slice.element.*);
}

/// The same question asked of a position that may still be wrapped in `?`,
/// for callers that classify the parameter as a whole rather than branching
/// on the optional first.
pub fn isCStringSliceThroughOptional(node: TypeNode, hint: ?SemanticHint) bool {
    return isCStringSlice(sliceThroughOptional(node), hint);
}

/// The integer widths a codepoint hint may sit on: Zig's own `u21` and the
/// `u32` most C text APIs use. Both promote to a `uint32` carrier.
pub fn isCodepointInt(node: TypeNode) bool {
    return node == .int and !node.int.signed and !node.int.is_usize and (node.int.bits == 21 or node.int.bits == 32);
}

/// A scalar the binding marked as a codepoint: Go sees `rune`.
pub fn isCodepoint(node: TypeNode, hint: ?SemanticHint) bool {
    return hint == .codepoint and isCodepointInt(node);
}

/// A plain (unsentinelled, non-optional) slice of codepoints: Go sees `[]rune`
/// over the same memory the raw `[]uint32` uses.
pub fn isCodepointSlice(node: TypeNode, hint: ?SemanticHint) bool {
    return hint == .codepoint and node == .slice and node.slice.sentinel == null and isCodepointInt(node.slice.element.*);
}

/// Whether a parameter is a codepoint position Go has to range-check before
/// the call: any scalar, or any input slice, marked `codepoint`.
pub fn isCheckedCodepointParameter(parameter: Parameter) bool {
    if (parameter.injected != null or parameter.flatten != null) return false;
    if (isCodepoint(parameter.type, parameter.semantic)) return true;
    return parameter.direction == .in and isCodepointSlice(parameter.type, parameter.semantic);
}

/// Either kind of string: both are rendered as a Go `string`.
pub fn isStringSlice(node: TypeNode, hint: ?SemanticHint) bool {
    return isUtf8Slice(node, hint) or isCStringSliceThroughOptional(node, hint);
}

/// The by-value and as-handle rules, per function, so callers holding lowered
/// functions can apply the same rule to their `origin` without a `Semantic`.
pub fn functionPassesByValue(function: SemanticFn, name: []const u8) bool {
    for (function.params) |parameter| {
        if (parameter.type == .value_struct and std.mem.eql(u8, parameter.type.value_struct.ref, name)) return true;
    }
    return false;
}

pub fn typeIsNamedValue(node: TypeNode, name: []const u8) bool {
    return switch (node) {
        .value_struct => |value| std.mem.eql(u8, value.ref, name),
        .error_union => |value| typeIsNamedValue(value.payload.*, name),
        else => false,
    };
}

pub fn functionUsesAsHandle(function: SemanticFn, name: []const u8) bool {
    if (function.receiver) |receiver| if (std.mem.eql(u8, receiver, name)) return true;
    for (function.params) |parameter| if (containsHandleReference(parameter.type, name)) return true;
    return containsHandleReference(function.@"return", name);
}

/// Whether `node` reaches the type `name` in a position that needs a handle.
pub fn containsHandleReference(node: TypeNode, name: []const u8) bool {
    return switch (node) {
        .opaque_ptr => |value| std.mem.eql(u8, value.ref, name),
        .slice => |value| containsHandleReference(value.element.*, name),
        .optional => |value| containsHandleReference(value.child.*, name),
        .error_union => |value| containsHandleReference(value.payload.*, name),
        .callback => |value| blk: {
            for (value.params) |parameter| if (containsHandleReference(parameter, name)) break :blk true;
            break :blk containsHandleReference(value.@"return".*, name);
        },
        else => false,
    };
}

test "stream parameters round-trip through the semantic document" {
    const document: Semantic = .{
        .functions = &.{.{
            .name = "dump",
            .params = &.{
                .{ .name = "w", .type = .{ .io_stream = .{ .direction = .writer } } },
                .{ .buffer = 8192, .name = "r", .type = .{ .io_stream = .{ .direction = .reader } } },
            },
            .@"return" = .{ .void = {} },
            .symbol = "zg_dump",
        }},
        .package = "stream",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const bytes = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\": \"io_writer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\": \"io_reader\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"buffer\": 8192") != null);

    var parsed = try Semantic.parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    const params = parsed.value.functions[0].params;
    try std.testing.expectEqual(StreamDirection.writer, params[0].type.io_stream.direction);
    try std.testing.expectEqual(@as(?u32, null), params[0].buffer);
    try std.testing.expectEqual(StreamDirection.reader, params[1].type.io_stream.direction);
    try std.testing.expectEqual(@as(u32, 8192), params[1].buffer.?);
}

test "callback contracts are optional and round-trip when present" {
    var result: TypeNode = .{ .void = {} };
    const callback: TypeNode = .{ .callback = .{
        .has_userdata = false,
        .params = &.{},
        .@"return" = &result,
    } };
    const document: Semantic = .{
        .functions = &.{.{
            .name = "watch",
            .params = &.{
                .{ .name = "plain", .type = callback },
                .{ .name = "contracted", .on_callback_failure = .{ .result = 7 }, .reentrancy = .forbidden, .thread = .any, .type = callback },
            },
            .@"return" = .{ .void = {} },
            .symbol = "zg_watch",
        }},
        .package = "callbacks",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const bytes = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "\"reentrancy\": \"forbidden\""));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "\"thread\": \"any\""));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "\"on_callback_failure\""));

    var parsed = try Semantic.parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?CallbackReentrancy, null), parsed.value.functions[0].params[0].reentrancy);
    try std.testing.expectEqual(CallbackReentrancy.forbidden, parsed.value.functions[0].params[1].reentrancy.?);
    try std.testing.expectEqual(CallbackThread.any, parsed.value.functions[0].params[1].thread.?);
    try std.testing.expectEqual(@as(i128, 7), parsed.value.functions[0].params[1].on_callback_failure.?.result);
}

test "child-of-receiver metadata is emitted only when enabled" {
    const base: SemanticFn = .{
        .name = "newChild",
        .params = &.{},
        .receiver = "Parent",
        .@"return" = .{ .void = {} },
        .symbol = "zg_parent_new_child",
    };
    var dependent = base;
    dependent.child_of_receiver = true;
    const document: Semantic = .{
        .functions = &.{ base, dependent },
        .package = "handles",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const bytes = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "\"child_of_receiver\": true"));
}

test "cancel error defaults to Canceled and only an override is serialized" {
    const base: SemanticFn = .{
        .cancel = "cancel",
        .name = "crunch",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "zg_crunch",
    };
    var configured = base;
    configured.cancel_error = "Cancelled";
    const document: Semantic = .{
        .functions = &.{ base, configured },
        .package = "job",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqualStrings("Canceled", base.cancelError());
    try std.testing.expectEqualStrings("Cancelled", configured.cancelError());
    const bytes = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "\"cancel_error\": \"Cancelled\""));
}

test "implements is omitted by default and round trips when present" {
    const plain: Semantic = .{
        .functions = &.{.{ .name = "feed", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_feed" }},
        .package = "sample",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const plain_bytes = try plain.serialize(std.testing.allocator);
    defer std.testing.allocator.free(plain_bytes);
    try std.testing.expect(std.mem.indexOf(u8, plain_bytes, "\"implements\"") == null);

    const declared: Semantic = .{
        .functions = &.{.{ .go = .{ .implements = .writer_to }, .name = "dump", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_dump" }},
        .package = "sample",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const bytes = try declared.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"implements\": \"writer_to\"") != null);
    var parsed = try Semantic.parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    try std.testing.expectEqual(Implements.writer_to, parsed.value.functions[0].goImplements().?);
}

test "package metadata is omitted by default and round trips when present" {
    const legacy: Semantic = .{ .package = "sample", .prefix = "zg", .zig_version = "0.16.0" };
    const legacy_bytes = try legacy.serialize(std.testing.allocator);
    defer std.testing.allocator.free(legacy_bytes);
    try std.testing.expect(std.mem.indexOf(u8, legacy_bytes, "\"packages\"") == null);

    const split: Semantic = .{
        .functions = &.{.{ .name = "width", .package = "text", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_width" }},
        .package = "sample",
        .packages = &.{.{ .doc = "Package text handles Unicode.", .name = "text", .path = "text" }},
        .prefix = "zg",
        .types = &.{.{ .kind = .@"enum", .name = "Mode", .package = "text" }},
        .zig_version = "0.16.0",
    };
    const bytes = try split.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var parsed = try Semantic.parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("text", parsed.value.packages.?[0].name);
    try std.testing.expectEqualStrings("text", parsed.value.types[0].package.?);
    try std.testing.expectEqualStrings("text", parsed.value.functions[0].package.?);
}

test "the rust namespace is a sibling of go, omitted when empty, and needs no migration" {
    // A document that names no Rust override must serialize with no `rust`
    // key at all. This is what makes the namespace an addition rather than an
    // IR version change: every `semantic.json` on disk stays byte-identical,
    // so `abi-check` reading a baseline through
    // `git show <ref>:zigo/semantic.json` keeps parsing documents written
    // before the namespace existed.
    const plain: Semantic = .{
        .functions = &.{.{ .name = "add", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_add" }},
        .package = "sample",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const plain_bytes = try plain.serialize(std.testing.allocator);
    defer std.testing.allocator.free(plain_bytes);
    try std.testing.expect(std.mem.indexOf(u8, plain_bytes, "\"rust\"") == null);
    try std.testing.expectEqual(@as(u32, current_ir_version), plain.ir_version);

    // Both namespaces on one declaration, neither reading the other's field.
    const both: Semantic = .{
        .functions = &.{.{
            .go = .{ .name = "Plus" },
            .rust = .{ .name = "plus" },
            .name = "add",
            .params = &.{},
            .@"return" = .{ .void = {} },
            .symbol = "zg_add",
        }},
        .package = "sample",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const bytes = try both.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var parsed = try Semantic.parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Plus", parsed.value.functions[0].goName().?);
    try std.testing.expectEqualStrings("plus", parsed.value.functions[0].rustName().?);

    // A document carrying only the Rust namespace still reads back, and Go's
    // reader answers null rather than borrowing Rust's spelling.
    const rust_only =
        \\{"functions":[{"name":"add","params":[],"return":{"kind":"void"},"rust":{"name":"plus"},"symbol":"zg_add"}],"ir_version":1,"package":"sample","prefix":"zg","types":[],"zig_version":"0.16.0"}
    ;
    var migrated = try Semantic.parse(std.testing.allocator, rust_only);
    defer migrated.deinit();
    try std.testing.expectEqualStrings("plus", migrated.value.functions[0].rustName().?);
    try std.testing.expect(migrated.value.functions[0].goName() == null);
}

test "interfaces are omitted by default and round trip when present" {
    const legacy: Semantic = .{ .package = "sample", .prefix = "zg", .zig_version = "0.16.0" };
    const legacy_bytes = try legacy.serialize(std.testing.allocator);
    defer std.testing.allocator.free(legacy_bytes);
    try std.testing.expect(std.mem.indexOf(u8, legacy_bytes, "\"interfaces\"") == null);

    const declared: Semantic = .{
        .interfaces = &.{.{
            .closer = false,
            .doc = "Batch counts staged values.",
            .methods = &.{ "len", "clear" },
            .name = "Batch",
            .types = &.{ "IntBatch", "FloatBatch" },
        }},
        .package = "sample",
        .prefix = "zg",
        .types = &.{
            .{ .kind = .@"opaque", .name = "IntBatch" },
            .{ .kind = .@"opaque", .name = "FloatBatch" },
        },
        .zig_version = "0.16.0",
    };
    const bytes = try declared.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var parsed = try Semantic.parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    const interface = parsed.value.interfaces.?[0];
    try std.testing.expectEqualStrings("Batch", interface.name);
    try std.testing.expect(!interface.closer);
    try std.testing.expectEqualStrings("Batch counts staged values.", interface.doc.?);
    try std.testing.expectEqualStrings("clear", interface.methods[1]);
    try std.testing.expectEqualStrings("FloatBatch", interface.types[1]);
    try std.testing.expect(interface.package == null);
}

test "string slice forms agree on every accepted element spelling" {
    var byte: TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var plain: TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    var sentinel: TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte, .sentinel = 0 } };
    var many: TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte, .sentinel = 0, .sentinel_many = true } };
    var other: TypeNode = .{ .int = .{ .bits = 32, .signed = true } };

    const plain_slice: TypeNode = .{ .slice = .{ .@"const" = true, .element = &plain } };
    // `[]const []const u8` is text only when the hint says so.
    try std.testing.expectEqual(@as(?StringSliceForm, .unsentinel), stringSliceForm(plain_slice, .utf8_string));
    try std.testing.expectEqual(@as(?StringSliceForm, null), stringSliceForm(plain_slice, null));
    // Both sentinel spellings are accepted on the spelling alone, and
    // `[*:0]const u8` is accepted exactly like `[:0]const u8`: reflection
    // records a many pointer as a slice carrying `sentinel_many`.
    try std.testing.expectEqual(@as(?StringSliceForm, .sentinel_slice), stringSliceForm(.{ .slice = .{ .@"const" = true, .element = &sentinel } }, null));
    try std.testing.expectEqual(@as(?StringSliceForm, .sentinel_many), stringSliceForm(.{ .slice = .{ .@"const" = true, .element = &many } }, null));
    // A non-byte element is not a string slice whatever the hint says.
    try std.testing.expectEqual(@as(?StringSliceForm, null), stringSliceForm(.{ .slice = .{ .@"const" = true, .element = &other } }, .utf8_string));

    try std.testing.expect(isStringSliceParameter(.{ .name = "names", .type = .{ .slice = .{ .@"const" = true, .element = &many } } }));
    // Only an `in` parameter is flattened; an out slice keeps its own lowering.
    try std.testing.expect(!isStringSliceParameter(.{ .name = "names", .direction = .out, .type = .{ .slice = .{ .@"const" = true, .element = &many } } }));
}

test "a callback or a stream parameter both make a function callback-bearing" {
    var ret: TypeNode = .{ .void = {} };
    const callback: SemanticFn = .{
        .name = "on",
        .params = &.{.{ .name = "cb", .type = .{ .callback = .{ .params = &.{}, .@"return" = &ret, .has_userdata = true } } }},
        .@"return" = .{ .void = {} },
        .symbol = "s",
    };
    const stream: SemanticFn = .{
        .name = "dump",
        .params = &.{.{ .name = "w", .type = .{ .io_stream = .{ .direction = .writer } } }},
        .@"return" = .{ .void = {} },
        .symbol = "s",
    };
    const plain: SemanticFn = .{ .name = "x", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "s" };
    try std.testing.expect(functionHasCallback(callback));
    try std.testing.expect(functionHasCallback(stream));
    try std.testing.expect(!functionHasCallback(plain));
}

test "codepoint predicates accept u21/u32 scalars and plain slices only" {
    var narrow21: TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    var u32_node: TypeNode = .{ .int = .{ .bits = 32, .signed = false } };
    var i32_node: TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const slice: TypeNode = .{ .slice = .{ .@"const" = true, .element = &narrow21 } };
    const out_slice: TypeNode = .{ .slice = .{ .@"const" = false, .element = &u32_node } };
    const sentinel: TypeNode = .{ .slice = .{ .@"const" = true, .element = &u32_node, .sentinel = 0 } };
    const signed_slice: TypeNode = .{ .slice = .{ .@"const" = true, .element = &i32_node } };
    try std.testing.expect(isCodepoint(narrow21, .codepoint));
    try std.testing.expect(isCodepoint(u32_node, .codepoint));
    try std.testing.expect(!isCodepoint(i32_node, .codepoint));
    try std.testing.expect(!isCodepoint(u32_node, null));
    try std.testing.expect(!isCodepoint(u32_node, .utf8_string));
    try std.testing.expect(isCodepointSlice(slice, .codepoint));
    try std.testing.expect(isCodepointSlice(out_slice, .codepoint));
    try std.testing.expect(!isCodepointSlice(sentinel, .codepoint));
    try std.testing.expect(!isCodepointSlice(signed_slice, .codepoint));
    try std.testing.expect(!isCodepointSlice(narrow21, .codepoint));
}

test "callback hints round-trip through the semantic document" {
    var cp: TypeNode = .{ .int = .{ .bits = 32, .signed = false } };
    const userdata: TypeNode = .{ .int = .{ .bits = 64, .signed = false, .is_usize = true } };
    const document: Semantic = .{
        .functions = &.{.{
            .name = "visit",
            .params = &.{.{ .name = "callback", .type = .{ .callback = .{
                .has_userdata = true,
                .params = &.{ cp, userdata },
                .param_semantics = &.{ .codepoint, null },
                .@"return" = &cp,
                .return_semantic = .codepoint,
            } } }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_visit",
        }},
        .package = "text",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const bytes = try document.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var parsed = try Semantic.parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    const callback = parsed.value.functions[0].params[0].type.callback;
    try std.testing.expectEqual(SemanticHint.codepoint, callback.paramHint(0).?);
    try std.testing.expectEqual(@as(?SemanticHint, null), callback.paramHint(1));
    try std.testing.expectEqual(SemanticHint.codepoint, callback.return_semantic.?);
    try std.testing.expect(callback.hasCodepoints());
}

test "plugin options round trip verbatim, in declaration order, and are omitted when absent" {
    const fixture =
        \\{"functions":[{"ext":{"SATIS":{"interfaces":["io.Writer"]},"JSON":{"lower":true}},"name":"feed","params":[],"return":{"kind":"void"},"symbol":"zg_feed"}],"ir_version":1,"package":"sample","prefix":"zg","types":[{"ext":{"JSON":{"lower":false}},"kind":"opaque","name":"Doc"}],"zig_version":"0.16.0"}
    ;
    var parsed = try Semantic.parse(std.testing.allocator, fixture);
    defer parsed.deinit();
    // Two plugins on one function, each reachable by its own key alone.
    const attached = parsed.value.functions[0].ext.?;
    try std.testing.expectEqual(@as(usize, 2), attached.entries.len);
    try std.testing.expectEqualStrings("SATIS", attached.entries[0].plugin);
    try std.testing.expectEqualStrings("io.Writer", attached.get("SATIS").?.object.get("interfaces").?.array.items[0].string);
    try std.testing.expect(attached.get("JSON").?.object.get("lower").?.bool);
    try std.testing.expect(parsed.value.types[0].ext.?.get("JSON").?.object.get("lower").?.bool == false);
    try std.testing.expect(attached.get("NOBODY") == null);

    // Serialization keeps the order the document had, so a round trip is
    // byte-identical and a golden cannot move on a rewrite.
    const bytes = try parsed.value.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"SATIS\"").? < std.mem.indexOf(u8, bytes, "\"JSON\"").?);

    var again = try Semantic.parse(std.testing.allocator, bytes);
    defer again.deinit();
    const rewritten = try again.value.serialize(std.testing.allocator);
    defer std.testing.allocator.free(rewritten);
    try std.testing.expectEqualStrings(bytes, rewritten);

    // A document no plugin extended carries no `ext` key at all.
    const plain: Semantic = .{
        .functions = &.{.{ .name = "feed", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_feed" }},
        .package = "sample",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const plain_bytes = try plain.serialize(std.testing.allocator);
    defer std.testing.allocator.free(plain_bytes);
    try std.testing.expect(std.mem.indexOf(u8, plain_bytes, "\"ext\"") == null);
}

test "enum value ranges cover unsorted and full-width domains" {
    try std.testing.expect(enumValueRange(&.{}) == null);
    const range = enumValueRange(&.{
        .{ .name = "max", .value = std.math.maxInt(i64) },
        .{ .name = "min", .value = std.math.minInt(i64) },
    }).?;
    try std.testing.expectEqual(std.math.minInt(i64), range.min);
    try std.testing.expectEqual(@as(u128, 1) << 64, range.span);
}

pub fn constructorForDeinit(constructors: []const Constructor, function: SemanticFn) ?Constructor {
    const receiver = function.receiver orelse return null;
    for (constructors) |constructor| {
        if (std.mem.eql(u8, constructor.type, receiver) and std.mem.eql(u8, constructor.deinit, function.name)) return constructor;
    }
    return null;
}

pub fn constructorForType(constructors: []const Constructor, type_name: []const u8) ?Constructor {
    for (constructors) |constructor| if (std.mem.eql(u8, constructor.type, type_name)) return constructor;
    return null;
}
