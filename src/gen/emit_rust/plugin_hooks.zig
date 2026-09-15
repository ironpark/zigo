//! Where the registered plugins get to write in the Rust crate. The sibling
//! of `emit/plugin_hooks.zig`, walking the same `Node` order and flushing at
//! the crate's equivalent insertion points: after each generated `impl`
//! method, after each type item, at the boundaries of every emitted `.rs`
//! file, and into `src/zigo_plugins.rs` for the package boundaries.
//!
//! Duplicated rather than abstracted. The two walks agree on the node order
//! and on nothing else -- Go flushes at top level into a package of many
//! files, Rust flushes inside an `impl` block into a crate of fixed ones --
//! and a shared walker would have to take both insertion models as
//! parameters, which is the pair of files again with a layer on top.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const emit = @import("../emit/emit.zig");
const plugin = @import("plugin");
const raw = @import("raw.zig");
const registry = @import("../plugins/registry.zig");
const rust_writers = @import("rust_writers.zig");
const semantic = @import("semantic");
const types = @import("types.zig");

/// The context a `type` node, a crate file or a plugin module sees.
pub fn context(allocator: std.mem.Allocator, program: abi.Program, options: emit.Options) plugin.RustContext {
    return .{ .allocator = allocator, .program = program, .options = options.view(), .facts = options.facts, .writers = &rust_writers.writers };
}

/// The context the nodes inside a generated item see: the same, plus the
/// names that item was written with.
pub fn methodContext(
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: emit.Options,
    method: plugin.Method,
) plugin.RustContext {
    var value = context(allocator, program, options);
    value.method = method;
    return value;
}

/// The plugin's Rust render slot, or an empty one when it renders no Rust.
pub fn rustSlot(comptime registered: plugin.Plugin) plugin.RustRender {
    return registered.rust orelse .{};
}

/// Whether the plugin at `index` writes for this generation.
pub fn runs(comptime index: usize, options: emit.Options) bool {
    return registry.runs(index, options.plugins, options.target);
}

/// Whether `registered` declared the subject this node belongs to. A file or
/// package boundary has no subject, so every plugin sees it.
fn attaches(comptime registered: plugin.Plugin, node: plugin.Node) bool {
    return registered.supports(node.subject() orelse return true);
}

/// Offers one node to every registered plugin that attaches to it, in
/// registration order, and flushes what each built into `writer`.
fn visitNode(options: emit.Options, value: plugin.RustContext, writer: *std.Io.Writer, node: plugin.Node) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (comptime rustSlot(registered).visit) |hook| {
            if (attaches(registered, node) and runs(index, options)) {
                var builder = value.builder();
                builder.out = writer;
                try hook(value, node, &builder);
            }
        }
    }
}

/// A public function or method: the function itself, then each of its
/// parameters, then its result, which share the insertion point the item's
/// body ended at.
pub fn visitFunction(options: emit.Options, value: plugin.RustContext, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    try visitNode(options, value, writer, .{ .function = function });
    for (function.origin.params, 0..) |_, index|
        try visitNode(options, value, writer, .{ .param = .{ .function = function, .index = index } });
    try visitNode(options, value, writer, .{ .result = function });
}

/// The same, re-indented by `depth` levels, which is what an item written
/// inside an `impl` block needs. The visit renders at the crate's top level
/// and the indentation is added here, the way `handles.renderAssociated`
/// already re-indents a shared body.
pub fn visitFunctionIndented(
    allocator: std.mem.Allocator,
    options: emit.Options,
    value: plugin.RustContext,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    depth: usize,
) !void {
    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();
    try visitFunction(options, value, &body.writer, function);
    try writeIndented(writer, body.written(), depth);
}

/// `text` with `depth` levels of four spaces added to every non-empty line.
pub fn writeIndented(writer: *std.Io.Writer, text: []const u8, depth: usize) !void {
    if (text.len == 0) return;
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, text, "\n"), '\n');
    while (lines.next()) |line| {
        if (line.len != 0) try writer.splatByteAll(' ', depth * 4);
        try writer.print("{s}\n", .{line});
    }
}

/// A type declaration and the members inside it, after the crate wrote the
/// type. A registered enum's members are tags; every other kind's are fields.
pub fn visitType(options: emit.Options, value: plugin.RustContext, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    try visitNode(options, value, writer, .{ .type = declaration });
    for (declaration.fields, 0..) |_, index| {
        const member: plugin.Node.Member = .{ .declaration = declaration, .index = index };
        try visitNode(options, value, writer, if (declaration.kind == .@"enum")
            .{ .enum_tag = member }
        else
            .{ .field = member });
    }
}

/// A crate file's body boundaries. A file the emitter gave no `FileInfo` has
/// no boundary to offer.
pub fn visitFileBegin(options: emit.Options, value: plugin.RustContext, writer: *std.Io.Writer) !void {
    const file = value.options.file orelse return;
    return visitNode(options, value, writer, .{ .file_begin = file });
}

