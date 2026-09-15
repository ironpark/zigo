//! External-module contract test: selective Must wrappers without emit imports
//! or Go signature parsing, with one helper file per active public package.
const std = @import("std");
const abi = @import("abi");
const api = @import("plugin");

pub const plugin: api.Plugin = .{
    .name = "WRAPTEST",
    .Config = struct { native: bool = false },
    .subjects = &.{.function},
    .go = .{ .visit = visit, .source_files = &.{.{ .pathAlloc = path, .render = helpers }} },
    // One Zig source and one symbol out of it, which is the whole native
    // path: the shim compiles the source and exports a wrapper, the C header
    // declares it, both Go raw backends bind it, the Rust raw module declares
    // it, and `abi-diff` sees it appear. Unconditional, because a plugin's
    // native contribution is part of one library whatever language is being
    // generated from it.
    .native = .{
        .sources = &.{.{ .path = "wrappers_native.zig", .module = "wraptest_native" }},
        .symbols = nativeSymbols,
    },
};

/// Inert until a case's `plugin_config` switches it on, so no golden that did
/// not ask for a native contribution can see one.
fn nativeSymbols(context: api.NativeContext) ![]const api.NativeSymbol {
    if (!(try context.config(plugin)).native) return &.{};
    return &.{.{
        .name = "answer",
        .ret = .{ .unsigned_int = 32 },
        .implementation = "answer",
        .doc = "The number this plugin contributes to the native library.",
    }};
}

fn visit(context: api.GoContext, node: api.Node, b: *api.Builder) !void {
    if (node != .function) return;
    const function = node.function;
    _ = try context.optionsOf(plugin, .function, node) orelse return;
    const writer = try b.output();
    const method = context.method.?;
    try writer.print("// Wrap{0s} panics on failure.\nfunc ", .{method.public_name});
    if (method.receiver) |receiver| try writer.print("({s} {s}{s}) ", .{ method.receiver_name.?, if (function.origin.receiverIsValue()) "" else "*", receiver });
    try writer.print("Wrap{s}", .{method.public_name});
    try context.writeParameters(writer, function);
    const count = try context.writeResultType(writer, function, .{ .omit_error = true });
    try writer.writeAll(" {\n\t");
    if (count != 0) try writer.writeAll("return ");
    try writer.print("zigoWrap{d}(", .{count});
    if (method.receiver_name) |receiver| try writer.print("{s}.", .{receiver});
    try writer.print("{s}(", .{method.public_name});
    try context.writeCallArguments(writer, function);
    try writer.writeAll("))\n}\n");
}

fn path(context: api.GoContext) ![]u8 {
    const allocator = context.allocator;
    const program = context.program;
    const options = context.options;
    return api.publicFilePathAlloc(allocator, program, options, "zigo_wrappers_gen.go");
}

fn helpers(context: api.GoContext, writer: *std.Io.Writer) !void {
    const options = context.options;
    if (options.emitsHelper("zigoWrap0")) try writer.writeAll("func zigoWrap0(err error) { if err != nil { panic(err) } }\n");
    if (options.emitsHelper("zigoWrap1")) try writer.writeAll("func zigoWrap1[T any](v T, err error) T { if err != nil { panic(err) }; return v }\n");
    if (options.emitsHelper("zigoWrap2")) try writer.writeAll("func zigoWrap2[T any](v T, ok bool, err error) (T, bool) { if err != nil { panic(err) }; return v, ok }\n");
    try nativeWrappers(context, writer);
}

/// The public side of the native contribution. Nothing is auto-wrapped: the
/// plugin reads back its own symbols and spells the call with `rawCall`, which
/// writes whatever the raw layer is called in this layout and backend.
fn nativeWrappers(context: api.GoContext, writer: *std.Io.Writer) !void {
    if (!(try context.config(plugin)).native) return;
    const b = context.builder();
    for (try context.nativeSymbols(plugin)) |symbol| {
        const name = try context.identifierAlloc(context.allocator, symbol.origin.name, .pascal);
        const doc = try std.fmt.allocPrint(context.allocator, "{s} returns what this plugin's own native symbol answers.", .{name});
        try b.render(writer, &.{try b.func(.{
            .doc = .{ .text = doc },
            .name = name,
            .signature = .{ .explicit = .{ .results = &.{b.ident("uint32")} } },
            .body = &.{try b.ret(&.{try b.rawCall(symbol.symbol, &.{})})},
            .single_line = true,
        })}, .{});
    }
}
