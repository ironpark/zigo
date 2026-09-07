const zigo = @import("zigo");
const library = @import("pipeline");

const api = zigo.scope(library);

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.handle("Pipeline", .{}),
        api.handle("IntBatch", .{}),
        api.handle("FloatBatch", .{}),
        api.in("IntBatch").function("create", .{}),
        api.in("IntBatch").function("push", .{}),
        api.in("IntBatch").function("len", .{}),
        api.in("IntBatch").function("deinit", .{}),
        api.in("FloatBatch").function("create", .{}),
        api.in("FloatBatch").function("push", .{}),
        api.in("FloatBatch").function("len", .{}),
        api.in("FloatBatch").function("deinit", .{}),
        api.in("Pipeline").function("create", .{ .params = &.{ .{ .index = 0, .go_name = "name", .semantic = .utf8_string }, .{ .index = 1, .go_name = "mode" }, .{ .index = 2, .go_name = "callback", .contract = .{ .callback = .{ .retention = .retained } } }, .{ .index = 3, .go_name = "userdata" } } }),
        api.in("Pipeline").function("process", .{ .params = &.{.{ .index = 1, .go_name = "values" }} }),
        api.in("Pipeline").function("name", .{ .returns = .{ .semantic = .utf8_string } }),
        api.in("Pipeline").function("mode", .{}),
        api.in("Pipeline").function("setEnabled", .{ .params = &.{.{ .index = 1, .go_name = "enabled" }} }),
        api.in("Pipeline").function("processed", .{}),
        api.in("Pipeline").function("total", .{}),
        api.in("Pipeline").function("deinit", .{}),
        api.function("liveBytes", .{}),
        api.function("compressionBound", .{}),
        zigo.interface(.{ .name = "Batch", .methods = &.{"len"}, .types = &.{ api.typeRef("IntBatch"), api.typeRef("FloatBatch") }, .doc = "Batch is any staged batch, whatever its element type." }),
    },
});
