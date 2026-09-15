const zigo = @import("zigo");
const library = @import("streams");
const satisfies = @import("zigo_satisfies");

const api = zigo.scope(library);
const document = api.handle("Document", .{});
const Sink = api.handle("Sink", .{}).context();
const Source = api.handle("Source", .{}).context();

// A declared interface over the two handles that count bytes. The satisfies
// plugin takes it as a reference, not as a name it cannot check: the claim
// below is verified against the methods the generator writes for `Document`.
const Counter = zigo.interface(.{
    .name = "Counter",
    .methods = &.{"count"},
    .types = &.{ document.typeRef(), Sink.typeRef() },
    .doc = "Counter is anything that reports how many bytes it holds.",
});
const Document = document.use(satisfies.plugin, .{
    .interfaces = &.{"io.ReadWriteCloser"},
    .generated = &.{.{ .entry = Counter }},
}).context();

// Members infer their Go receiver from the owning type and Zig signature. Indices
// still refer to the original Zig signature, including that receiver.
pub const bindings = zigo.define(api, .{
    .allocator = .c_allocator,
    .defaults = .{ .codepoints = .infer_u21 },
    .declarations = &.{
        Document.members(&.{
            Document.func("create", .{}),
            Document.func("deinit", .{}),
            // One method, two interfaces: Write hands the bytes over, and
            // WriteString lends the string's own bytes to the same method.
            Document.func("append", .{}).use(zigo.features.implements, .{ .kinds = &.{ .writer, .string_writer } }),
            Document.func("appendString", .{
                .params = &.{.{ .index = 1, .semantic = .utf8_string }},
            }),
            Document.func("count", .{}),
            Document.func("dump", .{}).use(zigo.features.implements, .{ .kinds = &.{.writer_to} }),
            Document.func("load", .{ .params = &.{
                zigo.param.stream(1, 4096),
            } }).use(zigo.features.implements, .{ .kinds = &.{.reader_from} }),
            Document.func("readInto", .{
                .params = &.{
                    zigo.param.output(1, .result),
                },
            }).use(zigo.features.implements, .{ .kinds = &.{.reader} }),
        }),
        Sink.members(&.{
            Sink.func("create", .{}),
            Sink.func("writer", .{}),
            Sink.func("count", .{}),
            Sink.func("deinit", .{}),
            // Opaque bytes, so the Go method takes `[]byte`; `.string_writer`
            // adds the `WriteString` that lends a string's bytes instead of
            // copying them.
            Sink.func("push", .{}).use(zigo.features.implements, .{ .kinds = &.{.string_writer} }),
        }),
        Source.select(.{ .names = &.{ "create", "reader", "deinit" } }),
        api.func("banner", .{}),
        api.func("tee", .{}),
        api.func("sumCodepoints", .{}),
        // Full schema spelling: omitting written means the entire output is filled.
        api.func("fillCodepoints", .{
            .params = &.{
                zigo.param.output(0, .all),
            },
        }),
        api.func("takeCodepoints", .{ .returns = zigo.result.releasedBy(api.ref("freeCodepoints")) }),
        api.func("freeCodepoints", .{}),
        Counter,
    },
});
