//! The capabilities the generator's own plugins publish.
//!
//! A capability is the whole contract between two plugins: the provider lists
//! it in `provides` and writes facts under it, the consumer lists it in
//! `requires` or `uses` and reads them. Both halves name the same value from
//! here, so a third-party plugin joins either side of a built-in's contract
//! without importing the built-in itself.
const contract = @import("../plugin.zig");

/// `MUST`: one fact per function that also gets a `Must` companion, carrying
/// the companion's exported name. A function with no fact under this
/// capability has no companion.
pub const must_variant: contract.Capability = .{
    .name = "zigo.must_variant",
    .Facts = struct {
        /// The exported name of the generated companion, `Must<Name>`.
        name: []const u8,
    },
};

/// `IMPLEMENTS`: the standard-interface wrappers a method's declaration asked
/// for are settled. It carries no facts -- what a wrapper replaces is read off
/// the declaration through `plugin.builtins.implements` -- so it is the
/// ordering alone: a plugin that writes next to a method it may have hidden
/// runs after it.
pub const implements_wrappers: contract.Capability = .{
    .name = "zigo.implements_wrappers",
    .Facts = struct {},
};
