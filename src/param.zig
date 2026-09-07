//! Small constructors for complete parameter contracts. Indices are original Zig indices.
const a = @import("author.zig");
const ir = @import("declare.zig");

pub fn input(index: usize) a.Param {
    return .{ .index = index, .contract = .{ .buffer = .input } };
}
pub fn output(index: usize, written: ir.Written) a.Param {
    return .{ .index = index, .contract = .{ .buffer = .{ .output = .{ .written = written } } } };
}
pub fn inout(index: usize, written: ir.Written) a.Param {
    return .{ .index = index, .contract = .{ .buffer = .{ .inout = .{ .written = written } } } };
}
pub fn stream(index: usize, buffer: ?u32) a.Param {
    return .{ .index = index, .contract = .{ .stream = .{ .buffer = buffer } } };
}
pub fn callback(index: usize, options: a.CallbackContract) a.Param {
    return .{ .index = index, .contract = .{ .callback = options } };
}
pub fn cancel(index: usize, canceled: ?[]const u8) a.Param {
    return .{ .index = index, .contract = .{ .cancel = .{ .canceled = canceled } } };
}
pub fn flatten(index: usize, fields: []const []const u8) a.Param {
    return .{ .index = index, .contract = .{ .flatten = fields } };
}
