const zigo = @import("zigo");
const library = @import("type_relations");

const api = zigo.scope(library);
const Counter = api.handle("Counter", .{}).context();
const Accumulator = api.handle("Accumulator", .{}).context();
const DeccolmMode = api.enumeration("DeccolmMode", .{}).context();
const text = api.in("text");

// Scopes keep source identity; Go adapters only change the public Go type.
pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        Counter.define(&.{
            Counter.function("create", .{}),
            Counter.function("get", .{}),
            Counter.function("add", .{}),
            Counter.function("deinit", .{}),
        }),
        Accumulator.define(&.{
            Accumulator.function("create", .{}),
            Accumulator.function("absorb", .{}),
            Accumulator.function("total", .{}),
            Accumulator.function("deinit", .{}),
        }),
        api.enumeration("CursorStyle", .{}),
        api.enumeration("CharsetSlot", .{}),
        DeccolmMode.define(&.{
            DeccolmMode.function("columns", .{}),
        }),
        api.enumeration("EraseDisplay", .{ .exhaustive = false }),
        api.value("Point", .{ .go = .{
            .type = "image.Point",
            .import = "image",
            .to_raw = "pointToRaw",
            .from_raw = "pointFromRaw",
        } }),
        api.function("liveObjects", .{
            .returns = .{ .go = .{ .type = "ObjectCount", .to_raw = "objectCountToRaw", .from_raw = "objectCountFromRaw" } },
        }),
        api.function("defaultCursorStyle", .{}),
        api.function("configureStyles", .{}),
        api.function("isWideColumns", .{}),
        api.function("echoEraseDisplay", .{}),
        text.function("runWidth", .{}),
        text.in("unicode").function("codepointWidth", .{}),
        api.function("doubleWidth", .{}),
        api.function("invert", .{}),
        api.function("styleOrDefault", .{}),
        api.function("blinkingStyle", .{}),
        api.function("shiftPoint", .{}),
        api.function("checkedShift", .{}),
        api.function("describeText", .{ .params = &.{
            .{ .index = 0, .semantic = .utf8_string },
        } }),
        api.function("sumOrZero", .{}),
        api.function("leadingDigits", .{}),
        api.function("styleName", .{ .returns = .{ .semantic = .utf8_string } }),
        api.function("cursorStyleBlinks", .{
            .name = "blinks",
            .role = .{ .method = api.typeRef("CursorStyle") },
        }),
    },
});
