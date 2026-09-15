//! `buildinfo`: one native symbol, wrapped for Go and for Rust.
//!
//! Every other shipped plugin renders out of the document -- it reads a
//! declaration and writes a method beside it. This one has nothing to read:
//! what it publishes is a fact about the native library, which only native
//! code can answer. So it ships a Zig source, declares the C symbol that
//! stands behind it, and each render slot wraps that symbol in the one
//! function its language would want.
//!
//! It is the reference for the native half of the plugin contract, and small
//! on purpose: one source, one symbol, one wrapper per target.
const std = @import("std");
const abi = @import("abi");
const plugin_api = @import("plugin");
const semantic = @import("semantic");

pub const name = "BUILDINFO";

/// What a build says with `.config = zigo.configJson(b, buildinfo.Config{ ... })`.
pub const Config = struct {
    /// Contribute the symbol and its wrappers at all. Off leaves the native
    /// library, the C header and both raw layers exactly as they were, which
    /// is what a build that ships the bindings but not the provenance wants.
    enabled: bool = true,
};

pub const plugin: plugin_api.Plugin = .{
    .name = name,
    .Config = Config,
    // Nothing. This plugin attaches to no declaration: it contributes at the
    // package boundary, out of the native library rather than out of the
    // document, so there is no node whose `ext` it would read.
    .subjects = &.{},
    .go = .{ .source_files = &.{.{ .enabled = enabledGo, .scope = .document, .pathAlloc = goPath, .render = renderGo }} },
    .rust = .{ .source_files = &.{.{ .enabled = enabledRust, .module = "buildinfo", .render = renderRust }} },
    // The native half is target-neutral: the shim compiles this source and
    // exports the symbol whichever language is being generated from the
    // document. The two slots above are what wrap it.
    .native = .{
        .sources = &.{.{ .path = "native.zig", .module = "buildinfo_native" }},
        .symbols = nativeSymbols,
    },
};

/// The one symbol, or none when the build turned the plugin off. Returning
/// nothing rather than leaving the declaration in place is what keeps a
/// disabled plugin out of the C header and both raw layers, and out of
/// `abi-diff`'s record of what this binding exports.
fn nativeSymbols(context: plugin_api.NativeContext) ![]const plugin_api.NativeSymbol {
    if (!(try context.config(plugin)).enabled) return &.{};
    return &.{.{
        .name = "build_info",
        // The one non-scalar a plugin symbol may return. `native.zig` builds
        // the string at comptime, so the pointer outlives every call.
        .ret = plugin_api.c_string,
        .implementation = "buildInfo",
        .doc = "How the native library behind this binding was built.",
    }};
}

fn enabledGo(context: plugin_api.GoContext) !bool {
    return (try context.config(plugin)).enabled;
}

fn enabledRust(context: plugin_api.RustContext) !bool {
    return (try context.config(plugin)).enabled;
}

fn goPath(context: plugin_api.GoContext) ![]u8 {
    return plugin_api.publicFilePathAlloc(context.allocator, context.program, context.options, "zigo_buildinfo_gen.go");
}

/// `func BuildInfo() string`, in one file of the binding's own package.
///
/// The raw layer already hands back a `string`: a C-string result is copied
/// out of native memory there, by `C.GoString` under cgo and by the purego
/// backend's own NUL scan without it. So the wrapper is the call and nothing
/// else -- there is no pointer for this file to spell, and no import beyond
/// the raw package the builder adds itself.
fn renderGo(context: plugin_api.GoContext, writer: *std.Io.Writer) !void {
    const symbols = try context.nativeSymbols(plugin);
    if (symbols.len == 0) return;
    const b = context.builder();
    try b.render(writer, &.{try b.func(.{
        .doc = .{ .text = "BuildInfo reports how the native library behind this binding was built:\nthe Zig version, the optimize mode and the target triple." },
        .name = "BuildInfo",
        .signature = .{ .explicit = .{ .results = &.{b.ident("string")} } },
        .body = &.{try b.ret(&.{try b.rawCall(symbols[0].symbol, &.{})})},
        .single_line = true,
    })}, .{});
}

