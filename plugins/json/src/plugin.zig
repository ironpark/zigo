//! `json`: `MarshalJSON` and `UnmarshalJSON` for generated value structs and
//! enums.
//!
//! Go's `encoding/json` already handles a plain struct, but it spells the keys
//! the way the Go fields are spelled and it encodes an enum as its number.
//! Neither is usually what a wire format wants, and the usual fix -- struct
//! tags and a hand-written pair of methods -- has to be kept next to generated
//! code. A `type_hook` writes it instead.
const std = @import("std");
const diagnostic = @import("diagnostic");
const naming = @import("naming");
const plugin_api = @import("plugin");
const semantic = @import("semantic");

/// The plugin's name: the `ext` key its options travel under and the prefix
/// of the diagnostics it reports.
pub const name = "JSON";

/// What a declaration says with `extend(json.plugin, .{ ... })`.
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
    .targets = &.{ .value, .enumeration },
    .validate = validateDocument,
    .type_hook = typeHook,
    // Written by the methods below. They are added to a file only when its
    // body really spells the qualifier.
    .imports = &.{
        .{ .qualifier = "json", .path = "encoding/json" },
        .{ .qualifier = "fmt", .path = "fmt" },
    },
};

fn typeHook(context: plugin_api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    const options = try context.typeOptions(plugin, declaration) orelse return;
    switch (declaration.kind) {
        .@"enum" => try renderEnum(context, writer, declaration),
        .value_struct => try renderValueStruct(context, writer, declaration, options),
        else => {},
    }
}

/// An enum crosses as its Zig tag name. `String` already spells it, so
/// marshalling is one call; unmarshalling is the switch that `String` does not
/// have an inverse for unless the binding asked for `.text`.
fn renderEnum(context: plugin_api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    try writer.print(
        "// MarshalJSON encodes {0s} as its Zig tag name.\n" ++
            "func (value {0s}) MarshalJSON() ([]byte, error) {{ return json.Marshal(value.String()) }}\n\n" ++
            "// UnmarshalJSON decodes a Zig tag name written by MarshalJSON.\n" ++
            "func (value *{0s}) UnmarshalJSON(data []byte) error {{\n" ++
            "\tvar text string\n" ++
            "\tif err := json.Unmarshal(data, &text); err != nil {{\n\t\treturn err\n\t}}\n" ++
            "\tswitch text {{\n",
        .{declaration.name},
    );
    for (declaration.fields) |field| {
        const member = try naming.pascalAlloc(context.allocator, field.name);
        defer context.allocator.free(member);
        try writer.print("\tcase \"{s}\":\n\t\t*value = {s}{s}\n", .{ field.name, declaration.name, member });
    }
    try writer.print(
        "\tdefault:\n\t\treturn fmt.Errorf(\"{0s}: unknown value %q\", text)\n\t}}\n\treturn nil\n}}\n\n",
        .{declaration.name},
    );
}

/// A value struct crosses as an object whose keys the binding chose. The wire
/// struct carries the tags so the public struct stays the mirror of the Zig
/// one, which is what every other generated conversion reads.
fn renderValueStruct(
    context: plugin_api.Context,
    writer: *std.Io.Writer,
    declaration: semantic.TypeDecl,
    options: Options,
) !void {
    const wire = try std.fmt.allocPrint(context.allocator, "zigo{s}JSON", .{declaration.name});
    defer context.allocator.free(wire);
    try writer.print("// {s} is the wire shape of {s}: the same fields under the JSON keys the binding chose.\ntype {s} struct {{\n", .{ wire, declaration.name, wire });
    for (declaration.fields) |field| {
        const member = try naming.pascalAlloc(context.allocator, field.name);
        defer context.allocator.free(member);
        try writer.print("\t{s} ", .{member});
        if (semantic.isCodepoint(field.type.?, field.semantic))
            try writer.writeAll("rune")
        else
            try context.writeGoType(writer, field.type.?);
        try writer.print(" `json:\"{s}\"`\n", .{switch (options.field_names) {
            .zig => field.name,
            .go => member,
        }});
    }
    try writer.print("}}\n\n// MarshalJSON encodes {0s} under the JSON keys the binding chose.\nfunc (value {0s}) MarshalJSON() ([]byte, error) {{\n\treturn json.Marshal({1s}{{", .{ declaration.name, wire });
    for (declaration.fields, 0..) |field, index| {
        const member = try naming.pascalAlloc(context.allocator, field.name);
        defer context.allocator.free(member);
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{0s}: value.{0s}", .{member});
    }
    try writer.print("}})\n}}\n\n// UnmarshalJSON decodes what MarshalJSON wrote.\nfunc (value *{0s}) UnmarshalJSON(data []byte) error {{\n\tvar wire {1s}\n\tif err := json.Unmarshal(data, &wire); err != nil {{\n\t\treturn err\n\t}}\n\t*value = {0s}{{", .{ declaration.name, wire });
    for (declaration.fields, 0..) |field, index| {
        const member = try naming.pascalAlloc(context.allocator, field.name);
        defer context.allocator.free(member);
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{0s}: wire.{0s}", .{member});
    }
    try writer.writeAll("}\n\treturn nil\n}\n\n");
}

/// The hook writes nothing for a type it cannot encode, which would leave the
/// binding author wondering. Saying so is the whole point of a plugin rule.
fn validateDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.types) |declaration| {
        _ = try plugin_api.readOptions(plugin, .type, allocator, declaration.ext) orelse continue;
        if (declaration.kind == .@"enum" or declaration.kind == .value_struct) continue;
        return .{
            .severity = .@"error",
            .code = name ++ "002",
            .message = try std.fmt.allocPrint(
                allocator,
                "`{s}` is a {s}, which has no JSON encoding to generate",
                .{ declaration.name, @tagName(declaration.kind) },
            ),
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "extend a value struct or an enum; a handle is a pointer into native memory and has no fields to encode",
        };
    }
    return null;
}
