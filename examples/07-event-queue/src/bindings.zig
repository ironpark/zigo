const zigo = @import("zigo");
const library = @import("event_queue");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.EventQueue, .repr = .@"opaque" },
        .{ .type = library.Stats, .repr = .value },
        .{ .type = library.Limits, .repr = .value },
    },
    .functions = .{
        .{
            .path = "EventQueue.create",
            .params = .{ "name", "capacity", "policy", "observer", "userdata" },
            .param_meta = .{
                .name = .{ .semantic = .utf8_string },
                .observer = .{ .retention = .retained },
            },
        },
        .{
            .path = "EventQueue.clone",
            .params = .{ "observer", "userdata" },
            .param_meta = .{ .observer = .{ .retention = .retained } },
            .returns = .caller,
        },
        .{ .path = "EventQueue.enqueue", .params = .{ "id", "value" } },
        .{ .path = "EventQueue.mergeFrom", .params = .{"source"} },
        .{ .path = "EventQueue.process", .params = .{"limit"} },
        .{ .path = "EventQueue.name", .semantic = .utf8_string },
        .{ .path = "EventQueue.sampleValues" },
        .{ .path = "EventQueue.sampleValuesChecked" },
        .{ .path = "EventQueue.echoCString", .params = .{"text"} },
        .{ .path = "EventQueue.sampleCString" },
        .{
            .path = "EventQueue.extractPaths",
            .params = .{"paths"},
            .param_meta = .{ .paths = .{ .semantic = .utf8_string } },
        },
        .{ .path = "EventQueue.extractSentinelSlices", .params = .{"paths"} },
        .{ .path = "EventQueue.extractSentinelPointers", .params = .{"paths"} },
        .{
            .path = "EventQueue.extractSamples",
            .returns = .caller,
            .release = "EventQueue.freeSamples",
        },
        .{ .path = "EventQueue.freeSamples", .params = .{"samples"} },
        .{ .path = "EventQueue.acceptStats", .params = .{"values"} },
        .{
            .path = "EventQueue.estimate",
            .params = .{"output"},
            .param_meta = .{ .output = .{ .direction = .out } },
        },
        .{ .path = "EventQueue.sampleStats" },
        .{ .path = "EventQueue.len" },
        .{ .path = "EventQueue.capacity" },
        .{ .path = "EventQueue.policy" },
        .{ .path = "EventQueue.dropped" },
        .{ .path = "EventQueue.processed" },
        .{ .path = "EventQueue.stats" },
        .{ .path = "EventQueue.limits" },
        .{ .path = "EventQueue.applyLimits", .params = .{"updated"} },
        .{ .path = "EventQueue.clear" },
        .{ .path = "EventQueue.deinit" },
        .{ .path = "root.liveQueues" },
        .{ .path = "root.liveSamples" },
    },
});
