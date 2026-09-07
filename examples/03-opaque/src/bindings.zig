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
            context.function("create", .{}),
            context.function("add", .{}),
            context.function("maybeTotal", .{}),
            context.function("setTotal", .{}),
            context.function("next", .{}).use(zigo.features.iterator, .{}),
            context.function("nextChecked", .{}).use(zigo.features.iterator, .{ .name = "Checked" }),
            context.function("rewind", .{}),
            context.function("addCopy", .{}),
            context.function("borrowView", .{ .returns = zigo.result.borrowed() }),
            context.function("crash", .{}),
            context.function("crashInfallible", .{}),
            context.function("deinit", .{}),
        }),
        api.handle("ContextView", .{}).members(&.{
            context_view.function("total", .{}),
        }),
        api.function("crashFatal", .{}),
        api.function("liveBytes", .{}),
        api.function("sumCopies", .{}),
        api.function("echo", .{
            .returns = .{ .semantic = .utf8_string },
            .params = &.{
                .{ .index = 0, .semantic = .utf8_string },
            },
        }),
        api.function("fallback", .{}),
    },
});
