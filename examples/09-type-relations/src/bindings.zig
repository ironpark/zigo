const zigo = @import("zigo");
const library = @import("type_relations");

const api = zigo.scope(library);
const counter = api.in("Counter");
const accumulator = api.in("Accumulator");
const deccolm_mode = api.in("DeccolmMode");
const text = api.in("text");

// Scopes keep source identity; Go adapters only change the public Go type.
pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.handle("Counter", .{}).members(&.{
            counter.function("create", .{}),
            counter.function("get", .{}),
            counter.function("add", .{}),
            counter.function("deinit", .{}),
        }),
        api.handle("Accumulator", .{}).members(&.{
            accumulator.function("create", .{}),
            accumulator.function("absorb", .{}),
            accumulator.function("total", .{}),
            accumulator.function("deinit", .{}),
        }),
        api.enumeration("CursorStyle", .{}),
        api.enumeration("CharsetSlot", .{}),
        api.enumeration("DeccolmMode", .{}).members(&.{
            deccolm_mode.function("columns", .{}),
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
