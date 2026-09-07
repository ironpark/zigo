//! A zigo generator plugin, packaged the way any other one is: it exposes a
//! module named `plugin` whose root file declares `pub const plugin`.
//!
//! The module deliberately declares no imports of its own. `addGoBindings`
//! injects `plugin`, `abi`, `semantic` and `diagnostic` into every listed
//! plugin module, so the plugin and the generator that runs it speak about
//! one set of types rather than two identical-looking copies.
const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("plugin", .{ .root_source_file = b.path("src/plugin.zig") });
}
