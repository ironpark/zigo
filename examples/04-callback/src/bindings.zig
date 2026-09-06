const zigo = @import("zigo");
const library = @import("callback");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.CallbackContext, .repr = .@"opaque", .fields = .{
            .{ .path = "stats.runs", .name = "runCount", .set = true, .doc = "RunCount reports how many callbacks have run." },
        } },
        .{ .name = "FloatBuffer", .type = library.FloatBuffer, .repr = .@"opaque" },
        .{ .name = "IntBuffer", .type = library.IntBuffer, .repr = .@"opaque" },
        // One Go type for every parameter of this signature, named after the
        // Zig alias: the alias itself has no reflectable name.
        .{ .name = "Observer", .type = library.Observer, .repr = .callback, .on_callback_failure = .{ .result = 0 } },
        .{ .name = "VoidObserver", .type = library.VoidObserver, .repr = .callback },
        // `bool` in a callback signature becomes Go `bool` on both backends.
        .{ .name = "Predicate", .type = library.Predicate, .repr = .callback },
        // The native signature puts the context first; `.userdata` says so and
        // the generated shim reorders the arguments for the Go dispatcher.
        .{ .name = "Reducer", .type = library.Reducer, .repr = .callback, .userdata = .first },
        // The visitor's `u32` parameter is a codepoint, so the Go type is
        // `func(rune)`. Hints are positional over the value parameters; the
        // trailing userdata is not listed.
        .{ .name = "Visitor", .type = library.Visitor, .repr = .callback, .param_semantics = .{.codepoint} },
    },
    .functions = .{
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
            .params = .{ "callback", "userdata" },
            // The Go callback may return an `error`. `go_error` belongs to the
            // signature rather than to one parameter, so `apply` below spells
            // it too: one Go `Observer` type is shared by both.
            .param_meta = .{ .callback = .{ .retention = .retained, .go_error = true } },
        },
        .{ .path = "CallbackContext.run" },
        .{ .path = "CallbackContext.deinit" },
        .{ .path = "root.panicNow" },
        .{ .path = "root.compressionBound" },
        .{ .path = "root.incrementShared", .params = .{ "counter", "delta" } },
        .{ .path = "root.readShared", .params = .{"value"} },
        .{
            .path = "root.apply",
            .params = .{ "value", "callback", "userdata" },
            .param_meta = .{ .callback = .{ .go_error = true } },
        },
        .{
            .path = "root.applyUntilCancelled",
            .params = .{ "limit", "callback", "userdata", "cancel" },
            .param_meta = .{ .callback = .{ .go_error = true } },
            .cancel = .{ .param = "cancel" },
        },
        .{
            .path = "root.notify",
            .params = .{ "value", "callback", "userdata" },
        },
        .{
            .path = "root.filter",
            .params = .{ "value", "strict", "predicate", "userdata" },
        },
        .{
            .path = "root.reduce",
            .params = .{ "ctx", "values", "reducer" },
            // The token parameter is not next to the callback, so it is named.
            .param_meta = .{ .reducer = .{ .userdata = "ctx" } },
        },
        .{
            .path = "root.visitCodepoints",
            .params = .{ "text", "visitor", "userdata" },
            .semantic = .codepoint,
        },
    },
});
