//! External-module contract test for reference-typed options: a plugin whose
//! declaration options name a type, a function and a set of interfaces
//! instead of spelling them as free text. Each hook resolves what it was
//! given and writes the declaration's current name, so the golden shows that
//! a reference survives the document and comes back as the declaration.
const std = @import("std");
const abi = @import("abi");
const api = @import("plugin");

pub const TypeOptions = struct {
    target: ?api.ref.Type = null,
    satisfies: []const api.ref.Interface = &.{},
};
pub const FunctionOptions = struct {
    helper: ?api.ref.Function = null,
};

pub const plugin: api.Plugin = .{
    .name = "REFS",
    .subjects = &.{ .function, .handle, .value, .enumeration },
    .FunctionOptions = FunctionOptions,
    .TypeOptions = TypeOptions,
    .go = .{ .visit = visit },
};

fn visit(context: api.GoContext, node: api.Node, b: *api.Builder) !void {
    switch (node) {
        .type => |declaration| {
            const options = try context.optionsOf(plugin, .type, node) orelse return;
            if (options.target) |reference| {
                const resolved = try context.resolveType(reference);
                try comment(context, b, "ZigoRefTarget", declaration.name, if (resolved) |target| target.name else "unresolved");
            }
            for (options.satisfies) |reference| {
                const resolved = try context.resolveInterface(reference);
                try comment(context, b, "ZigoRefInterface", declaration.name, if (resolved) |interface| interface.name else "unresolved");
            }
        },
        .function => |function| {
            const options = try context.optionsOf(plugin, .function, function.origin.ext) orelse return;
            const reference = options.helper orelse return;
            const resolved = try context.resolveFunction(reference);
            try comment(context, b, "ZigoRefHelper", function.origin.name, if (resolved) |helper| helper.name else "unresolved");
        },
        else => {},
    }
}

/// One comment per resolved reference: what it was written on, and what it
/// resolved to.
fn comment(context: api.GoContext, b: *api.Builder, kind: []const u8, owner: []const u8, resolved: []const u8) !void {
    const text = try std.fmt.allocPrint(context.allocator, "{s} {s}: {s}.", .{ kind, owner, resolved });
    try b.emit(&.{.{ .comment = .{ .text = text } }}, .{ .blank_after = true });
}
