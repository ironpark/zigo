//! External-module contract test for node-level extensions: a plugin that
//! reads the options a binding attached to a parameter, a result, a struct
//! field and an enum tag, and renders one Go constant for each. Nothing is
//! written for a node no declaration extended, so the golden shows exactly
//! which nodes carried options.
const std = @import("std");
const abi = @import("abi");
const api = @import("plugin");
const semantic = @import("semantic");

/// One shape for all four slots. The point of separate option types is that
/// each node kind declares its own, not that they must differ.
pub const Marker = struct { marker: []const u8 };

pub const plugin: api.Plugin = .{
    .name = "NODEEXT",
    .subjects = &.{ .function, .value, .enumeration, .param, .result, .field, .enum_tag },
    .ParamOptions = Marker,
    .ResultOptions = Marker,
    .FieldOptions = Marker,
    .TagOptions = Marker,
    .method_hook = methodHook,
    .type_hook = typeHook,
};

fn methodHook(context: api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    const origin = function.origin;
    const public_name = context.method.?.public_name;
    for (origin.params) |parameter| {
        const options = try context.optionsOf(plugin, .param, parameter.ext) orelse continue;
        try renderMarker(context, writer, &.{ "ZigoNodeParam", public_name, parameter.name }, options.marker);
    }
    if (try context.optionsOf(plugin, .result, origin.result_ext)) |options| {
        try renderMarker(context, writer, &.{ "ZigoNodeResult", public_name }, options.marker);
    }
}

fn typeHook(context: api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    // Tags and fields are the same IR node; the container's kind decides
    // which of the two option types reads it.
    const tags = declaration.kind == .@"enum";
    for (declaration.fields) |field| {
        const options = if (tags)
            try context.optionsOf(plugin, .enum_tag, field.ext)
        else
            try context.optionsOf(plugin, .field, field.ext);
        const attached = options orelse continue;
        const prefix = if (tags) "ZigoNodeTag" else "ZigoNodeField";
        try renderMarker(context, writer, &.{ prefix, declaration.name, field.name }, attached.marker);
    }
}

/// One exported constant per extended node, named after the node it came off
/// so two nodes of one declaration cannot collide.
fn renderMarker(context: api.Context, writer: *std.Io.Writer, parts: []const []const u8, value: []const u8) !void {
    const allocator = context.allocator;
    var name: std.ArrayList(u8) = .empty;
    for (parts) |part| {
        if (part.len == 0) continue;
        try name.append(allocator, std.ascii.toUpper(part[0]));
        try name.appendSlice(allocator, part[1..]);
    }
    const b = context.builder();
    const doc = try std.fmt.allocPrint(allocator, "{s} is the marker NODEEXT read from the declaration.", .{name.items});
    try b.render(writer, &.{try b.constant(.{
        .doc = .{ .text = doc },
        .names = &.{name.items},
        .value = b.string(value),
    })}, .{ .blank_before = true });
}
