//! Handles that live in Zig and travel through Go as opaque pointers.
//! This block sits in the bindings file, which zigo reads before the library's
//! root module: it is the one file the binding's author owns.
const zigo = @import("zigo");
const library = @import("opaque");

const api = zigo.scope(library);
const context = api.in("Context");
const context_view = api.in("ContextView");

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.handle("Context", .{}).members(&.{
            context.func("create", .{}),
            context.func("add", .{}),
            context.func("maybeTotal", .{}),
            context.func("setTotal", .{}),
            context.func("next", .{}).use(zigo.features.iterator, .{}),
            context.func("nextChecked", .{}).use(zigo.features.iterator, .{ .name = "Checked" }),
            context.func("rewind", .{}),
            context.func("addCopy", .{}),
            context.func("borrowView", .{ .returns = zigo.result.borrowed() }),
            context.func("crash", .{}),
            context.func("crashInfallible", .{}),
            context.func("deinit", .{}),
        }),
        api.handle("ContextView", .{}).members(&.{
            context_view.func("total", .{}),
        }),
        api.func("crashFatal", .{}),
        api.func("liveBytes", .{}),
        api.func("sumCopies", .{}),
        api.func("echo", .{
            .returns = .{ .semantic = .utf8_string },
            .params = &.{
                .{ .index = 0, .semantic = .utf8_string },
            },
        }),
        api.func("fallback", .{}),
    },
});
