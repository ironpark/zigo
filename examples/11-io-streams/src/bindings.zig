const zigo = @import("zigo");
const library = @import("streams");

pub const bindings = zigo.define(.{
    .allocator = .c_allocator,
    .root = library,
    // Every `u21` in this library is a codepoint, so the binding says so once
    // instead of at each site.
    .codepoints = .infer_u21,
    .types = &.{
        .{ .handle = .{ .type = library.Document } },
        .{ .handle = .{ .type = library.Sink } },
        .{ .handle = .{ .type = library.Source } },
    },
    .functions = &.{
        .{ .path = "Document.create" },
        .{ .path = "Document.deinit" },
        // `.implements` adds the method a Go standard interface needs next
        // to the bound one: `Write` calls `Append`, so `fmt.Fprintf(doc, ...)`
        // and `io.Copy(doc, r)` work, and `Append` is still there.
        .{ .path = "Document.append", .params = &.{.{ .name = "line" }}, .implements = .writer },
        .{ .path = "Document.count" },
        // The default 64 KiB staging buffer batches small writes. Explicit
        // flushes and the writer's behavior also affect the call count.
        // `WriteTo` calls `Dump` through a counting writer, since `dump`
        // returns no count of its own.
        .{ .path = "Document.dump", .params = &.{.{ .name = "w" }}, .implements = .writer_to },
        // A deliberately small buffer, so the test can count the crossings a
        // known payload costs and see the size decide them. `load` reports
        // its own count, so `ReadFrom` passes it on.
        .{ .path = "Document.load", .params = &.{.{ .name = "r", .buffer = 4096 }}, .implements = .reader_from },
        // An out buffer whose count is the result is the `io.Reader` shape;
        // `Read` reports io.EOF when a call fills nothing.
        .{
            .path = "Document.readInto",
            .params = &.{.{ .name = "dst", .direction = .out, .written = .result }},
            .implements = .reader,
        },
        .{ .path = "root.banner", .params = &.{ .{ .name = "w" }, .{ .name = "width" } } },
        .{ .path = "root.tee", .params = &.{ .{ .name = "r" }, .{ .name = "w" } } },
        // Inferred codepoints: these `[]u21` are Go `[]rune` over the same
        // memory the raw `[]uint32` uses, and inputs are checked against the
        // Unicode range.
        .{ .path = "root.sumCodepoints", .params = &.{.{ .name = "values" }} },
        .{
            .path = "root.fillCodepoints",
            .params = &.{.{ .name = "output", .direction = .out }},
        },
        .{ .path = "root.takeCodepoints", .returns = .{ .ownership = .caller, .release = "root.freeCodepoints" } },
        .{ .path = "root.freeCodepoints", .params = &.{.{ .name = "values" }} },
        // A method that hands a stream out. It generates `Write` and `Flush`
        // on the handle rather than a Go value standing for the pointer, so
        // `io.Copy(sink, src)` works and nothing outlives the call.
        .{ .path = "Sink.create" },
        .{ .path = "Sink.writer" },
        .{ .path = "Sink.count" },
        .{ .path = "Sink.deinit" },
        .{ .path = "Source.create", .params = &.{.{ .name = "bytes" }} },
        .{ .path = "Source.reader" },
        .{ .path = "Source.deinit" },
    },
});
