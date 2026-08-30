const zigo = @import("zigo");
const library = @import("pipeline");

pub const bindings = zigo.define(.{
    .specializations = .{
        .{ .name = "IntBatch", .type = library.IntBatch },
        .{ .name = "FloatBatch", .type = library.FloatBatch },
    },
    .types = .{
        .{ .type = library.Pipeline, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .name = "create", .@"fn" = library.IntBatch.create },
        .{ .name = "push", .@"fn" = library.IntBatch.push },
        .{ .name = "len", .@"fn" = library.IntBatch.len },
        .{ .name = "deinit", .@"fn" = library.IntBatch.deinit },
        .{ .name = "create", .@"fn" = library.FloatBatch.create },
        .{ .name = "push", .@"fn" = library.FloatBatch.push },
        .{ .name = "len", .@"fn" = library.FloatBatch.len },
        .{ .name = "deinit", .@"fn" = library.FloatBatch.deinit },
        .{
            .name = "create",
            .@"fn" = library.Pipeline.create,
            .params = .{ "name", "mode", "callback", "userdata" },
            .param_meta = .{
                .name = .{ .semantic = .utf8_string },
                .callback = .{ .retention = .retained },
            },
        },
        .{ .name = "process", .@"fn" = library.Pipeline.process, .params = .{"values"} },
        .{ .name = "name", .@"fn" = library.Pipeline.name, .semantic = .utf8_string },
        .{ .name = "mode", .@"fn" = library.Pipeline.mode },
        .{ .name = "setEnabled", .@"fn" = library.Pipeline.setEnabled, .params = .{"enabled"} },
        .{ .name = "processed", .@"fn" = library.Pipeline.processed },
        .{ .name = "total", .@"fn" = library.Pipeline.total },
        .{ .name = "deinit", .@"fn" = library.Pipeline.deinit },
        .{ .name = "liveBytes", .@"fn" = library.liveBytes },
        .{ .name = "compressionBound", .@"fn" = library.compressionBound },
    },
});
