const zigo = @import("zigo");
const library = @import("tagged_union");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.Child, .repr = .@"opaque" },
        .{ .type = library.Value, .repr = .tagged_union },
        .{ .type = library.Signal, .repr = .tagged_union, .access = .snapshot },
    },
    .functions = .{
        .{ .path = "Child.create", .params = .{"value"} },
        .{ .path = "Child.get" },
        .{ .path = "Child.deinit" },
        .{ .path = "Value.create", .params = .{"initial"} },
        .{ .path = "Value.setNone" },
        .{ .path = "Value.setFlag", .params = .{"flag"} },
        .{ .path = "Value.setMode", .params = .{"mode"} },
        .{ .path = "Value.usePresetSamples" },
        .{ .path = "Value.useEmptySamples" },
        .{ .path = "Value.useMutableSamples" },
        .{ .path = "Value.setChild", .params = .{"child"} },
        .{ .path = "Value.borrow" },
        .{ .path = "Value.deinit" },
        .{ .path = "Signal.create", .params = .{"initial"} },
        .{ .path = "Signal.setIdle" },
        .{ .path = "Signal.setTicks", .params = .{"ticks"} },
        .{ .path = "Signal.setLevel", .params = .{"level"} },
        .{ .path = "Signal.setOffset", .params = .{"offset"} },
        .{ .path = "Signal.setMode", .params = .{"mode"} },
        .{ .path = "Signal.setActive", .params = .{"active"} },
        .{ .path = "Signal.deinit" },
        .{ .path = "root.liveValues" },
        .{ .path = "root.divide", .params = .{ "numerator", "denominator" } },
        .{ .path = "root.sum", .params = .{"values"} },
        .{ .path = "root.panicError" },
    },
});
