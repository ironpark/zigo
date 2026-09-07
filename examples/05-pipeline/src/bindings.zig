const zigo = @import("zigo");
const library = @import("pipeline");

const api = zigo.scope(library);
const pipeline = api.in("Pipeline");
const int_batch = api.in("IntBatch");
const float_batch = api.in("FloatBatch");

// The same explicit export list applies to both generic instantiations.
const batch_members: zigo.Selector = .{ .names = &.{ "create", "push", "len", "deinit" } };

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.handle("Pipeline", .{}).members(&.{
            pipeline.function("create", .{
                .params = &.{
                    .{ .index = 0, .go_name = "name", .semantic = .utf8_string },
                    .{ .index = 1, .go_name = "mode" },
                    zigo.param.callback(2, .{ .retention = .retained }),
                },
            }),
            pipeline.function("process", .{}),
            pipeline.function("name", .{ .returns = .{ .semantic = .utf8_string } }),
            pipeline.function("mode", .{}),
            pipeline.function("setEnabled", .{}),
            pipeline.function("processed", .{}),
            pipeline.function("total", .{}),
            pipeline.function("deinit", .{}),
        }),
        api.handle("IntBatch", .{}).members(int_batch.functions(batch_members)),
        api.handle("FloatBatch", .{}).members(float_batch.functions(batch_members)),
        api.function("liveBytes", .{}),
        api.function("compressionBound", .{}),
        zigo.interface(.{
            .name = "Batch",
            .methods = &.{"len"},
            .types = &.{ api.typeRef("IntBatch"), api.typeRef("FloatBatch") },
            .doc = "Batch is any staged batch, whatever its element type.",
        }),
    },
});
