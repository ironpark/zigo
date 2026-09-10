//! Rust's answers to `Target`, plus the Rust-only naming rules its emitter
//! uses directly. Everything here is true of Rust rather than of the bound
//! Zig library; nothing here describes the C ABI, which every target shares.
//!
//! The counterpart of `targets/go.zig`, written against the same `Target`
//! record. Where the two disagree, the comment says why Rust's answer differs
//! rather than leaving the difference to be inferred.
const std = @import("std");
const naming = @import("naming");
const semantic = @import("semantic");
const target_api = @import("../targets.zig");
/// The `std`-only leaf. Public so the Rust emitter can reach the word rules
/// through the `targets` module: `targets.zig` owns these files, so an
/// emitter importing them by relative path would put one file in two modules.
pub const words = @import("rust_words.zig");

pub const target: target_api.Target = .{
    .name = "rust",
    .display_name = "Rust",
    .source_extension = ".rs",
    // Empty, where Go uses `_gen`. Go's suffix keeps a generated file from
    // being confused with a hand-written one in the same package directory;
    // generated Rust lives in its own `src/` directory under the output root,
    // where nothing hand-written sits beside it, so the suffix would only make
    // `raw_gen.rs` harder to `mod`-declare.
    .generated_suffix = "",
    // Null on purpose. Go makes a test file by naming it `_test.go`; Rust puts
    // its tests behind `#[cfg(test)]` in the file they test, so Rust has no
    // filename to answer with and says so rather than being pushed into Go's
    // shape.
    .test_file_suffix = null,
    .formatter = .{
        .default_executable = "rustfmt",
        // The edition is explicit because `rustfmt` invoked without one
        // assumes 2015, where `dyn`, `async` and `await` are not keywords and
        // `extern crate` is still required.
        .leading_args = &.{ "--edition", "2021" },
        .override_flag = "--rustfmt <path>",
        .install_hint = "install a Rust toolchain",
    },
    .vtable = &.{
        .isKeyword = isKeyword,
        .isIdentifier = isIdentifier,
        .isConversionFunctionName = isConversionFunctionName,
        .paramNamesAlloc = vtParamNamesAlloc,
        // The rule the target seam had to split. Rust spells a public type
        // `PascalCase` and a public function `snake_case`, so unlike Go these
        // are two different answers.
        .exportedTypeNameAlloc = vtExportedTypeNameAlloc,
        .exportedFunctionNameAlloc = vtExportedFunctionNameAlloc,
        .unexportedNameAlloc = vtUnexportedNameAlloc,
        .packageNameAlloc = vtPackageNameAlloc,
        .nameOverride = nameOverride,
        .constructorNameAlloc = vtConstructorNameAlloc,
        .setNameOverride = setNameOverride,
        .libraryPathEnvironmentAlloc = vtLibraryPathEnvironmentAlloc,
    },
};

// The vtable is a table of `anyerror` function pointers, and the rules below
// infer narrower error sets. These adapters are that widening and nothing
// else, so a direct caller keeps the narrow set.
fn vtParamNamesAlloc(allocator: std.mem.Allocator, zig_names: []const []const u8) anyerror![][]u8 {
    return paramNamesAlloc(allocator, zig_names);
}

fn vtExportedTypeNameAlloc(allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
    return typeNameAlloc(allocator, input);
}

fn vtExportedFunctionNameAlloc(allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
    return naming.snakeAlloc(allocator, input);
}

fn vtUnexportedNameAlloc(allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
    return naming.snakeAlloc(allocator, input);
}

fn vtPackageNameAlloc(allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
    return naming.snakeAlloc(allocator, input);
}

fn vtLibraryPathEnvironmentAlloc(allocator: std.mem.Allocator, package: []const u8) anyerror![]u8 {
    return naming.libraryPathEnvironmentAlloc(allocator, package);
}

/// Rust's word-level rules live in `rust_words.zig`, which imports only `std`
/// so that `build.zig` can reach them too. They are re-exported here so a
/// reader of the Rust target finds every rule in one namespace.
pub const isKeyword = words.isKeyword;
pub const isIdentifier = words.isIdentifier;
pub const isConversionFunctionName = words.isConversionFunctionName;
pub const isRawIdentifierEligible = words.isRawIdentifierEligible;

