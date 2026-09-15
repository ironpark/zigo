//! Ordered enum values and membership helpers for the generated Go and Rust
//! surfaces.
//!
//! One feature set, two render slots. The options say what the caller wants;
//! each slot says how that language spells it, and the two spellings differ
//! more than a naming convention would suggest -- Go's enum is an integer
//! newtype, so every value has to be tested, while Rust's closed enum makes
//! an unknown value unrepresentable.
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
/// The capability this plugin publishes: which membership helpers an enum
/// got. It is defined on the contract, so a consumer reads it without
/// importing this file.
pub const known = plugin_api.capabilities.enum_known;
pub const plugin: plugin_api.Plugin = .{
    .name = name,
    .TypeOptions = Options,
    .subjects = &.{.enumeration},
    .provides = &.{known},
    .analyze = analyze,
    .go = .{ .visit = visitGo },
    .rust = .{ .visit = visitRust },
    .validate = validateDocument,
};

/// One fact per enum this plugin is attached to, recorded before any package
/// is rendered so a consumer's render slot can read it. The options alone
/// decide it: both slots emit exactly what they ask for, whatever the
/// language spells them as.
fn analyze(context: plugin_api.AnalyzeContext) !void {
    for (context.render.program.types) |declaration| {
        if (declaration.kind != .@"enum") continue;
        const options = try context.optionsOf(plugin, .type, declaration.ext) orelse continue;
        try context.provide(plugin, known, .declaration(declaration), .{
            .is_known = options.is_known,
            .values = options.values,
        });
    }
}

/// The enum a `type` node carries, with the options it attached and the tags
/// that reach the public surface. Shared by both slots: which language is
/// being written decides what is rendered, never which declarations are, so
/// the answer is taken once and spelled twice.
const Attachment = struct {
    declaration: semantic.TypeDecl,
    fields: []const semantic.TypeField,
    options: Options,
};

/// Generic over the context because `GoContext` and `RustContext` are
/// separate types that answer `optionsOf` and `program` identically; this is
/// the whole of what the two slots share.
fn attachment(context: anytype, node: plugin_api.Node) !?Attachment {
    if (node != .type) return null;
    const declaration = node.type;
    const options = try context.optionsOf(plugin, .type, node) orelse return null;
    return .{
        .declaration = declaration,
        .fields = context.program.liveFields(declaration.name),
        .options = options,
    };
}

fn visitGo(context: plugin_api.GoContext, node: plugin_api.Node, b: *plugin_api.Builder) !void {
    const attached = try attachment(context, node) orelse return;
    try render(context, b, attached.declaration.name, attached.fields, attached.options);
}

fn visitRust(context: plugin_api.RustContext, node: plugin_api.Node, b: *plugin_api.RustBuilder) !void {
    const attached = try attachment(context, node) orelse return;
    try renderRust(context, b, attached.declaration, attached.fields, attached.options);
}

fn render(context: plugin_api.GoContext, b: *plugin_api.Builder, type_name: []const u8, fields: []const semantic.TypeField, options: Options) !void {
    const allocator = context.allocator;
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

    try b.emit(decls.items, .{ .blank_after = true });
}

/// Whether the crate renders this enum as an integer newtype rather than a
/// Rust `enum`, which is the same rule `emit_rust/enums.zig` applies.
fn isOpen(declaration: semantic.TypeDecl) bool {
    return !declaration.exhaustive or (declaration.open orelse false);
}

