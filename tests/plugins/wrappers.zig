//! External-module contract test: selective Must wrappers without emit imports
//! or Go signature parsing, with one helper file per active public package.
const std = @import("std");
const abi = @import("abi");
const api = @import("plugin");

pub const plugin: api.Plugin = .{
    .name = "WRAPTEST",
    .subjects = &.{.function},
    .method_hook = methodHook,
    .source_files = &.{.{ .pathAlloc = path, .render = helpers }},
};

fn methodHook(context: api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    _ = try context.functionOptions(plugin, function.origin.*) orelse return;
    const method = context.method.?;
    try writer.print("// Wrap{0s} panics on failure.\nfunc ", .{method.public_name});
    if (method.receiver) |receiver| try writer.print("({s} {s}{s}) ", .{ method.receiver_name.?, if (function.origin.receiverIsValue()) "" else "*", receiver });
    try writer.print("Wrap{s}", .{method.public_name});
    try context.writeParameters(writer, function);
    const count = try context.writeResultType(writer, function, .{ .omit_error = true });
    try writer.writeAll(" {\n\t");
    if (count != 0) try writer.writeAll("return ");
    try writer.print("zigoWrap{d}(", .{count});
    if (method.receiver_name) |receiver| try writer.print("{s}.", .{receiver});
    try writer.print("{s}(", .{method.public_name});
    try context.writeCallArguments(writer, function);
    try writer.writeAll("))\n}\n");
}

fn path(context: api.Context) ![]u8 {
    const allocator = context.allocator;
    const program = context.program;
    const options = context.options;
    return api.publicFilePathAlloc(allocator, program, options, "zigo_wrappers_gen.go");
}

fn helpers(context: api.Context, writer: *std.Io.Writer) !void {
    const options = context.options;
    if (options.emitsHelper("zigoWrap0")) try writer.writeAll("func zigoWrap0(err error) { if err != nil { panic(err) } }\n");
    if (options.emitsHelper("zigoWrap1")) try writer.writeAll("func zigoWrap1[T any](v T, err error) T { if err != nil { panic(err) }; return v }\n");
    if (options.emitsHelper("zigoWrap2")) try writer.writeAll("func zigoWrap2[T any](v T, ok bool, err error) (T, bool) { if err != nil { panic(err) }; return v, ok }\n");
}
