const zigo = @import("zigo");
const library = @import("tagged_union");

pub const bindings = zigo.define(.{
    .types = .{
        .{ .type = library.Child, .repr = .@"opaque" },
        .{ .type = library.Value, .repr = .tagged_union },
        .{ .type = library.Signal, .repr = .tagged_union_value },
    },
    .functions = .{
        .{ .name = "create", .@"fn" = library.Child.create, .params = .{"value"} },
        .{ .name = "get", .@"fn" = library.Child.get },
        .{ .name = "deinit", .@"fn" = library.Child.deinit },
        .{ .name = "create", .@"fn" = library.Value.create, .params = .{"initial"} },
        .{ .name = "setNone", .@"fn" = library.Value.setNone },
        .{ .name = "setFlag", .@"fn" = library.Value.setFlag, .params = .{"flag"} },
        .{ .name = "setMode", .@"fn" = library.Value.setMode, .params = .{"mode"} },
        .{ .name = "usePresetSamples", .@"fn" = library.Value.usePresetSamples },
        .{ .name = "useEmptySamples", .@"fn" = library.Value.useEmptySamples },
        .{ .name = "useMutableSamples", .@"fn" = library.Value.useMutableSamples },
        .{ .name = "setChild", .@"fn" = library.Value.setChild, .params = .{"child"} },
        .{ .name = "borrow", .@"fn" = library.Value.borrow },
        .{ .name = "deinit", .@"fn" = library.Value.deinit },
        .{ .name = "create", .@"fn" = library.Signal.create, .params = .{"initial"} },
        .{ .name = "setIdle", .@"fn" = library.Signal.setIdle },
        .{ .name = "setTicks", .@"fn" = library.Signal.setTicks, .params = .{"ticks"} },
        .{ .name = "setLevel", .@"fn" = library.Signal.setLevel, .params = .{"level"} },
        .{ .name = "setOffset", .@"fn" = library.Signal.setOffset, .params = .{"offset"} },
        .{ .name = "setMode", .@"fn" = library.Signal.setMode, .params = .{"mode"} },
        .{ .name = "setActive", .@"fn" = library.Signal.setActive, .params = .{"active"} },
        .{ .name = "deinit", .@"fn" = library.Signal.deinit },
        .{ .name = "liveValues", .@"fn" = library.liveValues },
        .{ .name = "divide", .@"fn" = library.divide, .params = .{ "numerator", "denominator" } },
        .{ .name = "sum", .@"fn" = library.sum, .params = .{"values"} },
        .{ .name = "panicError", .@"fn" = library.panicError },
    },
});