/// The same feature set for the crate, written into an `impl` block beside
/// the generated enum.
///
/// `Display` and `FromStr` are absent on purpose. The Rust emitter already
/// writes both for an enum the binding registered with `.text`, which is the
/// same condition Go's `String` and `Parse<Enum>` are written under; adding
/// them here would be a second impl of one trait rather than a feature.
fn renderRust(
    context: plugin_api.RustContext,
    b: *plugin_api.RustBuilder,
    declaration: semantic.TypeDecl,
    fields: []const semantic.TypeField,
    options: Options,
) !void {
    const allocator = context.allocator;
    var items: std.ArrayList(plugin_api.rustbuild.Item) = .empty;
    defer items.deinit(allocator);

    if (options.values) {
        var members: std.ArrayList(plugin_api.rustbuild.Expr) = .empty;
        defer members.deinit(allocator);
        for (fields) |field| {
            const member = try context.identifierAlloc(allocator, field.name, .pascal);
            try members.append(allocator, b.path(try std.fmt.allocPrint(allocator, "Self::{s}", .{member})));
        }
        // A borrowed static rather than Go's fresh slice: the array is
        // immutable and lives in the binary, so there is nothing for a caller
        // to mutate and nothing to allocate per call.
        try items.append(allocator, try b.func(.{
            .doc = .{ .text = "The known values, in declaration order." },
            .visibility = .public,
            .name = "values",
            .signature = .{ .explicit = .{ .result = try b.refType("'static", false, try b.sliceOf(b.path("Self"))) } },
            .body = &.{b.tail(try b.addr(try b.array(members.items)))},
        }));
    }

    if (options.is_known) try items.append(allocator, try b.func(.{
        .doc = .{ .text = if (isOpen(declaration))
            "Reports whether this value is an exported tag; an unknown open-enum value is false."
        else
            "Reports whether this value is an exported tag.\n\nAlways true: a closed enum makes an unknown value unrepresentable in Rust." },
        .visibility = .public,
        .name = "is_known",
        .signature = .{ .explicit = .{ .receiver = .value, .result = b.path("bool") } },
        .body = &.{b.tail(try knownExpr(b, declaration, fields))},
    }));

    if (items.items.len == 0) return;
    try b.emit(&.{try b.implBlock(.{ .type = b.typeName(declaration.name), .items = items.items })}, .{ .blank_before = true });
}

/// What `is_known` returns.
///
/// A closed enum is a real Rust `enum`, so every value of the type is one of
/// the variants the crate wrote and there is nothing to test. Go has to test
/// because its enum is an integer newtype -- the same reason the Go slot
/// always emits a body. An open enum is a `#[repr(transparent)]` newtype, so
/// the test is on its tag.
fn knownExpr(b: *plugin_api.RustBuilder, declaration: semantic.TypeDecl, fields: []const semantic.TypeField) !plugin_api.rustbuild.Expr {
    if (!isOpen(declaration)) return b.boolean(true);
    if (fields.len == 0) return b.boolean(false);
    const tag = try b.fieldOf(b.path("self"), "0");
    const range = semantic.enumValueRange(fields);
    if (range != null and range.?.span == fields.len) {
        // `contains` rather than two comparisons, which `clippy::manual_range_contains`
        // rejects, and rather than a `matches!` range pattern, whose arm would
        // be unreachable when the run covers the whole tag domain.
        const span = try b.paren(try b.range(b.int(range.?.min), b.int(range.?.max), true));
        return b.methodCall(span, "contains", &.{try b.addr(tag)});
    }
    // Holes: an or-pattern. `matches!` rather than a `match` returning
    // booleans, which `clippy::match_like_matches_macro` rejects. A sparse set
    // can never cover the tag domain, so this arm is always reachable.
    var pattern: std.Io.Writer.Allocating = .init(b.allocator);
    defer pattern.deinit();
    for (fields, 0..) |field, index| {
        if (index != 0) try pattern.writer.writeAll(" | ");
        try pattern.writer.print("{d}", .{field.value.?});
    }
    return b.macroCall("matches", .paren, &.{ tag, b.raw(try b.allocator.dupe(u8, pattern.written())) });
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
fn testContext(arena: *std.heap.ArenaAllocator) plugin_api.GoContext {
    return plugin_api.testing.goContext(arena.allocator(), .{ .package = "enumkit", .prefix = "zg", .functions = &.{} });
}

/// The builder a visit is handed: the same context, writing into `writer`.
fn testBuilder(context: plugin_api.GoContext, writer: *std.Io.Writer) plugin_api.Builder {
    var b = context.builder();
    b.out = writer;
    return b;
}

test "options independently disable helpers and empty enums stay valid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var empty = testBuilder(testContext(&arena), &output.writer);
    try render(empty.context, &empty, "Empty", &.{}, .{ .values = false, .is_known = false });
    try std.testing.expectEqualStrings("", output.written());
    try render(empty.context, &empty, "Empty", &.{}, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "func (value Empty) IsKnown() bool {\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "switch") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "EmptyValues") == null);
    var values: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer values.deinit();
    var only_values = testBuilder(testContext(&arena), &values.writer);
    try render(only_values.context, &only_values, "Empty", &.{}, .{ .is_known = false });
    try std.testing.expect(std.mem.indexOf(u8, values.written(), "func EmptyValues() []Empty {\n\treturn []Empty{") != null);
    try std.testing.expect(std.mem.indexOf(u8, values.written(), "IsKnown") == null);
}

test "membership range requires every value including excluded holes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var dense = testBuilder(testContext(&arena), &output.writer);
    try render(dense.context, &dense, "Dense", &.{
        .{ .name = "high", .value = 0 },
        .{ .name = "low", .value = -1 },
    }, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "return value >= -1 && value <= 0") != null);
    var sparse: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer sparse.deinit();
    var holes = testBuilder(testContext(&arena), &sparse.writer);
    try render(holes.context, &holes, "Holes", &.{
        .{ .name = "low_water", .value = -1 },
        .{ .name = "high", .value = 1 },
    }, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, sparse.written(), "switch value") != null);
    try std.testing.expect(std.mem.indexOf(u8, sparse.written(), "\tcase HolesLowWater:\n") != null);
}

