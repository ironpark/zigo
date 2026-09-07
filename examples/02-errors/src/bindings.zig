const zigo = @import("zigo");
const errors = @import("errors");

const api = zigo.scope(errors);

pub const bindings = zigo.define(.{
    .root = errors,
    .declarations = &.{
        api.func("divide", .{}),
        api.func("sum", .{}),
        api.func("normalizeFormat", .{}),
        api.func("codepointWidth", .{ .params = &.{
            .{ .index = 0, .semantic = .codepoint },
        } }),
    },
});
