//! Typed declaration trees for authoring Zig-to-Go bindings.
const author = @import("author.zig");
pub const scope = author.scope;
pub const package = author.package;
pub const interface = author.interface;
pub const session = author.session;
pub const features = @import("features.zig");
/// The value a plugin package exports and `Entry.use` takes; `zigo.features`
/// are values of this type too. Its hooks and contexts are documented with
/// the generator's plugin contract (`docs/plugins/`).
pub const Plugin = @import("plugin").Plugin;
/// The contract itself, for the reflector and for a binding that needs more
/// of it than the `Plugin` value: `zigo.plugin.builtins` holds the built-in
/// features' option types and the readers that decode them.
pub const plugin = @import("plugin");
pub const Binding = author.Binding;
pub const Entry = author.Entry;
pub const FunctionRef = author.FunctionRef;
pub const TypeRef = author.TypeRef;
/// How a plugin option names an interface: the entry `zigo.interface(...)`
/// returned, or its name.
pub const InterfaceRef = author.InterfaceRef;
pub const FunctionOptions = author.FunctionOptions;
pub const TypeOptions = author.TypeOptions;
pub const HandleOptions = author.HandleOptions;
pub const HandleField = author.HandleField;
pub const ValueField = author.ValueField;
pub const EnumField = author.EnumField;
pub const ValueOptions = author.ValueOptions;
pub const MaterializedOptions = author.MaterializedOptions;
pub const EnumOptions = author.EnumOptions;
pub const UnionOptions = author.UnionOptions;
pub const CallbackOptions = author.CallbackOptions;
pub const CallbackParam = author.CallbackParam;
pub const CallbackContract = author.CallbackContract;
pub const CallbackSite = author.CallbackSite;
pub const Package = author.Package;
pub const Interface = author.Interface;
pub const Session = author.Session;
pub const SessionChild = author.SessionChild;
pub const Discovery = author.Discovery;
pub const param = @import("param.zig");
pub const result = @import("result.zig");
pub const Param = author.Param;
pub const Returns = author.Returns;
pub const Role = author.Role;
pub const Receiver = author.Receiver;
pub const Defaults = author.Defaults;
pub const Selector = author.Selector;
pub const Subject = author.Subject;
pub const GoAdapter = author.GoAdapter;
pub const SemanticHint = author.SemanticHint;
pub const Injection = author.Injection;

/// Private lowering target shared with the reflector. Not an authoring API.
pub const normalized = @import("declare.zig");

/// Resolve and validate authoring declarations before reflection and lowering.
/// `api` is the scope from `zigo.scope(library)`; it names the root once.
pub fn define(comptime api: type, comptime binding: Binding) normalized.Binding {
    if (@typeInfo(api) != .@"struct" or !@hasDecl(api, "root")) @compileError("zigo define takes the scope returned by zigo.scope(library)");
    return @import("normalize.zig").binding(api.root, binding);
}

test {
    _ = author;
    _ = @import("normalize.zig");
    _ = features;
    _ = @import("context_tests.zig");
}
