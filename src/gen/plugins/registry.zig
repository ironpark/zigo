//! Which plugins the generator runs. The list is comptime: a plugin names the
//! type of its own options, so a registered plugin is a comptime value and the
//! hook walks are `inline for` over this list.
//!
//! Order is registration order: the built-ins first, then whatever the
//! consuming build passed to `addGoBindings(.plugins)`.
const builtin = @import("builtin");
const iterator = @import("iterator.zig");
const plugin = @import("plugin");
const testing_plugin = @import("testing.zig");

/// The features zigo ships with, migrated onto the plugin frame.
pub const builtins: []const plugin.Plugin = &.{iterator.plugin};

/// The plugins the consuming build compiled in. Replaced by the generated
/// `plugin_registry` module once a build passes `.plugins`.
pub const external: []const plugin.Plugin = &.{};

/// The plugins in force. Unit tests see one more: a plugin that stays inert
/// until a test switches it on, so the frame itself has something to exercise
/// without any golden moving.
pub const plugins: []const plugin.Plugin = builtins ++ external ++
    if (builtin.is_test) &[_]plugin.Plugin{testing_plugin.plugin} else &[_]plugin.Plugin{};
