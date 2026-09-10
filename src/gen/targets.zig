//! What an output language is, as far as the generator is concerned.
//!
//! The pipeline splits at the C ABI shim. `Zig -> semantic IR -> shim + C
//! header` describes the bound library and knows no output language; only the
//! public package written on top of the shim does. Everything that is true of
//! that language rather than of the library -- its keywords, what it accepts
//! as an identifier or a package name, how it spells a public name, how it
//! names a generated file, and what formats its sources -- is answered here
//! instead of being spread across the emitters and validators.
//!
//! A second output language is a second `Target`. The layers a second language
//! reuses -- validation, reflection, the plugin contract, the generator driver,
//! the CLI and the build integration -- take a `Target` value and never name
//! one. The language's own emitter sits behind this seam: `src/gen/emit/**` is
//! Go's emitter, so it calls `targets/go.zig` directly rather than through a
//! `Target`, because a second language replaces that tree instead of sharing
//! it.
//!
//! Nothing here reaches the C ABI. `naming.isCKeyword` and
//! `naming.cTypeNameAlloc` describe the header, which is the pivot every
//! target shares, so they stay out of `Target` on purpose.
const std = @import("std");
const naming = @import("naming");
const semantic = @import("semantic");

/// How generated sources are formatted. A target without a formatter leaves
/// its output exactly as emitted.
pub const Formatter = struct {
    /// Executable run when the caller passes no override.
    default_executable: []const u8,
    /// Arguments that precede the file list.
    leading_args: []const []const u8,
    /// How the user overrides the executable, as it appears in a diagnostic.
    override_flag: []const u8,
    /// What the user has to install for the default executable to exist.
    install_hint: []const u8,
};

/// The rules one output language answers. Every entry is a language rule, not
/// a convenience: a second target implements this table and nothing else.
pub const VTable = struct {
    /// Reserved words. A derived name that lands on one has to be escaped.
    isKeyword: *const fn (value: []const u8) bool,
    /// Whether a spelling can be an identifier at all.
    isIdentifier: *const fn (value: []const u8) bool,
    /// Whether a spelling can name a conversion function the user supplies in
    /// a type adapter. Deliberately laxer than `isIdentifier`: an adapter
    /// names a function that already exists in the user's package, so the
    /// generator only checks the shape it has to paste into a call.
    isConversionFunctionName: *const fn (value: []const u8) bool,
    /// Public names for one signature's parameters, escaped against keywords,
    /// against the locals the generated bodies introduce, and against each
    /// other. Free with `freeNames`.
    paramNamesAlloc: *const fn (allocator: std.mem.Allocator, zig_names: []const []const u8) anyerror![][]u8,
    /// The case a public *type* name takes. Go spells a public type and a
    /// public function the same way, so both of its answers are
    /// `naming.pascalAlloc`; Rust does not, which is why this is two rules
    /// rather than one. Splitting them here rather than at the call sites is
    /// what keeps the emitters out of it.
    exportedTypeNameAlloc: *const fn (allocator: std.mem.Allocator, input: []const u8) anyerror![]u8,
    /// The case a public *function* name takes.
    exportedFunctionNameAlloc: *const fn (allocator: std.mem.Allocator, input: []const u8) anyerror![]u8,
    /// The case a name takes when it is local to a generated body. No
    /// generator caller reads this today -- Go's emitter reaches
    /// `naming.camelAlloc` directly, being behind this seam -- so it is here
    /// as the rule a target states rather than as a dispatch point.
    unexportedNameAlloc: *const fn (allocator: std.mem.Allocator, input: []const u8) anyerror![]u8,
    /// The case a module or package name takes.
    packageNameAlloc: *const fn (allocator: std.mem.Allocator, input: []const u8) anyerror![]u8,
    /// The public-name override a declaration carries in its own IR
    /// namespace. `Parameter`, `SemanticFn` and `TypeDecl` each hold one
    /// namespace per target, so this is where a target reads its own.
    nameOverride: *const fn (function: semantic.SemanticFn) ?[]const u8,
    setNameOverride: *const fn (function: *semantic.SemanticFn, name: ?[]const u8) void,
    /// Environment variable a generated dynamic-loading package reads before
    /// the shared `ZIGO_LIBRARY_PATH`, so two packages in one process stay
    /// independent.
    libraryPathEnvironmentAlloc: *const fn (allocator: std.mem.Allocator, package: []const u8) anyerror![]u8,
};

