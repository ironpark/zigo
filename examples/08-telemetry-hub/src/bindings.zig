const zigo = @import("zigo");
const library = @import("telemetry_hub");

const api = zigo.scope(library);
const telemetry_hub = api.in("TelemetryHub");

pub const bindings = zigo.define(.{
    .root = library,
    .discovery = .{ .public = .{} },
    .declarations = &.{
        api.handle("TelemetryHub", .{}).members(&.{
            telemetry_hub.function("create", .{
                .params = &.{
                    .{ .index = 0, .semantic = .utf8_string },
                    zigo.param.callback(4, .{ .retention = .retained }),
                },
            }),
            telemetry_hub.function("rename", .{
                .params = &.{
                    .{ .index = 1, .semantic = .utf8_string },
                },
            }),
            telemetry_hub.function("name", .{ .returns = .{ .semantic = .utf8_string } }),
            telemetry_hub.function("reduce", .{
                .params = &.{
                    zigo.param.cancel(2, "Cancelled").named("cancel"),
                },
            }),
        }),
    },
});
