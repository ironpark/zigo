const zigo = @import("zigo");
const library = @import("callback");

pub const bindings = zigo.define(.{
    .root = library,
    .types = &.{
        .{
            .handle = .{
                .type = library.CallbackContext,
                .fields = &.{
                    .{ .path = "stats.runs", .name = "runCount", .set = true, .doc = "RunCount reports how many callbacks have run." },
                },
            },
        },
        .{ .handle = .{ .name = "FloatBuffer", .type = library.FloatBuffer } },
        .{ .handle = .{ .name = "IntBuffer", .type = library.IntBuffer } },
        // One Go type for every parameter of this signature, named after the
        // Zig alias: the alias itself has no reflectable name.
        .{ .callback = .{ .name = "Observer", .type = library.Observer, .on_callback_failure = .{ .result = 0 } } },
        .{ .callback = .{ .name = "VoidObserver", .type = library.VoidObserver } },
        // `bool` in a callback signature becomes Go `bool` on both backends.
        .{ .callback = .{ .name = "Predicate", .type = library.Predicate } },
        // The native signature puts the context first; `.userdata` says so and
        // the generated shim reorders the arguments for the Go dispatcher.
        .{ .callback = .{ .name = "Reducer", .type = library.Reducer, .userdata = .first } },
        // The visitor's `u32` parameter is a codepoint, so the Go type is
        // `func(rune)`. Hints are positional over the value parameters; the
        // trailing userdata is not listed.
        .{ .callback = .{ .name = "Visitor", .type = library.Visitor, .params = &.{.{ .semantic = .codepoint }} } },
        // A `[*:0]const u8` string and a `[*]const u8` + `usize` pair are one
        // Go `string` each: the pair's hint says the bytes are text.
        .{ .callback = .{ .name = "Logger", .type = library.Logger, .params = &.{ .{}, .{ .semantic = .utf8_string } } } },
        // The same pair marked `.opaque_bytes` is a `[]byte`.
        .{ .callback = .{ .name = "ByteSink", .type = library.ByteSink, .params = &.{.{ .semantic = .opaque_bytes }} } },
    },
    .functions = &.{
        .{ .path = "FloatBuffer.create" },
        .{ .path = "FloatBuffer.push" },
        .{ .path = "FloatBuffer.len" },
        .{ .path = "FloatBuffer.deinit" },
        .{ .path = "IntBuffer.create" },
        .{ .path = "IntBuffer.push" },
        .{ .path = "IntBuffer.len" },
        .{ .path = "IntBuffer.deinit" },
        .{
            .path = "CallbackContext.create",
            .params = &.{ .{ .name = "callback", .retention = .retained, .go_error = true }, .{ .name = "userdata" } },
        },
        .{ .path = "CallbackContext.run" },
        .{ .path = "CallbackContext.deinit" },
        .{ .path = "root.panicNow" },
        .{ .path = "root.compressionBound" },
        .{ .path = "root.incrementShared", .params = &.{ .{ .name = "counter" }, .{ .name = "delta" } } },
        .{ .path = "root.readShared", .params = &.{.{ .name = "value" }} },
        .{
            .path = "root.apply",
            .params = &.{ .{ .name = "value" }, .{ .name = "callback", .go_error = true }, .{ .name = "userdata" } },
        },
        .{
            .path = "root.applyUntilCancelled",
            .params = &.{ .{ .name = "limit" }, .{ .name = "callback", .go_error = true }, .{ .name = "userdata" }, .{ .name = "cancel" } },
            .cancel = .{ .param = "cancel" },
        },
        .{
            .path = "root.notify",
            .params = &.{ .{ .name = "value" }, .{ .name = "callback" }, .{ .name = "userdata" } },
        },
        .{
            .path = "root.filter",
            .params = &.{ .{ .name = "value" }, .{ .name = "strict" }, .{ .name = "predicate" }, .{ .name = "userdata" } },
        },
        .{
            .path = "root.reduce",
            .params = &.{ .{ .name = "ctx" }, .{ .name = "values" }, .{ .name = "reducer", .userdata = .{ .param = "ctx" } } },
        },
        .{
            .path = "root.logMessage",
            .params = &.{ .{ .name = "message" }, .{ .name = "logger" }, .{ .name = "userdata" } },
        },
        .{
            .path = "root.emitChunks",
            .params = &.{ .{ .name = "data" }, .{ .name = "chunkLen" }, .{ .name = "sink" }, .{ .name = "userdata" } },
        },
        .{
            .path = "root.visitCodepoints",
            .params = &.{ .{ .name = "text" }, .{ .name = "visitor" }, .{ .name = "userdata" } },
            .returns = .{ .semantic = .codepoint },
        },
    },
});
