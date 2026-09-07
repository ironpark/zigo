//! Complete result contracts; replacing a result never retains an old release reference.
const a = @import("author.zig");

pub fn owned() a.Returns {
    return .{ .lifetime = .{ .owned = .{} } };
}
pub fn releasedBy(comptime release: a.FunctionRef) a.Returns {
    return .{ .lifetime = .{ .owned = .{ .release = release } } };
}
pub fn borrowed() a.Returns {
    return .{ .lifetime = .{ .borrowed = .receiver } };
}
