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
        .{ .name = "CharsetSlot", .type = library.CharsetSlot, .repr = .enumeration },
        .{ .name = "DeccolmMode", .type = library.DeccolmMode, .repr = .enumeration },
        .{ .name = "EraseDisplay", .type = library.EraseDisplay, .repr = .enumeration, .exhaustive = false },
        .{ .type = library.Point, .repr = .value },
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
        .{ .path = "root.configureStyles", .params = .{ "slot", "style" } },
        .{ .path = "root.isWideColumns", .params = .{"mode"} },
        .{ .path = "root.echoEraseDisplay", .params = .{"value"} },
        .{ .path = "root.text.runWidth", .params = .{ "first", "second" } },
        .{ .path = "root.text.unicode.codepointWidth", .params = .{"cp"} },
        .{ .path = "root.doubleWidth", .params = .{"value"} },
        .{ .path = "root.invert", .params = .{"value"} },
        .{ .path = "root.styleOrDefault", .params = .{"style"} },
        .{ .path = "root.blinkingStyle", .params = .{"style"} },
        .{ .path = "root.shiftPoint", .params = .{ "origin", "delta" } },
        .{ .path = "root.checkedShift", .params = .{ "origin", "delta" } },
        .{
            .path = "root.describeText",
            .params = .{"label"},
            .param_meta = .{ .label = .{ .semantic = .utf8_string } },
        },
        .{ .path = "root.sumOrZero", .params = .{"values"} },
        .{ .path = "root.leadingDigits", .params = .{"count"} },
        .{ .path = "root.styleName", .params = .{"style"}, .semantic = .utf8_string },
    },
});
