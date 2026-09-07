const zigo = @import("zigo");
const library = @import("telemetry_hub");

pub const bindings = zigo.define(.{
    .root = library,
    .discover = .public,
    .types = &.{
        .{ .handle = .{ .type = library.TelemetryHub } },
    },
    .functions = &.{
        .{
            .path = "TelemetryHub.create",
            .params = &.{ .{ .name = "input_name", .semantic = .utf8_string }, .{ .name = "max_samples" }, .{ .name = "initial_mode" }, .{ .name = "overflow_policy" }, .{ .name = "observer", .retention = .retained }, .{ .name = "userdata" } },
        },
        .{
            .path = "TelemetryHub.rename",
            .params = &.{.{ .name = "new_name", .semantic = .utf8_string }},
        },
        .{ .path = "TelemetryHub.name", .returns = .{ .semantic = .utf8_string } },
        // A long call Go can stop. `.cancel` names the parameter that carries
        // the flag: it leaves the Go signature, a `ctx context.Context` takes
        // its place, and a goroutine watching `ctx.Done()` raises it.
        .{
            .path = "TelemetryHub.reduce",
            .params = &.{ .{ .name = "rounds" }, .{ .name = "cancel" } },
            .cancel = .{ .param = "cancel", .canceled = "Cancelled" },
        },
    },
});