/// One output language.
pub const Target = struct {
    /// Stable identifier, as `byName` accepts it.
    name: []const u8,
    /// The language's name as a reader spells it, for diagnostics.
    display_name: []const u8,
    /// Extension generated sources carry, with the dot.
    source_extension: []const u8,
    /// Stem suffix marking a source file this generator owns, so a
    /// hand-written file beside it is never mistaken for one to rewrite.
    generated_suffix: []const u8,
    /// Filename suffix that makes a source file a test file, including the
    /// extension: `_test.go` for Go. Null for a language whose tests are not
    /// a filename convention -- Rust puts them behind `#[cfg(test)]` in the
    /// file they test -- so such a target answers "none" rather than being
    /// pushed into Go's shape.
    test_file_suffix: ?[]const u8,
    formatter: ?Formatter,
    vtable: *const VTable,

    pub fn isKeyword(self: Target, value: []const u8) bool {
        return self.vtable.isKeyword(value);
    }

    pub fn isIdentifier(self: Target, value: []const u8) bool {
        return self.vtable.isIdentifier(value);
    }

    pub fn isConversionFunctionName(self: Target, value: []const u8) bool {
        return self.vtable.isConversionFunctionName(value);
    }

    /// Rejects a name that cannot be a package identifier in this language.
    pub fn validatePackageName(self: Target, name: []const u8) error{InvalidPackageName}!void {
        if (!self.isIdentifier(name)) return error.InvalidPackageName;
    }

    pub fn paramNamesAlloc(self: Target, allocator: std.mem.Allocator, zig_names: []const []const u8) anyerror![][]u8 {
        return self.vtable.paramNamesAlloc(allocator, zig_names);
    }

    pub fn exportedTypeNameAlloc(self: Target, allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
        return self.vtable.exportedTypeNameAlloc(allocator, input);
    }

    pub fn exportedFunctionNameAlloc(self: Target, allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
        return self.vtable.exportedFunctionNameAlloc(allocator, input);
    }

    pub fn unexportedNameAlloc(self: Target, allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
        return self.vtable.unexportedNameAlloc(allocator, input);
    }

    pub fn packageNameAlloc(self: Target, allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
        return self.vtable.packageNameAlloc(allocator, input);
    }

    pub fn nameOverride(self: Target, function: semantic.SemanticFn) ?[]const u8 {
        return self.vtable.nameOverride(function);
    }

    /// The write side of `nameOverride`. A plugin's `name_function` hook runs
    /// in target-neutral code, so the namespace it writes into has to be the
    /// selected target's; writing Go's would leave the name somewhere the
    /// selected target never reads.
    pub fn setNameOverride(self: Target, function: *semantic.SemanticFn, name: ?[]const u8) void {
        self.vtable.setNameOverride(function, name);
    }

    pub fn libraryPathEnvironmentAlloc(self: Target, allocator: std.mem.Allocator, package: []const u8) anyerror![]u8 {
        return self.vtable.libraryPathEnvironmentAlloc(allocator, package);
    }

    /// The public name one bound function is reachable under, ignoring the
    /// receiver: a method's name is scoped by its receiver type, so two
    /// methods on different receivers never collide even when this returns
    /// the same spelling for both. Constructors are the one function shape
    /// whose public name is not simply the exported spelling of the Zig name.
    ///
    /// This is the single rule. The collision check, the `abi-diff` contract
    /// guard and the report all read it from here -- three copies would let a
    /// rename rule silently make them disagree about the same function.
    pub fn publicFunctionNameAlloc(
        self: Target,
        allocator: std.mem.Allocator,
        document: semantic.Semantic,
        function: semantic.SemanticFn,
    ) ![]u8 {
        if (self.nameOverride(function)) |name| return allocator.dupe(u8, name);
        if (semantic.constructorForInit(document.constructors, function)) |constructor| {
            if (constructor.name) |name| return self.exportedFunctionNameAlloc(allocator, name);
            return std.fmt.allocPrint(allocator, "New{s}", .{constructor.type});
        }
        return self.exportedFunctionNameAlloc(allocator, function.name);
    }

    /// Releases names returned by `paramNamesAlloc`. Freeing a name list is
    /// not a language rule, so the one implementation stays in `naming`.
    pub fn freeNames(_: Target, allocator: std.mem.Allocator, names: [][]u8) void {
        naming.freeParamNames(allocator, names);
    }

    /// The file one generated source is written to: `<stem>_gen.go` for Go.
    /// The caller composes the stem, which is a question about the package
    /// layout; the suffix and the extension are the language's.
    pub fn generatedFileNameAlloc(self: Target, allocator: std.mem.Allocator, stem: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ stem, self.generated_suffix, self.source_extension });
    }

    /// Whether a path is a source file in this language, which is what decides
    /// whether the formatter is offered it and how the output manifest
    /// classifies it.
    pub fn isSource(self: Target, path: []const u8) bool {
        return std.mem.endsWith(u8, path, self.source_extension);
    }

    /// Whether a path names a test file. A language with no test-file naming
    /// convention has no such path, so every file is an ordinary source file.
    pub fn isTestFile(self: Target, path: []const u8) bool {
        const suffix = self.test_file_suffix orelse return false;
        return std.mem.endsWith(u8, path, suffix);
    }

    /// Whether `path` has the shape a file of `kind` must have in this
    /// language. A target with no test-file convention cannot express the
    /// distinction, so it accepts any source file for either kind.
    pub fn fileNameMatchesKind(self: Target, path: []const u8, is_test: bool) bool {
        if (!self.isSource(path)) return false;
        if (self.test_file_suffix == null) return true;
        return self.isTestFile(path) == is_test;
    }
};

