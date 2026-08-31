const std = @import("std");
const bindings = @import("bindings");
const names = @import("names.zig");
const walk = @import("walk.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
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
