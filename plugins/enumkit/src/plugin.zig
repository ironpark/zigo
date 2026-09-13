//! Ordered enum values and membership helpers for the generated Go surface.
const std = @import("std");
const plugin_api = @import("plugin");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");

pub const name = "ENUMKIT";
pub const Options = struct {
    /// Emit <Type>Values(), returning a fresh slice in declaration order.
    values: bool = true,
    /// Emit IsKnown(), which recognizes only exported tags, even for open enums.
    is_known: bool = true,
};
pub const plugin: plugin_api.Plugin = .{
    .name = name,
    .TypeOptions = Options,
    .subjects = &.{.enumeration},
    .type_hook = typeHook,
    .validate = validateDocument,
};

fn typeHook(context: plugin_api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    const options = try context.optionsOf(plugin, .type, declaration.ext) orelse return;
    try render(context, writer, declaration.name, context.program.liveFields(declaration.name), options);
}

fn render(context: plugin_api.Context, writer: *std.Io.Writer, type_name: []const u8, fields: []const semantic.TypeField, options: Options) !void {
    const allocator = context.allocator;
    if (options.values) {
        const func_name = try std.fmt.allocPrint(allocator, "{s}Values", .{type_name});
        defer allocator.free(func_name);
        const results = try std.fmt.allocPrint(allocator, "[]{s}", .{type_name});
        defer allocator.free(results);
        try writer.print("// {s} returns a fresh slice of known values in declaration order.\n", .{func_name});
        try context.writeFuncHeader(writer, func_name, "", results);
        try writer.print("\n\treturn []{s}{{\n", .{type_name});
        for (fields) |field| {
            const member = try context.identifierAlloc(allocator, field.name, .pascal);
            defer allocator.free(member);
            try writer.print("\t\t{s}{s},\n", .{ type_name, member });
        }
        try writer.writeAll("\t}\n}\n\n");
    }
    if (options.is_known) {
        try writer.writeAll("// IsKnown reports whether value is an exported tag; unknown open-enum values return false.\n");
        try context.writeMethodHeader(writer, .{ .name = "value", .type = type_name }, "IsKnown", "", "bool");
        try writer.writeByte('\n');
        const range = semantic.enumValueRange(fields);
        if (range != null and range.?.span == fields.len) {
            try writer.print("\treturn value >= {d} && value <= {d}\n}}\n\n", .{ range.?.min, range.?.max });
            return;
        }
        if (fields.len != 0) {
            try writer.writeAll("\tswitch value {\n");
            for (fields) |field| {
                const member = try context.identifierAlloc(allocator, field.name, .pascal);
                defer allocator.free(member);
                try writer.print("\tcase {s}{s}:\n\t\treturn true\n", .{ type_name, member });
            }
            try writer.writeAll("\t}\n");
        }
        try writer.writeAll("\treturn false\n}\n\n");
    }
}

fn validateDocument(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    const document = context.document;
    for (document.types) |declaration| {
        _ = try context.optionsOf(plugin, .type, declaration.ext) orelse continue;
        if (declaration.kind == .@"enum" and declaration.goAdapter() == null) continue;
        try context.diagnose(.{
            .severity = .@"error",
            .code = name ++ "002",
            .message = try std.fmt.allocPrint(allocator, "`{s}` requires a generated enum type for enumkit helpers", .{declaration.name}),
            .site = plugin_api.site.typeSite(declaration),
            .hint = "attach enumkit to an enum without a Go adapter",
        });
    }
}

fn testContext() plugin_api.Context {
    return plugin_api.testing.context(std.testing.allocator, .{ .package = "enumkit", .prefix = "zg", .functions = &.{} });
}

test "options independently disable helpers and empty enums stay valid" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try render(testContext(), &output.writer, "Empty", &.{}, .{ .values = false, .is_known = false });
    try std.testing.expectEqualStrings("", output.written());
    try render(testContext(), &output.writer, "Empty", &.{}, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "func (value Empty) IsKnown() bool {\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "switch") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "EmptyValues") == null);
    var values: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer values.deinit();
    try render(testContext(), &values.writer, "Empty", &.{}, .{ .is_known = false });
    try std.testing.expect(std.mem.indexOf(u8, values.written(), "func EmptyValues() []Empty {\n\treturn []Empty{") != null);
    try std.testing.expect(std.mem.indexOf(u8, values.written(), "IsKnown") == null);
}

test "membership range requires every value including excluded holes" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try render(testContext(), &output.writer, "Dense", &.{
        .{ .name = "high", .value = 0 },
        .{ .name = "low", .value = -1 },
    }, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "return value >= -1 && value <= 0") != null);
    var sparse: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer sparse.deinit();
    try render(testContext(), &sparse.writer, "Holes", &.{
        .{ .name = "low_water", .value = -1 },
        .{ .name = "high", .value = 1 },
    }, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, sparse.written(), "switch value") != null);
    try std.testing.expect(std.mem.indexOf(u8, sparse.written(), "\tcase HolesLowWater:\n") != null);
}
