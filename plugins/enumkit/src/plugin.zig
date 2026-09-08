//! Ordered enum values and membership helpers for the generated Go surface.
const std = @import("std");
const naming = @import("naming");
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
    .targets = &.{.enumeration},
    .type_hook = typeHook,
    .validate = validateDocument,
};

fn typeHook(context: plugin_api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    const options = try context.typeOptions(plugin, declaration) orelse return;
    try render(context.allocator, writer, declaration.name, context.program.liveFields(declaration.name), options);
}

fn render(allocator: std.mem.Allocator, writer: *std.Io.Writer, type_name: []const u8, fields: []const semantic.TypeField, options: Options) !void {
    if (options.values) {
        try writer.print("// {0s}Values returns a fresh slice of known values in declaration order.\nfunc {0s}Values() []{0s} {{\n\treturn []{0s}{{\n", .{type_name});
        for (fields) |field| {
            const member = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(member);
            try writer.print("\t\t{s}{s},\n", .{ type_name, member });
        }
        try writer.writeAll("\t}\n}\n\n");
    }
    if (options.is_known) {
        try writer.print("// IsKnown reports whether value is an exported tag; unknown open-enum values return false.\nfunc (value {s}) IsKnown() bool {{\n", .{type_name});
        const range = semantic.enumValueRange(fields);
        if (range != null and range.?.span == fields.len) {
            try writer.print("\treturn value >= {d} && value <= {d}\n}}\n\n", .{ range.?.min, range.?.max });
            return;
        }
        if (fields.len != 0) {
            try writer.writeAll("\tswitch value {\n");
            for (fields) |field| {
                const member = try naming.pascalAlloc(allocator, field.name);
                defer allocator.free(member);
                try writer.print("\tcase {s}{s}:\n\t\treturn true\n", .{ type_name, member });
            }
            try writer.writeAll("\t}\n");
        }
        try writer.writeAll("\treturn false\n}\n\n");
    }
}

fn validateDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.types) |declaration| {
        _ = try plugin_api.readOptions(plugin, .type, allocator, declaration.ext) orelse continue;
        if (declaration.kind == .@"enum" and declaration.go_adapter == null) continue;
        return .{
            .severity = .@"error",
            .code = name ++ "002",
            .message = try std.fmt.allocPrint(allocator, "`{s}` requires a generated enum type for enumkit helpers", .{declaration.name}),
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "attach enumkit to an enum without a Go adapter",
        };
    }
    return null;
}

test "options independently disable helpers and empty enums stay valid" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try render(std.testing.allocator, &output.writer, "Empty", &.{}, .{ .values = false, .is_known = false });
    try std.testing.expectEqualStrings("", output.written());
    try render(std.testing.allocator, &output.writer, "Empty", &.{}, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "IsKnown() bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "switch") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "EmptyValues") == null);
    var values: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer values.deinit();
    try render(std.testing.allocator, &values.writer, "Empty", &.{}, .{ .is_known = false });
    try std.testing.expect(std.mem.indexOf(u8, values.written(), "return []Empty{") != null);
    try std.testing.expect(std.mem.indexOf(u8, values.written(), "IsKnown") == null);
}

test "membership range requires every value including excluded holes" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try render(std.testing.allocator, &output.writer, "Dense", &.{
        .{ .name = "high", .value = 0 },
        .{ .name = "low", .value = -1 },
    }, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "return value >= -1 && value <= 0") != null);
    var sparse: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer sparse.deinit();
    try render(std.testing.allocator, &sparse.writer, "Holes", &.{
        .{ .name = "low", .value = -1 },
        .{ .name = "high", .value = 1 },
    }, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, sparse.written(), "switch value") != null);
}
