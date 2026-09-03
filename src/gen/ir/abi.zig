const semantic = @import("semantic");

/// C can only name 8, 16, 32, and 64-bit integers, so a Zig width outside that
/// set travels in the next one that exists. The declared width is still what
/// the value means, which is why the shim range-checks on the way in.
pub fn promotedIntBits(bits: u16) u16 {
    if (bits <= 8) return 8;
    if (bits <= 16) return 16;
    if (bits <= 32) return 32;
    return 64;
}

/// The declared integer, when it is narrower than the C type carrying it.
pub fn narrowInt(node: semantic.TypeNode) ?semantic.Int {
    if (node != .int) return null;
    const value = node.int;
    if (value.is_usize or promotedIntBits(value.bits) == value.bits) return null;
    return value;
}

pub const AbiScalar = union(enum) {
    void,
    bool_u8,
    isize,
    usize,
    signed_int: u16,
    unsigned_int: u16,
    float: u16,
    @"opaque": AbiOpaque,
    /// A zigo-owned value snapshot struct, named by its C typedef.
    snapshot: []const u8,
    /// A user `extern struct` mirrored into C. Aggregates never cross the
    /// boundary by value, so this only ever appears behind a pointer.
    value_struct: struct {
        /// Semantic type name, as Zig and public Go spell it.
        name: []const u8,
        /// C typedef, `<prefix>_<type>`.
        c_name: []const u8,
    },
    pointer: struct {
        child: *const AbiScalar,
        is_const: bool,
        is_many: bool = false,
        /// A sentinel byte pointer. C spells it `const char *`, while the
        /// generated Zig shim keeps the `[*:0]const u8` contract.
        is_c_string: bool = false,
        /// A handle argument the caller may leave null. C spells every pointer
        /// the same way, so this only changes the Zig shim signature, where a
        /// non-optional pointer would make a null argument illegal.
        is_optional: bool = false,
    },
    callback: struct {
        params: []const AbiScalar,
        ret: *const AbiScalar,
    },
};

/// A user type that C only ever sees behind a pointer: an `opaque` handle or
/// a tagged union. Lowering mints the typedef so no backend has to spell it.
pub const AbiOpaque = struct {
    /// Semantic type name, as Zig and public Go spell it.
    name: []const u8,
    /// C typedef, `<prefix>_<type>`.
    c_name: []const u8,
    /// How many retained callbacks a handle of this type owns. Lowering counts
    /// them once, in the same order it numbers the slots, so generated Go can
    /// size its handle array without rescanning the program. Only the entries
    /// in `Program.handles` carry it; a pointed-to copy inside a scalar keeps 0.
    retained_callback_slots: usize = 0,
};

/// A user enum mirrored into C as its tag type plus one constant per member.
pub const AbiEnum = struct {
    name: []const u8,
    /// C typedef, `<prefix>_<type>`.
    c_name: []const u8,
    /// The integer the typedef aliases.
    tag: AbiScalar,
    constants: []const Constant,

    pub const Constant = struct {
        name: []const u8,
        /// C macro, `<PREFIX>_<TYPE>_<MEMBER>`.
        c_name: []const u8,
        value: i64,
    };
};

pub const AbiParam = struct {
    /// Index in `Parameter.flatten` for a flattened struct field.
    field_index: ?usize = null,
    name: []const u8,
    role: Role = .value,
    scalar: AbiScalar,
    source_index: usize = 0,

    pub const Role = enum {
        receiver,
        flattened_field,
        value,
        slice_pointer,
        slice_length,
        slice_written,
        string_data,
        string_data_length,
        string_lengths,
        string_count,
        payload_out,
        return_slice_pointer,
        return_slice_length,
        struct_in,
        /// The discriminant of a scalar-payload tagged union passed by value.
        /// It is followed by one `union_payload` parameter for every non-void
        /// variant, in declaration order.
        union_tag,
        union_payload,
        struct_out,
        /// A `?T` parameter: `T` lowered behind a nullable pointer, `NULL`
        /// standing for the Zig `null`. Scalar and `extern struct` children
        /// share this role -- both cross as one pointer argument, so the
        /// scalar case needs no separate presence flag.
        optional_in,
        /// The `bool *` out parameter carrying presence for an error-union
        /// payload of `?T`: `out_result` (the existing `payload_out` or
        /// `struct_out` role) still carries the value, written only when this
        /// is true.
        payload_has_out,
        /// The three parts of a `*std.Io.Writer` / `*std.Io.Reader`
        /// parameter. cgo binds the trampoline by name and carries only the
        /// userdata token; purego passes the dispatcher pointer as well. The
        /// `stream_data` pair is reserved on a reader for the byte-slice fast
        /// path: the shim already honours it, and generated Go passes null.
        /// The `const uint32_t *` a cancellable call polls. Go owns the word
        /// and raises it from a goroutine watching `ctx.Done()`; the address
        /// is valid only for the call, which is all the contract asks for.
        cancel_flag,
        /// A borrowed Go `sync/atomic` value shared with Zig for this call.
        atomic_ptr,
        stream_callback,
        stream_data,
        stream_data_length,
        stream_userdata,
    };
};

