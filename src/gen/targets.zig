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
    /// The case a name takes when it is part of the public API.
    exportedNameAlloc: *const fn (allocator: std.mem.Allocator, input: []const u8) anyerror![]u8,
    /// The case a name takes when it is local to a generated body.
    unexportedNameAlloc: *const fn (allocator: std.mem.Allocator, input: []const u8) anyerror![]u8,
    /// The case a module or package name takes.
    packageNameAlloc: *const fn (allocator: std.mem.Allocator, input: []const u8) anyerror![]u8,
    /// The public-name override a declaration carries in its own IR
    /// namespace. `Parameter`, `SemanticFn` and `TypeDecl` each hold one
    /// namespace per target, so this is where a target reads its own.
    nameOverride: *const fn (function: semantic.SemanticFn) ?[]const u8,
    /// Environment variable a generated dynamic-loading package reads before
    /// the shared `ZIGO_LIBRARY_PATH`, so two packages in one process stay
    /// independent.
    libraryPathEnvironmentAlloc: *const fn (allocator: std.mem.Allocator, package: []const u8) anyerror![]u8,
};

/// One output language.
pub const Target = struct {
    /// Stable identifier, as `byName` accepts it.
    name: []const u8,
    /// Extension generated sources carry, with the dot.
    source_extension: []const u8,
    /// Stem suffix marking a file this generator owns.
    generated_suffix: []const u8,
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

    pub fn exportedNameAlloc(self: Target, allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
        return self.vtable.exportedNameAlloc(allocator, input);
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
            if (constructor.name) |name| return self.exportedNameAlloc(allocator, name);
            return std.fmt.allocPrint(allocator, "New{s}", .{constructor.type});
        }
        return self.exportedNameAlloc(allocator, function.name);
    }

    /// Releases names returned by `paramNamesAlloc`. Freeing a name list is
    /// not a language rule, so the one implementation stays in `naming`.
    pub fn freeNames(_: Target, allocator: std.mem.Allocator, names: [][]u8) void {
        naming.freeParamNames(allocator, names);
    }
};

/// Go's implementation. The namespace, not just the `Target` value: the Go
/// emitter under `src/gen/emit/**` is behind this seam and calls the rules
/// directly, so they are reachable as `target.go.<rule>`.
pub const go = @import("targets/go.zig");

/// Every target this build can generate for.
pub const all: []const Target = &.{go.target};

/// The target a caller that names none gets. Selection belongs to the CLI and
/// to the build integration; this is the answer for the layers that run before
/// either has spoken -- the comptime binding walk and the plugin contract --
/// and for the test entry points.
pub const default: Target = go.target;

pub fn byName(name: []const u8) ?Target {
    for (all) |candidate| if (std.mem.eql(u8, candidate.name, name)) return candidate;
    return null;
}

test "targets are addressable by name" {
    try std.testing.expectEqualStrings("go", byName("go").?.name);
    try std.testing.expect(byName("rust") == null);
    try std.testing.expectEqualStrings(default.name, go.target.name);
}

test "package names are rejected when they cannot be an identifier" {
    try default.validatePackageName("native_api");
    try std.testing.expectError(error.InvalidPackageName, default.validatePackageName("type"));
    try std.testing.expectError(error.InvalidPackageName, default.validatePackageName("123"));
}

test {
    std.testing.refAllDecls(go);
}
