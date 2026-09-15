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
    .go = .{ .visit = visit },
};

fn visit(context: api.GoContext, node: api.Node, b: *api.Builder) !void {
    switch (node) {
        .param => |parameter| {
            const options = try context.optionsOf(plugin, .param, node) orelse return;
            const name = parameter.function.origin.params[parameter.index].name;
            try renderMarker(context, b, &.{ "ZigoNodeParam", context.method.?.public_name, name }, options.marker);
        },
        .result => {
            const options = try context.optionsOf(plugin, .result, node) orelse return;
            try renderMarker(context, b, &.{ "ZigoNodeResult", context.method.?.public_name }, options.marker);
        },
        // Tags and fields are the same IR node; which node kind the walk
        // offers is what decides which of the two option types reads it.
        .field => |member| {
            const options = try context.optionsOf(plugin, .field, node) orelse return;
            const field = member.declaration.fields[member.index];
            try renderMarker(context, b, &.{ "ZigoNodeField", member.declaration.name, field.name }, options.marker);
        },
        .enum_tag => |member| {
            const options = try context.optionsOf(plugin, .enum_tag, node) orelse return;
            const field = member.declaration.fields[member.index];
            try renderMarker(context, b, &.{ "ZigoNodeTag", member.declaration.name, field.name }, options.marker);
        },
        else => {},
    }
}

/// One exported constant per extended node, named after the node it came off
/// so two nodes of one declaration cannot collide.
fn renderMarker(context: api.GoContext, b: *api.Builder, parts: []const []const u8, value: []const u8) !void {
    const allocator = context.allocator;
    var name: std.ArrayList(u8) = .empty;
    for (parts) |part| {
        if (part.len == 0) continue;
        try name.append(allocator, std.ascii.toUpper(part[0]));
        try name.appendSlice(allocator, part[1..]);
    }
    const doc = try std.fmt.allocPrint(allocator, "{s} is the marker NODEEXT read from the declaration.", .{name.items});
    try b.emit(&.{try b.constant(.{
        .doc = .{ .text = doc },
        .names = &.{name.items},
        .value = b.string(value),
    })}, .{ .blank_before = true });
}
