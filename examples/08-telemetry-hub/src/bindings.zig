const zigo = @import("zigo");
const library = @import("telemetry_hub");

const api = zigo.scope(library);
const TelemetryHub = api.handle("TelemetryHub", .{}).context();

pub const bindings = zigo.define(.{
    .root = library,
    .discovery = .{ .public = .{} },
    .declarations = &.{
        TelemetryHub.define(&.{
            TelemetryHub.function("create", .{
                .params = &.{
                    .{ .index = 0, .semantic = .utf8_string },
                    zigo.param.callback(4, .{ .retention = .retained }),
                },
            }),
            TelemetryHub.function("rename", .{
                .params = &.{
                    .{ .index = 1, .semantic = .utf8_string },
                },
            }),
            TelemetryHub.function("name", .{ .returns = .{ .semantic = .utf8_string } }),
            TelemetryHub.function("reduce", .{
                .params = &.{
                    zigo.param.cancel(2, "Cancelled").named("cancel"),
                },
            }),
        }),
    },
});
