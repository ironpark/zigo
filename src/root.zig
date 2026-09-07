//! Typed declaration trees for authoring Zig-to-Go bindings.
const author = @import("author.zig");
pub const dsl = @import("dsl.zig");
pub const scope = author.scope;
pub const package = author.package;
pub const interface = author.interface;
pub const features = @import("features.zig");
pub const Binding = author.Binding;
pub const Entry = author.Entry;
pub const FunctionRef = author.FunctionRef;
pub const TypeRef = author.TypeRef;
pub const FunctionOptions = author.FunctionOptions;
pub const TypeOptions = author.TypeOptions;
pub const HandleOptions = author.HandleOptions;
pub const ValueOptions = author.ValueOptions;
pub const MaterializedOptions = author.MaterializedOptions;
pub const EnumOptions = author.EnumOptions;
pub const UnionOptions = author.UnionOptions;
pub const CallbackOptions = author.CallbackOptions;
pub const Buffer = author.Buffer;
pub const CallbackContract = author.CallbackContract;
pub const Package = author.Package;
pub const Interface = author.Interface;
pub const Discovery = author.Discovery;
pub const Param = author.Param;
pub const ParamContract = author.ParamContract;
pub const Returns = author.Returns;
pub const Lifetime = author.Lifetime;
pub const Role = author.Role;
pub const Receiver = author.Receiver;
pub const Defaults = author.Defaults;
pub const Selector = author.Selector;
pub const GoAdapter = author.GoAdapter;
pub const SemanticHint = author.SemanticHint;
pub const Injection = author.Injection;

/// Private lowering target shared with the reflector. Not an authoring API.
pub const normalized = @import("declare.zig");

/// Resolve and validate authoring declarations before reflection and lowering.
pub fn define(comptime binding: Binding) normalized.Binding {
    return @import("normalize.zig").binding(binding);
}

test {
    _ = author;
    _ = @import("normalize.zig");
    _ = features;
    _ = dsl;
}

pub const param = @import("param.zig");
pub const result = @import("result.zig");
