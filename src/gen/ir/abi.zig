const semantic = @import("semantic");

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
    name: []const u8,
    role: Role = .value,
    scalar: AbiScalar,
    source_index: usize = 0,

    pub const Role = enum {
        receiver,
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
        struct_out,
    };
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
    /// Symbol of the function that frees a caller-owned slice result. Generated
    /// Go copies the payload out and then calls this with the same `ptr, len`.
    release_symbol: ?[]const u8 = null,
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

    pub const Field = struct {
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

    backend: Backend = .cgo,
    callback_convention: CallbackConvention = .fixed_go_export,
    constructors: []const semantic.Constructor = &.{},
    doc: ?[]const u8 = null,
    enums: []const AbiEnum = &.{},
    error_codes: []const ErrorCode = &.{},
    handles: []const AbiOpaque = &.{},
    functions: []const AbiFn,
    package: []const u8,
    prefix: []const u8,
    projections: []const AbiProjection = &.{},
    snapshots: []const AbiSnapshot = &.{},
    structs: []const AbiStruct = &.{},
    types: []const semantic.TypeDecl = &.{},
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
