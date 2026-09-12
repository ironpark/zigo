//! Go conveniences use the same attachment syntax as external plugins.
const ir = @import("declare.zig");
/// The declaration kinds a feature attaches to. Mirrors `plugin.Subject`
/// structurally, which is what the binding DSL checks against.
const Subject = enum { function, enumeration };
const Builtin = enum { iterator, implements, text };
pub const iterator = .{ .name = "ITERATOR", .FunctionOptions = ir.Iterator, .TypeOptions = struct {}, .subjects = [_]Subject{.function}, .builtin = Builtin.iterator };
/// One kind or several: a method can satisfy more than one interface, so the
/// options carry a list. `kind` is the spelling for the common single case and
/// `kinds` for the rest; exactly one of them belongs on a declaration.
pub const implements = .{ .name = "IMPLEMENTS", .FunctionOptions = struct { kind: ?ir.Implements = null, kinds: []const ir.Implements = &.{} }, .TypeOptions = struct {}, .subjects = [_]Subject{.function}, .builtin = Builtin.implements };
pub const text = .{ .name = "TEXT", .FunctionOptions = struct {}, .TypeOptions = struct {}, .subjects = [_]Subject{.enumeration}, .builtin = Builtin.text };
