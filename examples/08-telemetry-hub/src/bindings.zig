const zigo = @import("zigo");
const library = @import("telemetry_hub");

pub const bindings = zigo.define(.{
    .root = library,
    .discover = .public,
    .types = .{
        .{ .type = library.TelemetryHub, .repr = .@"opaque" },
    },
    .overrides = .{
        .{
            .path = "TelemetryHub.create",
            .params = .{ "input_name", "max_samples", "initial_mode", "overflow_policy", "observer", "userdata" },
            .param_meta = .{
                .input_name = .{ .semantic = .utf8_string },
                .observer = .{ .retention = .retained },
            },
        },
        .{
            .path = "TelemetryHub.rename",
            .params = .{"new_name"},
            .param_meta = .{ .new_name = .{ .semantic = .utf8_string } },
        },
        .{ .path = "TelemetryHub.name", .semantic = .utf8_string },
    },
});
