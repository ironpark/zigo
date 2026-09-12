const zigo = @import("zigo");
const library = @import("streams");
const satisfies = @import("zigo_satisfies");

const api = zigo.scope(library);
const Document = api.handle("Document", .{}).use(satisfies.plugin, .{
    .interfaces = &.{"io.ReadWriteCloser"},
}).context();
const Sink = api.handle("Sink", .{}).context();
const Source = api.handle("Source", .{}).context();

// Members infer their Go receiver from the owning type and Zig signature. Indices
// still refer to the original Zig signature, including that receiver.
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .c_allocator,
    .defaults = .{ .codepoints = .infer_u21 },
    .declarations = &.{
        Document.define(&.{
            Document.func("create", .{}),
            Document.func("deinit", .{}),
            Document.func("append", .{}).use(zigo.features.implements, .{ .kind = .writer }),
            Document.func("appendString", .{
                .params = &.{.{ .index = 1, .semantic = .utf8_string }},
            }).use(zigo.features.implements, .{ .kind = .string_writer }),
            Document.func("count", .{}),
            Document.func("dump", .{}).use(zigo.features.implements, .{ .kind = .writer_to }),
            Document.func("load", .{ .params = &.{
                zigo.param.stream(1, 4096),
            } }).use(zigo.features.implements, .{ .kind = .reader_from }),
            Document.func("readInto", .{
                .params = &.{
                    zigo.param.output(1, .result),
                },
            }).use(zigo.features.implements, .{ .kind = .reader }),
        }),
        Sink.define(&.{
            Sink.func("create", .{}),
            Sink.func("writer", .{}),
            Sink.func("count", .{}),
            Sink.func("deinit", .{}),
            // Opaque bytes, so the Go method takes `[]byte`; `.string_writer`
            // adds the `WriteString` that lends a string's bytes instead of
            // copying them.
            Sink.func("push", .{}).use(zigo.features.implements, .{ .kind = .string_writer }),
        }),
        Source.select(.{ .names = &.{ "create", "reader", "deinit" } }),
        api.func("banner", .{}),
        api.func("tee", .{}),
        api.func("sumCodepoints", .{}),
        // Full schema spelling: omitting written means the entire output is filled.
        api.func("fillCodepoints", .{
            .params = &.{
                .{ .index = 0, .contract = .{ .buffer = .{ .output = .{} } } },
            },
        }),
        api.func("takeCodepoints", .{ .returns = zigo.result.releasedBy(api.ref("freeCodepoints")) }),
        api.func("freeCodepoints", .{}),
    },
});
