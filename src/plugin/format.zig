//! The Go spellings a hook writes that need no generator state: a function
//! or method header, an identifier derived from a Zig name, and a string
//! literal. They are reached through `Context` -- `writeFuncHeader`,
//! `writeMethodHeader`, `identifierAlloc`, `writeStringLiteral` -- which is
//! the one path a plugin uses; this file is what the writers table points at.
const std = @import("std");
const naming = @import("naming");
const plugin = @import("../plugin.zig");

/// `func Name(params) results {`, with no trailing newline. `results` is
/// written as given after a space, so a tuple carries its own parentheses;
/// empty results write nothing between the parameter list and the brace.
pub fn writeFuncHeader(_: plugin.Context, writer: *std.Io.Writer, name: []const u8, params: []const u8, results: []const u8) anyerror!void {
    try writer.print("func {s}(", .{name});
    try writeTail(writer, params, results);
}

/// `func (name *Type) Name(params) results {`, the method form.
pub fn writeMethodHeader(_: plugin.Context, writer: *std.Io.Writer, receiver: plugin.Receiver, name: []const u8, params: []const u8, results: []const u8) anyerror!void {
    try writer.print("func ({s} {s}{s}) {s}(", .{ receiver.name, if (receiver.pointer) "*" else "", receiver.type, name });
    try writeTail(writer, params, results);
}

fn writeTail(writer: *std.Io.Writer, params: []const u8, results: []const u8) !void {
    try writer.writeAll(params);
    try writer.writeAll(")");
    if (results.len != 0) {
        try writer.writeByte(' ');
        try writer.writeAll(results);
    }
    try writer.writeAll(" {");
}

/// The exported (`.pascal`) or unexported (`.camel`) Go spelling of a Zig
/// name, with the same initialism rules the generated package applies to
/// its own members. The caller owns the result.
pub fn identifierAlloc(_: plugin.Context, allocator: std.mem.Allocator, name: []const u8, style: plugin.IdentifierStyle) anyerror![]u8 {
    return switch (style) {
        .pascal => naming.pascalAlloc(allocator, name),
        .camel => naming.camelAlloc(allocator, name),
    };
}

/// `text` as an interpreted Go string literal. Quotes, backslashes and the
/// common control characters take their short escapes; any other control
/// byte is written as `\xNN`. Bytes above ASCII pass through, so UTF-8 text
/// reads as it was written.
pub fn writeStringLiteral(writer: *std.Io.Writer, text: []const u8) anyerror!void {
    try writer.writeByte('"');
    for (text) |byte| switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\t' => try writer.writeAll("\\t"),
        '\r' => try writer.writeAll("\\r"),
        0...8, 11, 12, 14...31, 127 => try writer.print("\\x{x:0>2}", .{byte}),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}
