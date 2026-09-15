//! `json`: `MarshalJSON` and `UnmarshalJSON` for generated value structs and
//! enums.
//!
//! Go's `encoding/json` already handles a plain struct, but it spells the keys
//! the way the Go fields are spelled and it encodes an enum as its number.
//! Neither is usually what a wire format wants, and the usual fix -- struct
//! tags and a hand-written pair of methods -- has to be kept next to generated
//! code. A visit of the type node writes it instead.
const std = @import("std");
const diagnostic = @import("diagnostic");
const plugin_api = @import("plugin");
const semantic = @import("semantic");

/// The plugin's name: the `ext` key its options travel under and the prefix
/// of the diagnostics it reports.
pub const name = "JSON";

/// What a declaration says with `use(json.plugin, .{ ... })`.
pub const Options = struct {
    /// How a struct field's JSON key is spelled. An enum ignores it: an enum
    /// encodes as its Zig tag name, which is the one spelling it has.
    field_names: FieldNames = .zig,

    pub const FieldNames = enum {
        /// The Zig field name, verbatim. This is the default because it is
        /// the name the two sides already agree on.
        zig,
        /// The exported Go field name.
        go,
    };
};

pub const plugin: plugin_api.Plugin = .{
    .name = name,
    .TypeOptions = Options,
    .subjects = &.{ .value, .enumeration },
    .validate = validateDocument,
    // An enum's membership test belongs to whoever generates it. When a
    // plugin does, this one decodes through it instead of restating the tag
    // set, and the capability is what orders that plugin first.
    .uses = &.{plugin_api.capabilities.enum_known},
    .go = .{
        .visit = visit,
        // Written by the methods below. They are added to a file only when
        // its body really spells the qualifier.
        .imports = &.{
            .{ .qualifier = "json", .path = "encoding/json" },
            .{ .qualifier = "fmt", .path = "fmt" },
        },
    },
};

fn visit(context: plugin_api.GoContext, node: plugin_api.Node, b: *plugin_api.Builder) !void {
    if (node != .type) return;
    const declaration = node.type;
    const options = try context.optionsOf(plugin, .type, node) orelse return;
    switch (declaration.kind) {
        .@"enum" => try renderEnum(context, b, declaration),
        .value_struct => try renderValueStruct(context, b, declaration, options),
        else => {},
    }
}

/// Whether another plugin generates this enum's membership helpers, which is
/// what lets `UnmarshalJSON` decide "known" without a tag set of its own.
///
/// Both helpers are needed and both are one option away from being absent, so
/// a fact that only promises one of them is no use here and the switch stays.
fn hasMembershipHelpers(context: plugin_api.GoContext, declaration: semantic.TypeDecl) !bool {
    const known = plugin_api.capabilities.enum_known;
    if (!context.provided(known)) return false;
    const fact = try context.facts.get(known, .declaration(declaration)) orelse return false;
    return fact.is_known and fact.values;
}

