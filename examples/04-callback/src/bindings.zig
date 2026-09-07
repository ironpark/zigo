const zigo = @import("zigo");
const library = @import("callback");

const api = zigo.scope(library);
const callback_context = api.in("CallbackContext");
const float_buffer = api.in("FloatBuffer");
const int_buffer = api.in("IntBuffer");

// The same explicit export list applies to both generic instantiations.
const buffer_members: zigo.Selector = .{ .names = &.{ "create", "push", "len", "deinit" } };

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.handle("CallbackContext", .{ .fields = &.{
            .{
                .path = "stats.runs",
                .name = "runCount",
                .set = true,
                .doc = "RunCount reports how many callbacks have run.",
            },
        } }).members(&.{
            callback_context.function("create", .{
                .params = &.{
                    zigo.param.callback(0, .{ .retention = .retained, .go_error = true }),
                },
            }),
            callback_context.function("run", .{}),
            callback_context.function("deinit", .{}),
        }),
        api.handle("FloatBuffer", .{}).members(float_buffer.functions(buffer_members)),
        api.handle("IntBuffer", .{}).members(int_buffer.functions(buffer_members)),
        api.callback("Observer", .{ .on_failure = .{ .result = 0 } }),
        api.callback("VoidObserver", .{}),
        api.callback("Predicate", .{}),
        api.callback("Reducer", .{ .userdata = .first }),
        api.callback("Visitor", .{ .params = &.{.{ .index = 0, .semantic = .codepoint }} }),
        api.callback("Logger", .{ .params = &.{.{ .index = 1, .semantic = .utf8_string }} }),
        api.callback("ByteSink", .{ .params = &.{.{ .index = 0, .semantic = .opaque_bytes }} }),
        api.callback("Inspector", .{}),
        api.function("panicNow", .{}),
        api.function("compressionBound", .{}),
        api.function("incrementShared", .{}),
        api.function("readShared", .{}),
        api.function("apply", .{ .params = &.{
            zigo.param.callback(1, .{ .go_error = true }),
        } }),
        api.function("applyUntilCancelled", .{
            .params = &.{
                zigo.param.callback(1, .{ .go_error = true }),
                zigo.param.cancel(3, null).named("cancel"),
            },
        }),
        api.function("notify", .{}),
        api.function("filter", .{}),
        // Keep a stable name for the explicit userdata link.
        api.function("reduce", .{
            .params = &.{
                .{ .index = 0, .go_name = "ctx" },
                zigo.param.callback(2, .{ .userdata = 0 }),
            },
        }),
        api.function("logMessage", .{}),
        api.function("emitChunks", .{ .params = &.{
            .{ .index = 1, .go_name = "chunkLen" },
        } }),
        api.function("inspect", .{}),
        api.function("visitCodepoints", .{ .returns = .{ .semantic = .codepoint } }),
    },
});
