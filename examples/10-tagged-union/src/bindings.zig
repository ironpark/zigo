const zigo = @import("zigo");
const library = @import("tagged_union");
const enumkit = @import("zigo_enumkit");
const json = @import("zigo_json");

const api = zigo.scope(library);
const Child = api.handle("Child", .{}).context();
const Value = api.taggedUnion("Value", .{}).context();
const Signal = api.taggedUnion("Signal", .{ .access = .snapshot }).context();
const Palette = api.handle("Palette", .{ .fields = &.{
    .{ .path = "flags", .set = true },
    .{ .path = "pinned_mode", .name = "pinnedMode", .set = true },
    .{ .path = "name" },
} }).context();

// Plugin attachment targets and their option types are checked at this declaration.
pub const bindings = zigo.define(api, .{
    .declarations = &.{
        api.enumeration("Mode", .{}).use(json.plugin, .{}).use(enumkit.plugin, .{}),
        Child.members(&.{
            Child.func("create", .{}),
            Child.func("get", .{}),
            Child.func("deinit", .{}),
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
        Palette.members(&.{
            Palette.func("create", .{}),
            Palette.func("deinit", .{}),
        }),
        api.callback("FlagsObserver", .{}),
        api.taggedUnion("ScrollViewport", .{ .omit = &.{"unknown"} }),
        api.func("liveValues", .{}),
        api.func("divide", .{}),
        api.func("sum", .{}),
        api.func("scrollAmount", .{}),
        api.func("currentViewport", .{}),
        api.func("echoRGB", .{}),
        api.func("maybeRGB", .{}),
        api.func("checkedRGB", .{}),
        api.func("echoColorRecord", .{}),
        api.func("flattenFlags", .{ .params = &.{
            zigo.param.flatten(0, &.{"flags"}),
        } }),
        api.func("visitFlags", .{}),
        api.func("panicError", .{}),
    },
});