/// Go's implementation. The namespace, not just the `Target` value: the Go
/// emitter under `src/gen/emit/**` is behind this seam and calls the rules
/// directly, so they are reachable as `target.go.<rule>`.
pub const go = @import("targets/go.zig");

/// Rust's implementation, on the same terms as `go`: the namespace, because
/// the Rust emitter under `src/gen/emit_rust/**` is behind this seam too and
/// reaches its rules directly.
pub const rust = @import("targets/rust.zig");

/// Every target this build can generate for.
pub const all: []const Target = &.{ go.target, rust.target };

/// The target a caller that names none gets. Selection belongs to the CLI and
/// to the build integration; this is the answer for the layers that run before
/// either has spoken -- the comptime binding walk and the plugin contract --
/// and for the test entry points.
pub const default: Target = go.target;

pub fn byName(name: []const u8) ?Target {
    for (all) |candidate| if (std.mem.eql(u8, candidate.name, name)) return candidate;
    return null;
}

test "generated file names carry the language's suffix and extension" {
    const name = try default.generatedFileNameAlloc(std.testing.allocator, "event_queue_enums");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("event_queue_enums_gen.go", name);
    try std.testing.expect(default.isSource("a/b_gen.go"));
    try std.testing.expect(!default.isSource("a/b.zig"));
}

test "Go answers the type rule and the function rule identically" {
    // The seam separates two rules because Rust needs them separate. Go
    // spells a public type and a public function the same way, so this is the
    // check that the split cannot move a byte of generated Go.
    for ([_][]const u8{ "lookupID", "pushEvent", "add", "parse_url" }) |name| {
        const type_name = try default.exportedTypeNameAlloc(std.testing.allocator, name);
        defer std.testing.allocator.free(type_name);
        const function_name = try default.exportedFunctionNameAlloc(std.testing.allocator, name);
        defer std.testing.allocator.free(function_name);
        try std.testing.expectEqualStrings(type_name, function_name);
        const pascal = try naming.pascalAlloc(std.testing.allocator, name);
        defer std.testing.allocator.free(pascal);
        try std.testing.expectEqualStrings(pascal, function_name);
    }
}

test "targets are addressable by name" {
    try std.testing.expectEqualStrings("go", byName("go").?.name);
    try std.testing.expectEqualStrings("rust", byName("rust").?.name);
    try std.testing.expect(byName("zig") == null);
    // Naming no target still gets Go, so nothing that ran before Rust existed
    // changes behaviour by Rust existing.
    try std.testing.expectEqualStrings(default.name, go.target.name);
}

test "every target answers every rule" {
    // A target added without an answer is a compile error, not a runtime
    // surprise, because `VTable` has no defaults. This walk is here for the
    // parts `Target` derives rather than dispatches: a target whose extension
    // or display name were empty would produce unusable paths and diagnostics.
    for (all) |candidate| {
        try std.testing.expect(candidate.name.len != 0);
        try std.testing.expect(candidate.display_name.len != 0);
        try std.testing.expect(std.mem.startsWith(u8, candidate.source_extension, "."));
        const file = try candidate.generatedFileNameAlloc(std.testing.allocator, "sample");
        defer std.testing.allocator.free(file);
        try std.testing.expect(candidate.isSource(file));
    }
}

test "package names are rejected when they cannot be an identifier" {
    try default.validatePackageName("native_api");
    try std.testing.expectError(error.InvalidPackageName, default.validatePackageName("type"));
    try std.testing.expectError(error.InvalidPackageName, default.validatePackageName("123"));
}

test {
    std.testing.refAllDecls(go);
    std.testing.refAllDecls(rust);
}
