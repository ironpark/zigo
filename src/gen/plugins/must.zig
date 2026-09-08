//! `Must` variants of public functions, which panic instead of returning an error.
//!
//! A built-in plugin, gated by `options.go_must_variants` rather than by a
//! declaration key: the binding asks for the variants once, for the whole
//! package. The name-collision rule for the generated `Must` name stays in
//! `validate.findMustVariantIssue`, which runs on the promoted functions the
//! generator will actually emit.
const std = @import("std");
const abi = @import("abi");
const common = @import("../emit/common.zig");
const docs = @import("../emit/docs.zig");
const plugin_api = @import("plugin");
const public = @import("../emit/public.zig");
const public_writers = @import("../emit/public_writers.zig");
const semantic = @import("semantic");

pub const plugin: plugin_api.Plugin = .{
    .name = "MUST",
    .method_hook = methodHook,
};

fn methodHook(context: plugin_api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    if (!context.options.go_must_variants or !function.must_variant) return;
    const method = context.method.?;
    try renderMustVariant(
        .{ .program = context.program, .options = context.options },
        context.allocator,
        writer,
        function,
        method.param_names,
        method.receiver_name,
        method.go_name,
        method.owned_type,
    );
}

pub fn writeMustCallArguments(allocator: std.mem.Allocator, writer: *std.Io.Writer, function: abi.AbiFn, go_names: [][]u8) !void {
    return public.writePublicCallArguments(allocator, writer, function, go_names);
}

pub fn mustHasSecondResult(function: semantic.SemanticFn) bool {
    const result = function.@"return".errorPayload();
    return result == .optional or
        (result == .opaque_ptr and result.opaque_ptr.nullable and docs.returnsBorrowedView(function));
}

pub fn writeMustResultType(scope: public_writers.PublicScope, writer: *std.Io.Writer, function: semantic.SemanticFn, owned_type: ?[]const u8) !void {
    if (owned_type) |name| return writer.print("*{s}", .{name});
    const result = function.@"return".errorPayload();
    const node = if (result == .optional) result.optional.child.* else result;
    if (node == .opaque_ptr and docs.returnsBorrowedView(function))
        return writer.print("*{s}", .{node.opaque_ptr.ref});
    if (node == .opaque_ptr and docs.returnsBorrowedOpaque(function))
        return writer.print("*{s}Ref", .{node.opaque_ptr.ref});
    if (semantic.isStringSlice(node, function.return_semantic)) return writer.writeAll("string");
    if (public_writers.codepointTypeName(node, function.return_semantic)) |name| return writer.writeAll(name);
    if (function.return_go_adapter) |adapter| return writer.writeAll(adapter.type);
    try public_writers.writePublicGoType(scope, writer, node);
}

/// The parameters and result of a `Must` variant, from the parameter list's
/// opening parenthesis onward. Shared with the interface file so a method
/// and the interface that lists it can never spell the variant differently.
pub fn writeMustSignature(
    scope: public_writers.PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    go_names: [][]u8,
    owned_type: ?[]const u8,
) !void {
    try public.writePublicParameters(scope, allocator, writer, function, go_names);
    try writer.writeByte(')');
    if (function.origin.@"return".errorPayload() == .void) return;
    try writer.writeByte(' ');
    const second = mustHasSecondResult(function.origin.*);
    if (second) try writer.writeByte('(');
    try writeMustResultType(scope, writer, function.origin.*, owned_type);
    if (second) try writer.writeAll(", bool)");
}

pub fn renderMustVariant(
    scope: public_writers.PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    go_names: [][]u8,
    receiver_name: ?[]const u8,
    go_name: []const u8,
    owned_type: ?[]const u8,
) !void {
    const must_name = try std.fmt.allocPrint(allocator, "Must{s}", .{go_name});
    defer allocator.free(must_name);
    try writer.print("\n// {s} calls {s} and panics with its typed error on failure.\n", .{ must_name, go_name });
    if (function.origin.receiver) |receiver|
        try writer.print("func ({s} *{s}) {s}(", .{ receiver_name.?, receiver, must_name })
    else
        try writer.print("func {s}(", .{must_name});
    try writeMustSignature(scope, allocator, writer, function, go_names, owned_type);
    const result = function.origin.@"return".errorPayload();
    try writer.writeAll(" { ");
    if (result == .void)
        try writer.writeAll("_ = zigoMust(struct{}{}, ")
    else if (mustHasSecondResult(function.origin.*))
        try writer.writeAll("return zigoMustMatch(")
    else
        try writer.writeAll("return zigoMust(");
    if (function.origin.receiver != null)
        try writer.print("{s}.{s}(", .{ receiver_name.?, go_name })
    else
        try writer.print("{s}(", .{go_name});
    try writeMustCallArguments(allocator, writer, function, go_names);
    try writer.writeAll(")) }\n");
}
