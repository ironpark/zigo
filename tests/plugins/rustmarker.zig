//! A plugin that renders for Rust and for nothing else. It exists so the
//! frame itself has something to exercise on the Rust side: one slot, filled,
//! and no `go` slot at all, which is what proves a plugin contributes to the
//! target it named and to no other.
//!
//! Inert until a case's `plugin_config` switches it on, so no golden that did
//! not ask for it can see it.
const std = @import("std");
const abi = @import("abi");
const api = @import("plugin");
const semantic = @import("semantic");

pub const plugin: api.Plugin = .{
    .name = "RUSTMARK",
    .Config = struct { enabled: bool = false },
    .subjects = &.{ .function, .handle, .enumeration },
    .rust = .{
        .visit = visit,
        .source_files = &.{.{ .enabled = enabled, .module = "rustmark", .render = renderModule }},
        // Written by the module below, and added only because its body
        // really spells the path's last segment.
        .imports = &.{ .{ .path = "core::fmt::Write" }, .{ .path = "std::collections::HashMap" } },
    },
};

fn enabled(context: api.RustContext) !bool {
    return (try context.config(plugin)).enabled;
}

/// A marker beside every type the crate rendered, a marker method beside
/// every bound method, and one item at the package boundary.
fn visit(context: api.RustContext, node: api.Node, b: *api.RustBuilder) !void {
    if (!try enabled(context)) return;
    switch (node) {
        .type => |declaration| try renderTypeMarker(context, b, declaration),
        .function => |function| try renderMethodMarker(context, b, function),
        .package_begin => try b.emit(&.{b.constItem(.{
            .doc = .{ .text = "The package this binding was generated from." },
            .visibility = .public,
            .name = "RUSTMARK_PACKAGE",
            .type = b.path("&str"),
            .value = b.string(context.program.package),
        })}, .{}),
        else => {},
    }
}

/// `pub const RUSTMARK_<TYPE>: &str = "<Type>";`, written after the type's
/// own items.
fn renderTypeMarker(context: api.RustContext, b: *api.RustBuilder, declaration: semantic.TypeDecl) !void {
    const screaming = try context.identifierAlloc(context.allocator, declaration.name, .screaming);
    const name = try std.fmt.allocPrint(context.allocator, "RUSTMARK_{s}", .{screaming});
    try b.emit(&.{b.constItem(.{
        .doc = .{ .text = "The Zig name of the type this marker was written after." },
        .visibility = .public,
        .name = name,
        .type = b.path("&str"),
        .value = b.string(declaration.name),
    })}, .{ .blank_before = true });
}

/// `pub fn <name>_marker(&self) -> &'static str`, written inside the `impl`
/// block the method was written in. A constructor has no receiver, and the
/// generator is what answers for that.
fn renderMethodMarker(context: api.RustContext, b: *api.RustBuilder, function: abi.AbiFn) !void {
    const method = context.method orelse return;
    if (method.receiver == null) return;
    if (try context.receiverFormAlloc(context.allocator, function) == null) return;
    const name = try std.fmt.allocPrint(context.allocator, "{s}_marker", .{method.public_name});
    const doc = try std.fmt.allocPrint(context.allocator, "The name `{s}` was generated under.", .{method.public_name});
    try b.emit(&.{try b.func(.{
        .doc = .{ .text = doc },
        .visibility = .public,
        .name = name,
        .signature = .{ .explicit = .{ .receiver = .reference, .result = b.path("&'static str") } },
        .body = &.{b.tail(b.string(method.public_name))},
    })}, .{ .blank_before = true });
}

/// The plugin's own module. The frame adds the generated marker and the `use`
/// block; this writes only the items.
fn renderModule(context: api.RustContext, writer: *std.Io.Writer) !void {
    if (!try enabled(context)) return;
    const b = context.builder();
    try b.render(writer, &.{
        b.constItem(.{
            .doc = .{ .text = "What this plugin calls itself." },
            .visibility = .public,
            .name = "RUSTMARK_NAME",
            .type = b.path("&str"),
            .value = b.string("RUSTMARK"),
        }),
        try b.func(.{
            .doc = .{ .text = "Writes the plugin's name into `out`." },
            .visibility = .public,
            .name = "rustmark_write",
            .generics = "<W: Write>",
            .signature = .{ .explicit = .{
                .params = &.{.{ .name = "out", .type = try b.refType(null, true, b.path("W")) }},
                .result = b.path("core::fmt::Result"),
            } },
            .body = &.{b.tail(try b.macroCall("write", .paren, &.{ b.path("out"), b.string("{RUSTMARK_NAME}") }))},
        }),
    }, .{});
}
