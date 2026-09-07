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
            Document.function("create", .{}),
            Document.function("deinit", .{}),
            Document.function("append", .{}).use(zigo.features.implements, .{ .kind = .writer }),
            Document.function("count", .{}),
            Document.function("dump", .{}).use(zigo.features.implements, .{ .kind = .writer_to }),
            Document.function("load", .{ .params = &.{
                zigo.param.stream(1, 4096),
            } }).use(zigo.features.implements, .{ .kind = .reader_from }),
            Document.function("readInto", .{
                .params = &.{
                    zigo.param.output(1, .result),
                },
            }).use(zigo.features.implements, .{ .kind = .reader }),
        }),
        Sink.define(&.{
            Sink.function("create", .{}),
            Sink.function("writer", .{}),
            Sink.function("count", .{}),
            Sink.function("deinit", .{}),
        }),
        Source.define(&.{
            Source.function("create", .{}),
            Source.function("reader", .{}),
            Source.function("deinit", .{}),
        }),
        api.function("banner", .{}),
        api.function("tee", .{}),
        api.function("sumCodepoints", .{}),
        // Full schema spelling: omitting written means the entire output is filled.
        api.function("fillCodepoints", .{
            .params = &.{
                .{ .index = 0, .contract = .{ .buffer = .{ .output = .{} } } },
            },
        }),
        api.function("takeCodepoints", .{ .returns = zigo.result.releasedBy(api.ref("freeCodepoints")) }),
        api.function("freeCodepoints", .{}),
    },
});
