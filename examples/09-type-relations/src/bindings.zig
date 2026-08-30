const zigo = @import("zigo");
const library = @import("type_relations");

pub const bindings = zigo.define(.{
    .types = .{
        .{ .type = library.Counter, .repr = .@"opaque" },
        .{ .type = library.Accumulator, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .name = "create", .@"fn" = library.Counter.create, .params = .{"initial"} },
        .{ .name = "get", .@"fn" = library.Counter.get },
        .{ .name = "add", .@"fn" = library.Counter.add, .params = .{"delta"} },
        .{ .name = "deinit", .@"fn" = library.Counter.deinit },
        .{ .name = "create", .@"fn" = library.Accumulator.create },
        .{ .name = "absorb", .@"fn" = library.Accumulator.absorb, .params = .{"counter"} },
        .{ .name = "total", .@"fn" = library.Accumulator.total },
        .{ .name = "deinit", .@"fn" = library.Accumulator.deinit },
        .{ .name = "liveObjects", .@"fn" = library.liveObjects },
    },
});
