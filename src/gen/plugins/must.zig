//! Checked-call convenience wrappers. Policy and analysis belong to this plugin.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const plugin_api = @import("plugin");
const naming = @import("naming");

pub const Config = struct { enabled: bool = false };
pub const Variant = struct { enabled: bool };
pub const plugin: plugin_api.Plugin = .{
    .name = "MUST",
    .Config = Config,
    .Facts = Variant,
    .analyze = analyze,
    .visit = visit,
};

pub fn hasVariant(context: plugin_api.Context, function: abi.AbiFn) !bool {
    return if (try context.facts.get(plugin, .function(function.origin.*))) |fact| fact.enabled else false;
}

fn analyze(context: plugin_api.AnalyzeContext) !void {
    const render = context.render;
    if (!(try render.config(plugin)).enabled) return;
    const allocator = render.allocator;
    const functions = render.program.functions;
    const info = try allocator.alloc(plugin_api.FunctionInfo, functions.len);
    for (functions, info) |function, *entry| entry.* = try render.functionInfo(function);
    for (functions, info) |function, entry| {
        // A mirror exists for a method that hands back a value beside its
        // error: `Must` is the caller's way to take the value without the
        // check. An error-only method has no value to take, so it has no
        // mirror -- `if err := m(); err != nil { panic(err) }` is the caller's
        // own line. A method `.implements` hid has no exported form to mirror.
        const returns_value = function.origin.@"return".errorPayload() != .void;
        const enabled = entry.is_public and entry.has_error and returns_value and !std.mem.eql(u8, entry.public_name, "Close") and !function.origin.goImplementsHidesOriginal();
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
        if (origin.receiver == null) {
            for (functions) |other| {
                const other_origin = other.origin.*;
                if (!semantic.optionalStringEqual(origin.package, other_origin.package)) continue;
                for (other_origin.params) |param| {
                    const opt_spec = param.goOptions() orelse continue;
                    const fields = param.flatten orelse continue;
                    const prefix_source = other_origin.goOwner() orelse other_origin.receiver;
                    const opt_names = try naming.resolveOptionsNamesAlloc(
                        allocator,
                        opt_spec.prefix,
                        opt_spec.type_name,
                        prefix_source,
                        other_origin.goName() orelse other_origin.name,
                    );
                    defer opt_names.deinit(allocator);
                    const clashes_type = std.mem.eql(u8, must_name, opt_names.type_name);
                    var clashes_field = false;
                    for (fields) |f| {
                        if (f.default == null) continue; // required fields are positional, not `With*`
                        const with_name = try opt_names.withNameAlloc(allocator, f.name);
                        defer allocator.free(with_name);
                        if (std.mem.eql(u8, must_name, with_name)) {
                            clashes_field = true;
                            break;
                        }
                    }
                    if (clashes_type or clashes_field) {
                        const other_path = try plugin_api.site.functionDeclarationAlloc(allocator, other_origin);
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
        }
    }
}

/// The mirror of one method: the values through `zigoMust`, or the value
/// and its presence flag through `zigoMustMatch`. `analyze` only enables a
/// method that has a value, so there is no error-only shape here.
fn visit(context: plugin_api.Context, node: plugin_api.Node, b: *plugin_api.Builder) !void {
    const function = switch (node) {
        .function => |value| value,
        else => return,
    };
    if (!try hasVariant(context, function)) return;
    const method = context.method.?;
    const name = try std.fmt.allocPrint(context.allocator, "Must{s}", .{method.public_name});
    const doc = try std.fmt.allocPrint(context.allocator, "{0s} calls {1s} and panics with its typed error on failure.", .{ name, method.public_name });
    // The name the generated body was written under, which differs from the
    // exported one when another plugin claimed this declaration.
    const callee = if (method.receiver_name) |receiver|
        try b.selName(receiver, method.checked_name)
    else
        b.ident(method.checked_name);
    const count = try b.resultCount(function, .{ .omit_error = true });
    const helper: []const u8 = switch (count) {
        0 => unreachable,
        1 => "zigoMust",
        else => "zigoMustMatch",
    };
    try b.emit(&.{try b.func(.{
        .doc = .{ .text = doc },
        .receiver = if (method.receiver) |receiver| .{ .name = method.receiver_name.?, .type = receiver, .pointer = true } else null,
        .name = name,
        .signature = .{ .function = .{ .function = function, .options = .{ .omit_error = true } } },
        .body = &.{try b.ret(&.{try b.callName(helper, &.{try b.callForwarding(callee, function)})})},
        .single_line = true,
    })}, .{ .blank_before = true });
}
