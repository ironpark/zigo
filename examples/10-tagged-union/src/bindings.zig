const zigo = @import("zigo");
const library = @import("tagged_union");

pub const bindings = zigo.define(.{
    .types = .{
        .{ .type = library.Child, .repr = .@"opaque" },
        .{ .type = library.Value, .repr = .tagged_union },
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
        .{ .name = "liveValues", .@"fn" = library.liveValues },
    },
});
