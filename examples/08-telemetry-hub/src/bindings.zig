const zigo = @import("zigo");
const library = @import("telemetry_hub");

const api = zigo.scope(library);

pub const bindings = zigo.define(.{
    .root = library,
    .discovery = .{ .public = .{} },
    .declarations = &.{
        api.handle("TelemetryHub", .{}),
        api.in("TelemetryHub").function("create", .{ .params = &.{
            .{ .index = 0, .go_name = "input_name", .semantic = .utf8_string }, .{ .index = 1, .go_name = "max_samples" }, .{ .index = 2, .go_name = "initial_mode" }, .{ .index = 3, .go_name = "overflow_policy" }, .{ .index = 4, .go_name = "observer", .contract = .{ .callback = .{ .retention = .retained } } }, .{ .index = 5, .go_name = "userdata" },
        } }),
        api.in("TelemetryHub").function("rename", .{ .params = &.{.{ .index = 1, .go_name = "new_name", .semantic = .utf8_string }} }),
        api.in("TelemetryHub").function("name", .{ .returns = .{ .semantic = .utf8_string } }),
        api.in("TelemetryHub").function("reduce", .{ .params = &.{
            .{ .index = 1, .go_name = "rounds" }, .{ .index = 2, .go_name = "cancel", .contract = .{ .cancel = .{ .canceled = "Cancelled" } } },
        } }),
    },
});
