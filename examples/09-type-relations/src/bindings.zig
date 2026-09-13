const zigo = @import("zigo");
const library = @import("type_relations");

const api = zigo.scope(library);
const Counter = api.handle("Counter", .{}).context();
const Accumulator = api.handle("Accumulator", .{}).context();
const DeccolmMode = api.enumeration("DeccolmMode", .{}).context();
const text = api.namespace("text");

// Scopes keep source identity; Go adapters only change the public Go type.
pub const bindings = zigo.define(api, .{
    .declarations = &.{
        Counter.members(&.{
            Counter.func("create", .{}),
            Counter.func("get", .{}),
            Counter.func("add", .{}),
            Counter.func("deinit", .{}),
        }),
        Accumulator.members(&.{
            Accumulator.func("create", .{}),
            Accumulator.func("absorb", .{}),
            Accumulator.func("total", .{}),
            Accumulator.func("deinit", .{}),
        }),
        // A table-built enum has no `///` in the source to lend: the tags are
        // strings in a slice. `.fields` is where those members get documented.
        api.enumeration("CursorStyle", .{ .fields = &.{
            .{ .name = "block", .doc = "The filled cell the terminal starts in." },
            .{ .name = "bar", .doc = "A vertical bar between two cells." },
        } }),
        api.enumeration("CharsetSlot", .{}),
        DeccolmMode.members(&.{
            DeccolmMode.func("columns", .{}),
        }),
        api.enumeration("EraseDisplay", .{ .exhaustive = false }),
        api.value("Point", .{ .go = .{
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
        text.namespace("unicode").func("codepointWidth", .{}),
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
