//! A zigo generator plugin. `addGoBindings` compiles `src/plugin.zig` against
//! the generator's own modules, so the module declared here exists for editors
//! and for a standalone `zig build` rather than for the generator.
const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("plugin", .{ .root_source_file = b.path("src/plugin.zig") });
}
