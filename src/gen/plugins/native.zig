//! The native half of the plugin contract, on the generator's side: ask every
//! registered plugin for its C symbols and append them to the lowered program.
//!
//! Appending is the whole design. A plugin symbol becomes an ordinary
//! `abi.AbiFn` with a synthetic `origin`, so the shim, the C header, both Go
//! raw backends and the Rust raw module carry it through the loops they
//! already run over `Program.functions`; the only thing that reads the
//! `origin.plugin` marker is the shim, which calls the plugin's Zig instead of
//! the bound library's, and the two public emitters, which write nothing for
//! it. A parallel list would have been a third thing every emitter had to
//! learn about.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const diagnostic = @import("diagnostic");
const plugin = @import("plugin");
const targets = @import("targets");
const registry = @import("registry.zig");

/// What the collection needs to know about the run: which added plugins are
/// enabled, how they are configured, and which language is being generated.
pub const Options = struct {
    plugins: ?[]const []const u8 = null,
    configurations: []const plugin.Configuration = &.{},
    target: targets.Target = targets.default,
};

/// One symbol and the plugin that contributed it.
pub const Contribution = struct {
    plugin: []const u8,
    symbol: plugin.NativeSymbol,
    /// The source module the implementation was resolved to.
    module: []const u8,
};

/// The site a native diagnostic is reported against. Plugin symbols have no
/// declaration in `semantic.json`, so the site names the plugin instead.
fn siteFor(allocator: std.mem.Allocator, name: []const u8) !diagnostic.Site {
    return .{ .path = "plugin", .declaration = try allocator.dupe(u8, name) };
}

/// Every enabled plugin's native symbols, in registration order, with the
/// module each implementation was resolved to. Reports every problem it finds
/// rather than stopping at the first, so one run names them all.
pub fn collect(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    options: Options,
    issues: *std.ArrayList(diagnostic.Diagnostic),
) ![]const Contribution {
    var found: std.ArrayList(Contribution) = .empty;
    inline for (registry.plugins, 0..) |registered, index| {
        if (comptime registered.native) |native| {
            if (registry.contributes(index, options.plugins)) if (native.symbols) |symbols| {
                const declared = try symbols(.{
                    .allocator = allocator,
                    .document = document,
                    .configurations = options.configurations,
                    .target = options.target,
                });
                for (declared) |symbol| {
                    const module = resolveModule(native, symbol) orelse {
                        try issues.append(allocator, .{
                            .severity = .@"error",
                            .code = "ZIGO068",
                            .message = try std.fmt.allocPrint(allocator, "plugin `{s}` symbol `{s}` names no native source", .{ registered.name, symbol.name }),
                            .site = try siteFor(allocator, registered.name),
                            .hint = "set `module` to one of the plugin's `native.sources`",
                        });
                        continue;
                    };
                    try found.append(allocator, .{ .plugin = registered.name, .symbol = symbol, .module = module });
                }
            };
        }
    }
    return found.toOwnedSlice(allocator);
}

/// Which of the plugin's sources implements `symbol`: the one it names, or the
/// only one it has when it names none.
fn resolveModule(native: plugin.Native, symbol: plugin.NativeSymbol) ?[]const u8 {
    if (symbol.module.len == 0) return if (native.sources.len == 1) native.sources[0].module else null;
    for (native.sources) |source| {
        if (std.mem.eql(u8, source.module, symbol.module)) return source.module;
    }
    return null;
}

