//! `satisfies`: the compile-time assertion that a generated Go type implements
//! an interface the binding names.
//!
//! Go has no way to declare that a type implements an interface, so the idiom
//! is `var _ io.ReadWriteCloser = (*Document)(nil)`: a compiler error the day
//! a method changes shape, rather than a caller's build breaking later. Writing
//! that line by hand means keeping a file next to generated code, which is
//! what a visit of the type node is for.
const std = @import("std");
const diagnostic = @import("diagnostic");
const plugin_api = @import("plugin");
const semantic = @import("semantic");

/// The plugin's name: the `ext` key its options travel under and the prefix
/// of the diagnostics it reports.
pub const name = "SATIS";

/// What a declaration says with `use(satisfies.plugin, .{ ... })`.
pub const Options = struct {
    /// Which method set the assertion checks; pointer preserves the legacy default.
    form: enum { pointer, value } = .pointer,
    /// Qualified Go interface names, such as `io.ReadWriteCloser`. The
    /// qualifier has to be a package the generated file already imports; the
    /// import block is derived from the body, so writing the name is what
    /// brings the package in.
    interfaces: []const []const u8 = &.{},
};

pub const plugin: plugin_api.Plugin = .{
    .name = name,
    .TypeOptions = Options,
    .subjects = &.{ .handle, .value, .enumeration, .tagged_union },
    .validate = validateDocument,
    .go = .{ .visit = visit },
};

/// The assertion goes after the type, in the file that declares it, so the
/// two are read together and `go build` reports them together.
fn visit(context: plugin_api.GoContext, node: plugin_api.Node, b: *plugin_api.Builder) !void {
    if (node != .type) return;
    const declaration = node.type;
    const options = try context.optionsOf(plugin, .type, node) orelse return;
    for (options.interfaces) |interface| {
        const doc = try std.fmt.allocPrint(context.allocator, "{0s} satisfies {1s}; this assertion stops compiling the day it does not.", .{ declaration.name, interface });
        defer context.allocator.free(doc);
        try b.emit(&.{try b.assertImplements(.{
            .doc = .{ .text = doc },
            .interface = b.raw(interface),
            .type_name = declaration.name,
            // A typed zero works for enums and other non-struct value types too.
            .form = switch (options.form) {
                .pointer => .pointer,
                .value => .value,
            },
        })}, .{ .blank_after = true });
    }
}

/// A name Go cannot resolve would reach the user as a compile error in
/// generated code, which is exactly the report a plugin exists to replace.
fn validateDocument(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    const document = context.document;
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    errdefer issues.deinit(allocator);
    for (document.types) |declaration| {
        const options = try context.optionsOf(plugin, .type, declaration.ext) orelse continue;
        for (options.interfaces) |interface| {
            const dot = std.mem.indexOfScalar(u8, interface, '.');
            if (dot != null and dot.? != 0 and dot.? + 1 != interface.len) continue;
            try issues.append(allocator, .{
                .severity = .@"error",
                .code = name ++ "002",
                .message = try std.fmt.allocPrint(allocator, "`{s}` claims interface `{s}`, which {s}", .{
                    declaration.name, interface, if (dot == null) "names no package" else "is not a qualified Go name",
                }),
                .site = plugin_api.site.typeSite(declaration),
                .hint = if (dot == null) "write the interface as `<package>.<Name>`; the qualifier is what brings its import into the generated file" else "write the interface as `<package>.<Name>`",
            });
        }
    }
    for (issues.items) |issue| try context.diagnose(issue);
}

test "each claimed interface gets one assertion in the requested form" {
    // Options read off `ext` live on the context's allocator, which the
    // generator backs with the run arena; the test does the same.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context = plugin_api.testing.goContext(arena.allocator(), .{ .package = "streams", .prefix = "zg", .functions = &.{} });
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var b = context.builder();
    b.out = &output.writer;
    const options = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), "{\"form\":\"value\",\"interfaces\":[\"fmt.Stringer\",\"io.Closer\"]}", .{});
    try visit(context, .{ .type = .{ .kind = .@"opaque", .name = "Document", .ext = .{ .entries = &.{.{ .plugin = name, .options = options }} } } }, &b);
    try std.testing.expectEqualStrings(
        "// Document satisfies fmt.Stringer; this assertion stops compiling the day it does not.\nvar _ fmt.Stringer = *new(Document)\n\n" ++
            "// Document satisfies io.Closer; this assertion stops compiling the day it does not.\nvar _ io.Closer = *new(Document)\n\n",
        output.written(),
    );
    output.clearRetainingCapacity();
    try visit(context, .{ .type = .{ .kind = .@"opaque", .name = "Document" } }, &b);
    try std.testing.expectEqualStrings("", output.written());
}
