const zigo = @import("zigo");
const library = @import("type_relations");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.Counter, .repr = .@"opaque" },
        .{ .type = library.Accumulator, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .path = "Counter.create", .params = .{"initial"} },
        .{ .path = "Counter.get" },
        .{ .path = "Counter.add", .params = .{"delta"} },
        .{ .path = "Counter.deinit" },
        .{ .path = "Accumulator.create" },
        .{ .path = "Accumulator.absorb", .params = .{"counter"} },
        .{ .path = "Accumulator.total" },
        .{ .path = "Accumulator.deinit" },
        .{ .path = "root.liveObjects" },
    },
});
