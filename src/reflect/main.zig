const std = @import("std");
const bindings = @import("bindings");
const coverage = @import("coverage.zig");
const names = @import("names.zig");
const walk = @import("walk.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if ((args.len == 5 or args.len == 6) and (std.mem.eql(u8, args[1], "coverage") or std.mem.eql(u8, args[1], "coverage-json"))) {
        const document = try walk.reflect(allocator, bindings.bindings, args[2], args[3]);
        var source_document = try coverage.sourceDocument(allocator, bindings.bindings, args[2], args[3]);
        var stderr_buffer: [1024]u8 = undefined;
        var stderr = std.Io.File.Writer.init(.stderr(), init.io, &stderr_buffer);
        try names.applyWithCoverageImports(allocator, init.io, &source_document, args[4], if (args.len == 6) args[5] else null, &stderr.interface);
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
    // <name> <prefix> <bindings.zig> [source_root]
    if (args.len != 4 and args.len != 5) return error.InvalidArguments;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.Writer.init(.stderr(), init.io, &stderr_buffer);
    var document = try walk.reflect(allocator, bindings.bindings, args[1], args[2]);
    try names.apply(allocator, init.io, &document, args[3], if (args.len == 5) args[4] else null, &stderr.interface);
    try names.writeWarnings(&stderr.interface, document);
    try stderr.interface.flush();
    const semantic_json = try document.serialize(allocator);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), init.io, &stdout_buffer);
    try stdout.interface.writeAll(semantic_json);
    try stdout.interface.flush();
}
