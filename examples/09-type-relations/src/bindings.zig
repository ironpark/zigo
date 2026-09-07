const zigo = @import("zigo");
const library = @import("type_relations");

const api = zigo.scope(library);

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.handle("Counter", .{}),
        api.handle("Accumulator", .{}),
        api.enumeration("CursorStyle", .{}),
        api.enumeration("CharsetSlot", .{}),
        api.enumeration("DeccolmMode", .{}),
        api.enumeration("EraseDisplay", .{ .exhaustive = false }),
        api.value("Point", .{ .go = .{
            .type = "image.Point",
            .import = "image",
            .to_raw = "pointToRaw",
            .from_raw = "pointFromRaw",
        } }),
        api.in("Counter").function("create", .{ .params = &.{.{ .index = 0, .go_name = "initial" }} }),
        api.in("Counter").function("get", .{}),
        api.in("Counter").function("add", .{ .params = &.{.{ .index = 1, .go_name = "delta" }} }),
        api.in("Counter").function("deinit", .{}),
        api.in("Accumulator").function("create", .{}),
        api.in("Accumulator").function("absorb", .{ .params = &.{.{ .index = 1, .go_name = "counter" }} }),
        api.in("Accumulator").function("total", .{}),
        api.in("Accumulator").function("deinit", .{}),
        api.function("liveObjects", .{ .returns = .{ .go = .{ .type = "ObjectCount", .to_raw = "objectCountToRaw", .from_raw = "objectCountFromRaw" } } }),
        api.function("defaultCursorStyle", .{}),
        api.in("DeccolmMode").function("columns", .{}),
        api.function("configureStyles", .{ .params = &.{ .{ .index = 0, .go_name = "slot" }, .{ .index = 1, .go_name = "style" } } }),
        api.function("isWideColumns", .{ .params = &.{.{ .index = 0, .go_name = "mode" }} }),
        api.function("echoEraseDisplay", .{ .params = &.{.{ .index = 0, .go_name = "value" }} }),
        api.in("text").function("runWidth", .{ .params = &.{ .{ .index = 0, .go_name = "first" }, .{ .index = 1, .go_name = "second" } } }),
        api.in("text").in("unicode").function("codepointWidth", .{ .params = &.{.{ .index = 0, .go_name = "cp" }} }),
        api.function("doubleWidth", .{ .params = &.{.{ .index = 0, .go_name = "value" }} }),
        api.function("invert", .{ .params = &.{.{ .index = 0, .go_name = "value" }} }),
        api.function("styleOrDefault", .{ .params = &.{.{ .index = 0, .go_name = "style" }} }),
        api.function("blinkingStyle", .{ .params = &.{.{ .index = 0, .go_name = "style" }} }),
        api.function("shiftPoint", .{ .params = &.{ .{ .index = 0, .go_name = "origin" }, .{ .index = 1, .go_name = "delta" } } }),
        api.function("checkedShift", .{ .params = &.{ .{ .index = 0, .go_name = "origin" }, .{ .index = 1, .go_name = "delta" } } }),
        api.function("describeText", .{ .params = &.{.{ .index = 0, .go_name = "label", .semantic = .utf8_string }} }),
        api.function("sumOrZero", .{ .params = &.{.{ .index = 0, .go_name = "values" }} }),
        api.function("leadingDigits", .{ .params = &.{.{ .index = 0, .go_name = "count" }} }),
        api.function("styleName", .{ .returns = .{ .semantic = .utf8_string }, .params = &.{.{ .index = 0, .go_name = "style" }} }),
        api.function("cursorStyleBlinks", .{ .name = "blinks", .role = .{ .method = api.typeRef("CursorStyle") } }),
    },
});
