const std = @import("std");
const bindings = @import("bindings");
const coverage = @import("coverage.zig");
const names = @import("names.zig");
const plugin = @import("plugin");
const plugin_registry = @import("plugin_registry");
const semantic = @import("semantic");
const walk = @import("walk.zig");

/// The C symbols the registered plugins contribute, recorded in the document.
///
/// The reflector writes them rather than the generator because `semantic.json`
/// is what `abi-diff` compares: a document from before a plugin was registered
/// carries no section at all, so its symbols show up as added exactly once.
/// A symbol whose signature the C ABI cannot carry is left out here and
/// reported by the generator, which is where every diagnostic belongs.
fn pluginSymbols(allocator: std.mem.Allocator, document: semantic.Semantic, prefix: []const u8) !?[]const semantic.PluginSymbol {
    var found: std.ArrayList(semantic.PluginSymbol) = .empty;
    inline for (plugin_registry.plugins) |registered| {
        if (comptime registered.native) |native| {
            if (native.symbols) |symbols| for (try symbols(.{
                .allocator = allocator,
                .document = document,
                .configurations = plugin_registry.configurations,
            })) |symbol| {
                const signature = plugin.nativeSignatureAlloc(allocator, symbol) catch |err| switch (err) {
                    error.OutOfMemory => return err,
                    else => continue,
                };
                try found.append(allocator, .{
                    .plugin = registered.name,
                    .name = symbol.name,
                    .symbol = try plugin.nativeSymbolNameAlloc(allocator, prefix, registered.name, symbol.name),
                    .signature = signature,
                });
            };
        }
    }
    if (found.items.len == 0) return null;
    return try found.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    // Beyond the optional source root the trailing arguments are the root
    // sources of the modules the bound module imports, in build-graph order.
    if (args.len >= 5 and (std.mem.eql(u8, args[1], "coverage") or std.mem.eql(u8, args[1], "coverage-json"))) {
        const document = try walk.reflect(allocator, bindings.bindings, args[2], args[3]);
        var source_document = try coverage.sourceDocument(allocator, bindings.bindings, args[2], args[3]);
        var stderr_buffer: [1024]u8 = undefined;
        var stderr = std.Io.File.Writer.init(.stderr(), init.io, &stderr_buffer);
        try names.applyWithCoverageImports(
            allocator,
            init.io,
            &source_document,
            args[4],
            if (args.len >= 6) args[5] else null,
            if (args.len > 6) args[6..] else &.{},
            &stderr.interface,
        );
        try stderr.interface.flush();
        const report = try coverage.classify(allocator, bindings.bindings, args[2], document, source_document.functions);
        var stdout_buffer: [4096]u8 = undefined;
        var stdout = std.Io.File.Writer.init(.stdout(), init.io, &stdout_buffer);
        if (std.mem.eql(u8, args[1], "coverage-json")) {
            const json = try report.json(allocator);
            try stdout.interface.writeAll(json);
            try stdout.interface.writeByte('\n');
        } else try report.render(&stdout.interface);
        try stdout.interface.flush();
        return;
    }
    // <name> <prefix> <bindings.zig> [source_root [dependency_root...]]
    if (args.len < 4) return error.InvalidArguments;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.Writer.init(.stderr(), init.io, &stderr_buffer);
    var document = try walk.reflect(allocator, bindings.bindings, args[1], args[2]);
    try names.apply(
        allocator,
        init.io,
        &document,
        args[3],
        if (args.len >= 5) args[4] else null,
        if (args.len > 5) args[5..] else &.{},
        &stderr.interface,
    );
    try names.writeWarnings(&stderr.interface, document);
    try stderr.interface.flush();
    document.plugin_symbols = try pluginSymbols(allocator, document, args[2]);
    const semantic_json = try document.serialize(allocator);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), init.io, &stdout_buffer);
    try stdout.interface.writeAll(semantic_json);
    try stdout.interface.flush();
}
