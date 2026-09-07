const zigo = @import("zigo");
const library = @import("pipeline");

const api = zigo.scope(library);
const Pipeline = api.handle("Pipeline", .{}).context();
const IntBatch = api.handle("IntBatch", .{}).context();
const FloatBatch = api.handle("FloatBatch", .{}).context();

// The same explicit export list applies to both generic instantiations.
const batch_members: zigo.Selector = .{ .names = &.{ "create", "push", "len", "deinit" } };

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        Pipeline.define(&.{
            Pipeline.function("create", .{
                .params = &.{
                    .{ .index = 0, .go_name = "name", .semantic = .utf8_string },
                    .{ .index = 1, .go_name = "mode" },
                    zigo.param.callback(2, .{ .retention = .retained }),
                },
            }),
            Pipeline.function("process", .{}),
            Pipeline.function("name", .{ .returns = .{ .semantic = .utf8_string } }),
            Pipeline.function("mode", .{}),
            Pipeline.function("setEnabled", .{}),
            Pipeline.function("processed", .{}),
            Pipeline.function("total", .{}),
            Pipeline.function("deinit", .{}),
        }),
        IntBatch.select(batch_members),
        FloatBatch.select(batch_members),
        api.function("liveBytes", .{}),
        api.function("compressionBound", .{}),
        zigo.interface(.{
            .name = "Batch",
            .methods = &.{"len"},
            .types = &.{ IntBatch.typeRef(), FloatBatch.typeRef() },
            .doc = "Batch is any staged batch, whatever its element type.",
        }),
    },
});
