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
