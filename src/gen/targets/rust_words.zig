//! Rust's word-level rules: what is reserved and what may be an identifier.
//!
//! A leaf, for the same reason `go_words.zig` is one. It imports nothing but
//! `std`, so `build.zig` can reach it where no module graph exists yet and a
//! `Target` -- which knows the semantic IR -- cannot be constructed.
//! `rust.zig` composes these into the `Target` the generator uses, so there is
//! still one definition of each rule.
const std = @import("std");

/// Words Rust 2021 reserves for the language. `dyn`, `async`, `await` and
/// `try` are in here rather than in `reserved` below because the 2018 and
/// 2021 editions made them real keywords, and the generator emits 2021.
pub const strict_keywords = [_][]const u8{
    "as",    "break", "const",  "continue", "crate", "dyn",
    "else",  "enum",  "extern", "false",    "fn",    "for",
    "if",    "impl",  "in",     "let",      "loop",  "match",
    "mod",   "move",  "mut",    "pub",      "ref",   "return",
    "self",  "Self",  "static", "struct",   "super", "trait",
    "true",  "type",  "unsafe", "use",      "where", "while",
    "async", "await", "try",
};

/// Words Rust reserves for future use. They are not usable as identifiers
/// today either, so a derived name landing on one has to be escaped just the
/// same.
pub const reserved_keywords = [_][]const u8{
    "abstract", "become", "box",    "do",      "final",   "macro",
    "override", "priv",   "typeof", "unsized", "virtual", "yield",
};

/// Words that only mean something in a particular position (`union` before a
/// name, `macro_rules` before `!`). They are legal identifiers, so they are
/// not escaped -- but `r#`-escaping them is illegal, which is why the list
/// exists: `isRawIdentifierEligible` has to know them.
pub const weak_keywords = [_][]const u8{ "macro_rules", "union", "safe", "raw" };

pub fn isKeyword(value: []const u8) bool {
    for (strict_keywords) |keyword| if (std.mem.eql(u8, value, keyword)) return true;
    for (reserved_keywords) |keyword| if (std.mem.eql(u8, value, keyword)) return true;
    return false;
}

/// Whether `value` can be spelled `r#value`. Rust forbids the raw form for
/// `crate`, `self`, `super` and `Self` -- the four path keywords -- so a
/// derived name landing on one of those has to be escaped some other way.
/// `_` is also excluded because `r#_` is not an identifier.
pub fn isRawIdentifierEligible(value: []const u8) bool {
    if (!isKeyword(value)) return false;
    for ([_][]const u8{ "crate", "self", "super", "Self", "_" }) |excluded|
        if (std.mem.eql(u8, value, excluded)) return false;
    return true;
}

/// Whether a spelling can be an identifier at all.
///
/// The same shape as Go's rule with one deliberate difference: Go rejects a
/// bare `_` and this does not reject a leading one, because `_name` is an
/// ordinary Rust identifier meaning "deliberately unused" rather than Go's
/// blank. A bare `_` is still rejected -- it is a pattern, not a name.
pub fn isIdentifier(value: []const u8) bool {
    if (value.len == 0 or std.mem.eql(u8, value, "_") or isKeyword(value) or
        !(std.ascii.isAlphabetic(value[0]) or value[0] == '_')) return false;
    for (value[1..]) |character| if (!(std.ascii.isAlphanumeric(character) or character == '_')) return false;
    return true;
}

/// The shape a conversion function a user supplies in a type adapter has to
/// have. Laxer than `isIdentifier`, like Go's, because the spelling names a
/// function that already exists in the user's own crate: only what would
/// break the generated call is rejected.
///
/// Rust's version additionally accepts `::`, because a Rust conversion name
/// is a path -- `MyType::from_raw` is the idiomatic spelling and rejecting it
/// would force every adapter through a free function.
pub fn isConversionFunctionName(name: []const u8) bool {
    if (name.len == 0 or std.ascii.isDigit(name[0])) return false;
    var index: usize = 0;
    while (index < name.len) {
        if (name[index] == ':') {
            // A single colon is not a path separator, and a path may neither
            // begin nor end with one.
            if (index == 0 or index + 1 >= name.len or name[index + 1] != ':') return false;
            if (index + 2 >= name.len) return false;
            index += 2;
            continue;
        }
        if (!(std.ascii.isAlphanumeric(name[index]) or name[index] == '_')) return false;
        index += 1;
    }
    return true;
}

/// Rejects a name that cannot be a Rust crate or module identifier. `Target`
/// answers the same question for whichever target is selected; this spelling
/// exists for `build.zig`, which validates its own options before a target is
/// chosen.
pub fn validateCrateName(name: []const u8) error{InvalidPackageName}!void {
    if (!isIdentifier(name)) return error.InvalidPackageName;
}

test "Rust keyword and identifier checks cover boundaries" {
    for ([_][]const u8{ "raw", "native_api", "_private", "x9", "add", "sum" }) |name|
        try std.testing.expect(isIdentifier(name));
    // `type`, `fn` and `match` are Rust keywords; `9raw` and `raw-name` are
    // not identifiers in any language here.
    for ([_][]const u8{ "", "_", "type", "fn", "match", "become", "9raw", "raw-name" }) |name|
        try std.testing.expect(!isIdentifier(name));
    // Where Go and Rust disagree: `go`, `range` and `func` are Go keywords
    // and ordinary Rust names; `fn`, `let` and `impl` are the reverse.
    for ([_][]const u8{ "go", "range", "func", "chan", "defer" }) |name|
        try std.testing.expect(!isKeyword(name));
    for ([_][]const u8{ "fn", "let", "impl", "unsafe", "Self" }) |name|
        try std.testing.expect(isKeyword(name));
    // Weak keywords are legal identifiers.
    for (weak_keywords) |name| try std.testing.expect(isIdentifier(name));
}

test "raw identifiers are available except for the path keywords" {
    for ([_][]const u8{ "type", "fn", "match", "let", "become" }) |name|
        try std.testing.expect(isRawIdentifierEligible(name));
    for ([_][]const u8{ "crate", "self", "super", "Self" }) |name|
        try std.testing.expect(!isRawIdentifierEligible(name));
    // Not a keyword at all, so there is nothing to escape.
    try std.testing.expect(!isRawIdentifierEligible("values"));
}

test "adapter conversion names accept the paths Rust spells them as" {
    for ([_][]const u8{ "to_raw", "from_raw", "_x", "MyType::from_raw", "crate::conv::of" }) |name|
        try std.testing.expect(isConversionFunctionName(name));
    for ([_][]const u8{ "", "9raw", "to-raw", "a:b", "::leading", "trailing::", "a:::b" }) |name|
        try std.testing.expect(!isConversionFunctionName(name));
}