pub fn visitFileEnd(options: emit.Options, value: plugin.RustContext, writer: *std.Io.Writer) !void {
    const file = value.options.file orelse return;
    return visitNode(options, value, writer, .{ .file_end = file });
}

/// The crate's own plugin module, `src/zigo_plugins.rs`: both boundaries in
/// one body, since nothing of the generator's sits between them.
pub fn visitPackage(options: emit.Options, value: plugin.RustContext, writer: *std.Io.Writer) !void {
    try visitNode(options, value, writer, .package_begin);
    try visitNode(options, value, writer, .package_end);
}

/// The `pub(crate)` name the generated item takes when a plugin claims this
/// declaration's public surface. In the reserved `zigo` namespace, so it
/// cannot collide with anything the binding or a plugin names.
pub fn checkedNameAlloc(allocator: std.mem.Allocator, public_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "zigo_checked_{s}", .{public_name});
}

/// Whether a plugin claimed this declaration's public surface. Two claims on
/// one declaration are refused in `analyze`, so the first answer is the only
/// one.
pub fn claimed(options: emit.Options, value: plugin.RustContext, function: abi.AbiFn) !bool {
    const node: plugin.Node = .{ .function = function };
    inline for (registry.plugins, 0..) |registered, index| {
        if (comptime rustSlot(registered).claims) |claims| {
            if (registered.supports(.function) and runs(index, options) and try claims(value, node)) return true;
        }
    }
    return false;
}

/// The names a Rust hook is told the generated item used.
pub fn methodFor(
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: emit.Options,
    value: plugin.RustContext,
    function: abi.AbiFn,
    /// The name the generated item was written under, which is the raw
    /// wrapper's name for a free function and the associated name for a
    /// method or a constructor.
    name: []const u8,
    receiver_type: ?[]const u8,
) !plugin.Method {
    const shape = try raw.Shape.of(allocator, program, function);
    defer shape.deinit(allocator);
    const public_name = try allocator.dupe(u8, name);
    const names = try allocator.alloc([]u8, function.origin.params.len);
    for (names, function.origin.params) |*slot, parameter| slot.* = try allocator.dupe(u8, parameter.name);
    return .{
        .public_name = public_name,
        .checked_name = if (try claimed(options, value, function)) try checkedNameAlloc(allocator, public_name) else public_name,
        .receiver = receiver_type,
        .receiver_name = if (shape.receiver != null) "self" else null,
        .param_names = names,
        .needs_check = shape.declares_errors,
    };
}

/// The plugin analyses, run once with the Rust context in hand, and the claim
/// rules that can only be answered after them.
pub fn analyze(
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: emit.Options,
    facts: *plugin.Facts,
    diagnostics: *std.ArrayList(diagnostic.Diagnostic),
) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.analyze) |check| {
            if (runs(index, options)) {
                const value = context(allocator, program, options);
                try check(.{ .render = value.base(), .rust = value, .facts = facts, .diagnostics = diagnostics });
            }
        }
    }
    try checkClaims(allocator, program, options, diagnostics);
}

/// What `claims` is allowed to answer for, under Go's two rules: one public
/// item has one owner, and only a function node has a public item at all.
fn checkClaims(
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: emit.Options,
    diagnostics: *std.ArrayList(diagnostic.Diagnostic),
) !void {
    const value = context(allocator, program, options);
    for (program.functions) |function| {
        var claimant: ?[]const u8 = null;
        const node: plugin.Node = .{ .function = function };
        inline for (registry.plugins, 0..) |registered, index| {
            if (comptime rustSlot(registered).claims) |claims| {
                if (registered.supports(.function) and runs(index, options) and try claims(value, node)) {
                    if (claimant) |first| {
                        const path = try plugin.site.functionDeclarationAlloc(allocator, function.origin.*);
                        try diagnostics.append(allocator, .{
                            .severity = .@"error",
                            .code = "ZIGO024",
                            .message = try std.fmt.allocPrint(allocator, "plugins `{s}` and `{s}` both replace the public Rust surface of `{s}`", .{ first, registered.name, path }),
                            .site = plugin.site.functionSiteFor(function.origin.*, path),
                            .hint = "one declaration has one public item; disable one of the plugins for it",
                        });
                    } else claimant = registered.name;
                }
            }
        }
        for (function.origin.params, 0..) |_, index|
            try refuseClaim(allocator, value, options, diagnostics, .{ .param = .{ .function = function, .index = index } });
        try refuseClaim(allocator, value, options, diagnostics, .{ .result = function });
    }
    for (program.types) |declaration| {
        try refuseClaim(allocator, value, options, diagnostics, .{ .type = declaration });
        for (declaration.fields, 0..) |_, index| {
            const member: plugin.Node.Member = .{ .declaration = declaration, .index = index };
            try refuseClaim(allocator, value, options, diagnostics, if (declaration.kind == .@"enum")
                .{ .enum_tag = member }
            else
                .{ .field = member });
        }
    }
}

