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
        // `.go` maps the extern struct onto a Go type the caller already
        // uses; the two conversions live in point_adapter.go beside the
        // generated files.
        .{ .type = library.Point, .repr = .value, .go = .{
            .type = "image.Point",
            .import = "image",
            .to_raw = "pointToRaw",
            .from_raw = "pointFromRaw",
        } },
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
        // A per-function `.go` adapts a scalar result: Go sees ObjectCount,
        // a type defined beside the generated files, instead of uint.
        .{ .path = "root.liveObjects", .go = .{ .type = "ObjectCount", .to_raw = "objectCountToRaw", .from_raw = "objectCountFromRaw" } },
        .{ .path = "root.defaultCursorStyle" },
        // A registered enum owns its methods. `DeccolmMode.columns` is a Zig
        // method and binds as one; `cursorStyleBlinks` is a free function the
        // group attaches to `CursorStyle`, dropping the shared prefix. Both
        // become Go methods on the enum, with the enum value as the receiver.
        .{ .path = "DeccolmMode.columns" },
        .{
            .receiver = "CursorStyle",
            .strip_prefix = "cursorStyle",
            .functions = .{"root.cursorStyleBlinks"},
        },
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