/// An enum crosses as its Zig tag name. `String` already spells it, so
/// marshalling is one call; unmarshalling is the inverse `String` does not
/// have unless the binding asked for `.text`.
///
/// Two ways to write that inverse. On its own this plugin lists the tag names
/// in a switch, which means it decides what "known" is a second time. When
/// `enum_known` says another plugin generated the membership helpers, the
/// body walks that plugin's value list instead and asks `IsKnown` -- one tag
/// set, owned by whoever wrote it, and a body that does not grow with the
/// enum.
fn renderEnum(context: plugin_api.GoContext, b: *plugin_api.Builder, declaration: semantic.TypeDecl) !void {
    const allocator = context.allocator;
    const by_value: plugin_api.Receiver = .{ .name = "value", .type = declaration.name };
    const by_pointer: plugin_api.Receiver = .{ .name = "value", .type = declaration.name, .pointer = true };

    const unknown = try std.fmt.allocPrint(allocator, "{s}: unknown value %q", .{declaration.name});
    const reject = try b.ret(&.{try b.call(try b.selName("fmt", "Errorf"), &.{ b.string(unknown), b.ident("text") })});

    var body: std.ArrayList(plugin_api.gobuild.Stmt) = .empty;
    defer body.deinit(allocator);
    try body.append(allocator, b.declare("text", b.ident("string"), null));
    try body.append(allocator, try unmarshalInto(b, "text"));

    var unmarshal_doc: []const u8 = "UnmarshalJSON decodes a Zig tag name written by MarshalJSON.";
    if (try hasMembershipHelpers(context, declaration)) {
        unmarshal_doc = try std.fmt.allocPrint(
            allocator,
            "UnmarshalJSON decodes a Zig tag name written by MarshalJSON.\n\n{s}Values supplies the candidates and IsKnown decides which of them a name may\nselect, so this and the membership helpers cannot disagree.",
            .{declaration.name},
        );
        const values_call = try b.call(b.ident(try std.fmt.allocPrint(allocator, "{s}Values", .{declaration.name})), &.{});
        try body.append(allocator, try b.forRange(.{
            .value = "candidate",
            .over = values_call,
            .body = &.{try b.ifStmt(.{
                .cond = try b.bin(
                    "&&",
                    try b.callSel(b.ident("candidate"), "IsKnown", &.{}),
                    try b.bin("==", try b.callSel(b.ident("candidate"), "String", &.{}), b.ident("text")),
                ),
                .body = &.{
                    try b.assign(&.{try b.deref(b.ident("value"))}, "=", &.{b.ident("candidate")}),
                    try b.ret(&.{.nil}),
                },
            })},
        }));
        try body.append(allocator, reject);
    } else {
        var cases: std.ArrayList(plugin_api.gobuild.Stmt.Case) = .empty;
        defer cases.deinit(allocator);
        for (declaration.fields) |field| {
            const member = try context.identifierAlloc(allocator, field.name, .pascal);
            const tag = try std.fmt.allocPrint(allocator, "{s}{s}", .{ declaration.name, member });
            try cases.append(allocator, .{
                .values = try b.dupExprs(&.{b.string(field.name)}),
                .body = try b.dupStmts(&.{try b.assign(&.{try b.deref(b.ident("value"))}, "=", &.{b.ident(tag)})}),
            });
        }
        try body.append(allocator, try b.switchStmt(.{
            .tag = b.ident("text"),
            .cases = cases.items,
            .default = &.{reject},
        }));
        try body.append(allocator, try b.ret(&.{.nil}));
    }

    const marshal_doc = try std.fmt.allocPrint(allocator, "MarshalJSON encodes {s} as its Zig tag name.", .{declaration.name});
    try b.emit(&.{
        try b.func(.{
            .doc = .{ .text = marshal_doc },
            .receiver = by_value,
            .name = "MarshalJSON",
            .signature = .{ .explicit = .{ .results = &.{ try b.sliceOf(b.ident("byte")), b.ident("error") } } },
            .body = &.{try b.ret(&.{try b.call(try b.selName("json", "Marshal"), &.{try b.callSel(b.ident("value"), "String", &.{})})})},
            .single_line = true,
        }),
        try b.func(.{
            .doc = .{ .text = unmarshal_doc },
            .receiver = by_pointer,
            .name = "UnmarshalJSON",
            .signature = .{ .explicit = .{
                .params = &.{.{ .names = &.{"data"}, .type = try b.sliceOf(b.ident("byte")) }},
                .results = &.{b.ident("error")},
            } },
            .body = body.items,
        }),
    }, .{ .blank_after = true });
}

/// `if err := json.Unmarshal(data, &target); err != nil { return err }`, the
/// first line of both generated `UnmarshalJSON` bodies.
fn unmarshalInto(b: *plugin_api.Builder, target: []const u8) !plugin_api.gobuild.Stmt {
    return b.ifStmt(.{
        .init = try b.define(&.{"err"}, try b.call(try b.selName("json", "Unmarshal"), &.{ b.ident("data"), try b.addr(b.ident(target)) })),
        .cond = try b.bin("!=", b.ident("err"), .nil),
        .body = &.{try b.ret(&.{b.ident("err")})},
    });
}

