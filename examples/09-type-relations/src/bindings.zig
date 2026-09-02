const zigo = @import("zigo");
const library = @import("type_relations");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.Counter, .repr = .@"opaque" },
        .{ .type = library.Accumulator, .repr = .@"opaque" },
        // The enum has no name of its own: `@typeName` ends in the slice
        // expression that built it. `.name` is what Go and C get called.
        .{ .name = "CursorStyle", .type = library.CursorStyle, .repr = .enumeration },
    },
    .functions = .{
        .{ .path = "Counter.create", .params = .{"initial"} },
        .{ .path = "Counter.get" },
        .{ .path = "Counter.add", .params = .{"delta"} },
        .{ .path = "Counter.deinit" },
        .{ .path = "Accumulator.create" },
        .{ .path = "Accumulator.absorb", .params = .{"counter"} },
        .{ .path = "Accumulator.total" },
        .{ .path = "Accumulator.deinit" },
        .{ .path = "root.liveObjects" },
        .{ .path = "root.defaultCursorStyle" },
        .{ .path = "root.cursorStyleBlinks", .params = .{"style"} },
        .{ .path = "root.text.runWidth", .params = .{ "first", "second" } },
        .{ .path = "root.text.unicode.codepointWidth", .params = .{"cp"} },
    },
});
