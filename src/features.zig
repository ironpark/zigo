//! Built-in Go conveniences. They attach with the same `.use` as an external
//! plugin and are the same kind of value -- a `plugin.Plugin` -- carrying the
//! names the generator's registry gives the built-in plugins
//! (`src/gen/plugins/registry.zig`), which is how `Entry.use` tells them
//! apart from an external attachment.
const ir = @import("declare.zig");
const plugin = @import("plugin");

/// `iter.Seq`/`iter.Seq2` wrappers for a `next()` method that returns `?T`.
pub const iterator: plugin.Plugin = .{
    .name = "ITERATOR",
    .FunctionOptions = ir.Iterator,
    .subjects = &.{.function},
};

/// Standard Go I/O methods next to a bound method. A method can satisfy more
/// than one interface, so the list is the only spelling; it must not be empty.
pub const implements: plugin.Plugin = .{
    .name = "IMPLEMENTS",
    .FunctionOptions = struct {
        kinds: []const ir.Implements,
        /// Keep the bound method exported beside the interface wrappers. By
        /// default only the standard-library shaped method (`Write`,
        /// `Read`, ...) is public and the zigo-shaped original is hidden.
        keep_original: bool = false,
    },
    .subjects = &.{.function},
};
