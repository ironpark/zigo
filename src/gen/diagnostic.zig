const std = @import("std");

pub const Severity = enum { warning, @"error" };

pub const Site = struct {
    path: []const u8,
    declaration: []const u8,
};

pub const Diagnostic = struct {
    severity: Severity,
    code: []const u8,
    message: []const u8,
    site: Site,
    hint: []const u8,

    pub fn renderAlloc(self: Diagnostic, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}[{s}]: {s}\n  --> {s} ({s})\n  hint: {s}\n", .{
            @tagName(self.severity), self.code, self.message, self.site.path, self.site.declaration, self.hint,
        });
    }

    pub fn emitAndExit(self: Diagnostic, allocator: std.mem.Allocator) noreturn {
        const rendered = self.renderAlloc(allocator) catch "error[ZIGO000]: unable to render diagnostic\n";
        std.debug.print("{s}", .{rendered});
        std.process.exit(1);
    }
};

test "diagnostic rendering includes actionable context" {
    const diagnostic: Diagnostic = .{
        .severity = .@"error",
        .code = "ZIGO003",
        .message = "cannot pass `mylib.Config` by value",
        .site = .{ .path = "src/bindings.zig:3", .declaration = "mylib.configure" },
        .hint = "declare it as `extern struct`, or expose it as opaque",
    };
    const rendered = try diagnostic.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "error[ZIGO003]") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "src/bindings.zig:3") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "hint:") != null);
}