/// The bit layout of one `packed struct` field, decided in lowering so the
/// header, the shim and both Go backends shift and mask identically.
pub const AbiPacked = struct {
    /// Semantic type name of the packed struct.
    name: []const u8,
    fields: []const Field,

    pub const Field = struct {
        /// Semantic field name, in declaration order.
        name: []const u8,
        /// Offset from the least significant bit of the backing integer.
        bit_offset: u16,
        bits: u16,
        /// `bits` ones, ready to mask the shifted value.
        mask: u64,
    };
};

/// A declaration's members minus the ones `omit` dropped, in declaration
/// order. Lowering applies the rule once; every emitter loop that renders
/// members walks this instead of re-testing `variantOmitted`.
pub const AbiLiveFields = struct {
    /// Semantic type name of the enum or tagged union.
    type_name: []const u8,
    fields: []const semantic.TypeField,
};

pub const ErrorCode = struct { code: i32, name: []const u8 };

pub const AbiFn = struct {
    symbol: []const u8,
    params: []const AbiParam,
    ret: AbiScalar,
    errors: []const ErrorCode = &.{},
    origin: *const semantic.SemanticFn,
    /// The mirror the call fills when the function returns an `extern struct`
    /// directly. Aggregates never cross by value, so the C signature returns
    /// `void` and takes a `struct_out` pointer instead.
    ret_struct: ?*const AbiStruct = null,
    /// The same, for an `extern struct` carried as an error-union payload. It
    /// is a separate field because the two spell different Go: one returns the
    /// struct, the other returns it alongside an error code.
    payload_struct: ?*const AbiStruct = null,
    /// True when the return itself is `?T` (not inside an error union): the C
    /// return becomes `bool` (presence) instead of `void`, with the value
    /// written through `out_result` (or `ret_struct`'s pointer) only when true.
    ret_optional: bool = false,
    /// This synthetic error-union payload is a tagged-union return snapshot.
    value_union_return: bool = false,
    /// Symbol of the function that frees a caller-owned slice result. Generated
    /// Go copies the payload out and then calls this with the same `ptr, len`.
    release_symbol: ?[]const u8 = null,
    /// Indexed by semantic parameter index: where this parameter's flattened
    /// fields start in `params`. Lowering appends one `flattened_field` per
    /// declared field, contiguously and in order, so field `n` sits at
    /// `start + n`.
    flatten_start: []const ?usize = &.{},
    /// Indexed by semantic parameter index: the slot a retained callback
    /// parameter takes in the handle that owns it, or null for every other
    /// parameter. Slots are numbered once in lowering, by owner type, over the
    /// functions in program order and then the retained callback parameters in
    /// parameter order.
    callback_slots: []const ?usize = &.{},
    /// Indexed by semantic parameter index: how this parameter carries text,
    /// decided once here so no backend re-reads the hint and the spelling.
    param_strings: []const ParamString = &.{},
    /// How the function's result carries text. `c_string` is the return that
    /// crosses as a bare `const char *`; a caller-owned slice return with a
    /// release target is not one of these, because it crosses as the
    /// out-pointer-and-length pair `slice_return_element` describes.
    ret_string: StringRole = .none,
    /// The element a function hands back through `out_result_ptr` and
    /// `out_result_len`, or null when it returns something else. This is the
    /// calling-convention question; `validate.releasableSliceReturnElement`
    /// asks the ownership one and answers differently for a C-string return.
    slice_return_element: ?semantic.TypeNode = null,
    /// Indexed by semantic parameter index: the callback parameter this
    /// userdata token belongs to. A callback's userdata is always the
    /// parameter directly after it, so the pair is fixed by position.
    userdata_for: []const ?usize = &.{},
    /// Indexed by semantic parameter index: the public Go type a callback
    /// parameter is spelled with, and whether this is the first parameter in
    /// program order to use that name -- the declarations are emitted once,
    /// at that first use.
    callback_types: []const ?CallbackType = &.{},

    /// How a parameter or return carries text.
    pub const StringRole = enum {
        none,
        /// `[]const u8` marked `utf8_string`: pointer plus length.
        utf8_slice,
        /// `[]const u8` marked `c_string`: one NUL-terminated pointer.
        c_string,
        /// `[]const []const u8` and its sentinel spellings: flattened data,
        /// lengths and count.
        string_slice,
    };

    pub const ParamString = struct {
        role: StringRole = .none,
        /// The element spelling the shim rebuilds, set only for
        /// `string_slice`.
        form: ?semantic.StringSliceForm = null,
    };

    pub const CallbackType = struct {
        name: []const u8,
        first_use: bool,
    };

    /// How semantic parameter `source_index` carries text.
    pub fn paramString(self: AbiFn, source_index: usize) ParamString {
        if (source_index >= self.param_strings.len) return .{};
        return self.param_strings[source_index];
    }

    /// The callback semantic parameter `source_index` is the userdata of.
    pub fn userdataFor(self: AbiFn, source_index: usize) ?usize {
        if (source_index >= self.userdata_for.len) return null;
        return self.userdata_for[source_index];
    }

    /// The Go callback type of semantic parameter `source_index`.
    pub fn callbackType(self: AbiFn, source_index: usize) ?CallbackType {
        if (source_index >= self.callback_types.len) return null;
        return self.callback_types[source_index];
    }

    /// The ABI parameter carrying field `field_index` of the flattened
    /// parameter `source_index`.
    pub fn flattenedParam(self: AbiFn, source_index: usize, field_index: usize) AbiParam {
        return self.params[self.flatten_start[source_index].? + field_index];
    }

    /// The retained callback slot of semantic parameter `source_index`.
    pub fn callbackSlot(self: AbiFn, source_index: usize) ?usize {
        if (source_index >= self.callback_slots.len) return null;
        return self.callback_slots[source_index];
    }
};

