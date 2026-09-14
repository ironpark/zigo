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
const Decl = plugin_api.gobuild.Decl;
const Field = plugin_api.gobuild.Field;
const Stmt = plugin_api.gobuild.Stmt;

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
    const b = context.builder();
    const members = try sessionMembers(allocator, session);
    defer members.deinit(allocator);
    const primary = members.items[0];
    const children = members.items[1..];
    const session_type = b.ident(session.name);
    const session_ptr = try b.ptr(session_type);
    const primary_ptr = try b.ptr(b.ident(primary.type_name));

    var decls: std.ArrayList(Decl) = .empty;
    defer decls.deinit(allocator);

    // The binding's own words first, then the one sentence the type cannot be
    // used correctly without. A blank comment line keeps the two apart instead
    // of running the contract on as if the author had written it.
    var doc: std.Io.Writer.Allocating = .init(allocator);
    defer doc.deinit();
    if (session.doc) |text| try doc.writer.print("{s}\n\n", .{text});
    try doc.writer.print(
        "{s} adopts one {s} and the child handles that primary handed out, and\ncloses them in that order: the children it adopted, most recent first,\nthen the primary.",
        .{ session.name, primary.type_name },
    );

    var fields: std.ArrayList(Field) = .empty;
    defer fields.deinit(allocator);
    try fields.append(allocator, .{ .name = primary.field, .type = primary_ptr });
    for (children) |child| try fields.append(allocator, .{
        .name = child.field,
        .type = try b.sliceOf(try b.ptr(b.ident(child.type_name))),
    });
    // `mu` guards the adopted slices against an `Add` racing the `Close` that
    // drains them; the once and the error it keeps are what make `Close`
    // idempotent, and what make a second call answer with the first result.
    try fields.append(allocator, .{ .name = "mu", .type = try b.selName("sync", "Mutex") });
    try fields.append(allocator, .{ .name = "closed", .type = b.ident("bool") });
    try fields.append(allocator, .{ .name = "closeOnce", .type = try b.selName("sync", "Once") });
    try fields.append(allocator, .{ .name = "closeErr", .type = b.ident("error") });
    // One column for every field, so the block reads the way gofmt lays it out
    // whether or not the consumer runs the formatter over generated files.
    try decls.append(allocator, try b.structDecl(.{
        .doc = .{ .text = doc.written() },
        .name = session.name,
        .fields = fields.items,
        .align_fields = true,
    }));

    const constructor_name = try std.fmt.allocPrint(allocator, "New{s}", .{session.name});
    try decls.append(allocator, try b.func(.{
        .doc = .{ .text = try std.fmt.allocPrint(
            allocator,
            "{s} adopts the primary handle. Adopt the children it hands out with the\nAdd methods below. A nil primary is skipped when the session closes.",
            .{constructor_name},
        ) },
        .name = constructor_name,
        .signature = .{ .explicit = .{
            .params = &.{.{ .names = &.{primary.field}, .type = primary_ptr }},
            .results = &.{session_ptr},
        } },
        .body = &.{try b.ret(&.{try b.addr(try b.composite(session_type, &.{.{ .key = primary.field, .value = b.ident(primary.field) }}))})},
    }));

    for (children) |child| try decls.append(allocator, try renderAdd(b, session, child));

    try decls.append(allocator, try renderClose(b, session, primary, children));

    try decls.append(allocator, try b.func(.{
        .doc = .{ .text = try std.fmt.allocPrint(allocator, "{s} returns the primary handle the session owns.", .{primary.type_name}) },
        .receiver = .{ .name = "s", .type = session.name, .pointer = true },
        .name = primary.accessor,
        .signature = .{ .explicit = .{ .results = &.{primary_ptr} } },
        .body = &.{try b.ret(&.{try b.selName("s", primary.field)})},
        .single_line = true,
    }));

    for (children) |child| {
        const child_slice = try b.sliceOf(try b.ptr(b.ident(child.type_name)));
        try decls.append(allocator, try b.func(.{
            .doc = .{ .text = try std.fmt.allocPrint(allocator, "{s} returns the {s} handles the session adopted, oldest first.", .{ child.accessor, child.type_name }) },
            .receiver = .{ .name = "s", .type = session.name, .pointer = true },
            .name = child.accessor,
            .signature = .{ .explicit = .{ .results = &.{child_slice} } },
            .body = &.{
                b.exprStmt(try b.callSel(try b.selName("s", "mu"), "Lock", &.{})),
                b.deferStmt(try b.callSel(try b.selName("s", "mu"), "Unlock", &.{})),
                try b.ret(&.{try b.callSpread(b.ident("append"), &.{
                    try b.call(child_slice, &.{.nil}),
                    try b.selName("s", child.field),
                })}),
            },
        }));
    }

    try decls.append(allocator, try b.assertImplements(.{
        .interface = try b.selName("io", "Closer"),
        .type_name = session.name,
    }));

    try b.render(writer, decls.items, .{});
}