/// Rust's public type spelling: `PascalCase` with no initialism table.
///
/// Go maps `id` -> `ID`, `url` -> `URL` and `utf8` -> `UTF8` because Go's
/// style guide asks for it. Rust's asks for the opposite -- `Id`, `Url`,
/// `Utf8` -- so this passes an empty table to the same transform. That is the
/// whole of the initialism difference plan 186 deferred; in the minimal
/// backend it is reachable only through error-variant names, since bound
/// functions take the snake_case path, which has no table.
pub fn typeNameAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return naming.pascalWithInitialismsAlloc(allocator, input, &.{});
}

fn vtConstructorNameAlloc(allocator: std.mem.Allocator, type_name: []const u8, declared_name: ?[]const u8) anyerror![]u8 {
    return constructorNameAlloc(allocator, type_name, declared_name);
}

/// Rust's constructor spelling: `new`, or the snake spelling of the name the
/// binding asked for.
///
/// The type is not in the name. A Rust constructor is an associated function
/// reached as `Context::new()`, so the path already says which type is being
/// constructed and Go's `NewContext` would spell `Context::new_context`.
/// `new` is the convention Rust's own API guidelines state for the primary
/// constructor.
pub fn constructorNameAlloc(
    allocator: std.mem.Allocator,
    type_name: []const u8,
    declared_name: ?[]const u8,
) ![]u8 {
    _ = type_name;
    if (declared_name) |name| return naming.snakeAlloc(allocator, name);
    return allocator.dupe(u8, "new");
}

/// The public Rust spelling of a function's name override, read from the
/// `rust` namespace the declaration carries.
fn setNameOverride(function: *semantic.SemanticFn, name: ?[]const u8) void {
    function.setRustName(name);
}

fn nameOverride(function: semantic.SemanticFn) ?[]const u8 {
    return function.rustName();
}

/// Names the generated Rust bodies introduce, which a parameter must not
/// shadow. A different table from Go's, not a translation of it: the Rust
/// bodies bind `code`, the out-parameter pair and `result`, and they never
/// introduce `self` (a method takes it as a receiver, which cannot collide
/// with a named parameter) or Go's `callbackHandle`.
const reserved_locals = [_][]const u8{
    "code",           "result",         "out_result",
    "out_result_ptr", "out_result_len",
};

/// Public Rust names for one signature's parameters. Zig already spells
/// parameters in snake_case, so the case conversion is usually a no-op and
/// the work is the escaping: a name that lands on a Rust keyword, shadows a
/// generated local, or repeats an earlier parameter has to move.
///
/// A keyword takes the `r#` raw-identifier escape rather than Go's trailing
/// `_`. `r#type` reads as the parameter the Zig author named `type`, where
/// `type_` reads as a different name that happens to be close, so the raw form
/// keeps the public signature honest about the binding. The four path keywords
/// (`crate`, `self`, `super`, `Self`) cannot be spelled `r#`, so those fall
/// back to the trailing underscore -- which is also what shadowing and
/// duplication use, since neither is a keyword problem and `r#` would not help.
pub fn paramNamesAlloc(allocator: std.mem.Allocator, zig_names: []const []const u8) ![][]u8 {
    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }
    for (zig_names) |zig_name| {
        var candidate = try naming.snakeAlloc(allocator, zig_name);
        if (isKeyword(candidate)) {
            const previous = candidate;
            defer allocator.free(previous);
            candidate = if (isRawIdentifierEligible(previous))
                try std.fmt.allocPrint(allocator, "r#{s}", .{previous})
            else
                try std.fmt.allocPrint(allocator, "{s}_", .{previous});
        } else if (isReservedLocal(candidate)) {
            const previous = candidate;
            defer allocator.free(previous);
            candidate = try std.fmt.allocPrint(allocator, "{s}_", .{previous});
        }
        var suffix: usize = 2;
        while (naming.containsName(names.items, candidate)) : (suffix += 1) {
            const previous = candidate;
            defer allocator.free(previous);
            candidate = try std.fmt.allocPrint(allocator, "{s}{d}", .{ previous, suffix });
        }
        try names.append(allocator, candidate);
    }
    return names.toOwnedSlice(allocator);
}

fn isReservedLocal(value: []const u8) bool {
    for (reserved_locals) |reserved| if (std.mem.eql(u8, value, reserved)) return true;
    return false;
}