pub const AbiProjection = struct {
    kind: Kind,
    symbol: []const u8,
    params: []const AbiParam,
    ret: AbiScalar,
    owner: *const semantic.TypeDecl,
    field: ?*const semantic.TypeField = null,

    pub const Kind = enum { tag, payload };
    pub const Status = enum(u8) {
        mismatch = 0,
        success = 1,
        invalid_handle = 2,
        panic = 3,
    };
};

/// One tagged union lowered to a value snapshot: the zigo-owned `extern
/// struct` layout plus the single call that fills it. The layout is decided
/// here so the header, the shim and both Go backends render the same bytes.
pub const AbiSnapshot = struct {
    owner: *const semantic.TypeDecl,
    /// Exported C function, `<prefix>_<type>_snapshot`.
    symbol: []const u8,
    /// C typedef of the snapshot struct, `<prefix>_<type>_snapshot_t`.
    type_name: []const u8,
    /// Struct members in layout order, padding included.
    fields: []const Field,
    /// Total struct width in bytes, padding included.
    size: usize,
    /// Struct alignment: the widest member.
    alignment: usize,
    params: []const AbiParam,
    ret: AbiScalar,

    pub const Field = struct {
        kind: Kind,
        /// C and Zig member name. Padding members are `reserved_<n>`.
        name: []const u8,
        /// Member width in bytes; the element count for padding members.
        bytes: usize,
        scalar: AbiScalar,
        /// The semantic node behind a tag or payload member, for languages
        /// that spell enums with their own type name.
        node: ?semantic.TypeNode = null,
        /// The union variant a payload member mirrors.
        source: ?*const semantic.TypeField = null,

        pub const Kind = enum { tag, padding, payload };
    };
};

