//! Go's word-level rules: what is reserved and what may be an identifier.
//!
//! A leaf on purpose. It imports nothing but `std`, so the build integration
//! can reach it from `build.zig`, where no module graph exists yet and a
//! `Target` -- which knows the semantic IR -- cannot be constructed. `go.zig`
//! composes these into the `Target` the generator uses, so there is still one
//! definition of each rule.
const std = @import("std");

pub fn isKeyword(value: []const u8) bool {
    const keywords = [_][]const u8{
        "break",    "default",     "func",   "interface", "select",
        "case",     "defer",       "go",     "map",       "struct",
        "chan",     "else",        "goto",   "package",   "switch",
        "const",    "fallthrough", "if",     "range",     "type",
        "continue", "for",         "import", "return",    "var",
    };
    for (keywords) |keyword| if (std.mem.eql(u8, value, keyword)) return true;
    return false;
}

pub fn isIdentifier(value: []const u8) bool {
    if (value.len == 0 or std.mem.eql(u8, value, "_") or isKeyword(value) or
        !(std.ascii.isAlphabetic(value[0]) or value[0] == '_')) return false;
    for (value[1..]) |character| if (!(std.ascii.isAlphanumeric(character) or character == '_')) return false;
    return true;
}

/// The shape a `.go` adapter's `to_raw` and `from_raw` have to have. It is
/// laxer than `isIdentifier` on purpose: the spelling names a function in the
/// user's own package, so only what would break the generated call is
/// rejected. A keyword or `_` passes here and fails to compile in the user's
/// own Go, which is a clearer place to learn about it than a generator rule.
pub fn isConversionFunctionName(name: []const u8) bool {
    if (name.len == 0 or std.ascii.isDigit(name[0])) return false;
    for (name) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    return true;
}

/// Rejects a name that cannot be a Go package identifier. `Target` answers the
/// same question for whichever target is selected; this spelling exists for
/// `build.zig`, which validates its own options before a target is chosen.
pub fn validatePackageName(name: []const u8) error{InvalidPackageName}!void {
    if (!isIdentifier(name)) return error.InvalidPackageName;
}
