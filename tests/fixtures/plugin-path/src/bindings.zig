const zigo = @import("zigo");
const fixture = @import("fixture");
const wrappers = @import("wrappers");
const api = zigo.scope(fixture);

pub const bindings = zigo.define(.{
    .root = fixture,
    .declarations = &.{api.func("ping", .{}).use(wrappers.plugin, .{})},
});