/// A value struct crosses as an object whose keys the binding chose. The wire
/// struct carries the tags so the public struct stays the mirror of the Zig
/// one, which is what every other generated conversion reads.
fn renderValueStruct(
    context: plugin_api.GoContext,
    b: *plugin_api.Builder,
    declaration: semantic.TypeDecl,
    options: Options,
) !void {
    const allocator = context.allocator;
    const wire = try std.fmt.allocPrint(allocator, "zigo{s}JSON", .{declaration.name});
    const by_value: plugin_api.Receiver = .{ .name = "value", .type = declaration.name };
    const by_pointer: plugin_api.Receiver = .{ .name = "value", .type = declaration.name, .pointer = true };

    var fields: std.ArrayList(plugin_api.gobuild.Field) = .empty;
    defer fields.deinit(allocator);
    var to_wire: std.ArrayList(plugin_api.gobuild.Expr.Element) = .empty;
    defer to_wire.deinit(allocator);
    var from_wire: std.ArrayList(plugin_api.gobuild.Expr.Element) = .empty;
    defer from_wire.deinit(allocator);
    for (declaration.fields) |field| {
        const member = try context.identifierAlloc(allocator, field.name, .pascal);
        try fields.append(allocator, .{
            .name = member,
            .type = if (semantic.isCodepoint(field.type.?, field.semantic)) b.ident("rune") else b.goType(field.type.?),
            .tag = try std.fmt.allocPrint(allocator, "json:\"{s}\"", .{switch (options.field_names) {
                .zig => field.name,
                .go => member,
            }}),
        });
        try to_wire.append(allocator, .{ .key = member, .value = try b.selName("value", member) });
        try from_wire.append(allocator, .{ .key = member, .value = try b.selName("wire", member) });
    }

    const wire_doc = try std.fmt.allocPrint(allocator, "{s} is the wire shape of {s}: the same fields under the JSON keys the binding chose.", .{ wire, declaration.name });
    const marshal_doc = try std.fmt.allocPrint(allocator, "MarshalJSON encodes {s} under the JSON keys the binding chose.", .{declaration.name});
    try b.emit(&.{
        try b.structDecl(.{ .doc = .{ .text = wire_doc }, .name = wire, .fields = fields.items }),
        try b.func(.{
            .doc = .{ .text = marshal_doc },
            .receiver = by_value,
            .name = "MarshalJSON",
            .signature = .{ .explicit = .{ .results = &.{ try b.sliceOf(b.ident("byte")), b.ident("error") } } },
            .body = &.{try b.ret(&.{try b.call(
                try b.selName("json", "Marshal"),
                &.{try b.composite(b.ident(wire), to_wire.items)},
            )})},
        }),
        try b.func(.{
            .doc = .{ .text = "UnmarshalJSON decodes what MarshalJSON wrote." },
            .receiver = by_pointer,
            .name = "UnmarshalJSON",
            .signature = .{ .explicit = .{
                .params = &.{.{ .names = &.{"data"}, .type = try b.sliceOf(b.ident("byte")) }},
                .results = &.{b.ident("error")},
            } },
            .body = &.{
                b.declare("wire", b.ident(wire), null),
                try unmarshalInto(b, "wire"),
                try b.assign(&.{try b.deref(b.ident("value"))}, "=", &.{try b.composite(b.ident(declaration.name), from_wire.items)}),
                try b.ret(&.{.nil}),
            },
        }),
    }, .{ .blank_after = true });
}

