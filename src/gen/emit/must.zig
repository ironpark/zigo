//! `Must` variants of public functions, which panic instead of returning an error.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const common = @import("common.zig");
const docs = @import("docs.zig");
const public = @import("public.zig");
const public_writers = @import("public_writers.zig");

fn writeMustCallArguments(allocator: std.mem.Allocator, writer: *std.Io.Writer, function: abi.AbiFn, go_names: [][]u8) !void {
    var index: usize = 0;
    if (function.origin.cancel != null) {
        try writer.writeAll("ctx");
        index = 1;
    }
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (function.userdataFor(parameter_index) != null or parameter.injected != null or parameter.type == .cancel_flag) continue;
        if (parameter.flatten) |fields| {
            for (fields, 0..) |_, field_index| {
                const abi_parameter = function.flattenedParam(parameter_index, field_index);
                const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                defer allocator.free(name);
                if (index != 0) try writer.writeAll(", ");
                try writer.writeAll(name);
                index += 1;
            }
            continue;
        }
        if (index != 0) try writer.writeAll(", ");
        try writer.writeAll(go_names[parameter_index]);
        index += 1;
    }
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
