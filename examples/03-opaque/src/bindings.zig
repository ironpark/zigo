const zigo = @import("zigo");
const library = @import("opaque");

pub const bindings = zigo.define(.{
    .types = .{
        .{ .type = library.Context, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .name = "create", .@"fn" = library.Context.create },
        .{ .name = "add", .@"fn" = library.Context.add, .params = .{"value"} },
        .{ .name = "deinit", .@"fn" = library.Context.deinit },
        .{ .name = "liveBytes", .@"fn" = library.liveBytes },
    },
});
