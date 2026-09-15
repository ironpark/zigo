//! The Go spelling a hook needs that no generator state answers for: an
//! identifier derived from a Zig name. It is reached through
//! `Context.identifierAlloc`, which is the one path a plugin uses; this file
//! is what the writers table points at. Everything else a hook writes is a
//! node the Go builder renders.
const std = @import("std");
const naming = @import("naming");
const plugin = @import("../plugin.zig");

/// The exported (`.pascal`) or unexported (`.camel`) Go spelling of a Zig
/// name, with the same initialism rules the generated package applies to
/// its own members. The caller owns the result.
pub fn identifierAlloc(_: plugin.GoContext, allocator: std.mem.Allocator, name: []const u8, style: plugin.IdentifierStyle) anyerror![]u8 {
    return switch (style) {
        .pascal => naming.pascalAlloc(allocator, name),
        .camel => naming.camelAlloc(allocator, name),
    };
}
