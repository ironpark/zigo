const zigo = @import("zigo");
const invalid = @import("invalid");

pub const bindings = zigo.define(.{
    .functions = .{
        .{ .name = "lookupID", .@"fn" = invalid.lookupID },
        .{ .name = "lookup_id", .@"fn" = invalid.lookup_id },
    },
});