/// Appends the collected symbols to `program.functions`, in the order they
/// were collected. A symbol whose signature the C ABI cannot carry, or whose
/// exported name another symbol already took, is reported and left out.
pub fn append(
    allocator: std.mem.Allocator,
    program: *abi.Program,
    contributions: []const Contribution,
    issues: *std.ArrayList(diagnostic.Diagnostic),
) !void {
    if (contributions.len == 0) return;
    var functions: std.ArrayList(abi.AbiFn) = .empty;
    try functions.appendSlice(allocator, program.functions);
    for (contributions) |contribution| {
        const owner = contribution.plugin;
        const declared = contribution.symbol;
        if (try signatureIssue(allocator, owner, declared)) |issue| {
            try issues.append(allocator, issue);
            continue;
        }
        const symbol = try plugin.nativeSymbolNameAlloc(allocator, program.prefix, owner, declared.name);
        var taken = false;
        for (functions.items) |existing| {
            if (!std.mem.eql(u8, existing.symbol, symbol)) continue;
            taken = true;
            try issues.append(allocator, .{
                .severity = .@"error",
                .code = "ZIGO066",
                .message = try std.fmt.allocPrint(allocator, "plugin `{s}` exports `{s}`, which is already exported", .{ owner, symbol }),
                .site = try siteFor(allocator, owner),
                .hint = "rename the plugin's symbol; two plugins cannot contribute the same name",
            });
        }
        if (taken) continue;

        const params = try allocator.alloc(abi.AbiParam, declared.params.len);
        const semantic_params = try allocator.alloc(semantic.Parameter, declared.params.len);
        for (declared.params, 0..) |parameter, index| {
            params[index] = .{ .name = parameter.name, .role = .value, .scalar = parameter.scalar, .source_index = index };
            semantic_params[index] = .{ .name = parameter.name, .type = nodeFor(parameter.scalar).? };
        }
        const returns_text = plugin.isNativeCString(declared.ret);
        const origin = try allocator.create(semantic.SemanticFn);
        origin.* = .{
            // The Go raw layer names a function by pascal-casing this, so the
            // plugin's own name is part of it: `TEST`'s `answer` reaches Go as
            // `TestAnswer` and can never collide with a bound `Answer`.
            .name = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ try std.ascii.allocLowerString(allocator, owner), declared.name }),
            .doc = declared.doc,
            .params = semantic_params,
            .@"return" = if (returns_text) try cStringNode(allocator) else nodeFor(declared.ret).?,
            // What makes the raw layers copy the bytes instead of handing a
            // pointer over. Lowering decides this for a bound function from
            // the hint; a plugin symbol has no hint to read, so it is stated.
            .return_semantic = if (returns_text) .c_string else null,
            .symbol = symbol,
            .custom_symbol = true,
            .plugin = .{ .plugin = owner, .module = contribution.module, .implementation = declared.implementation },
        };
        try functions.append(allocator, .{
            .symbol = symbol,
            .params = params,
            .ret = declared.ret,
            .ret_string = if (returns_text) .c_string else .none,
            .origin = origin,
        });
    }
    program.functions = try functions.toOwnedSlice(allocator);
}

/// The symbols as `semantic.json` records them, so a later comparison against
/// this document sees exactly what this run contributed.
pub fn recordAlloc(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    contributions: []const Contribution,
) ![]const semantic.PluginSymbol {
    const record = try allocator.alloc(semantic.PluginSymbol, contributions.len);
    for (contributions, record) |contribution, *entry| entry.* = .{
        .plugin = contribution.plugin,
        .name = contribution.symbol.name,
        .symbol = try plugin.nativeSymbolNameAlloc(allocator, prefix, contribution.plugin, contribution.symbol.name),
        .signature = try plugin.nativeSignatureAlloc(allocator, contribution.symbol),
    };
    return record;
}

/// The refusal for a signature the C ABI cannot carry, or null when every part
/// of it can. Pointers, aggregates and callbacks are all out: a plugin symbol
/// is a plain scalar call, which is the whole of what the header, both raw
/// backends and the Rust raw module can spell without a semantic type behind it.
fn signatureIssue(allocator: std.mem.Allocator, owner: []const u8, symbol: plugin.NativeSymbol) !?diagnostic.Diagnostic {
    var offender: ?[]const u8 = null;
    // The return may also be a C string, which is the one shape both raw
    // layers already copy out of native memory without a semantic type behind
    // it. A parameter may not: the plugin would then have to answer for the
    // lifetime of a string the caller built.
    if (!plugin.nativeScalarSupported(symbol.ret) and !plugin.isNativeCString(symbol.ret)) offender = "the return";
    for (symbol.params) |parameter| {
        if (plugin.nativeScalarSupported(parameter.scalar)) continue;
        offender = parameter.name;
        break;
    }
    const part = offender orelse return null;
    return .{
        .severity = .@"error",
        .code = "ZIGO067",
        .message = try std.fmt.allocPrint(allocator, "plugin `{s}` symbol `{s}` cannot carry {s} across the C ABI", .{ owner, symbol.name, part }),
        .site = try siteFor(allocator, owner),
        .hint = "a plugin symbol takes and returns plain scalars: bool, an 8, 16, 32 or 64-bit integer, usize, isize, f32 or f64; a return may also be `plugin.c_string`",
    };
}

