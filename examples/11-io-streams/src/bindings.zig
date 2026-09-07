const zigo = @import("zigo");
const library = @import("streams");
const satisfies = @import("zigo_satisfies");

const api = zigo.scope(library);
const document = api.in("Document");
const sink = api.in("Sink");
const source = api.in("Source");

// Members infer their Go receiver from the owning type and Zig signature. Indices
// still refer to the original Zig signature, including that receiver.
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .c_allocator,
    .defaults = .{ .codepoints = .infer_u21 },
    .declarations = &.{
        api.handle("Document", .{}).use(satisfies.plugin, .{ .interfaces = &.{"io.ReadWriteCloser"} }).members(&.{
            document.function("create", .{}),
            document.function("deinit", .{}),
            document.function("append", .{}).use(zigo.features.implements, .{ .kind = .writer }),
            document.function("count", .{}),
            document.function("dump", .{}).use(zigo.features.implements, .{ .kind = .writer_to }),
            document.function("load", .{ .params = &.{
                zigo.param.stream(1, 4096),
            } }).use(zigo.features.implements, .{ .kind = .reader_from }),
            document.function("readInto", .{
                .params = &.{
                    zigo.param.output(1, .result),
                },
            }).use(zigo.features.implements, .{ .kind = .reader }),
        }),
        api.handle("Sink", .{}).members(&.{
            sink.function("create", .{}),
            sink.function("writer", .{}),
            sink.function("count", .{}),
            sink.function("deinit", .{}),
        }),
        api.handle("Source", .{}).members(&.{
            source.function("create", .{}),
            source.function("reader", .{}),
            source.function("deinit", .{}),
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
