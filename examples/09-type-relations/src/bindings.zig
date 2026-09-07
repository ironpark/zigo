const zigo = @import("zigo");
const library = @import("type_relations");

pub const bindings = zigo.define(.{
    .root = library,
    .types = &.{
        .{ .handle = .{ .type = library.Counter } },
        .{ .handle = .{ .type = library.Accumulator } },
        // The enum has no name of its own: `@typeName` ends in the slice
        // expression that built it. `.name` is what Go and C get called.
        .{ .enumeration = .{ .name = "CursorStyle", .type = library.CursorStyle } },
        .{ .enumeration = .{ .name = "CharsetSlot", .type = library.CharsetSlot } },
        .{ .enumeration = .{ .name = "DeccolmMode", .type = library.DeccolmMode } },
        .{ .enumeration = .{ .name = "EraseDisplay", .type = library.EraseDisplay, .exhaustive = false } },
        // `.go` maps the extern struct onto a Go type the caller already
        // uses; the two conversions live in point_adapter.go beside the
        // generated files.
        .{
            .value = .{
                .type = library.Point,
                .go = .{
                    .type = "image.Point",
                    .import = "image",
                    .to_raw = "pointToRaw",
                    .from_raw = "pointFromRaw",
                },
            },
        },
    },
    .functions = &.{
        .{ .path = "Counter.create", .params = &.{.{ .name = "initial" }} },
        .{ .path = "Counter.get" },
        .{ .path = "Counter.add", .params = &.{.{ .name = "delta" }} },
        .{ .path = "Counter.deinit" },
        .{ .path = "Accumulator.create" },
        .{ .path = "Accumulator.absorb", .params = &.{.{ .name = "counter" }} },
        .{ .path = "Accumulator.total" },
        .{ .path = "Accumulator.deinit" },
        // A per-function `.go` adapts a scalar result: Go sees ObjectCount,
        // a type defined beside the generated files, instead of uint.
        .{ .path = "root.liveObjects", .returns = .{ .go = .{ .type = "ObjectCount", .to_raw = "objectCountToRaw", .from_raw = "objectCountFromRaw" } } },
        .{ .path = "root.defaultCursorStyle" },
        // A registered enum owns its methods. `DeccolmMode.columns` is a Zig
        // method and binds as one; `cursorStyleBlinks` is a free function the
        // group attaches to `CursorStyle`, dropping the shared prefix. Both
        // become Go methods on the enum, with the enum value as the receiver.
        .{ .path = "DeccolmMode.columns" },
        .{ .path = "root.configureStyles", .params = &.{ .{ .name = "slot" }, .{ .name = "style" } } },
        .{ .path = "root.isWideColumns", .params = &.{.{ .name = "mode" }} },
        .{ .path = "root.echoEraseDisplay", .params = &.{.{ .name = "value" }} },
        .{ .path = "root.text.runWidth", .params = &.{ .{ .name = "first" }, .{ .name = "second" } } },
        .{ .path = "root.text.unicode.codepointWidth", .params = &.{.{ .name = "cp" }} },
        .{ .path = "root.doubleWidth", .params = &.{.{ .name = "value" }} },
        .{ .path = "root.invert", .params = &.{.{ .name = "value" }} },
        .{ .path = "root.styleOrDefault", .params = &.{.{ .name = "style" }} },
        .{ .path = "root.blinkingStyle", .params = &.{.{ .name = "style" }} },
        .{ .path = "root.shiftPoint", .params = &.{ .{ .name = "origin" }, .{ .name = "delta" } } },
        .{ .path = "root.checkedShift", .params = &.{ .{ .name = "origin" }, .{ .name = "delta" } } },
        .{
            .path = "root.describeText",
            .params = &.{.{ .name = "label", .semantic = .utf8_string }},
        },
        .{ .path = "root.sumOrZero", .params = &.{.{ .name = "values" }} },
        .{ .path = "root.leadingDigits", .params = &.{.{ .name = "count" }} },
        .{ .path = "root.styleName", .params = &.{.{ .name = "style" }}, .returns = .{ .semantic = .utf8_string } },
    },
    .methods = &.{
        .{
            .receiver = library.CursorStyle,
            .strip_prefix = "cursorStyle",
            .functions = &.{.{ .path = "root.cursorStyleBlinks" }},
        },
    },
});
