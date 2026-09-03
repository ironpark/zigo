const std = @import("std");

pub const Severity = enum { warning, @"error" };

pub const Site = struct {
    path: []const u8,
    declaration: []const u8,
    /// Set together, from an AST token location `names.zig` recorded. Absent
    /// whenever the declaration that raised the diagnostic has no known
    /// source position (or none was threaded through), in which case
    /// rendering falls back to naming `semantic.json` the way it always has.
    line: ?u32 = null,
    column: ?u32 = null,
};

pub const Diagnostic = struct {
    severity: Severity,
    code: []const u8,
    message: []const u8,
    site: Site,
    hint: []const u8,
    note: ?[]const u8 = null,

    pub fn render(self: Diagnostic, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.site.line) |line| {
            try writer.print("{s}[{s}]: {s}\n  --> {s}:{d}:{d} ({s})\n  hint: {s}\n", .{
                @tagName(self.severity), self.code, self.message, self.site.path, line, self.site.column orelse 0, self.site.declaration, self.hint,
            });
        } else {
            try writer.print("{s}[{s}]: {s}\n  --> {s} ({s})\n  hint: {s}\n", .{
                @tagName(self.severity), self.code, self.message, self.site.path, self.site.declaration, self.hint,
            });
        }
        if (self.note) |note| try writer.print("  note: {s}\n", .{note});
    }

    pub fn renderAlloc(self: Diagnostic, allocator: std.mem.Allocator) ![]u8 {
        var rendered: std.Io.Writer.Allocating = .init(allocator);
        errdefer rendered.deinit();
        self.render(&rendered.writer) catch return error.OutOfMemory;
        return rendered.toOwnedSlice();
    }
};

test "diagnostic rendering includes actionable context" {
    const diagnostic: Diagnostic = .{
        .severity = .@"error",
        .code = "ZIGO003",
        .message = "cannot pass `mylib.Config` by value",
        .site = .{ .path = "src/bindings.zig:3", .declaration = "mylib.configure" },
        .hint = "declare it as `extern struct`, or expose it as opaque",
        .note = "consider registering `Config` with `.name = \"ConfigValue\"`",
    };
    const rendered = try diagnostic.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "error[ZIGO003]") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "src/bindings.zig:3") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "hint:") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "  note: consider registering") != null);
}

test "a site with a source location renders path:line:col" {
    const diagnostic: Diagnostic = .{
        .severity = .@"error",
        .code = "ZIGO018",
        .message = "unsupported integer width `u128` in parameter `cp`",
        .site = .{ .path = "src/bindings.zig", .declaration = "unicode.codepointWidth", .line = 12, .column = 5 },
        .hint = "use an integer of 64 bits or fewer",
    };
    const rendered = try diagnostic.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "--> src/bindings.zig:12:5 (unicode.codepointWidth)") != null);
}

test "allocated diagnostic rendering propagates OOM" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expectRenderedDiagnostic, .{});
}

fn expectRenderedDiagnostic(allocator: std.mem.Allocator) !void {
    const diagnostic: Diagnostic = .{
        .severity = .@"error",
        .code = "ZIGO003",
        .message = "cannot pass a value",
        .site = .{ .path = "semantic.json", .declaration = "configure" },
        .hint = "expose it as opaque",
    };
    const rendered = try diagnostic.renderAlloc(allocator);
    defer allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "error[ZIGO003]") != null);
}
