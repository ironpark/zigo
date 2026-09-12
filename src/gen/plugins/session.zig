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
    .source_files = &.{.{ .imports = sessionImports, .pathAlloc = sessionsPath, .render = renderSessionsBody }},
};

/// Every session file closes handles, joins the failures and guards the whole
/// thing with a `sync.Once`, so the three standard packages are always used.
fn sessionImports(_: plugin_api.Context) anyerror![]const plugin_api.Import {
    return &.{
        .{ .path = "errors", .qualifier = "errors" },
        .{ .path = "io", .qualifier = "io" },
        .{ .path = "sync", .qualifier = "sync" },
    };
}

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
    const primary = members.items[0];
    const children = members.items[1..];

    // The binding's own words first, then the one sentence the type cannot be
    // used correctly without. A blank comment line keeps the two apart instead
    // of running the contract on as if the author had written it.
    if (session.doc) |doc| {
        var lines = std.mem.splitScalar(u8, doc, '\n');
        while (lines.next()) |line| try plugin_api.writeCommentLine(writer, line);
        try writer.writeAll("//\n");
    }
    try writer.print(
        "// {s} adopts one {s} and the child handles that primary handed out, and\n// closes them in that order: the children it adopted, most recent first,\n// then the primary.\ntype {s} struct {{\n",
        .{ session.name, primary.type_name, session.name },
    );
    // One column for every field, so the block reads the way gofmt lays it out
    // whether or not the consumer runs the formatter over generated files.
    var width: usize = "closeOnce".len;
    for (members.items) |member| width = @max(width, member.field.len);
    try writeStructField(writer, primary.field, width);
    try writer.print("*{s}\n", .{primary.type_name});
    for (children) |child| {
        try writeStructField(writer, child.field, width);
        try writer.print("[]*{s}\n", .{child.type_name});
    }
    // `mu` guards the adopted slices against an `Add` racing the `Close` that
    // drains them; the once and the error it keeps are what make `Close`
    // idempotent, and what make a second call answer with the first result.
    try writeStructField(writer, "mu", width);
    try writer.writeAll("sync.Mutex\n");
    try writeStructField(writer, "closed", width);
    try writer.writeAll("bool\n");
    try writeStructField(writer, "closeOnce", width);
    try writer.writeAll("sync.Once\n");
    try writeStructField(writer, "closeErr", width);
    try writer.writeAll("error\n}\n");

    try writer.print(
        "\n// {s} adopts the primary handle. Adopt the children it hands out with the\n// Add methods below. A nil primary is skipped when the session closes.\n",
        .{constructor_name},
    );
    try writer.print(
        "func {0s}({1s} *{2s}) *{3s} {{\n\treturn &{3s}{{{1s}: {1s}}}\n}}\n",
        .{ constructor_name, primary.field, primary.type_name, session.name },
    );

    for (children) |child| try renderAdd(writer, session, child);

    // Children first, then the primary: that is the order the native side
    // insists on, since a parent refuses to close while a child it handed out
    // is still open.
    try writer.writeAll("\n// Close closes every child handle the session adopted, most recent first,\n// and then the primary. It is idempotent and safe to call from several\n// goroutines: a later call returns the first result without closing anything\n// again. A member that fails to close does not stop the others, and the\n// failures are reported together.\n");
    try writer.print("func (s *{s}) Close() error {{\n\ts.closeOnce.Do(func() {{\n\t\ts.mu.Lock()\n\t\ts.closed = true\n", .{session.name});
    for (children) |child| try writer.print("\t\t{0s} := s.{0s}\n\t\ts.{0s} = nil\n", .{child.field});
    try writer.writeAll("\t\ts.mu.Unlock()\n\n\t\tvar failures []error\n");
    for (children) |child| try writer.print(
        "\t\tfor index := len({0s}) - 1; index >= 0; index-- {{\n\t\t\tif err := {0s}[index].Close(); err != nil {{\n\t\t\t\tfailures = append(failures, err)\n\t\t\t}}\n\t\t}}\n",
        .{child.field},
    );
    try writer.print(
        "\t\tif s.{0s} != nil {{\n\t\t\tif err := s.{0s}.Close(); err != nil {{\n\t\t\t\tfailures = append(failures, err)\n\t\t\t}}\n\t\t}}\n",
        .{primary.field},
    );
    try writer.writeAll("\t\ts.closeErr = errors.Join(failures...)\n\t})\n\treturn s.closeErr\n}\n");

    try writer.print("\n// {s} returns the primary handle the session owns.\n", .{primary.type_name});
    try writer.print("func (s *{0s}) {1s}() *{2s} {{ return s.{3s} }}\n", .{ session.name, primary.accessor, primary.type_name, primary.field });
    for (children) |child| {
        try writer.print("\n// {s} returns the {s} handles the session adopted, oldest first.\n", .{ child.accessor, child.type_name });
        try writer.print(
            "func (s *{0s}) {1s}() []*{2s} {{\n\ts.mu.Lock()\n\tdefer s.mu.Unlock()\n\treturn append([]*{2s}(nil), s.{3s}...)\n}}\n",
            .{ session.name, child.accessor, child.type_name, child.field },
        );
    }
    try writer.print("\nvar _ io.Closer = (*{s})(nil)\n", .{session.name});
}

