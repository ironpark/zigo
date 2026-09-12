//! The session contract: one primary handle, the dependent children it hands
//! out, and nothing else. A session never crosses the C boundary, so every
//! rule here is about the generated Go type and the lifetime contract it
//! carries -- which members it may adopt, and whether closing it in order can
//! work at all.
const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const targets = @import("targets");

pub fn sessionIssue(allocator: std.mem.Allocator, document: semantic.Semantic, target: targets.Target) !?diagnostic.Diagnostic {
    const sessions = document.sessions orelse return null;
    for (sessions, 0..) |session, index| {
        if (!target.isIdentifier(session.name)) return try issueFmt(
            allocator,
            session,
            "session name is not a {s} identifier",
            .{target.display_name},
            try std.fmt.allocPrint(allocator, "give the session a `.name` that is a valid exported {s} identifier", .{target.display_name}),
        );
        if (try collisionIssue(allocator, document, sessions[0..index], session, target)) |found| return found;
        if (session.children.len == 0) return issue(
            session,
            "session lists no child handles",
            "list at least one dependent child in `.children`, or use the primary handle on its own",
        );
        const primary_declaration = semantic.typeDecl(document.types, session.primary);
        if (primary_declaration == null or primary_declaration.?.kind != .@"opaque") return try issueFmt(
            allocator,
            session,
            "session primary `{s}` is not a registered handle",
            .{session.primary},
            "name a type registered with `.handle` as the primary",
        );
        // The primary is closed last, so it needs a `Close` exactly as much as
        // a child does. Without this the session would emit a call to a method
        // a borrowed view never generates.
        if (semantic.constructorForType(document.constructors, session.primary) == null) return try issueFmt(
            allocator,
            session,
            "session primary `{s}` has no Close method",
            .{session.primary},
            "a session primary must be a constructed handle with a destructor; borrowed views and Ref types are not closeable",
        );
        for (session.children, 0..) |member, child_index| {
            const child = member.type;
            const declaration = semantic.typeDecl(document.types, child) orelse return try issueFmt(
                allocator,
                session,
                "session lists `{s}`, which is not a registered handle",
                .{child},
                "list only types registered with `.handle` in `.children`",
            );
            if (declaration.kind != .@"opaque") return try issueFmt(
                allocator,
                session,
                "session lists `{s}`, which is not a registered handle",
                .{child},
                "list only types registered with `.handle` in `.children`",
            );
            for (session.children[0..child_index]) |previous| if (std.mem.eql(u8, previous.type, child))
                return try issueFmt(allocator, session, "session lists `{s}` twice", .{child}, "list each child handle once");
            if (std.mem.eql(u8, child, session.primary)) return try issueFmt(
                allocator,
                session,
                "session lists its primary `{s}` as a child",
                .{child},
                "the primary closes last, so it is not one of `.children`",
            );
            // Whether a member can be closed at all comes first: a borrowed
            // view has no `Close` to call, which is a more useful thing to say
            // than that no handle handed it out.
            if (semantic.constructorForType(document.constructors, child) == null) return try issueFmt(
                allocator,
                session,
                "`{s}` has no Close method",
                .{child},
                "a session member must be a constructed handle with a destructor; borrowed views and Ref types are not closeable",
            );
            // A session closes children before the primary, which only works
            // if the native side agrees that is the order: a child is one the
            // primary handed out, not any handle that happens to be listed.
            const parents = try dependentParentsAlloc(allocator, document, child);
            defer allocator.free(parents);
            if (parents.len == 0) return try issueFmt(
                allocator,
                session,
                "`{s}` is not a dependent child of any handle",
                .{child},
                "declare its constructor with `.parent = .receiver` so the parent tracks it",
            );
            var claimed = false;
            for (parents) |parent| {
                if (std.mem.eql(u8, parent, session.primary)) claimed = true;
            }
            if (!claimed) return try issueFmt(
                allocator,
                session,
                "`{s}` is a dependent child of {s}, not of `{s}`",
                .{ child, try joinNamesAlloc(allocator, parents), session.primary },
                "list only handles the primary itself hands out",
            );
        }
        // The generated method set is checked once the members are known to be
        // well formed, so a structural mistake speaks before a name clash the
        // mistake itself caused.
        if (try methodIssue(allocator, session)) |found| return found;
        if (document.packages != null) {
            const primary_package = if (semantic.typeDecl(document.types, session.primary)) |declaration| declaration.package else null;
            for (session.children) |child| {
                const child_package = if (semantic.typeDecl(document.types, child.type)) |declaration| declaration.package else null;
                if (semantic.optionalStringEqual(primary_package, child_package)) continue;
                return try issueFmt(
                    allocator,
                    session,
                    "session primary `{s}` and child `{s}` are in different public packages",
                    .{ session.primary, child.type },
                    "assign every session member to one package",
                );
            }
        }
    }
    return null;
}

