//! Go conveniences use the same attachment syntax as external plugins.
const ir = @import("declare.zig");
const Target = enum { function, enumeration };
const Builtin = enum { iterator, implements, text };
pub const iterator = .{ .name = "ITERATOR", .FunctionOptions = ir.Iterator, .TypeOptions = struct {}, .targets = [_]Target{.function}, .builtin = Builtin.iterator };
pub const implements = .{ .name = "IMPLEMENTS", .FunctionOptions = struct { kind: ir.Implements }, .TypeOptions = struct {}, .targets = [_]Target{.function}, .builtin = Builtin.implements };
pub const text = .{ .name = "TEXT", .FunctionOptions = struct {}, .TypeOptions = struct {}, .targets = [_]Target{.enumeration}, .builtin = Builtin.text };
