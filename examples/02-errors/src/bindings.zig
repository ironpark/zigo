const zigo = @import("zigo");
const errors = @import("errors");

pub const bindings = zigo.define(.{
    .functions = .{
        .{ .name = "divide", .@"fn" = errors.divide },
        .{ .name = "sum", .@"fn" = errors.sum },
        .{ .name = "normalizeFormat", .@"fn" = errors.normalizeFormat },
    },
});