/// The semantic return of a C-string symbol: the same `[]const u8` a bound
/// function carrying `.c_string` declares, so every emitter reads one shape.
fn cStringNode(allocator: std.mem.Allocator) !semantic.TypeNode {
    const element = try allocator.create(semantic.TypeNode);
    element.* = .{ .int = .{ .bits = 8, .signed = false } };
    return .{ .slice = .{ .@"const" = true, .element = element } };
}

/// The semantic type one supported scalar stands for. Every emitter that
/// reads `origin.params` rather than the lowered ones needs it, and it is
/// exact: `nativeScalarSupported` admits only the scalars this can answer for.
fn nodeFor(scalar: abi.AbiScalar) ?semantic.TypeNode {
    return switch (scalar) {
        .void => .{ .void = {} },
        .bool_u8 => .{ .bool = {} },
        .usize => .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } },
        .isize => .{ .int = .{ .bits = 64, .is_usize = true, .signed = true } },
        .signed_int => |bits| .{ .int = .{ .bits = bits, .signed = true } },
        .unsigned_int => |bits| .{ .int = .{ .bits = bits, .signed = false } },
        .float => |bits| .{ .float = .{ .bits = bits } },
        else => null,
    };
}

test "an unsupported scalar is refused rather than lowered" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const issue = try signatureIssue(arena.allocator(), "TEST", .{
        .name = "answer",
        .params = &.{.{ .name = "handle", .scalar = .{ .snapshot = "zg_value" } }},
        .implementation = "answer",
    });
    try std.testing.expectEqualStrings("ZIGO067", issue.?.code);
    try std.testing.expect(try signatureIssue(arena.allocator(), "TEST", .{ .name = "answer", .ret = .{ .unsigned_int = 32 }, .implementation = "answer" }) == null);
}

test "a second plugin symbol of the same name is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var program: abi.Program = .{ .package = "sample", .prefix = "zg", .functions = &.{} };
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    const declared: plugin.NativeSymbol = .{ .name = "answer", .ret = .{ .unsigned_int = 32 }, .implementation = "answer" };
    try append(allocator, &program, &.{
        .{ .plugin = "TEST", .symbol = declared, .module = "test_native" },
        .{ .plugin = "TEST", .symbol = declared, .module = "test_native" },
    }, &issues);
    try std.testing.expectEqual(@as(usize, 1), program.functions.len);
    try std.testing.expectEqualStrings("zg_test_answer", program.functions[0].symbol);
    try std.testing.expectEqualStrings("test_answer", program.functions[0].origin.name);
    try std.testing.expectEqualStrings("TEST", program.functions[0].origin.plugin.?.plugin);
    try std.testing.expectEqual(@as(usize, 1), issues.items.len);
    try std.testing.expectEqualStrings("ZIGO066", issues.items[0].code);
}

test "a C-string return lowers to the shape both raw layers already copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var program: abi.Program = .{ .package = "sample", .prefix = "zg", .functions = &.{} };
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    try append(allocator, &program, &.{.{
        .plugin = "BUILDINFO",
        .symbol = .{ .name = "build_info", .ret = plugin.c_string, .implementation = "buildInfo" },
        .module = "buildinfo_native",
    }}, &issues);
    try std.testing.expectEqual(@as(usize, 0), issues.items.len);
    const lowered = program.functions[0];
    try std.testing.expectEqual(abi.AbiFn.StringRole.c_string, lowered.ret_string);
    try std.testing.expect(lowered.ret.pointer.is_c_string);
    try std.testing.expect(semantic.isCStringSlice(lowered.origin.@"return", lowered.origin.return_semantic));
}

test "a C string is refused as a parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const issue = try signatureIssue(arena.allocator(), "BUILDINFO", .{
        .name = "build_info",
        .params = &.{.{ .name = "label", .scalar = plugin.c_string }},
        .ret = plugin.c_string,
        .implementation = "buildInfo",
    });
    try std.testing.expectEqualStrings("ZIGO067", issue.?.code);
}

test "the record names every contributed symbol" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const record = try recordAlloc(arena.allocator(), "zg", &.{.{
        .plugin = "TEST",
        .symbol = .{ .name = "answer", .ret = .{ .unsigned_int = 32 }, .implementation = "answer" },
        .module = "test_native",
    }});
    try std.testing.expectEqualStrings("zg_test_answer", record[0].symbol);
    try std.testing.expectEqualStrings("u32()", record[0].signature);
}
