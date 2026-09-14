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
/// a typed option survives `use`, the document, and the parse on the way
/// back, and that a value outside the type is a diagnostic rather than a panic.
pub const Options = struct {
    mode: enum { a, b } = .a,
};

/// What a node-level attachment carries. One shape serves the parameter, the
/// result, the field and the tag: the point of the four slots is that each
/// node kind has a type of its own, not that they have to differ.
pub const NodeOptions = struct {
    tag: []const u8,
};

pub const plugin: plugin_api.Plugin = .{
    .name = "TEST",
    .validate = validateAll,
    .FunctionOptions = Options,
    .ParamOptions = NodeOptions,
    .ResultOptions = NodeOptions,
    .FieldOptions = NodeOptions,
    .TagOptions = NodeOptions,
    .method_hook = methodHook,
    .type_hook = typeHook,
    .source_files = &.{.{ .pathAlloc = filePath, .render = renderFile }},
};

/// A method next to the bound one, spelled from the names the method used.
fn methodHook(context: plugin_api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    if (!enabled) return;
    const method = context.method.?;
    const receiver = method.receiver orelse return;
    const options = try context.optionsOf(plugin, .function, function.origin.ext) orelse Options{};
    const b = context.builder();
    const name = try std.fmt.allocPrint(context.allocator, "{s}TestHook", .{method.public_name});
    const doc = try std.fmt.allocPrint(context.allocator, "{s} reports the name of {s}.", .{ name, method.public_name });
    try b.render(writer, &.{try b.func(.{
        .doc = .{ .text = doc },
        .receiver = .{ .name = method.receiver_name.?, .type = receiver, .pointer = true },
        .name = name,
        .signature = .{ .explicit = .{ .results = &.{b.ident("string")} } },
        .body = &.{try b.ret(&.{b.string(@tagName(options.mode))})},
        .single_line = true,
    })}, .{ .blank_before = true });
    try renderNodeMarkers(context, writer, function.origin);
}

/// One comment per node of this function that attached `TEST`, which is what
/// proves a parameter's and a result's `ext` reach a hook at all. Nothing is
/// written for a function whose nodes none of them extended.
fn renderNodeMarkers(context: plugin_api.Context, writer: *std.Io.Writer, function: *const semantic.SemanticFn) !void {
    const b = context.builder();
    for (function.params, 0..) |parameter, index| {
        const options = try context.optionsOf(plugin, .param, parameter.ext) orelse continue;
        const text = try std.fmt.allocPrint(context.allocator, "zigoTestHook param {s} at {d}: {s}.", .{ parameter.name, index, options.tag });
        try b.render(writer, &.{.{ .comment = .{ .text = text } }}, .{});
    }
    if (try context.optionsOf(plugin, .result, function.result_ext)) |options| {
        const text = try std.fmt.allocPrint(context.allocator, "zigoTestHook result of {s}: {s}.", .{ function.name, options.tag });
        try b.render(writer, &.{.{ .comment = .{ .text = text } }}, .{});
    }
}

/// A line after a type, which is what a `type_hook` is for.
fn typeHook(context: plugin_api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    if (!enabled) return;
    const b = context.builder();
    const text = try std.fmt.allocPrint(context.allocator, "zigoTestHook saw {s}.", .{declaration.name});
    try b.render(writer, &.{.{ .comment = .{ .text = text } }}, .{ .blank_after = true });
    // Tags and fields are the same IR node; the container's kind is what says
    // which of the two option types reads it.
    const member = if (declaration.kind == .@"enum") "tag" else "field";
    for (declaration.fields) |field| {
        const options = if (declaration.kind == .@"enum")
            try context.optionsOf(plugin, .enum_tag, field.ext)
        else
            try context.optionsOf(plugin, .field, field.ext);
        const attached = options orelse continue;
        const marker = try std.fmt.allocPrint(context.allocator, "zigoTestHook {s} {s}.{s}: {s}.", .{ member, declaration.name, field.name, attached.tag });
        try b.render(writer, &.{.{ .comment = .{ .text = marker } }}, .{ .blank_after = true });
    }
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
    if (!enabled) return;
    const b = context.builder();
    try b.render(writer, &.{try b.constant(.{
        .doc = .{ .text = "ZigoTestPluginName is what the test plugin calls itself." },
        .names = &.{"ZigoTestPluginName"},
        .value = b.string("TEST"),
    })}, .{});
}

fn validateAll(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    if (!validation_enabled) return;
    const issues = try allocator.alloc(diagnostic.Diagnostic, 2);
    for (issues, 0..) |*issue, index| issue.* = .{
        .severity = .@"error",
        .code = if (index == 0) "TEST002" else "TEST003",
        .message = "test plugin diagnostic",
        .site = plugin_api.site.documentSite("sample"),
        .hint = "test hint",
    };
    for (issues) |issue| try context.diagnose(issue);
}
