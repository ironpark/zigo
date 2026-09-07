//! `satisfies`: the compile-time assertion that a generated Go type implements
//! an interface the binding names.
//!
//! Go has no way to declare that a type implements an interface, so the idiom
//! is `var _ io.ReadWriteCloser = (*Document)(nil)`: a compiler error the day
//! a method changes shape, rather than a caller's build breaking later. Writing
//! that line by hand means keeping a file next to generated code, which is
//! what a `type_hook` is for.
const std = @import("std");
const diagnostic = @import("diagnostic");
const plugin_api = @import("plugin");
const semantic = @import("semantic");

/// The plugin's name: the `ext` key its options travel under and the prefix
/// of the diagnostics it reports.
pub const name = "SATIS";

/// What a declaration says with `extend(satisfies.plugin, .{ ... })`.
pub const Options = struct {
    /// Qualified Go interface names, such as `io.ReadWriteCloser`. The
    /// qualifier has to be a package the generated file already imports; the
    /// import block is derived from the body, so writing the name is what
    /// brings the package in.
    interfaces: []const []const u8 = &.{},
};

pub const plugin: plugin_api.Plugin = .{
    .name = name,
    .TypeOptions = Options,
    .targets = &.{ .handle, .value, .enumeration, .tagged_union },
    .validate = validateDocument,
    .type_hook = typeHook,
};

/// The assertion goes after the type, in the file that declares it, so the
/// two are read together and `go build` reports them together.
fn typeHook(context: plugin_api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    const options = try context.typeOptions(plugin, declaration) orelse return;
    for (options.interfaces) |interface| {
        // `(*T)(nil)` is the spelling that works either way: a pointer
        // type's method set contains the value-receiver methods too, so one
        // assertion covers a handle and a value struct alike.
        try writer.print(
            "// {0s} satisfies {1s}; this assertion stops compiling the day it does not.\nvar _ {1s} = (*{0s})(nil)\n\n",
            .{ declaration.name, interface },
        );
    }
}

/// A name Go cannot resolve would reach the user as a compile error in
/// generated code, which is exactly the report a plugin exists to replace.
fn validateDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.types) |declaration| {
        const options = try plugin_api.readOptions(plugin, .type, allocator, declaration.ext) orelse continue;
        for (options.interfaces) |interface| {
            const dot = std.mem.indexOfScalar(u8, interface, '.') orelse return .{
                .severity = .@"error",
                .code = name ++ "002",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "`{s}` claims interface `{s}`, which names no package",
                    .{ declaration.name, interface },
                ),
                .site = .{ .path = "semantic.json", .declaration = declaration.name },
                .hint = "write the interface as `<package>.<Name>`; the qualifier is what brings its import into the generated file",
            };
            if (dot == 0 or dot + 1 == interface.len) return .{
                .severity = .@"error",
                .code = name ++ "002",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "`{s}` claims interface `{s}`, which is not a qualified Go name",
                    .{ declaration.name, interface },
                ),
                .site = .{ .path = "semantic.json", .declaration = declaration.name },
                .hint = "write the interface as `<package>.<Name>`",
            };
        }
    }
    return null;
}
