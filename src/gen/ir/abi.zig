const semantic = @import("semantic");

pub const AbiScalar = union(enum) {
    void,
    bool_u8,
    isize,
    usize,
    signed_int: u16,
    unsigned_int: u16,
    float: u16,
    @"opaque": []const u8,
    pointer: struct {
        child: *const AbiScalar,
        is_const: bool,
        is_many: bool = false,
    },
    callback: struct {
        params: []const AbiScalar,
        ret: *const AbiScalar,
    },
};

pub const AbiParam = struct {
    name: []const u8,
    role: Role = .value,
    scalar: AbiScalar,
    source_index: usize = 0,

    pub const Role = enum { receiver, value, slice_pointer, slice_length, slice_written, payload_out, return_slice_pointer, return_slice_length };
};

pub const ErrorCode = struct { code: i32, name: []const u8 };

pub const AbiFn = struct {
    symbol: []const u8,
    params: []const AbiParam,
    ret: AbiScalar,
    errors: []const ErrorCode = &.{},
    origin: *const semantic.SemanticFn,
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

pub const Program = struct {
    pub const Backend = enum { cgo, purego };
    pub const CallbackConvention = enum { fixed_go_export, function_pointer_userdata_v1 };

    backend: Backend = .cgo,
    callback_convention: CallbackConvention = .fixed_go_export,
    constructors: []const semantic.Constructor = &.{},
    error_codes: []const ErrorCode = &.{},
    functions: []const AbiFn,
    package: []const u8,
    prefix: []const u8,
    projections: []const AbiProjection = &.{},
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
