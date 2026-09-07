//! Handles that live in Zig and travel through Go as opaque pointers.
//! This block sits in the bindings file, which zigo reads before the library's
//! root module: it is the one file the binding's author owns.
const zigo = @import("zigo");
const library = @import("opaque");

const api = zigo.scope(library);

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.handle("Context", .{}),
        api.handle("ContextView", .{}),
        api.in("Context").function("create", .{}),
        api.in("Context").function("add", .{ .params = &.{.{ .index = 1, .go_name = "value" }} }),
        api.in("Context").function("maybeTotal", .{ .params = &.{.{ .index = 1, .go_name = "present" }} }),
        api.in("Context").function("setTotal", .{ .params = &.{.{ .index = 1, .go_name = "c" }} }),
        api.in("Context").function("next", .{}).use(zigo.features.iterator, .{}),
        api.in("Context").function("nextChecked", .{}).use(zigo.features.iterator, .{ .name = "Checked" }),
        api.in("Context").function("rewind", .{}),
        api.in("Context").function("addCopy", .{ .params = &.{.{ .index = 1, .go_name = "value" }} }),
        api.in("Context").function("borrowView", .{ .returns = .{ .lifetime = .{ .borrowed = .receiver } } }),
        api.in("ContextView").function("total", .{}),
        api.in("Context").function("crash", .{}),
        api.in("Context").function("crashInfallible", .{}),
        api.in("Context").function("deinit", .{}),
        api.function("crashFatal", .{}),
        api.function("liveBytes", .{}),
        api.function("sumCopies", .{ .params = &.{
            .{ .index = 0, .go_name = "bias" }, .{ .index = 1, .go_name = "left" }, .{ .index = 2, .go_name = "right" },
        } }),
        api.function("echo", .{
            .returns = .{ .semantic = .utf8_string },
            .params = &.{.{ .index = 0, .go_name = "text", .semantic = .utf8_string }},
        }),
        api.function("fallback", .{}),
    },
});
