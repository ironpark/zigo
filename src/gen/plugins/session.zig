//! Declared sessions: the Go container that adopts one handle and the
//! dependent children it handed out, and closes them in that order.
//!
//! A built-in plugin, and one that adds a whole file rather than writing next
//! to something. `.sessions` keeps its declaration key, its file name and
//! `ZIGO062`; the file itself is registered as the plugin's `source_files`
//! entry. Nothing here reaches C -- a session is a Go object over handles that
//! already exist.
const std = @import("std");
const abi = @import("abi");
const naming = @import("naming");
const plugin_api = @import("plugin");
const session_rules = plugin_api.session;
const targets = @import("targets");

pub const plugin: plugin_api.Plugin = .{
    .name = "SESSION",
    .validate = validateDocument,
    .source_files = &.{.{ .pathAlloc = sessionsPath, .render = renderSessionsBody }},
};

/// The declaration rules live with the other validation rules; the plugin is
/// what runs them, so `.sessions` has one owner.
fn validateDocument(context: plugin_api.ValidateContext) !void {
    if (try session_rules.sessionIssue(context.allocator, context.document, context.target)) |issue| try context.diagnose(issue);
}

pub fn sessionsPath(context: plugin_api.Context) ![]u8 {
    const package = if (context.options.go_package.len != 0) try context.allocator.dupe(u8, context.options.go_package) else try naming.snakeAlloc(context.allocator, context.program.package);
    defer context.allocator.free(package);
    const filename = try std.fmt.allocPrint(context.allocator, "{s}_sessions_gen.go", .{package});
    defer context.allocator.free(filename);
    return context.publicFilePathAlloc(filename);
}

/// `<package>_sessions_gen.go`: every declared session of the active package,
/// in declaration order.
pub fn renderSessionsBody(context: plugin_api.Context, writer: *std.Io.Writer) !void {
    var written: usize = 0;
    for (context.program.sessions) |session| {
        if (!plugin_api.packageMatches(session.package, context.options.active_package)) continue;
        if (written != 0) try writer.writeByte('\n');
        try renderSession(context, writer, session);
        written += 1;
    }
}

fn renderSession(context: plugin_api.Context, writer: *std.Io.Writer, session: abi.AbiSession) !void {
    const allocator = context.allocator;
    const members = try sessionMembers(allocator, session);
    defer members.deinit(allocator);
    const constructor_name = try std.fmt.allocPrint(allocator, "New{s}", .{session.name});
    defer allocator.free(constructor_name);

    if (session.doc) |doc| {
        var lines = std.mem.splitScalar(u8, doc, '\n');
        while (lines.next()) |line| try plugin_api.writeCommentLine(writer, line);
    }
    try writer.print(
        "// {s} owns {s} and the child handles it adopted, and closes them in that\n// order: children first, then the primary.\ntype {s} struct {{\n",
        .{ session.name, session.primary, session.name },
    );
    for (members.items) |member| try writer.print("\t{s} *{s}\n", .{ member.field, member.type_name });
    try writer.writeAll("}\n");

    try writer.print("\n// {s} adopts the primary handle and every child it handed out.\n// A nil member is skipped when the session closes.\n", .{constructor_name});
    try writer.print("func {s}(", .{constructor_name});
    for (members.items, 0..) |member, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s} *{s}", .{ member.field, member.type_name });
    }
    try writer.print(") *{s} {{\n\treturn &{s}{{", .{ session.name, session.name });
    for (members.items, 0..) |member, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s}: {s}", .{ member.field, member.field });
    }
    try writer.writeAll("}\n}\n");

    for (members.items, 0..) |member, index| {
        const role = if (index == 0) "primary" else "child";
        try writer.print("\n// {s} returns the {s} handle the session owns.\n", .{ member.type_name, role });
        try writer.print("func (s *{s}) {s}() *{s} {{ return s.{s} }}\n", .{ session.name, member.type_name, member.type_name, member.field });
    }
}

/// One Go field per member: the primary first, then the children in
/// declaration order. The field is the type name in lower camel case, and the
/// accessor keeps the type name itself.
const Member = struct {
    type_name: []const u8,
    /// Borrowed from `fields`, which the caller frees.
    field: []const u8,
};

/// The members of a session, with the field names owned alongside them: the
/// renderer reads both, so both live until it is done.
const Members = struct {
    items: []Member,
    fields: [][]u8,

    fn deinit(self: Members, allocator: std.mem.Allocator) void {
        naming.freeParamNames(allocator, self.fields);
        allocator.free(self.items);
    }
};

fn sessionMembers(allocator: std.mem.Allocator, session: abi.AbiSession) !Members {
    var members: Members = .{ .items = &.{}, .fields = &.{} };
    errdefer members.deinit(allocator);
    const names = try allocator.alloc([]const u8, session.children.len + 1);
    defer allocator.free(names);
    names[0] = session.primary;
    for (session.children, names[1..]) |child, *slot| slot.* = child;
    members.fields = try targets.go.paramNamesAlloc(allocator, names);
    members.items = try allocator.alloc(Member, names.len);
    for (names, members.fields, members.items) |type_name, field, *member| member.* = .{ .type_name = type_name, .field = field };
    return members;
}