test "Rust splits the exported-name rule where Go does not" {
    const cases = [_]struct { zig: []const u8, type_name: []const u8, function: []const u8 }{
        .{ .zig = "add", .type_name = "Add", .function = "add" },
        .{ .zig = "pushEvent", .type_name = "PushEvent", .function = "push_event" },
        .{ .zig = "EventQueue", .type_name = "EventQueue", .function = "event_queue" },
    };
    for (cases) |case| {
        const type_name = try target.exportedTypeNameAlloc(std.testing.allocator, case.zig);
        defer std.testing.allocator.free(type_name);
        try std.testing.expectEqualStrings(case.type_name, type_name);
        const function = try target.exportedFunctionNameAlloc(std.testing.allocator, case.zig);
        defer std.testing.allocator.free(function);
        try std.testing.expectEqualStrings(case.function, function);
    }
}

test "Rust and Go disagree about initialisms and about function case" {
    const go = @import("go.zig");
    const cases = [_]struct { zig: []const u8, go_name: []const u8, rust_type: []const u8, rust_fn: []const u8 }{
        .{ .zig = "lookupID", .go_name = "LookupID", .rust_type = "LookupId", .rust_fn = "lookup_id" },
        .{ .zig = "parseURL", .go_name = "ParseURL", .rust_type = "ParseUrl", .rust_fn = "parse_url" },
        .{ .zig = "validateUTF8", .go_name = "ValidateUTF8", .rust_type = "ValidateUtf8", .rust_fn = "validate_utf8" },
    };
    for (cases) |case| {
        const go_name = try go.target.exportedTypeNameAlloc(std.testing.allocator, case.zig);
        defer std.testing.allocator.free(go_name);
        try std.testing.expectEqualStrings(case.go_name, go_name);
        const rust_type = try target.exportedTypeNameAlloc(std.testing.allocator, case.zig);
        defer std.testing.allocator.free(rust_type);
        try std.testing.expectEqualStrings(case.rust_type, rust_type);
        const rust_fn = try target.exportedFunctionNameAlloc(std.testing.allocator, case.zig);
        defer std.testing.allocator.free(rust_fn);
        try std.testing.expectEqualStrings(case.rust_fn, rust_fn);
    }
}

test "Rust parameter names are snake_case and escape keywords, locals and duplicates" {
    const zig_names = [_][]const u8{
        // Ordinary; already snake_case.
        "source_len",
        // A Rust keyword eligible for the raw form.
        "type",
        // A Go keyword that is an ordinary Rust name, so it must not move.
        "range",
        // A path keyword, which `r#` cannot escape.
        "self",
        // A generated local.
        "code",
        // Not a Rust local, unlike Go, where `outResult` is one.
        "out_result",
        // camelCase input, and then the same name twice.
        "newName",
        "new_name",
    };
    const names = try paramNamesAlloc(std.testing.allocator, &zig_names);
    defer target.freeNames(std.testing.allocator, names);
    const expected = [_][]const u8{
        "source_len", "r#type",      "range",    "self_",
        "code_",      "out_result_", "new_name", "new_name2",
    };
    for (expected, names) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "the Rust name override reads its own namespace" {
    var function: semantic.SemanticFn = .{ .name = "add", .@"return" = .void, .params = &.{}, .symbol = "zg_add" };
    try std.testing.expect(target.nameOverride(function) == null);
    // Go's override must not be visible through Rust's namespace, which is
    // the whole reason the two are siblings rather than one shared field.
    function.setGoName("Plus");
    try std.testing.expect(target.nameOverride(function) == null);
    function.setRustName("plus");
    try std.testing.expectEqualStrings("plus", target.nameOverride(function).?);
    try std.testing.expectEqualStrings("Plus", @import("go.zig").target.nameOverride(function).?);
    // `compact` must drop the namespace again so a cleared override serializes
    // to nothing.
    function.setRustName(null);
    try std.testing.expect(function.rust == null);
}

test "Rust generated file names carry no stem suffix" {
    const name = try target.generatedFileNameAlloc(std.testing.allocator, "raw");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("raw.rs", name);
    try std.testing.expect(target.isSource("src/lib.rs"));
    try std.testing.expect(!target.isSource("src/lib.go"));
    // With no test-file convention, no path is a test file and either kind of
    // source file is accepted.
    try std.testing.expect(!target.isTestFile("src/lib.rs"));
    try std.testing.expect(target.fileNameMatchesKind("src/lib.rs", true));
    try std.testing.expect(target.fileNameMatchesKind("src/lib.rs", false));
}
