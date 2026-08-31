const zigo = @import("zigo");
const invalid = @import("invalid");

pub const bindings = zigo.define(.{
    .root = invalid,
    .functions = .{
        .{ .path = "root.lookupID" },
        .{ .path = "root.lookup_id" },
    },
});
