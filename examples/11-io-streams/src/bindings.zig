const zigo = @import("zigo");
const library = @import("streams");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.Document, .repr = .@"opaque" },
        .{ .type = library.Sink, .repr = .@"opaque" },
        .{ .type = library.Source, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .path = "Document.create" },
        .{ .path = "Document.deinit" },
        .{ .path = "Document.append", .params = .{"line"} },
        .{ .path = "Document.count" },
        // The default 64 KiB staging buffer: one Go `Write` per 64 KiB of
        // output however many times the Zig side calls `writeAll`.
        .{ .path = "Document.dump", .params = .{"w"} },
        // A deliberately small buffer, so the test can count the crossings a
        // known payload costs and see the size decide them.
        .{ .path = "Document.load", .params = .{"r"}, .param_meta = .{ .r = .{ .buffer = 4096 } } },
        .{ .path = "root.banner", .params = .{ "w", "width" } },
        .{ .path = "root.tee", .params = .{ "r", "w" } },
        // A method that hands a stream out. It generates `Write` and `Flush`
        // on the handle rather than a Go value standing for the pointer, so
        // `io.Copy(sink, src)` works and nothing outlives the call.
        .{ .path = "Sink.create" },
        .{ .path = "Sink.writer" },
        .{ .path = "Sink.count" },
        .{ .path = "Sink.deinit" },
        .{ .path = "Source.create", .params = .{"bytes"} },
        .{ .path = "Source.reader" },
        .{ .path = "Source.deinit" },
    },
});
