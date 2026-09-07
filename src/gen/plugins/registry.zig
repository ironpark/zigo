//! Which plugins the generator runs. The list is comptime: a plugin names the
//! type of its own options, so a registered plugin is a comptime value and the
//! hook walks are `inline for` over this list.
//!
//! Order is registration order: the built-ins first, then whatever the
//! consuming build passed to `addGoBindings(.plugins)`.
const builtin = @import("builtin");
const implements = @import("implements.zig");
const interfaces = @import("interfaces.zig");
const iterator = @import("iterator.zig");
const must = @import("must.zig");
const plugin = @import("plugin");
const testing_plugin = @import("testing.zig");

/// The features zigo ships with, migrated onto the plugin frame.
pub const builtins: []const plugin.Plugin = &.{
    // `Must` writes first, so a method that has both a `Must` variant and an
    // iterator wrapper keeps the order the generated file has always had.
    must.plugin,
    // `.implements` judges before `.iterator`: a method that claims both is
    // an `.implements` fault, and the order the two validators ran in when
    // they lived in `functions.zig` is what decides which code it gets.
    implements.plugin,
    iterator.plugin,
    interfaces.plugin,
};

/// The plugins the consuming build compiled in, from the module its build
/// integration generated. It is always present and empty when `.plugins` was
/// not used, so there is one spelling either way.
pub const external: []const plugin.Plugin = @import("plugin_registry").plugins;

/// The plugins in force. Unit tests see one more: a plugin that stays inert
/// until a test switches it on, so the frame itself has something to exercise
/// without any golden moving.
pub const plugins: []const plugin.Plugin = builtins ++ external ++
    if (builtin.is_test) &[_]plugin.Plugin{testing_plugin.plugin} else &[_]plugin.Plugin{};

/// Validation and emission share the same selection; built-ins always run.
pub fn runs(comptime index: usize, selected: ?[]const []const u8) bool {
    if (index < builtins.len) return true;
    return (plugin.Options{ .go_module = "", .plugins = selected }).runsPlugin(plugins[index].name);
}