/// Every handle whose `Close` waits for `type_name`, read from the IR the same
/// way the emitters read it: a constructor declared with `.parent = .receiver`
/// whose constructed type is this one.
///
/// All of them, not the first one: nothing stops two handles from each handing
/// out the same child type, and answering with whichever constructor the
/// document happens to list first would refuse a session over the other one.
fn dependentParentsAlloc(allocator: std.mem.Allocator, document: semantic.Semantic, type_name: []const u8) ![]const []const u8 {
    var parents: std.ArrayList([]const u8) = .empty;
    errdefer parents.deinit(allocator);
    for (document.functions) |function| {
        if (!function.childOfReceiver()) continue;
        const constructor = semantic.constructorForInit(document.constructors, function) orelse continue;
        if (!std.mem.eql(u8, constructor.type, type_name)) continue;
        const receiver = function.receiver orelse continue;
        for (parents.items) |seen| {
            if (std.mem.eql(u8, seen, receiver)) break;
        } else try parents.append(allocator, receiver);
    }
    return parents.toOwnedSlice(allocator);
}

/// `` `A` `` or `` `A` and `B` ``: the parents a diagnostic names, so the
/// message reads the same whether one handle or several hand the child out.
fn joinNamesAlloc(allocator: std.mem.Allocator, names: []const []const u8) ![]u8 {
    var joined: std.ArrayList(u8) = .empty;
    errdefer joined.deinit(allocator);
    for (names, 0..) |name, index| {
        if (index != 0) try joined.appendSlice(allocator, if (index + 1 == names.len) " and " else ", ");
        try joined.print(allocator, "`{s}`", .{name});
    }
    return joined.toOwnedSlice(allocator);
}

/// A session name reaches Go as a `type` declaration in its package, so it
/// collides with the same things a registered type name does. So does its
/// `New<Name>` constructor, and the accessors it declares are methods on the
/// session type: they can only collide with the methods that type generates
/// itself, which is what `Close` is.
fn collisionIssue(allocator: std.mem.Allocator, document: semantic.Semantic, previous: []const semantic.Session, session: semantic.Session, target: targets.Target) !?diagnostic.Diagnostic {
    for (previous) |other| {
        if (std.mem.eql(u8, other.name, session.name)) return try collision(allocator, session, "two sessions");
    }
    const session_package = if (semantic.typeDecl(document.types, session.primary)) |declaration| declaration.package else null;
    if (semantic.typeDecl(document.types, session.name)) |declaration| {
        if (semantic.optionalStringEqual(declaration.package, session_package))
            return try collision(allocator, session, try std.fmt.allocPrint(allocator, "session `{s}` and type `{s}`", .{ session.name, declaration.zig_path orelse declaration.name }));
    }
    const constructor_name = try std.fmt.allocPrint(allocator, "New{s}", .{session.name});
    defer allocator.free(constructor_name);
    if (semantic.typeDecl(document.types, constructor_name)) |declaration| {
        if (semantic.optionalStringEqual(declaration.package, session_package))
            return try collision(allocator, session, try std.fmt.allocPrint(allocator, "the constructor `{s}` and type `{s}`", .{ constructor_name, declaration.zig_path orelse declaration.name }));
    }
    for (document.functions) |function| {
        if (function.receiver != null or !semantic.optionalStringEqual(function.package, session_package)) continue;
        const function_name = try target.publicFunctionNameAlloc(allocator, document, function);
        defer allocator.free(function_name);
        if (std.mem.eql(u8, function_name, constructor_name))
            return try collision(allocator, session, try std.fmt.allocPrint(allocator, "the constructor `{s}` and function `{s}`", .{ constructor_name, function.name }));
        if (!std.mem.eql(u8, function_name, session.name)) continue;
        return try collision(allocator, session, try std.fmt.allocPrint(allocator, "session `{s}` and function `{s}`", .{ session.name, function.name }));
    }
    return null;
}

