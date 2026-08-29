const std = @import("std");
const bindings = @import("bindings");
const names = @import("names.zig");
const walk = @import("walk.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 5) return error.InvalidArguments;

    var document = try walk.reflect(allocator, bindings.bindings, args[2], args[3]);
    try names.apply(allocator, init.io, &document, args[4]);
    var stderr_buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.Writer.init(.stderr(), init.io, &stderr_buffer);
    try names.writeWarnings(&stderr.interface, document);
    try stderr.interface.flush();
    const semantic_json = try document.serialize(allocator);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), init.io, &stdout_buffer);
    try stdout.interface.writeAll(semantic_json);
    try stdout.interface.flush();

    const target = @import("builtin").target;
    const layout_json = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "ir_version": 1,
        \\  "pointer_bits": {d},
        \\  "structs": {{}},
        \\  "target": "{s}-{s}",
        \\  "usize_bits": {d}
        \\}}
        \\
    , .{ @bitSizeOf(usize), @tagName(target.cpu.arch), @tagName(target.os.tag), @bitSizeOf(usize) });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = layout_json });
}
