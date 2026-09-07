const zigo = @import("zigo");
const library = @import("type_relations");

const api = zigo.scope(library);
const Counter = api.handle("Counter", .{}).context();
const Accumulator = api.handle("Accumulator", .{}).context();
const DeccolmMode = api.enumType("DeccolmMode", .{}).context();
const text = api.in("text");

// Scopes keep source identity; Go adapters only change the public Go type.
pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        Counter.define(&.{
            Counter.func("create", .{}),
            Counter.func("get", .{}),
            Counter.func("add", .{}),
            Counter.func("deinit", .{}),
        }),
        Accumulator.define(&.{
            Accumulator.func("create", .{}),
            Accumulator.func("absorb", .{}),
            Accumulator.func("total", .{}),
            Accumulator.func("deinit", .{}),
        }),
        api.enumType("CursorStyle", .{}),
        api.enumType("CharsetSlot", .{}),
        DeccolmMode.define(&.{
            DeccolmMode.func("columns", .{}),
        }),
        api.enumType("EraseDisplay", .{ .exhaustive = false }),
        api.val("Point", .{ .go = .{
            .type = "image.Point",
            .import = "image",
            .to_raw = "pointToRaw",
            .from_raw = "pointFromRaw",
        } }),
        api.func("liveObjects", .{
            .returns = .{ .go = .{ .type = "ObjectCount", .to_raw = "objectCountToRaw", .from_raw = "objectCountFromRaw" } },
        }),
        api.func("defaultCursorStyle", .{}),
        api.func("configureStyles", .{}),
        api.func("isWideColumns", .{}),
        api.func("echoEraseDisplay", .{}),
        text.func("runWidth", .{}),
        text.in("unicode").func("codepointWidth", .{}),
        api.func("doubleWidth", .{}),
        api.func("invert", .{}),
        api.func("styleOrDefault", .{}),
        api.func("blinkingStyle", .{}),
        api.func("shiftPoint", .{}),
        api.func("checkedShift", .{}),
        api.func("describeText", .{ .params = &.{
            .{ .index = 0, .semantic = .utf8_string },
        } }),
        api.func("sumOrZero", .{}),
        api.func("leadingDigits", .{}),
        api.func("styleName", .{ .returns = .{ .semantic = .utf8_string } }),
        api.func("cursorStyleBlinks", .{
            .name = "blinks",
            .role = .{ .method = api.typeRef("CursorStyle") },
        }),
    },
});