/// The session type's whole method set, checked against itself. The primary's
/// accessor is its type name, a child contributes `<Child>s` and `Add<Child>`,
/// and the session always declares `Close`. Two members that resolve to one
/// name would give the type two methods with that name, so the declaration is
/// refused rather than emitted as Go that does not compile.
fn methodIssue(allocator: std.mem.Allocator, session: semantic.Session) !?diagnostic.Diagnostic {
    const Method = struct { name: []const u8, owner: []const u8 };
    var methods: std.ArrayList(Method) = .empty;
    defer methods.deinit(allocator);
    try methods.append(allocator, .{ .name = "Close", .owner = "the session's own Close method" });
    try methods.append(allocator, .{
        .name = session.primary,
        .owner = try std.fmt.allocPrint(allocator, "the accessor for `{s}`", .{session.primary}),
    });
    for (session.children) |child| {
        try methods.append(allocator, .{
            .name = try std.fmt.allocPrint(allocator, "{s}s", .{child.base()}),
            .owner = try std.fmt.allocPrint(allocator, "the accessor for `{s}`", .{child.type}),
        });
        try methods.append(allocator, .{
            .name = try std.fmt.allocPrint(allocator, "Add{s}", .{child.base()}),
            .owner = try std.fmt.allocPrint(allocator, "the adopt method for `{s}`", .{child.type}),
        });
    }
    for (methods.items, 0..) |method, index| {
        for (methods.items[0..index]) |previous| {
            if (!std.mem.eql(u8, previous.name, method.name)) continue;
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(allocator, "public Go name `{s}` collides between {s} and {s}", .{ method.name, method.owner, previous.owner }),
                .site = .{ .path = "semantic.json", .declaration = session.name },
                .hint = "a session closes its members itself and names one accessor per member; rename the type or leave it out of `.children`",
            };
        }
    }
    return null;
}

fn collision(allocator: std.mem.Allocator, session: semantic.Session, between: []const u8) !diagnostic.Diagnostic {
    return .{
        .severity = .@"error",
        .code = "ZIGO024",
        .message = try std.fmt.allocPrint(allocator, "public Go name `{s}` collides between {s}", .{ session.name, between }),
        .site = .{ .path = "semantic.json", .declaration = session.name },
        .hint = "give the session a `.name` that resolves to a different Go identifier",
    };
}

fn issue(session: semantic.Session, message: []const u8, hint: []const u8) diagnostic.Diagnostic {
    return .{
        .severity = .@"error",
        .code = "ZIGO062",
        .message = message,
        .site = .{ .path = "semantic.json", .declaration = session.name },
        .hint = hint,
    };
}

fn issueFmt(allocator: std.mem.Allocator, session: semantic.Session, comptime format: []const u8, args: anytype, hint: []const u8) !diagnostic.Diagnostic {
    return issue(session, try std.fmt.allocPrint(allocator, format, args), hint);
}
