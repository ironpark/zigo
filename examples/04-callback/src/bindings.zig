const zigo = @import("zigo");
const library = @import("callback");

pub const bindings = zigo.define(.{
    .specializations = .{
        .{ .name = "FloatBuffer", .type = library.FloatBuffer },
        .{ .name = "IntBuffer", .type = library.IntBuffer },
    },
    .types = .{
        .{ .type = library.CallbackContext, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .name = "create", .@"fn" = library.FloatBuffer.create },
        .{ .name = "push", .@"fn" = library.FloatBuffer.push },
        .{ .name = "len", .@"fn" = library.FloatBuffer.len },
        .{ .name = "deinit", .@"fn" = library.FloatBuffer.deinit },
        .{ .name = "create", .@"fn" = library.IntBuffer.create },
        .{ .name = "push", .@"fn" = library.IntBuffer.push },
        .{ .name = "len", .@"fn" = library.IntBuffer.len },
        .{ .name = "deinit", .@"fn" = library.IntBuffer.deinit },
        .{
            .name = "create",
            .@"fn" = library.CallbackContext.create,
            .params = .{ "callback", "userdata" },
            .param_meta = .{ .callback = .{ .retention = .retained } },
        },
        .{ .name = "run", .@"fn" = library.CallbackContext.run },
        .{ .name = "deinit", .@"fn" = library.CallbackContext.deinit },
    },
});
