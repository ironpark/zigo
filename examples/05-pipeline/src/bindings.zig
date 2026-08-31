const zigo = @import("zigo");
const library = @import("pipeline");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.Pipeline, .repr = .@"opaque" },
        .{ .name = "IntBatch", .type = library.IntBatch, .repr = .@"opaque" },
        .{ .name = "FloatBatch", .type = library.FloatBatch, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .path = "IntBatch.create" },
        .{ .path = "IntBatch.push" },
        .{ .path = "IntBatch.len" },
        .{ .path = "IntBatch.deinit" },
        .{ .path = "FloatBatch.create" },
        .{ .path = "FloatBatch.push" },
        .{ .path = "FloatBatch.len" },
        .{ .path = "FloatBatch.deinit" },
        .{
            .path = "Pipeline.create",
            .params = .{ "name", "mode", "callback", "userdata" },
            .param_meta = .{
                .name = .{ .semantic = .utf8_string },
                .callback = .{ .retention = .retained },
            },
        },
        .{ .path = "Pipeline.process", .params = .{"values"} },
        .{ .path = "Pipeline.name", .semantic = .utf8_string },
        .{ .path = "Pipeline.mode" },
        .{ .path = "Pipeline.setEnabled", .params = .{"enabled"} },
        .{ .path = "Pipeline.processed" },
        .{ .path = "Pipeline.total" },
        .{ .path = "Pipeline.deinit" },
        .{ .path = "root.liveBytes" },
        .{ .path = "root.compressionBound" },
    },
});
