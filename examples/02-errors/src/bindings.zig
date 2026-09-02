const zigo = @import("zigo");
const errors = @import("errors");

pub const bindings = zigo.define(.{
    .root = errors,
    .functions = .{
        .{ .path = "root.divide" },
        .{ .path = "root.sum" },
        .{ .path = "root.normalizeFormat" },
        .{ .path = "root.codepointWidth", .params = .{"cp"} },
    },
});