/// A user `extern struct` mirrored into the C header. `extern` already fixes
/// the layout, so the members are the user's own; the recorded size and
/// alignment let the shim assert that the Zig type still matches the mirror.
pub const AbiStruct = struct {
    owner: *const semantic.TypeDecl,
    name: []const u8,
    c_name: []const u8,
    fields: []const Field,
    size: usize,
    alignment: usize,
    /// True when the Go mirror can be reinterpreted as the C one instead of
    /// being converted member by member. A `bool` member rules it out -- Go
    /// spells it one byte wide but does not promise C's representation -- and
    /// so does a nested struct that is itself not castable. Lowering decides
    /// this once, after every member's own record exists.
    castable: bool = true,

    pub const Field = struct {
        /// The target member is an atomic wrapper over `node`.
        atomic: bool = false,
        name: []const u8,
        scalar: AbiScalar,
        node: semantic.TypeNode,
        /// Byte offset in the C mirror, which Go must reproduce exactly.
        offset: usize,
        bytes: usize,
    };
};

pub const Program = struct {
    pub const Backend = enum { cgo, purego };
    /// `function_pointer_userdata_v2` differs from v1 only in how float callback
    /// parameters travel: as their IEEE-754 bit pattern in a same-width integer
    /// rather than as a float. The version rides in the exported symbol name, so a
    /// stale library and regenerated Go fail to resolve instead of misreading bits.
    pub const CallbackConvention = enum { fixed_go_export, function_pointer_userdata_v1, function_pointer_userdata_v2 };

    /// The Zig expression the shim passes for injected `std.mem.Allocator`
    /// and `std.Io` parameters, carried straight through from the document.
    allocator: ?[]const u8 = null,
    backend: Backend = .cgo,
    callback_convention: CallbackConvention = .fixed_go_export,
    constructors: []const semantic.Constructor = &.{},
    doc: ?[]const u8 = null,
    enums: []const AbiEnum = &.{},
    error_codes: []const ErrorCode = &.{},
    handles: []const AbiOpaque = &.{},
    functions: []const AbiFn,
    io: ?[]const u8 = null,
    live_fields: []const AbiLiveFields = &.{},
    packed_structs: []const AbiPacked = &.{},
    package: []const u8,
    packages: ?[]const semantic.Package = null,
    prefix: []const u8,
    projections: []const AbiProjection = &.{},
    snapshots: []const AbiSnapshot = &.{},
    structs: []const AbiStruct = &.{},
    types: []const semantic.TypeDecl = &.{},

    /// The members of `type_name` that survived `omit`.
    pub fn liveFields(self: Program, type_name: []const u8) []const semantic.TypeField {
        for (self.live_fields) |entry| {
            if (@import("std").mem.eql(u8, entry.type_name, type_name)) return entry.fields;
        }
        return &.{};
    }

    /// The bit layout of the `packed struct` named `type_name`.
    pub fn packedLayout(self: Program, type_name: []const u8) []const AbiPacked.Field {
        for (self.packed_structs) |entry| {
            if (@import("std").mem.eql(u8, entry.name, type_name)) return entry.fields;
        }
        return &.{};
    }

    /// Whether the Go mirror of `type_name` can be cast to the C one.
    pub fn structCastable(self: Program, type_name: []const u8) bool {
        for (self.structs) |record| {
            if (@import("std").mem.eql(u8, record.name, type_name)) return record.castable;
        }
        return true;
    }

    /// How many retained callback slots a handle of this type owns.
    pub fn retainedCallbackSlotCount(self: Program, type_name: []const u8) usize {
        for (self.handles) |handle| {
            if (@import("std").mem.eql(u8, handle.name, type_name)) return handle.retained_callback_slots;
        }
        return 0;
    }
};

test "ABI functions retain their semantic origin" {
    const origin: semantic.SemanticFn = .{
        .name = "ping",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "zg_ping",
    };
    const abi: AbiFn = .{
        .symbol = origin.symbol,
        .params = &.{},
        .ret = .void,
        .origin = &origin,
    };
    try @import("std").testing.expectEqualStrings("ping", abi.origin.name);
}
