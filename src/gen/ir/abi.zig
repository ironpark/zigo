const semantic = @import("semantic");

pub const AbiScalar = union(enum) {
    void,
    bool_u8,
    signed_int: u16,
    unsigned_int: u16,
    float: u16,
    pointer: struct {
        child: *const AbiScalar,
        is_const: bool,
    },
};

pub const AbiParam = struct {
    name: []const u8,
    scalar: AbiScalar,
};

pub const AbiFn = struct {
    symbol: []const u8,
    params: []const AbiParam,
    ret: AbiScalar,
    origin: *const semantic.SemanticFn,
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
