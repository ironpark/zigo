const zigo = @import("zigo");
const library = @import("streams");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.Document, .repr = .@"opaque" },
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
    },
});