/// The same wrapper for the crate. The raw module borrows the C string as
/// `&'static str`, again because the plugin contract says the bytes live as
/// long as the process, so this side spells no pointer and no `unsafe` block.
fn renderRust(context: plugin_api.RustContext, writer: *std.Io.Writer) !void {
    const symbols = try context.nativeSymbols(plugin);
    if (symbols.len == 0) return;
    const b = context.builder();
    try b.render(writer, &.{try b.func(.{
        .doc = .{ .text = "How the native library behind this binding was built: the Zig version,\nthe optimize mode and the target triple." },
        .visibility = .public,
        .name = "build_info",
        .signature = .{ .explicit = .{ .result = b.path("&'static str") } },
        .body = &.{b.tail(try b.rawCall(symbols[0].symbol, &.{}))},
    })}, .{});
}

/// The lowered symbol a render slot is handed, built by hand: the generator's
/// `native.zig` mints exactly this out of `nativeSymbols` above, and the two
/// tests below need a program that already contains it.
var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
const lowered_origin: semantic.SemanticFn = .{
    .name = "buildinfo_build_info",
    .params = &.{},
    .@"return" = .{ .slice = .{ .@"const" = true, .element = &byte } },
    .return_semantic = .c_string,
    .symbol = "zg_buildinfo_build_info",
    .custom_symbol = true,
    .plugin = .{ .plugin = name, .module = "buildinfo_native", .implementation = "buildInfo" },
};
const lowered: []const abi.AbiFn = &.{.{
    .symbol = "zg_buildinfo_build_info",
    .params = &.{},
    .ret = plugin_api.c_string,
    .ret_string = .c_string,
    .origin = &lowered_origin,
}};

fn testDocument() semantic.Semantic {
    return .{ .package = "calculator", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{}, .types = &.{} };
}

fn testProgram() abi.Program {
    return .{ .package = "calculator", .prefix = "zg", .functions = lowered };
}

test "a symbol is declared unless the build turned the plugin off" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const declared = try nativeSymbols(.{ .allocator = allocator, .document = testDocument() });
    try std.testing.expectEqual(@as(usize, 1), declared.len);
    try std.testing.expectEqualStrings("build_info", declared[0].name);
    try std.testing.expectEqualStrings("buildInfo", declared[0].implementation);
    try std.testing.expect(plugin_api.isNativeCString(declared[0].ret));
    // The signature `semantic.json` records, which is what `abi-diff` compares.
    const signature = try plugin_api.nativeSignatureAlloc(allocator, declared[0]);
    try std.testing.expectEqualStrings("c_string()", signature);

    const off = try nativeSymbols(.{
        .allocator = allocator,
        .document = testDocument(),
        .configurations = &.{.{ .name = name, .json = "{\"enabled\":false}" }},
    });
    try std.testing.expectEqual(@as(usize, 0), off.len);
}

test "the Go wrapper is the raw call and nothing else" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try renderGo(plugin_api.testing.goContext(arena.allocator(), testProgram()), &output.writer);
    try std.testing.expectEqualStrings(
        \\// BuildInfo reports how the native library behind this binding was built:
        \\// the Zig version, the optimize mode and the target triple.
        \\func BuildInfo() string { return raw.BuildinfoBuildInfo() }
        \\
    , output.written());
}

test "the Rust wrapper borrows the same string through the crate's raw module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try renderRust(plugin_api.testing.rustContext(arena.allocator(), testProgram()), &output.writer);
    try std.testing.expectEqualStrings(
        \\/// How the native library behind this binding was built: the Zig version,
        \\/// the optimize mode and the target triple.
        \\pub fn build_info() -> &'static str {
        \\    crate::raw::buildinfo_build_info()
        \\}
        \\
    , output.written());
}
