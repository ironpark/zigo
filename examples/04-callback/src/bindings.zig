const zigo = @import("zigo");
const library = @import("callback");

const api = zigo.scope(library);

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.handle("CallbackContext", .{ .fields = &.{
            .{ .path = "stats.runs", .name = "runCount", .set = true, .doc = "RunCount reports how many callbacks have run." },
        } }),
        api.handle("FloatBuffer", .{}),
        api.handle("IntBuffer", .{}),
        api.callback("Observer", .{ .on_callback_failure = .{ .result = 0 } }),
        api.callback("VoidObserver", .{}),
        api.callback("Predicate", .{}),
        api.callback("Reducer", .{ .userdata = .first }),
        api.callback("Visitor", .{ .params = &.{.{ .semantic = .codepoint }} }),
        api.callback("Logger", .{ .params = &.{ .{}, .{ .semantic = .utf8_string } } }),
        api.callback("ByteSink", .{ .params = &.{.{ .semantic = .opaque_bytes }} }),
        api.callback("Inspector", .{}),
        api.in("FloatBuffer").function("create", .{}),
        api.in("FloatBuffer").function("push", .{}),
        api.in("FloatBuffer").function("len", .{}),
        api.in("FloatBuffer").function("deinit", .{}),
        api.in("IntBuffer").function("create", .{}),
        api.in("IntBuffer").function("push", .{}),
        api.in("IntBuffer").function("len", .{}),
        api.in("IntBuffer").function("deinit", .{}),
        api.in("CallbackContext").function("create", .{ .params = &.{ .{ .index = 0, .go_name = "callback", .contract = .{ .callback = .{ .retention = .retained, .go_error = true } } }, .{ .index = 1, .go_name = "userdata" } } }),
        api.in("CallbackContext").function("run", .{}),
        api.in("CallbackContext").function("deinit", .{}),
        api.function("panicNow", .{}),
        api.function("compressionBound", .{}),
        api.function("incrementShared", .{ .params = &.{ .{ .index = 0, .go_name = "counter" }, .{ .index = 1, .go_name = "delta" } } }),
        api.function("readShared", .{ .params = &.{.{ .index = 0, .go_name = "value" }} }),
        api.function("apply", .{ .params = &.{ .{ .index = 0, .go_name = "value" }, .{ .index = 1, .go_name = "callback", .contract = .{ .callback = .{ .go_error = true } } }, .{ .index = 2, .go_name = "userdata" } } }),
        api.function("applyUntilCancelled", .{ .params = &.{ .{ .index = 0, .go_name = "limit" }, .{ .index = 1, .go_name = "callback", .contract = .{ .callback = .{ .go_error = true } } }, .{ .index = 2, .go_name = "userdata" }, .{ .index = 3, .go_name = "cancel", .contract = .{ .cancel = .{} } } } }),
        api.function("notify", .{ .params = &.{ .{ .index = 0, .go_name = "value" }, .{ .index = 1, .go_name = "callback" }, .{ .index = 2, .go_name = "userdata" } } }),
        api.function("filter", .{ .params = &.{ .{ .index = 0, .go_name = "value" }, .{ .index = 1, .go_name = "strict" }, .{ .index = 2, .go_name = "predicate" }, .{ .index = 3, .go_name = "userdata" } } }),
        api.function("reduce", .{ .params = &.{ .{ .index = 0, .go_name = "ctx" }, .{ .index = 1, .go_name = "values" }, .{ .index = 2, .go_name = "reducer", .contract = .{ .callback = .{ .userdata = 0 } } } } }),
        api.function("logMessage", .{ .params = &.{ .{ .index = 0, .go_name = "message" }, .{ .index = 1, .go_name = "logger" }, .{ .index = 2, .go_name = "userdata" } } }),
        api.function("emitChunks", .{ .params = &.{ .{ .index = 0, .go_name = "data" }, .{ .index = 1, .go_name = "chunkLen" }, .{ .index = 2, .go_name = "sink" }, .{ .index = 3, .go_name = "userdata" } } }),
        api.function("inspect", .{ .params = &.{ .{ .index = 0, .go_name = "context" }, .{ .index = 1, .go_name = "level" }, .{ .index = 2, .go_name = "strict" }, .{ .index = 3, .go_name = "inspector" }, .{ .index = 4, .go_name = "userdata" } } }),
        api.function("visitCodepoints", .{ .returns = .{ .semantic = .codepoint }, .params = &.{ .{ .index = 0, .go_name = "text" }, .{ .index = 1, .go_name = "visitor" }, .{ .index = 2, .go_name = "userdata" } } }),
    },
});