/// One adopt method per child type. It is variadic because a primary hands out
/// as many children as the caller asks for, and it returns the session so a
/// caller can chain the adoption onto the constructor.
fn renderAdd(writer: *std.Io.Writer, session: abi.AbiSession, child: Member) !void {
    try writer.print(
        "\n// {0s} adopts {1s} handles the primary handed out and returns the session,\n// so calls chain. A nil handle is ignored. A handle adopted after Close has\n// run is closed immediately rather than leaked.\n",
        .{ child.adder, child.type_name },
    );
    try writer.print(
        "func (s *{0s}) {1s}({2s} ...*{3s}) *{0s} {{\n\tfor _, handle := range {2s} {{\n\t\tif handle == nil {{\n\t\t\tcontinue\n\t\t}}\n\t\ts.mu.Lock()\n\t\tif s.closed {{\n\t\t\ts.mu.Unlock()\n\t\t\t_ = handle.Close()\n\t\t\tcontinue\n\t\t}}\n\t\ts.{2s} = append(s.{2s}, handle)\n\t\ts.mu.Unlock()\n\t}}\n\treturn s\n}}\n",
        .{ session.name, child.adder, child.field, child.type_name },
    );
}

fn writeStructField(writer: *std.Io.Writer, name: []const u8, width: usize) !void {
    try writer.writeByte('\t');
    try writer.writeAll(name);
    try writer.splatByteAll(' ', width - name.len + 1);
}

/// One Go field per member: the primary first, then the children in
/// declaration order. The primary is a single handle, so its field is the type
/// name in lower camel case and its accessor is the type name itself. A child
/// is a list, so both gain the plural `s` -- which is also what keeps a child's
/// accessor from colliding with the session's own `Close`.
const Member = struct {
    type_name: []const u8,
    /// Borrowed from `fields`, which the caller frees.
    field: []const u8,
    /// Borrowed from `names`, which the caller frees.
    accessor: []const u8,
    /// Borrowed from `adders`, which the caller frees. Empty for the primary.
    adder: []const u8,
};

/// The members of a session, with the names owned alongside them: the renderer
/// reads all of them, so all of them live until it is done.
const Members = struct {
    items: []Member,
    fields: [][]u8,
    accessors: [][]u8,
    adders: [][]u8,

    fn deinit(self: Members, allocator: std.mem.Allocator) void {
        naming.freeParamNames(allocator, self.fields);
        naming.freeParamNames(allocator, self.accessors);
        naming.freeParamNames(allocator, self.adders);
        allocator.free(self.items);
    }
};

pub fn sessionMembers(allocator: std.mem.Allocator, session: abi.AbiSession) !Members {
    var members: Members = .{ .items = &.{}, .fields = &.{}, .accessors = &.{}, .adders = &.{} };
    errdefer members.deinit(allocator);
    members.accessors = try allocator.alloc([]u8, session.children.len + 1);
    @memset(members.accessors, &.{});
    members.adders = try allocator.alloc([]u8, session.children.len + 1);
    @memset(members.adders, &.{});
    members.accessors[0] = try allocator.dupe(u8, session.primary);
    for (session.children, members.accessors[1..], members.adders[1..]) |child, *accessor, *adder| {
        accessor.* = try std.fmt.allocPrint(allocator, "{s}s", .{child});
        adder.* = try std.fmt.allocPrint(allocator, "Add{s}", .{child});
    }
    // The field is the accessor in lower camel case, so the plural travels to
    // the field with it and one rule answers for both.
    members.fields = try targets.go.paramNamesAlloc(allocator, @ptrCast(members.accessors));
    members.items = try allocator.alloc(Member, members.accessors.len);
    for (members.items, members.fields, members.accessors, members.adders, 0..) |*member, field, accessor, adder, index| {
        member.* = .{
            .type_name = if (index == 0) session.primary else session.children[index - 1],
            .field = field,
            .accessor = accessor,
            .adder = adder,
        };
    }
    return members;
}
