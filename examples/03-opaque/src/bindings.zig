//! Handles that live in Zig and travel through Go as opaque pointers.
//! This block sits in the bindings file, which zigo reads before the library's
//! root module: it is the one file the binding's author owns.
const zigo = @import("zigo");
const library = @import("opaque");

const api = zigo.scope(library);
const Context = api.handle("Context", .{}).context();
const ContextView = api.handle("ContextView", .{}).context();

pub const bindings = zigo.define(api, .{
    .declarations = &.{
        Context.members(&.{
            Context.func("create", .{}),
            Context.func("add", .{}),
            Context.func("maybeTotal", .{}),
            Context.func("setTotal", .{}),
            Context.func("next", .{}).use(zigo.features.iterator, .{}),
            Context.func("nextChecked", .{}).use(zigo.features.iterator, .{}),
            Context.func("rewind", .{}),
            Context.func("addCopy", .{}),
            Context.func("borrowView", .{ .returns = zigo.result.borrowed() }),
            Context.func("crash", .{}),
            Context.func("crashInfallible", .{}),
            Context.func("deinit", .{}),
        }),
        ContextView.members(&.{
            ContextView.func("total", .{}),
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
