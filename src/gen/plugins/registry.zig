//! Which plugins the generator runs. The list is comptime: a plugin names the
//! type of its own options, so a registered plugin is a comptime value and the
//! hook walks are `inline for` over this list.
//!
//! Order is registration order: the built-ins first, then whatever the
//! consuming build passed to `addGoBindings(.plugins)`.
const builtin = @import("builtin");
const implements = @import("builtin_plugins").implements;
const interfaces = @import("builtin_plugins").interfaces;
const iterator = @import("builtin_plugins").iterator;
const must = @import("builtin_plugins").must;
const session = @import("builtin_plugins").session;
const plugin = @import("plugin");
const targets = @import("targets");
const testing_plugin = @import("testing.zig");

/// The features zigo ships with, migrated onto the plugin frame.
pub const builtins: []const plugin.Plugin = &.{
    must.plugin,
    implements.plugin,
    iterator.plugin,
    interfaces.plugin,
    session.plugin,
};

/// The plugins the consuming build compiled in, from the module its build
/// integration generated. It is always present and empty when `.plugins` was
/// not used, so there is one spelling either way.
pub const external: []const plugin.Plugin = @import("plugin_registry").plugins;

/// The plugins in force. Unit tests see one more: a plugin that stays inert
/// until a test switches it on, so the frame itself has something to exercise
/// without any golden moving.
const sorted = plugin.ordered(builtins ++ external ++
    if (builtin.is_test) &[_]plugin.Plugin{testing_plugin.plugin} else &[_]plugin.Plugin{});
pub const plugins: []const plugin.Plugin = &sorted;
pub const configurations = @import("plugin_registry").configurations;

/// The same selection without the language gate. A plugin's native
/// contribution is part of one native library whatever language is being
/// generated from it, so the shim a Go binding set builds and the shim a Rust
/// one builds stay byte for byte the same; which render slot the plugin filled
/// says nothing about that.
pub fn contributes(comptime index: usize, selected: ?[]const []const u8) bool {
    inline for (builtins) |entry| {
        if (@import("std").mem.eql(u8, entry.name, plugins[index].name)) return true;
    }
    const names = selected orelse return true;
    for (names) |name| {
        if (@import("std").mem.eql(u8, name, plugins[index].name)) return true;
    }
    return false;
}

/// Validation and emission share the same selection; built-ins always run.
pub fn runs(comptime index: usize, selected: ?[]const []const u8, target: targets.Target) bool {
    // The output language gates first, and gates the built-ins too: a
    // built-in that fills only the `go` render slot has nothing to contribute
    // to another language. A plugin that fills neither slot is a plugin whose
    // whole contribution is to the IR, and it runs for every target.
    if (!plugins[index].runsFor(target)) return false;
    inline for (builtins) |entry| {
        if (@import("std").mem.eql(u8, entry.name, plugins[index].name)) return true;
    }
    const names = selected orelse return true;
    for (names) |name| {
        if (@import("std").mem.eql(u8, name, plugins[index].name)) return true;
    }
    return false;
}
