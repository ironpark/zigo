//! Go conveniences use the same attachment syntax as external plugins.
const ir = @import("declare.zig");
/// The declaration kinds a feature attaches to. Mirrors `plugin.Subject`
/// structurally, which is what the binding DSL checks against.
const Subject = enum { function, enumeration };
const Builtin = enum { iterator, implements, text };
pub const iterator = .{ .name = "ITERATOR", .FunctionOptions = ir.Iterator, .TypeOptions = struct {}, .subjects = [_]Subject{.function}, .builtin = Builtin.iterator };
pub const implements = .{ .name = "IMPLEMENTS", .FunctionOptions = struct { kind: ir.Implements }, .TypeOptions = struct {}, .subjects = [_]Subject{.function}, .builtin = Builtin.implements };
pub const text = .{ .name = "TEXT", .FunctionOptions = struct {}, .TypeOptions = struct {}, .subjects = [_]Subject{.enumeration}, .builtin = Builtin.text };
