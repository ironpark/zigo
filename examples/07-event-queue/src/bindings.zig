const zigo = @import("zigo");
const library = @import("event_queue");

pub const bindings = zigo.define(.{
    .types = .{
        .{ .type = library.EventQueue, .repr = .@"opaque" },
        .{ .type = library.Stats, .repr = .value },
        .{ .type = library.Limits, .repr = .value },
    },
    .functions = .{
        .{
            .name = "create",
            .@"fn" = library.EventQueue.create,
            .params = .{ "name", "capacity", "policy", "observer", "userdata" },
            .param_meta = .{
                .name = .{ .semantic = .utf8_string },
                .observer = .{ .retention = .retained },
            },
        },
        .{ .name = "enqueue", .@"fn" = library.EventQueue.enqueue, .params = .{ "id", "value" } },
        .{ .name = "process", .@"fn" = library.EventQueue.process, .params = .{"limit"} },
        .{ .name = "name", .@"fn" = library.EventQueue.name, .semantic = .utf8_string },
        .{ .name = "len", .@"fn" = library.EventQueue.len },
        .{ .name = "capacity", .@"fn" = library.EventQueue.capacity },
        .{ .name = "policy", .@"fn" = library.EventQueue.policy },
        .{ .name = "dropped", .@"fn" = library.EventQueue.dropped },
        .{ .name = "processed", .@"fn" = library.EventQueue.processed },
        .{ .name = "stats", .@"fn" = library.EventQueue.stats },
        .{ .name = "limits", .@"fn" = library.EventQueue.limits },
        .{ .name = "applyLimits", .@"fn" = library.EventQueue.applyLimits, .params = .{"updated"} },
        .{ .name = "clear", .@"fn" = library.EventQueue.clear },
        .{ .name = "deinit", .@"fn" = library.EventQueue.deinit },
        .{ .name = "liveQueues", .@"fn" = library.liveQueues },
    },
});