/// Children first, then the primary: that is the order the native side insists
/// on, since a parent refuses to close while a child it handed out is still
/// open.
fn renderClose(b: plugin_api.Builder, session: abi.AbiSession, primary: Member, children: []const Member) !Decl {
    const allocator = b.allocator;
    var once: std.ArrayList(Stmt) = .empty;
    defer once.deinit(allocator);
    try once.append(allocator, b.exprStmt(try b.callSel(try b.selName("s", "mu"), "Lock", &.{})));
    try once.append(allocator, try b.assign(&.{try b.selName("s", "closed")}, "=", &.{b.boolean(true)}));
    for (children) |child| {
        try once.append(allocator, try b.define(&.{child.field}, try b.selName("s", child.field)));
        try once.append(allocator, try b.assign(&.{try b.selName("s", child.field)}, "=", &.{.nil}));
    }
    try once.append(allocator, b.exprStmt(try b.callSel(try b.selName("s", "mu"), "Unlock", &.{})));
    try once.append(allocator, .blank);
    try once.append(allocator, b.declare("failures", try b.sliceOf(b.ident("error")), null));
    const collect = try b.dupStmts(&.{try b.assign(
        &.{b.ident("failures")},
        "=",
        &.{try b.callName("append", &.{ b.ident("failures"), b.ident("err") })},
    )});
    for (children) |child| try once.append(allocator, try b.forLoop(.{
        .init = try b.define(&.{"index"}, try b.bin("-", try b.callName("len", &.{b.ident(child.field)}), b.int(1))),
        .cond = try b.bin(">=", b.ident("index"), b.int(0)),
        .post = try b.incDec(b.ident("index"), "--"),
        .body = try b.dupStmts(&.{try b.ifStmt(.{
            .init = try b.define(&.{"err"}, try b.callSel(try b.indexExpr(b.ident(child.field), &.{b.ident("index")}), "Close", &.{})),
            .cond = try b.bin("!=", b.ident("err"), .nil),
            .body = collect,
        })}),
    }));
    try once.append(allocator, try b.ifStmt(.{
        .cond = try b.bin("!=", try b.selName("s", primary.field), .nil),
        .body = try b.dupStmts(&.{try b.ifStmt(.{
            .init = try b.define(&.{"err"}, try b.callSel(try b.selName("s", primary.field), "Close", &.{})),
            .cond = try b.bin("!=", b.ident("err"), .nil),
            .body = collect,
        })}),
    }));
    try once.append(allocator, try b.assign(
        &.{try b.selName("s", "closeErr")},
        "=",
        &.{try b.callSpread(try b.selName("errors", "Join"), &.{b.ident("failures")})},
    ));

    return b.func(.{
        .doc = .{ .text = "Close closes every child handle the session adopted, most recent first,\nand then the primary. It is idempotent and safe to call from several\ngoroutines: a later call returns the first result without closing anything\nagain. A member that fails to close does not stop the others, and the\nfailures are reported together." },
        .receiver = .{ .name = "s", .type = session.name, .pointer = true },
        .name = "Close",
        .signature = .{ .explicit = .{ .results = &.{b.ident("error")} } },
        .body = &.{
            b.exprStmt(try b.call(
                try b.sel(try b.selName("s", "closeOnce"), "Do"),
                &.{try b.funcLiteral(&.{}, &.{}, once.items)},
            )),
            try b.ret(&.{try b.selName("s", "closeErr")}),
        },
    });
}

/// One adopt method per child type. It is variadic because a primary hands out
/// as many children as the caller asks for, and it returns the session so a
/// caller can chain the adoption onto the constructor.
fn renderAdd(b: plugin_api.Builder, session: abi.AbiSession, child: Member) !Decl {
    const allocator = b.allocator;
    return b.func(.{
        .doc = .{ .text = try std.fmt.allocPrint(
            allocator,
            "{s} adopts {s} handles the primary handed out and returns the session,\nso calls chain. A nil handle is ignored. A handle adopted after Close has\nrun is closed immediately rather than leaked.",
            .{ child.adder, child.type_name },
        ) },
        .receiver = .{ .name = "s", .type = session.name, .pointer = true },
        .name = child.adder,
        .signature = .{ .explicit = .{
            .params = &.{.{ .names = &.{child.field}, .type = try b.variadic(try b.ptr(b.ident(child.type_name))) }},
            .results = &.{try b.ptr(b.ident(session.name))},
        } },
        .body = &.{
            try b.forRange(.{
                .key = "_",
                .value = "handle",
                .over = b.ident(child.field),
                .body = &.{
                    try b.ifStmt(.{
                        .cond = try b.bin("==", b.ident("handle"), .nil),
                        .body = &.{.continue_stmt},
                    }),
                    b.exprStmt(try b.callSel(try b.selName("s", "mu"), "Lock", &.{})),
                    try b.ifStmt(.{
                        .cond = try b.selName("s", "closed"),
                        .body = &.{
                            b.exprStmt(try b.callSel(try b.selName("s", "mu"), "Unlock", &.{})),
                            try b.assign(&.{b.ident("_")}, "=", &.{try b.callSel(b.ident("handle"), "Close", &.{})}),
                            .continue_stmt,
                        },
                    }),
                    try b.assign(
                        &.{try b.selName("s", child.field)},
                        "=",
                        &.{try b.callName("append", &.{ try b.selName("s", child.field), b.ident("handle") })},
                    ),
                    b.exprStmt(try b.callSel(try b.selName("s", "mu"), "Unlock", &.{})),
                },
            }),
            try b.ret(&.{b.ident("s")}),
        },
    });
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
        accessor.* = try child.accessorAlloc(allocator);
        adder.* = try std.fmt.allocPrint(allocator, "Add{s}", .{child.base()});
    }
    // The field is the accessor in lower camel case, so the plural travels to
    // the field with it and one rule answers for both.
    members.fields = try targets.go.paramNamesAlloc(allocator, @ptrCast(members.accessors));
    members.items = try allocator.alloc(Member, members.accessors.len);
    for (members.items, members.fields, members.accessors, members.adders, 0..) |*member, field, accessor, adder, index| {
        member.* = .{
            .type_name = if (index == 0) session.primary else session.children[index - 1].type,
            .field = field,
            .accessor = accessor,
            .adder = adder,
        };
    }
    return members;
}
