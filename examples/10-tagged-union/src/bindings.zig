const zigo = @import("zigo");
const library = @import("tagged_union");
const json = @import("zigo_json");

const api = zigo.scope(library);
const Child = api.handle("Child", .{}).context();
const Value = api.taggedUnion("Value", .{}).context();
const Signal = api.taggedUnion("Signal", .{ .access = .snapshot }).context();
const Palette = api.handle("Palette", .{ .fields = &.{.{ .path = "flags", .set = true }} }).context();

// Plugin attachment targets and their option types are checked at this declaration.
pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.enumeration("Mode", .{}).use(json.plugin, .{}),
        Child.define(&.{
            Child.function("create", .{}),
            Child.function("get", .{}),
            Child.function("deinit", .{}),
        }),
        Value.select(.{ .names = &.{
            "create",
            "setNone",
            "setFlag",
            "setMode",
            "usePresetSamples",
            "useEmptySamples",
            "useMutableSamples",
            "setChild",
            "borrow",
            "deinit",
        } }),
        Signal.select(.{ .names = &.{
            "create",
            "setIdle",
            "setTicks",
            "setLevel",
            "setOffset",
            "setMode",
            "setActive",
            "deinit",
        } }),
        api.value("RGB", .{}).use(json.plugin, .{ .field_names = .zig }),
        api.value("Flags", .{}),
        api.value("ColorRecord", .{}),
        Palette.define(&.{
            Palette.function("create", .{}),
            Palette.function("deinit", .{}),
        }),
        api.callback("FlagsObserver", .{}),
        api.taggedUnion("ScrollViewport", .{ .omit = &.{"unknown"} }),
        api.function("liveValues", .{}),
        api.function("divide", .{}),
        api.function("sum", .{}),
        api.function("scrollAmount", .{}),
        api.function("currentViewport", .{}),
        api.function("echoRGB", .{}),
        api.function("maybeRGB", .{}),
        api.function("checkedRGB", .{}),
        api.function("echoColorRecord", .{}),
        api.function("flattenFlags", .{ .params = &.{
            zigo.param.flatten(0, &.{"flags"}),
        } }),
        api.function("visitFlags", .{}),
        api.function("panicError", .{}),
    },
});
