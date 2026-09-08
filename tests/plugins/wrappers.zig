//! External-module contract test: selective Must wrappers without emit imports
//! or Go signature parsing, with one helper file per active public package.
const std = @import("std");
const abi = @import("abi");
const api = @import("plugin");

pub const plugin: api.Plugin = .{
    .name = "WRAPTEST",
    .targets = &.{.function},
    .method_hook = methodHook,
    .files = &.{.{ .pathAlloc = path, .render = helpers }},
};

fn methodHook(context: api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    _ = try context.functionOptions(plugin, function.origin.*) orelse return;
    const method = context.method.?;
    try writer.print("// Wrap{0s} panics on failure.\nfunc ", .{method.go_name});
    if (method.receiver) |receiver| try writer.print("({s} {s}{s}) ", .{ method.receiver_name.?, if (function.origin.receiverIsValue()) "" else "*", receiver });
    try writer.print("Wrap{s}", .{method.go_name});
    try context.writeParameters(writer, function);
    const count = try context.writeResultType(writer, function, .{ .omit_error = true });
    try writer.writeAll(" {\n\t");
    if (count != 0) try writer.writeAll("return ");
    try writer.print("zigoWrap{d}(", .{count});
    if (method.receiver_name) |receiver| try writer.print("{s}.", .{receiver});
    try writer.print("{s}(", .{method.go_name});
    try context.writeCallArguments(writer, function);
    try writer.writeAll("))\n}\n");
}

fn path(allocator: std.mem.Allocator, program: abi.Program, options: api.Options) ![]u8 {
    return api.publicFilePathAlloc(allocator, program, options, "zigo_wrappers_gen.go");
}

fn helpers(_: std.mem.Allocator, writer: *std.Io.Writer, _: abi.Program, options: api.Options) !void {
    if (options.emitsHelper("zigoWrap0")) try writer.writeAll("func zigoWrap0(err error) { if err != nil { panic(err) } }\n");
    if (options.emitsHelper("zigoWrap1")) try writer.writeAll("func zigoWrap1[T any](v T, err error) T { if err != nil { panic(err) }; return v }\n");
    if (options.emitsHelper("zigoWrap2")) try writer.writeAll("func zigoWrap2[T any](v T, ok bool, err error) (T, bool) { if err != nil { panic(err) }; return v, ok }\n");
}
