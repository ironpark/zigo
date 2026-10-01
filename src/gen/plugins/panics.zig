//! `.panics`: a method whose only failures are misuse loses its Go `error`
//! and panics with the error instead.
//!
//! A built-in plugin on the same terms as an added one. It claims the method,
//! so the generated body is written under its unexported checked name, and
//! its visit writes the exported method over it: the same signature without
//! the trailing `error`, calling the body and panicking with what it returned.
//! Every handle check, range check and error mapping stays in the body, so the
//! value the panic carries is the typed error the method would have returned.
//!
//! The rules for which methods may drop the `error` are the contract's
//! (`plugin.builtins.panics`), so `MUST` asks the same question this file
//! does before it writes a `Must` companion the method no longer needs.
const std = @import("std");
const abi = @import("abi");
const plugin_api = @import("plugin");
const semantic = @import("semantic");
const site = plugin_api.site;
const contract = plugin_api.builtins.panics;

/// The contract's descriptor -- name, options and subjects, the half the
/// authoring module attaches with -- plus this file's hooks.
pub const plugin: plugin_api.Plugin = blk: {
    var declared = contract.plugin;
    declared.analyze = analyze;
    declared.go = .{ .claims = applies, .visit = visit };
    break :blk declared;
};

/// Whether this method is written as a panicking wrapper over its checked
/// body: it asked, nothing keeps its `error`, and it has one to drop.
fn applies(context: plugin_api.GoContext, node: plugin_api.Node) !bool {
    if (node != .function) return false;
    return replaces(context, node.function);
}

/// The question `applies` answers, for a caller holding the function rather
/// than a node.
pub fn replaces(context: plugin_api.GoContext, function: abi.AbiFn) !bool {
    if (!try contract.requested(context.allocator, context.program.types, function.origin.*)) return false;
    if (try blockerOf(context, function) != null) return false;
    const info = try context.functionInfo(function);
    return info.is_public and info.has_error;
}

fn blockerOf(context: plugin_api.GoContext, function: abi.AbiFn) !?contract.Blocker {
    return contract.blocker(context.allocator, function.origin.*, function.reaches_callback_errors, isInterfaceMethod(context.program, function));
}

/// Every implementation of a declared interface has to spell the method the
/// same way, so one that dropped its `error` would stop satisfying it.
fn isInterfaceMethod(program: abi.Program, function: abi.AbiFn) bool {
    const receiver = function.origin.receiver orelse return false;
    for (program.interfaces) |interface| {
        for (interface.methods) |method| {
            for (method.functions) |candidate| {
                if (semantic.optionalStringEqual(candidate.origin.receiver, receiver) and std.mem.eql(u8, candidate.origin.name, function.origin.name)) return true;
            }
        }
    }
    return false;
}

/// A function that asked by itself is told why it cannot have it. A handle
/// that asked covers the methods that can, and the rest keep their `error`
/// without a word: the handle-wide request is a default, not a promise.
fn analyze(context: plugin_api.AnalyzeContext) !void {
    const render = context.go orelse return;
    const allocator = render.allocator;
    for (render.program.functions) |function| {
        if (try plugin_api.optionsOn(contract.plugin, .function, allocator, function.origin.ext) == null) continue;
        const origin = function.origin.*;
        const path = try site.functionDeclarationAlloc(allocator, origin);
        if (try blockerOf(render, function)) |reason| {
            try context.diagnose(.{
                .severity = .@"error",
                .code = "ZIGO069",
                .message = try std.fmt.allocPrint(allocator, "`.panics` on `{s}`, which {s}", .{ path, reason.describe() }),
                .site = site.functionSiteFor(origin, path),
                .hint = "the error reports a condition the caller has to handle; remove `.panics` from this function",
            });
            continue;
        }
        const info = try render.functionInfo(function);
        if (!info.is_public or !info.has_error) try context.diagnose(.{
            .severity = .@"error",
            .code = "ZIGO069",
            .message = try std.fmt.allocPrint(allocator, "`.panics` on `{s}`, whose Go signature has no `error` to drop", .{path}),
            .site = site.functionSiteFor(origin, path),
            .hint = "remove `.panics`; the function already cannot fail in Go",
        });
    }
}

/// The exported method over the checked body. Its doc is the method's own,
/// followed by what replaced the `error`.
fn visit(context: plugin_api.GoContext, node: plugin_api.Node, b: *plugin_api.Builder) !void {
    if (node != .function) return;
    const function = node.function;
    if (!try replaces(context, function)) return;
    const allocator = context.allocator;
    const method = context.method.?;
    const origin = function.origin.*;

    var doc: std.Io.Writer.Allocating = .init(allocator);
    if (origin.doc) |text| {
        try context.writeDoc(&doc.writer, method.public_name, origin.name, text);
    } else if (method.owned_type) |owned| {
        try doc.writer.print("\n// {s} creates a caller-owned {s}.\n// The caller must call Close on the returned handle.\n", .{ method.public_name, owned });
    } else if (origin.receiver) |receiver| {
        try doc.writer.print("\n// {s} calls the Zig function {s}.{s}.\n", .{ method.public_name, receiver, origin.name });
    } else {
        try doc.writer.print("\n// {s} calls the Zig function {s}.\n", .{ method.public_name, origin.name });
    }
    try doc.writer.writeAll("// It panics with the typed error it would otherwise return.\n");

    const callee = if (method.receiver_name) |receiver|
        try b.selName(receiver, method.checked_name)
    else
        b.ident(method.checked_name);
    const call = try b.callForwarding(callee, function);
    const count = try b.resultCount(function, .{ .omit_error = true });
    const body: []const plugin_api.gobuild.Stmt = switch (count) {
        0 => &.{try b.ifStmt(.{
            .init = try b.define(&.{"err"}, call),
            .cond = try b.bin("!=", b.ident("err"), .nil),
            .body = &.{b.exprStmt(try b.callName("panic", &.{b.ident("err")}))},
        })},
        1 => &.{try b.ret(&.{try b.callName("zigoMust", &.{call})})},
        else => &.{try b.ret(&.{try b.callName("zigoMustMatch", &.{call})})},
    };
    try b.emit(&.{try b.func(.{
        .doc = .{ .rendered = std.mem.trim(u8, doc.written(), "\n") },
        .receiver = if (method.receiver) |receiver| .{ .name = method.receiver_name.?, .type = receiver, .pointer = true } else null,
        .name = method.public_name,
        .signature = .{ .function = .{ .function = function, .options = .{ .omit_error = true } } },
        .body = body,
    })}, .{ .blank_before = true });
}
