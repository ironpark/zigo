const std = @import("std");
const shim = @import("expected/shim.zig");
const target = @import("zigo_target");

// `std.log` reads the compilation root's `std_options`, and the root of a
// zigo build is the shim. What a test can check is the declaration the shim
// makes: that it exists, that it is a `std.Options`, and that it is the bound
// module's own rather than the std default. The routing itself is std's
// contract on whatever file is root.
//
// The `materialized` case covers the other branch: its target declares no
// `std_options`, and its shim compiles all the same.
test "the generated shim hands its root options to the bound module" {
    try std.testing.expect(shim.std_options.logFn == target.std_options.logFn);
    try std.testing.expectEqual(std.log.Level.debug, shim.std_options.log_level);
    shim.std_options.logFn(.warn, .default, "attributes {d}", .{7});
    try std.testing.expectEqual(std.log.Level.warn, target.last_level.?);
    try std.testing.expectEqualStrings("attributes 7", target.last_message[0..target.last_length]);
}
