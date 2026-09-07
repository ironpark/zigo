const zigo = @import("zigo");
const library = @import("tagged_union");
const json = @import("zigo_json");

const api = zigo.scope(library);
const child = api.in("Child");
const value = api.in("Value");
const signal = api.in("Signal");
const palette = api.in("Palette");

// Plugin attachment targets and their option types are checked at this declaration.
pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.enumeration("Mode", .{}).use(json.plugin, .{}),
        api.handle("Child", .{}).members(&.{
            child.function("create", .{}),
            child.function("get", .{}),
            child.function("deinit", .{}),
        }),
        api.taggedUnion("Value", .{}).members(&.{
            value.function("create", .{}),
            value.function("setNone", .{}),
            value.function("setFlag", .{}),
            value.function("setMode", .{}),
            value.function("usePresetSamples", .{}),
            value.function("useEmptySamples", .{}),
            value.function("useMutableSamples", .{}),
            value.function("setChild", .{}),
            value.function("borrow", .{}),
            value.function("deinit", .{}),
        }),
        api.taggedUnion("Signal", .{ .access = .snapshot }).members(&.{
            signal.function("create", .{}),
            signal.function("setIdle", .{}),
            signal.function("setTicks", .{}),
            signal.function("setLevel", .{}),
            signal.function("setOffset", .{}),
            signal.function("setMode", .{}),
            signal.function("setActive", .{}),
            signal.function("deinit", .{}),
        }),
        api.value("RGB", .{}).use(json.plugin, .{ .field_names = .zig }),
        api.value("Flags", .{}),
        api.value("ColorRecord", .{}),
        api.handle("Palette", .{ .fields = &.{.{ .path = "flags", .set = true }} }).members(&.{
            palette.function("create", .{}),
            palette.function("deinit", .{}),
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
