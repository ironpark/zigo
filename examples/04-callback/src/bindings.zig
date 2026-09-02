const zigo = @import("zigo");
const library = @import("callback");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.CallbackContext, .repr = .@"opaque" },
        .{ .name = "FloatBuffer", .type = library.FloatBuffer, .repr = .@"opaque" },
        .{ .name = "IntBuffer", .type = library.IntBuffer, .repr = .@"opaque" },
        // One Go type for every parameter of this signature, named after the
        // Zig alias: the alias itself has no reflectable name.
        .{ .name = "Observer", .type = library.Observer, .repr = .callback },
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
        .{
            .path = "root.apply",
            .params = .{ "value", "callback", "userdata" },
            .param_meta = .{ .callback = .{ .go_error = true } },
        },
    },
});
