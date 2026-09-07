//! Declaration DSL imported by a user's `bindings.zig`.
//!
//! `define` takes a `Binding`; the schema it and every nested entry follow is
//! in `declare.zig` and re-exported here, so a binding can name a type
//! (`zigo.Param`, `zigo.Type`) to build entries in helper functions.
const declare = @import("declare.zig");

pub const dsl = @import("dsl.zig");

pub const Binding = declare.Binding;
pub const Type = declare.Type;
pub const Handle = declare.Handle;
pub const Value = declare.Value;
pub const Materialized = declare.Materialized;
pub const Enum = declare.Enum;
pub const TaggedUnion = declare.TaggedUnion;
pub const Callback = declare.Callback;
pub const CallbackParam = declare.CallbackParam;
pub const Function = declare.Function;
pub const FunctionOptions = declare.FunctionOptions;
pub const Methods = declare.Methods;
pub const Param = declare.Param;
pub const Returns = declare.Returns;
pub const HandleField = declare.HandleField;
pub const ValueField = declare.ValueField;
pub const Package = declare.Package;
pub const Interface = declare.Interface;
pub const Injection = declare.Injection;
pub const GoAdapter = declare.GoAdapter;
pub const Iterator = declare.Iterator;
pub const Cancel = declare.Cancel;
pub const Userdata = declare.Userdata;
pub const SemanticHint = declare.SemanticHint;

/// Preserve a binding declaration as comptime data for the reflector.
pub fn define(comptime binding: Binding) Binding {
    return binding;
}

test {
    const testing = @import("std").testing;
    testing.refAllDecls(declare);
    testing.refAllDecls(dsl);
}

test "define preserves the declaration" {
    const Lib = struct {
        pub fn add(a: i32, b: i32) i32 {
            return a + b;
        }
    };
    const binding = define(.{ .root = Lib, .functions = &.{.{ .path = "root.add" }} });
    try @import("std").testing.expectEqual(@as(usize, 1), binding.functions.len);
}
