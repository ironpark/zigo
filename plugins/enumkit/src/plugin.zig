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
    const b = context.builder();
    var decls: std.ArrayList(plugin_api.gobuild.Decl) = .empty;
    defer decls.deinit(allocator);

    if (options.values) {
        const func_name = try std.fmt.allocPrint(allocator, "{s}Values", .{type_name});
        const doc = try std.fmt.allocPrint(allocator, "{s} returns a fresh slice of known values in declaration order.", .{func_name});
        var members: std.ArrayList(plugin_api.gobuild.Expr.Element) = .empty;
        defer members.deinit(allocator);
        for (fields) |field| {
            const member = try context.identifierAlloc(allocator, field.name, .pascal);
            try members.append(allocator, .{ .value = b.ident(try std.fmt.allocPrint(allocator, "{s}{s}", .{ type_name, member })) });
        }
        const slice = try b.sliceOf(b.ident(type_name));
        try decls.append(allocator, try b.func(.{
            .doc = .{ .text = doc },
            .name = func_name,
            .signature = .{ .explicit = .{ .results = &.{slice} } },
            .body = &.{try b.ret(&.{try b.compositeLines(slice, members.items)})},
        }));
    }

    if (options.is_known) {
        const range = semantic.enumValueRange(fields);
        var body: std.ArrayList(plugin_api.gobuild.Stmt) = .empty;
        defer body.deinit(allocator);
        if (range != null and range.?.span == fields.len) {
            try body.append(allocator, try b.ret(&.{try b.bin(
                "&&",
                try b.bin(">=", b.ident("value"), b.int(range.?.min)),
                try b.bin("<=", b.ident("value"), b.int(range.?.max)),
            )}));
        } else {
            if (fields.len != 0) {
                var cases: std.ArrayList(plugin_api.gobuild.Stmt.Case) = .empty;
                defer cases.deinit(allocator);
                for (fields) |field| {
                    const member = try context.identifierAlloc(allocator, field.name, .pascal);
                    try cases.append(allocator, .{
                        .values = try b.dupExprs(&.{b.ident(try std.fmt.allocPrint(allocator, "{s}{s}", .{ type_name, member }))}),
                        .body = try b.dupStmts(&.{try b.ret(&.{b.boolean(true)})}),
                    });
                }
                try body.append(allocator, try b.switchStmt(.{ .tag = b.ident("value"), .cases = cases.items }));
            }
            try body.append(allocator, try b.ret(&.{b.boolean(false)}));
        }
        try decls.append(allocator, try b.func(.{
            .doc = .{ .text = "IsKnown reports whether value is an exported tag; unknown open-enum values return false." },
            .receiver = .{ .name = "value", .type = type_name },
            .name = "IsKnown",
            .signature = .{ .explicit = .{ .results = &.{b.ident("bool")} } },
            .body = body.items,
        }));
    }

    try b.render(writer, decls.items, .{ .blank_after = true });
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

/// The builder keeps the strings it is handed, and the generator backs the
/// context allocator with the run arena; the tests do the same.
fn testContext(arena: *std.heap.ArenaAllocator) plugin_api.Context {
    return plugin_api.testing.context(arena.allocator(), .{ .package = "enumkit", .prefix = "zg", .functions = &.{} });
}

test "options independently disable helpers and empty enums stay valid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try render(testContext(&arena), &output.writer, "Empty", &.{}, .{ .values = false, .is_known = false });
    try std.testing.expectEqualStrings("", output.written());
    try render(testContext(&arena), &output.writer, "Empty", &.{}, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "func (value Empty) IsKnown() bool {\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "switch") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "EmptyValues") == null);
    var values: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer values.deinit();
    try render(testContext(&arena), &values.writer, "Empty", &.{}, .{ .is_known = false });
    try std.testing.expect(std.mem.indexOf(u8, values.written(), "func EmptyValues() []Empty {\n\treturn []Empty{") != null);
    try std.testing.expect(std.mem.indexOf(u8, values.written(), "IsKnown") == null);
}

test "membership range requires every value including excluded holes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try render(testContext(&arena), &output.writer, "Dense", &.{
        .{ .name = "high", .value = 0 },
        .{ .name = "low", .value = -1 },
    }, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "return value >= -1 && value <= 0") != null);
    var sparse: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer sparse.deinit();
    try render(testContext(&arena), &sparse.writer, "Holes", &.{
        .{ .name = "low_water", .value = -1 },
        .{ .name = "high", .value = 1 },
    }, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, sparse.written(), "switch value") != null);
    try std.testing.expect(std.mem.indexOf(u8, sparse.written(), "\tcase HolesLowWater:\n") != null);
}
