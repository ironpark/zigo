const zigo = @import("zigo");
const library = @import("streams");
const satisfies = @import("zigo_satisfies");

const api = zigo.scope(library);

// Members inherit their Go receiver from the owning type. Parameter indices
// still refer to the original Zig signature, including that receiver.
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .c_allocator,
    .defaults = .{ .codepoints = .infer_u21 },
    .declarations = &.{
        api.handle("Document", .{}).use(satisfies.plugin, .{ .interfaces = &.{"io.ReadWriteCloser"} }).with(.{ .members = &.{
            api.in("Document").function("create", .{}),
            api.in("Document").function("deinit", .{}),
            api.in("Document").function("append", .{ .params = &.{.{ .index = 1, .go_name = "line" }} }).use(zigo.features.implements, .{ .kind = .writer }),
            api.in("Document").function("count", .{}),
            api.in("Document").function("dump", .{ .params = &.{.{ .index = 1, .go_name = "w" }} }).use(zigo.features.implements, .{ .kind = .writer_to }),
            api.in("Document").function("load", .{ .params = &.{.{ .index = 1, .go_name = "r", .contract = .{ .stream = .{ .buffer = 4096 } } }} }).use(zigo.features.implements, .{ .kind = .reader_from }),
            api.in("Document").function("readInto", .{
                .params = &.{.{ .index = 1, .go_name = "dst", .contract = .{ .buffer = .{ .output = .{ .written = .result } } } }},
            }).use(zigo.features.implements, .{ .kind = .reader }),
        } }),
        api.handle("Sink", .{}).with(.{ .members = &.{
            api.in("Sink").function("create", .{}),
            api.in("Sink").function("writer", .{}),
            api.in("Sink").function("count", .{}),
            api.in("Sink").function("deinit", .{}),
        } }),
        api.handle("Source", .{}).with(.{ .members = &.{
            api.in("Source").function("create", .{ .params = &.{.{ .index = 0, .go_name = "bytes" }} }),
            api.in("Source").function("reader", .{}),
            api.in("Source").function("deinit", .{}),
        } }),
        api.function("banner", .{ .params = &.{ .{ .index = 0, .go_name = "w" }, .{ .index = 1, .go_name = "width" } } }),
        api.function("tee", .{ .params = &.{ .{ .index = 0, .go_name = "r" }, .{ .index = 1, .go_name = "w" } } }),
        api.function("sumCodepoints", .{ .params = &.{.{ .index = 0, .go_name = "values" }} }),
        api.function("fillCodepoints", .{ .params = &.{.{ .index = 0, .go_name = "output", .contract = .{ .buffer = .{ .output = .{} } } }} }),
        api.function("takeCodepoints", .{ .returns = .{ .lifetime = .{ .owned = .{ .release = api.ref("freeCodepoints") } } } }),
        api.function("freeCodepoints", .{ .params = &.{.{ .index = 0, .go_name = "values" }} }),
    },
});
