const zigo = @import("zigo");
const library = @import("calculator");

const api = zigo.scope(library);

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        // One declaration per shape the minimal Rust backend covers: a
        // scalar, a borrowed slice, and an error union.
        api.func("add", .{}),
        api.func("sum", .{}),
        api.func("divide", .{}),
    },
});
