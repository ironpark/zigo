//! A plugin that exists only to exercise the frame from a unit test. It is
//! registered in test builds alone and writes nothing until a test sets
//! `enabled`, so no golden and no example can see it.
const std = @import("std");
const abi = @import("abi");
const plugin_api = @import("plugin");
const semantic = @import("semantic");

/// Set by the test that wants the hooks to write, cleared by the same test.
pub var enabled = false;

pub const plugin: plugin_api.Plugin = .{
    .name = "TEST",
    .method_hook = methodHook,
    .type_hook = typeHook,
    .files = &.{.{ .pathAlloc = filePath, .render = renderFile }},
};

/// A method next to the bound one, spelled from the names the method used.
fn methodHook(context: plugin_api.Context, writer: *std.Io.Writer, _: abi.AbiFn) !void {
    if (!enabled) return;
    const method = context.method.?;
    const receiver = method.receiver orelse return;
    try writer.print(
        "\n// {0s}TestHook reports the name of {0s}.\nfunc ({1s} *{2s}) {0s}TestHook() string {{ return \"{0s}\" }}\n",
        .{ method.go_name, method.receiver_name.?, receiver },
    );
}

/// A line after a type, which is what a `type_hook` is for.
fn typeHook(_: plugin_api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    if (!enabled) return;
    try writer.print("// zigoTestHook saw {s}.\n\n", .{declaration.name});
}

fn filePath(allocator: std.mem.Allocator, _: abi.Program, _: plugin_api.Options) ![]u8 {
    return allocator.dupe(u8, "zigo_test_plugin_gen.go");
}

/// Only the declarations: the marker, the package clause and the import block
/// come from the public-file frame the generator wraps every plugin file in.
fn renderFile(_: std.mem.Allocator, writer: *std.Io.Writer, _: abi.Program, _: plugin_api.Options) !void {
    if (!enabled) return;
    try writer.writeAll(
        "// ZigoTestPluginName is what the test plugin calls itself.\nconst ZigoTestPluginName = \"TEST\"\n",
    );
}