/// The hook writes nothing for a type it cannot encode, which would leave the
/// binding author wondering. Saying so is the whole point of a plugin rule.
fn validateDocument(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    const document = context.document;
    for (document.types) |declaration| {
        _ = try context.optionsOf(plugin, .type, declaration.ext) orelse continue;
        if (declaration.kind == .@"enum" or declaration.kind == .value_struct) continue;
        try context.diagnose(.{
            .severity = .@"error",
            .code = name ++ "002",
            .message = try std.fmt.allocPrint(
                allocator,
                "`{s}` is a {s}, which has no JSON encoding to generate",
                .{ declaration.name, @tagName(declaration.kind) },
            ),
            .site = plugin_api.site.typeSite(declaration),
            .hint = "attach json to a value struct or an enum; a handle is a pointer into native memory and has no fields to encode",
        });
    }
}

test "an enum writes its tag names as string literals through the builder" {
    // The builder keeps the strings it is handed, and the generator backs the
    // context allocator with the run arena; the test does the same.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context = plugin_api.testing.goContext(arena.allocator(), .{ .package = "palette", .prefix = "zg", .functions = &.{} });
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var b = context.builder();
    b.out = &output.writer;
    try renderEnum(context, &b, .{
        .kind = .@"enum",
        .name = "Mode",
        .fields = &.{ .{ .name = "idle", .value = 0 }, .{ .name = "get_all", .value = 1 } },
    });
    const rendered = output.written();
    try std.testing.expect(std.mem.indexOf(u8, rendered, "func (value Mode) MarshalJSON() ([]byte, error) { return json.Marshal(value.String()) }\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "func (value *Mode) UnmarshalJSON(data []byte) error {\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\tcase \"get_all\":\n\t\t*value = ModeGetAll\n") != null);
}

/// A context that reports the same enum's membership helpers as generated,
/// which is what a run with `enumkit` enabled hands the visit.
fn testContextWithKnown(allocator: std.mem.Allocator, facts: *plugin_api.Facts, declaration: semantic.TypeDecl, fact: plugin_api.capabilities.enum_known.Facts) !plugin_api.GoContext {
    try facts.put(allocator, plugin_api.capabilities.enum_known, .declaration(declaration), fact);
    var context = plugin_api.testing.goContext(allocator, .{ .package = "palette", .prefix = "zg", .functions = &.{} });
    context.options.capabilities = &.{plugin_api.capabilities.enum_known.name};
    context.facts = facts;
    return context;
}

const test_mode: semantic.TypeDecl = .{
    .kind = .@"enum",
    .name = "Mode",
    .fields = &.{ .{ .name = "idle", .value = 0 }, .{ .name = "get_all", .value = 1 } },
};

test "the membership capability replaces the tag switch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var facts: plugin_api.Facts = .{};
    const context = try testContextWithKnown(arena.allocator(), &facts, test_mode, .{ .is_known = true, .values = true });
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var b = context.builder();
    b.out = &output.writer;
    try renderEnum(context, &b, test_mode);
    const rendered = output.written();
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\tfor _, candidate := range ModeValues() {\n\t\tif candidate.IsKnown() && candidate.String() == text {\n\t\t\t*value = candidate\n\t\t\treturn nil\n") != null);
    // The tag set is no longer restated here; the error is the same one.
    try std.testing.expect(std.mem.indexOf(u8, rendered, "switch") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "case \"get_all\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\treturn fmt.Errorf(\"Mode: unknown value %q\", text)\n") != null);
}

test "a fact missing either helper leaves the switch in place" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_]plugin_api.capabilities.enum_known.Facts{
        .{ .is_known = false, .values = true },
        .{ .is_known = true, .values = false },
    }) |fact| {
        var facts: plugin_api.Facts = .{};
        const context = try testContextWithKnown(arena.allocator(), &facts, test_mode, fact);
        var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer output.deinit();
        var b = context.builder();
        b.out = &output.writer;
        try renderEnum(context, &b, test_mode);
        try std.testing.expect(std.mem.indexOf(u8, output.written(), "\tcase \"get_all\":\n\t\t*value = ModeGetAll\n") != null);
        try std.testing.expect(std.mem.indexOf(u8, output.written(), "ModeValues") == null);
    }
}
