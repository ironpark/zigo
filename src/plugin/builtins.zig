//! The built-in plugins' public half: the identity each one is attached
//! under, the option types its declaration writes, and the readers that
//! decode those options off an `ext` object.
//!
//! It lives on the contract rather than in the emitter for two reasons. The
//! authoring module (`zigo.features`) and the generator's registry attach and
//! run the same descriptor, so a built-in has one name, one option type and
//! one subject list instead of two that can drift. And the readers are
//! ordinary contract functions: a third-party plugin that wants to know
//! whether a method is also an iterator, or which interfaces it satisfies,
//! calls exactly what the generator's own rules call.
//!
//! The hooks are not here. They are written against `abi` and the Go builder
//! and live with the plugin (`src/gen/plugins/`), which imports this file and
//! adds them to the descriptor; the generator's rules never read more than
//! what this file exposes.
const std = @import("std");
const semantic = @import("semantic");
const contract = @import("../plugin.zig");

/// A Go standard interface an `.implements` wrapper satisfies. The vocabulary
/// is `semantic`'s, so a document, a diagnostic and a plugin all spell it the
/// same way.
pub const Implements = semantic.Implements;

/// `ITERATOR`: the range-over-func wrapper a `next()` method also gets.
pub const iterator = struct {
    /// An empty name asks for the derived one; the reflector resolves it to
    /// `All` (or `AllChecked`) before it writes the attachment, so a rule
    /// reading this never sees an empty name.
    pub const Options = struct { name: []const u8 = "" };

    pub const plugin: contract.Plugin = .{
        .name = "ITERATOR",
        .FunctionOptions = Options,
        .subjects = &.{.function},
    };

    /// The wrapper this declaration asked for, or null when it asked for none.
    pub fn read(allocator: std.mem.Allocator, ext: ?semantic.Extensions) !?Options {
        return contract.optionsOn(plugin, .function, allocator, ext);
    }
};

/// `IMPLEMENTS`: the Go standard interfaces a handle method also satisfies.
pub const implements = struct {
    pub const Options = struct {
        /// The interfaces the method satisfies, in the order the wrappers are
        /// written.
        kinds: []const Implements,
        /// Keep the bound method exported beside the wrappers. By default only
        /// the standard-library shaped method is public and the zigo-shaped
        /// original is written under an unexported name.
        keep_original: bool = false,

        /// Whether the zigo-shaped method is hidden behind the wrappers.
        pub fn hidesOriginal(self: Options) bool {
            return self.kinds.len != 0 and !self.keep_original;
        }
    };

    pub const plugin: contract.Plugin = .{
        .name = "IMPLEMENTS",
        .FunctionOptions = Options,
        // The options attach to a method; the assertions the type node writes
        // sit after the handle that method belongs to.
        .subjects = &.{ .function, .handle },
    };

    /// The interfaces this declaration asked for, or null when it asked for
    /// none.
    pub fn read(allocator: std.mem.Allocator, ext: ?semantic.Extensions) !?Options {
        return contract.optionsOn(plugin, .function, allocator, ext);
    }

    /// Whether the wrappers replace the zigo-shaped method, which is what the
    /// core asks before it publishes anything beside them.
    pub fn hidesOriginal(allocator: std.mem.Allocator, ext: ?semantic.Extensions) !bool {
        const options = try read(allocator, ext) orelse return false;
        return options.hidesOriginal();
    }
};

/// `PANICS`: the method's Go signature drops its `error`, and the wrapper
/// panics with the error the call would have returned. On a function it asks
/// for that one function; on a handle, for every method of the handle that can
/// take it, leaving the others as they are.
///
/// It is for errors that only a misuse produces -- a nil or closed handle, an
/// argument out of range, a native panic -- the ones Go code conventionally
/// panics on. A Zig error set, a stream, a cancellation or a callback that
/// returns an error each report a condition the caller has to handle, so a
/// method with any of them keeps its `error`.
pub const panics = struct {
    pub const Options = struct {};

    pub const plugin: contract.Plugin = .{
        .name = "PANICS",
        .FunctionOptions = Options,
        .TypeOptions = Options,
        .subjects = &.{ .function, .handle },
    };

    /// Whether the declaration asked for it, on the function itself or on
    /// the handle the function is a method of.
    pub fn requested(allocator: std.mem.Allocator, types: []const semantic.TypeDecl, function: semantic.SemanticFn) !bool {
        if (try contract.optionsOn(plugin, .function, allocator, function.ext) != null) return true;
        return onReceiver(allocator, types, function);
    }

    /// Whether the handle `function` is a method of asked for it.
    pub fn onReceiver(allocator: std.mem.Allocator, types: []const semantic.TypeDecl, function: semantic.SemanticFn) !bool {
        const receiver = function.receiver orelse return false;
        const declaration = semantic.typeDecl(types, receiver) orelse return false;
        return try contract.optionsOn(plugin, .type, allocator, declaration.ext) != null;
    }

    /// Why `function` has to keep its `error`, or null when it may drop it.
    pub const Blocker = enum {
        zig_errors,
        stream,
        cancel,
        callback_error,
        interface_method,
        iterator,
        implements,

        pub fn describe(self: Blocker) []const u8 {
            return switch (self) {
                .zig_errors => "returns a Zig error set",
                .stream => "takes a stream, whose Go side can fail",
                .cancel => "can be cancelled, which it reports as ctx.Err()",
                .callback_error => "reports the error a Go callback returns",
                .interface_method => "is a method of a declared interface, which every implementation shares",
                .iterator => "drives an `.iterator` wrapper",
                .implements => "has `.implements` wrappers",
            };
        }
    };

    /// The first reason `function` keeps its `error`. The two flags are what
    /// only the lowered program knows: whether a callback error can surface
    /// through this call, which includes its receiver's retained callbacks,
    /// and whether a declared interface lists the method.
    pub fn blocker(
        allocator: std.mem.Allocator,
        function: semantic.SemanticFn,
        reaches_callback_errors: bool,
        interface_method: bool,
    ) !?Blocker {
        if (function.@"return" == .error_union and function.@"return".error_union.error_set.len != 0) return .zig_errors;
        for (function.params) |parameter| switch (parameter.type) {
            .io_stream => return .stream,
            .cancel_flag => return .cancel,
            else => {},
        };
        if (function.cancel != null) return .cancel;
        if (reaches_callback_errors) return .callback_error;
        if (try iterator.read(allocator, function.ext) != null) return .iterator;
        if (try implements.read(allocator, function.ext) != null) return .implements;
        if (interface_method) return .interface_method;
        return null;
    }
};
