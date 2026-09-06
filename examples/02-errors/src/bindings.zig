const zigo = @import("zigo");
const errors = @import("errors");

pub const bindings = zigo.define(.{
    .root = errors,
    .functions = .{
        .{ .path = "root.divide" },
        .{ .path = "root.sum" },
        .{ .path = "root.normalizeFormat" },
        // A `u21` is Go's `rune` once the binding says it is a codepoint; the
        // range check stays, so a value above 0x1FFFFF is still a RangeError.
        .{ .path = "root.codepointWidth", .params = .{"cp"}, .param_meta = .{ .cp = .{ .semantic = .codepoint } } },
    },
});
