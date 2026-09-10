//! Checked-call convenience wrappers. Policy and analysis belong to this plugin.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const plugin_api = @import("plugin");

pub const Config = struct { enabled: bool = false };
pub const Variant = struct { enabled: bool };
pub const plugin: plugin_api.Plugin = .{
    .name = "MUST",
    .Config = Config,
    .Facts = Variant,
    .analyze = analyze,
    .method_hook = methodHook,
};

pub fn hasVariant(context: plugin_api.Context, function: abi.AbiFn) !bool {
    return if (try context.options.facts.get(plugin, .function(function.origin.*))) |fact| fact.enabled else false;
}

fn analyze(context: plugin_api.AnalyzeContext) !void {
    const render = context.render;
    if (!(try render.config(plugin)).enabled) return;
    const allocator = render.allocator;
    const functions = render.program.functions;
    const info = try allocator.alloc(plugin_api.FunctionInfo, functions.len);
    for (functions, info) |function, *entry| entry.* = try render.functionInfo(function);
    for (functions, info) |function, entry| {
        const enabled = entry.is_public and entry.has_error and !std.mem.eql(u8, entry.public_name, "Close");
        try context.facts.put(allocator, plugin, .function(function.origin.*), .{ .enabled = enabled });
        if (!enabled) continue;
        const must_name = try std.fmt.allocPrint(allocator, "Must{s}", .{entry.public_name});
        const origin = function.origin.*;
        const path = try plugin_api.site.functionDeclarationAlloc(allocator, origin);
        if (origin.receiver == null) for (render.program.types) |declaration| {
            if (!semantic.optionalStringEqual(declaration.package, origin.package) or !std.mem.eql(u8, declaration.name, must_name)) continue;
            try context.diagnose(.{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(allocator, "public Go name `{s}` collides between type `{s}` and generated Must variant for `{s}`", .{ must_name, declaration.zig_path orelse declaration.name, path }),
                .site = plugin_api.site.functionSiteFor(origin, path),
                .hint = "rename the function or conflicting type so the generated Must name is unique",
            });
        };
        for (functions, info) |other, other_info| {
            if (!other_info.is_public or !semantic.optionalStringEqual(origin.receiver, other.origin.receiver) or !semantic.optionalStringEqual(origin.package, other.origin.package) or !std.mem.eql(u8, must_name, other_info.public_name)) continue;
            const other_path = try plugin_api.site.functionDeclarationAlloc(allocator, other.origin.*);
            try context.diagnose(.{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(allocator, "public Go name `{s}` collides between `{s}` and generated Must variant for `{s}`", .{ must_name, other_path, path }),
                .site = plugin_api.site.functionSiteFor(origin, path),
                .hint = "rename one declaration so the generated Must name is unique",
            });
        }
    }
}

fn methodHook(context: plugin_api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    if (!try hasVariant(context, function)) return;
    const method = context.method.?;
    try writer.print("\n// Must{0s} calls {0s} and panics with its typed error on failure.\n", .{method.public_name});
    if (method.receiver) |receiver|
        try writer.print("func ({s} *{s}) Must{s}", .{ method.receiver_name.?, receiver, method.public_name })
    else
        try writer.print("func Must{s}", .{method.public_name});
    try context.writeParameters(writer, function);
    const count = try context.writeResultType(writer, function, .{ .omit_error = true });
    try writer.writeAll(" { ");
    try writer.writeAll(switch (count) {
        0 => "_ = zigoMust(struct{}{}, ",
        1 => "return zigoMust(",
        else => "return zigoMustMatch(",
    });
    if (method.receiver_name) |receiver| try writer.print("{s}.", .{receiver});
    try writer.print("{s}(", .{method.public_name});
    try context.writeCallArguments(writer, function);
    try writer.writeAll(")) }\n");
}
