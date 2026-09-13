//! Built-in Go conveniences. They attach with the same `.use` as an external
//! plugin and carry the names the generator's registry gives the built-in
//! plugins (`src/gen/plugins/registry.zig`), which is how `Entry.use` tells
//! them apart from an external attachment.
const author = @import("author.zig");
const ir = @import("declare.zig");

/// `iter.Seq`/`iter.Seq2` wrappers for a `next()` method that returns `?T`.
pub const iterator = .{
    .name = "ITERATOR",
    .FunctionOptions = ir.Iterator,
    .TypeOptions = struct {},
    .subjects = &[_]author.Subject{.function},
};

/// Standard Go I/O methods next to a bound method. A method can satisfy more
/// than one interface, so the list is the only spelling; it must not be empty.
pub const implements = .{
    .name = "IMPLEMENTS",
    .FunctionOptions = struct { kinds: []const ir.Implements },
    .TypeOptions = struct {},
    .subjects = &[_]author.Subject{.function},
};
