//! Built-in Go conveniences. They attach with the same `.use` as an external
//! plugin and are the same kind of value -- a `plugin.Plugin` -- because they
//! are the very descriptors the generator's registry runs
//! (`src/gen/plugins/`), re-exported from the contract. One definition names
//! each built-in, types its options and lists its subjects; the generator's
//! copy only adds the hooks, which are written against the emitter and cannot
//! live here.
const plugin = @import("plugin");

/// `iter.Seq`/`iter.Seq2` wrappers for a `next()` method that returns `?T`.
pub const iterator = plugin.builtins.iterator.plugin;

/// Standard Go I/O methods next to a bound method. A method can satisfy more
/// than one interface, so the list is the only spelling; it must not be empty.
pub const implements = plugin.builtins.implements.plugin;
