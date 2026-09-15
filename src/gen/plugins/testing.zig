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
    .go = .{ .visit = visit, .source_files = &.{.{ .pathAlloc = filePath, .render = renderFile }} },
};

/// Every node the frame offers, which is what makes this plugin a test of the
/// walk itself: a method beside the bound one, a comment after a type, and one
/// marker per node that attached `TEST`.
fn visit(context: plugin_api.GoContext, node: plugin_api.Node, b: *plugin_api.Builder) !void {
    if (!enabled) return;
    switch (node) {
        .function => |function| try renderMethod(context, b, function),
        .param => |parameter| {
            const options = try context.optionsOf(plugin, .param, node) orelse return;
            const name = parameter.function.origin.params[parameter.index].name;
            const text = try std.fmt.allocPrint(context.allocator, "zigoTestHook param {s} at {d}: {s}.", .{ name, parameter.index, options.tag });
            try b.emit(&.{.{ .comment = .{ .text = text } }}, .{});
        },
        .result => |function| {
            const options = try context.optionsOf(plugin, .result, node) orelse return;
            const text = try std.fmt.allocPrint(context.allocator, "zigoTestHook result of {s}: {s}.", .{ function.origin.name, options.tag });
            try b.emit(&.{.{ .comment = .{ .text = text } }}, .{});
        },
        .type => |declaration| {
            const text = try std.fmt.allocPrint(context.allocator, "zigoTestHook saw {s}.", .{declaration.name});
            try b.emit(&.{.{ .comment = .{ .text = text } }}, .{ .blank_after = true });
        },
        // Tags and fields are the same IR node; which node kind the walk
        // offers is what says which of the two option types reads it.
        .field => |member| try renderMember(context, b, node, member, "field"),
        .enum_tag => |member| try renderMember(context, b, node, member, "tag"),
        else => {},
    }
}

/// A method next to the bound one, spelled from the names the method used.
fn renderMethod(context: plugin_api.GoContext, b: *plugin_api.Builder, function: abi.AbiFn) !void {
    const method = context.method.?;
    const receiver = method.receiver orelse return;
    const options = try context.optionsOf(plugin, .function, function.origin.ext) orelse Options{};
    const name = try std.fmt.allocPrint(context.allocator, "{s}TestHook", .{method.public_name});
    const doc = try std.fmt.allocPrint(context.allocator, "{s} reports the name of {s}.", .{ name, method.public_name });
    try b.emit(&.{try b.func(.{
        .doc = .{ .text = doc },
        .receiver = .{ .name = method.receiver_name.?, .type = receiver, .pointer = true },
        .name = name,
        .signature = .{ .explicit = .{ .results = &.{b.ident("string")} } },
        .body = &.{try b.ret(&.{b.string(@tagName(options.mode))})},
        .single_line = true,
    })}, .{ .blank_before = true });
}

/// One comment per member that attached `TEST`, which is what proves a field's
/// and a tag's `ext` reach a visit at all.
fn renderMember(context: plugin_api.GoContext, b: *plugin_api.Builder, node: plugin_api.Node, member: plugin_api.Node.Member, kind: []const u8) !void {
    const options = if (node == .enum_tag)
        try context.optionsOf(plugin, .enum_tag, node)
    else
        try context.optionsOf(plugin, .field, node);
    const attached = options orelse return;
    const field = member.declaration.fields[member.index];
    const marker = try std.fmt.allocPrint(context.allocator, "zigoTestHook {s} {s}.{s}: {s}.", .{ kind, member.declaration.name, field.name, attached.tag });
    try b.emit(&.{.{ .comment = .{ .text = marker } }}, .{ .blank_after = true });
}

fn filePath(context: plugin_api.GoContext) ![]u8 {
    const allocator = context.allocator;
    const program = context.program;
    const options = context.options;

    if (path_override) |path| return allocator.dupe(u8, path);
    return plugin_api.publicFilePathAlloc(allocator, program, options, "zigo_test_plugin_gen.go");
}

/// Only the declarations: the marker, the package clause and the import block
/// come from the public-file frame the generator wraps every plugin file in.
fn renderFile(context: plugin_api.GoContext, writer: *std.Io.Writer) !void {
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
