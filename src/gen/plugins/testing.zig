//! A plugin that exists only to exercise the frame from a unit test. It is
//! registered in test builds alone and writes nothing until a test sets
//! `enabled`, so no golden and no example can see it.
const std = @import("std");
const abi = @import("abi");
const plugin_api = @import("plugin");
const semantic = @import("semantic");
const diagnostic = @import("diagnostic");

/// Set by the test that wants the hooks to write, cleared by the same test.
pub var enabled = false;
pub var validation_enabled = false;
pub var path_override: ?[]const u8 = null;

/// What the test plugin can be told to do. It exists so a test can prove that
/// a typed option survives `extend`, the document, and the parse on the way
/// back, and that a value outside the type is a diagnostic rather than a panic.
pub const Options = struct {
    mode: enum { a, b } = .a,
};

pub const plugin: plugin_api.Plugin = .{
    .name = "TEST",
    .validate = validateAll,
    .FunctionOptions = Options,
    .method_hook = methodHook,
    .type_hook = typeHook,
    .files = &.{.{ .pathAlloc = filePath, .render = renderFile }},
};

/// A method next to the bound one, spelled from the names the method used.
fn methodHook(context: plugin_api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    if (!enabled) return;
    const method = context.method.?;
    const receiver = method.receiver orelse return;
    const options = try context.functionOptions(plugin, function.origin.*) orelse Options{};
    try writer.print(
        "\n// {0s}TestHook reports the name of {0s}.\nfunc ({1s} *{2s}) {0s}TestHook() string {{ return \"{3s}\" }}\n",
        .{ method.go_name, method.receiver_name.?, receiver, @tagName(options.mode) },
    );
}

/// A line after a type, which is what a `type_hook` is for.
fn typeHook(_: plugin_api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    if (!enabled) return;
    try writer.print("// zigoTestHook saw {s}.\n\n", .{declaration.name});
}

fn filePath(context: plugin_api.Context) ![]u8 {
    const allocator = context.allocator;
    const program = context.program;
    const options = context.options;

    if (path_override) |path| return allocator.dupe(u8, path);
    return plugin_api.publicFilePathAlloc(allocator, program, options, "zigo_test_plugin_gen.go");
}

/// Only the declarations: the marker, the package clause and the import block
/// come from the public-file frame the generator wraps every plugin file in.
fn renderFile(context: plugin_api.Context, writer: *std.Io.Writer) !void {
    _ = context;

    if (!enabled) return;
    try writer.writeAll(
        "// ZigoTestPluginName is what the test plugin calls itself.\nconst ZigoTestPluginName = \"TEST\"\n",
    );
}

fn validateAll(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    if (!validation_enabled) return;
    const issues = try allocator.alloc(diagnostic.Diagnostic, 2);
    for (issues, 0..) |*issue, index| issue.* = .{
        .severity = .@"error",
        .code = if (index == 0) "TEST002" else "TEST003",
        .message = "test plugin diagnostic",
        .site = .{ .path = "semantic.json", .declaration = "sample" },
        .hint = "test hint",
    };
    for (issues) |issue| try context.diagnose(issue);
}