/// A claim on a node that has no public Rust surface of its own.
fn refuseClaim(
    allocator: std.mem.Allocator,
    value: plugin.RustContext,
    options: emit.Options,
    diagnostics: *std.ArrayList(diagnostic.Diagnostic),
    node: plugin.Node,
) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (comptime rustSlot(registered).claims) |claims| {
            if (attaches(registered, node) and runs(index, options) and try claims(value, node)) {
                const site = try node.site(value.base());
                try diagnostics.append(allocator, .{
                    .severity = .@"error",
                    .code = "ZIGO065",
                    .message = try std.fmt.allocPrint(allocator, "plugin `{s}` claims the `{s}` node `{s}`, which has no public Rust surface of its own", .{ registered.name, @tagName(node), site.declaration }),
                    .site = site,
                    .hint = "`claims` answers for a function node; leave every other node to `visit`",
                });
            }
        }
    }
}

/// The crate's plugin module body, which is empty when no plugin wrote at a
/// package boundary. The caller owns the result.
pub fn packageBodyAlloc(allocator: std.mem.Allocator, program: abi.Program, options: emit.Options) ![]u8 {
    var file_options = options;
    file_options.file = .{ .path = package_module_path, .owner = "plugins", .kind = .package };
    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();
    try visitPackage(file_options, context(allocator, program, file_options), &body.writer);
    return allocator.dupe(u8, body.written());
}

/// The module every package-scoped plugin contribution lands in.
pub const package_module = "zigo_plugins";
pub const package_module_path = "src/" ++ package_module ++ ".rs";

/// `lib.rs`'s declarations of the modules the plugins add: one per enabled
/// `rust` source file, then the package module when anything wrote into it.
/// Re-exported with a glob, so a plugin's public item is reachable from the
/// crate root the way a generated one is.
pub fn writeModuleDeclarations(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: emit.Options,
) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        inline for (comptime rustSlot(registered).source_files) |file| {
            if (runs(index, options) and try sourceFileEnabled(allocator, program, options, file)) {
                try writer.print("\nmod {0s};\npub use {0s}::*;\n", .{file.module});
            }
        }
    }
    const body = try packageBodyAlloc(allocator, program, options);
    defer allocator.free(body);
    if (body.len != 0) try writer.print("\nmod {0s};\npub use {0s}::*;\n", .{package_module});
}

/// Whether one plugin module is written at all.
pub fn sourceFileEnabled(
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: emit.Options,
    comptime file: plugin.RustSourceFile,
) !bool {
    const predicate = file.enabled orelse return true;
    var file_options = options;
    file_options.file = .{ .path = "", .owner = "plugins", .kind = .plugin, .rust_source_file = file };
    return predicate(context(allocator, program, file_options));
}

/// Whether any registered plugin writes at a package boundary, which is what
/// decides whether the crate has a `zigo_plugins` module at all.
pub fn hasPackageHooks() bool {
    inline for (registry.plugins) |registered| if (rustSlot(registered).visit != null) return true;
    return false;
}

/// Every `use` path a registered plugin declares, in registration order. A
/// plugin file writes the ones its own body spells.
pub fn declaredUses() []const plugin.RustImport {
    comptime var all: []const plugin.RustImport = &.{};
    comptime {
        for (registry.plugins) |registered| all = all ++ rustSlot(registered).imports;
    }
    return all;
}

/// The `use` block of a plugin-written file: the declared paths whose last
/// segment the body actually spells, in the order they were declared. The
/// same rule Go's import block follows, which is what keeps a declared import
/// a plugin never writes from tripping `-D warnings`.
pub fn writeUses(writer: *std.Io.Writer, uses: []const plugin.RustImport, body: []const u8) !void {
    var written = false;
    for (uses) |entry| {
        const segment = lastSegment(entry.path);
        if (std.mem.indexOf(u8, body, segment) == null) continue;
        try writer.print("use {s};\n", .{entry.path});
        written = true;
    }
    if (written) try writer.writeByte('\n');
}

fn lastSegment(path: []const u8) []const u8 {
    const trimmed = std.mem.trimEnd(u8, path, ";");
    if (std.mem.lastIndexOf(u8, trimmed, "::")) |index| return trimmed[index + 2 ..];
    return trimmed;
}

test "a plugin file's use block writes only the paths the body spells" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try writeUses(&output.writer, &.{ .{ .path = "core::fmt::Write" }, .{ .path = "std::collections::HashMap" } }, "fn f(w: &mut impl Write) {}");
    try std.testing.expectEqualStrings("use core::fmt::Write;\n\n", output.written());
}

test "an impl-block flush is indented one level per depth" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try writeIndented(&output.writer, "fn marker() -> u8 {\n\n    1\n}\n", 1);
    try std.testing.expectEqualStrings("    fn marker() -> u8 {\n\n        1\n    }\n", output.written());
}