/// The Rust counterparts of the two helpers above. `plugin.testing` answers
/// `writeTypeName`, which is all the Rust slot asks the generator for.
fn testRustContext(arena: *std.heap.ArenaAllocator) plugin_api.RustContext {
    return plugin_api.testing.rustContext(arena.allocator(), .{ .package = "enumkit", .prefix = "zg", .functions = &.{} });
}

fn testRustBuilder(context: plugin_api.RustContext, writer: *std.Io.Writer) plugin_api.RustBuilder {
    var b = context.builder();
    b.out = writer;
    return b;
}

fn closedEnum(fields: []const semantic.TypeField) semantic.TypeDecl {
    return .{ .name = "Mode", .kind = .@"enum", .fields = fields, .exhaustive = true };
}

fn openEnum(fields: []const semantic.TypeField) semantic.TypeDecl {
    return .{ .name = "Mode", .kind = .@"enum", .fields = fields, .exhaustive = false };
}

test "the Rust slot writes one impl block and the options gate its items" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fields: []const semantic.TypeField = &.{
        .{ .name = "fast", .value = 1 },
        .{ .name = "low_water", .value = 2 },
    };

    var both: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer both.deinit();
    var b = testRustBuilder(testRustContext(&arena), &both.writer);
    try renderRust(b.context, &b, closedEnum(fields), fields, .{});
    try std.testing.expectEqualStrings(
        \\
        \\impl crate::Mode {
        \\    /// The known values, in declaration order.
        \\    pub fn values() -> &'static [Self] {
        \\        &[Self::Fast, Self::LowWater]
        \\    }
        \\
        \\    /// Reports whether this value is an exported tag.
        \\    ///
        \\    /// Always true: a closed enum makes an unknown value unrepresentable in Rust.
        \\    pub fn is_known(self) -> bool {
        \\        true
        \\    }
        \\}
        \\
    , both.written());

    // Neither option leaves no impl block at all, rather than an empty one.
    var none: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer none.deinit();
    var off = testRustBuilder(testRustContext(&arena), &none.writer);
    try renderRust(off.context, &off, closedEnum(fields), fields, .{ .values = false, .is_known = false });
    try std.testing.expectEqualStrings("", none.written());

    var only: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer only.deinit();
    var values_only = testRustBuilder(testRustContext(&arena), &only.writer);
    try renderRust(values_only.context, &values_only, closedEnum(fields), fields, .{ .is_known = false });
    try std.testing.expect(std.mem.indexOf(u8, only.written(), "pub fn values()") != null);
    try std.testing.expect(std.mem.indexOf(u8, only.written(), "is_known") == null);
}

test "an open enum tests its tag, by range when the values are contiguous" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var dense: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer dense.deinit();
    var contiguous = testRustBuilder(testRustContext(&arena), &dense.writer);
    const run: []const semantic.TypeField = &.{ .{ .name = "high", .value = 0 }, .{ .name = "low", .value = -1 } };
    try renderRust(contiguous.context, &contiguous, openEnum(run), run, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, dense.written(), "        (-1..=0).contains(&self.0)\n") != null);

    var sparse: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer sparse.deinit();
    var holes = testRustBuilder(testRustContext(&arena), &sparse.writer);
    const gapped: []const semantic.TypeField = &.{ .{ .name = "low_water", .value = -1 }, .{ .name = "high", .value = 1 } };
    try renderRust(holes.context, &holes, openEnum(gapped), gapped, .{ .values = false });
    try std.testing.expect(std.mem.indexOf(u8, sparse.written(), "        matches!(self.0, -1 | 1)\n") != null);

    // An open enum may publish no names at all; nothing is then known.
    var empty: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer empty.deinit();
    var nameless = testRustBuilder(testRustContext(&arena), &empty.writer);
    try renderRust(nameless.context, &nameless, openEnum(&.{}), &.{}, .{});
    try std.testing.expect(std.mem.indexOf(u8, empty.written(), "        &[]\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, empty.written(), "        false\n") != null);
}
