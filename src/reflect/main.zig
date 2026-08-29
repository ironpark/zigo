const std = @import("std");
const bindings = @import("bindings");
const walk = @import("walk.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4) return error.InvalidArguments;

    const document = try walk.reflect(allocator, bindings.bindings, args[2], args[3]);
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
