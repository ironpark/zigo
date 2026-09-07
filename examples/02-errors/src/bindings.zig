const zigo = @import("zigo");
const errors = @import("errors");

const api = zigo.scope(errors);

pub const bindings = zigo.define(.{
    .root = errors,
    .declarations = &.{
        api.function("divide", .{}),
        api.function("sum", .{}),
        api.function("normalizeFormat", .{}),
        api.function("codepointWidth", .{ .params = &.{.{ .index = 0, .go_name = "cp", .semantic = .codepoint }} }),
    },
});
