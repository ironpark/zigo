const zigo = @import("zigo");
const library = @import("opaque");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.Context, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .path = "Context.create" },
        .{ .path = "Context.add", .params = .{"value"} },
        .{ .path = "Context.crash" },
        .{ .path = "Context.deinit" },
        .{ .path = "root.liveBytes" },
        .{
            .path = "root.echo",
            .params = .{"text"},
            .param_meta = .{ .text = .{ .semantic = .utf8_string } },
            .semantic = .utf8_string,
        },
        .{ .path = "root.fallback" },
    },
});
