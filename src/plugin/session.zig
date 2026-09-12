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
        if (try accessorIssue(allocator, session)) |found| return found;
        if (session.children.len == 0) return issue(
            session,
            "session lists no child handles",
            "list at least one dependent child in `.children`, or use the primary handle on its own",
        );
        if (semantic.typeDecl(document.types, session.primary)) |declaration| {
            if (declaration.kind != .@"opaque") return try issueFmt(
                allocator,
                session,
                "session primary `{s}` is not a registered handle",
                .{session.primary},
                "name a type registered with `.handle` as the primary",
            );
        } else return try issueFmt(
            allocator,
            session,
            "session primary `{s}` is not a registered handle",
            .{session.primary},
            "name a type registered with `.handle` as the primary",
        );
        for (session.children, 0..) |child, child_index| {
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
            for (session.children[0..child_index]) |previous| if (std.mem.eql(u8, previous, child))
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
            const parent = dependentParent(document, child) orelse return try issueFmt(
                allocator,
                session,
                "`{s}` is not a dependent child of any handle",
                .{child},
                "declare its constructor with `.parent = .receiver` so the parent tracks it",
            );
            if (!std.mem.eql(u8, parent, session.primary)) return try issueFmt(
                allocator,
                session,
                "`{s}` is a dependent child of `{s}`, not of `{s}`",
                .{ child, parent, session.primary },
                "list only handles the primary itself hands out",
            );
        }
        if (document.packages != null) {
            const primary_package = if (semantic.typeDecl(document.types, session.primary)) |declaration| declaration.package else null;
            for (session.children) |child| {
                const child_package = if (semantic.typeDecl(document.types, child)) |declaration| declaration.package else null;
                if (semantic.optionalStringEqual(primary_package, child_package)) continue;
                return try issueFmt(
                    allocator,
                    session,
                    "session primary `{s}` and child `{s}` are in different public packages",
                    .{ session.primary, child },
                    "assign every session member to one package",
                );
            }
        }
    }
    return null;
}

/// The handle whose `Close` waits for `type_name`, read from the IR the same
/// way the emitters read it: a constructor declared with `.parent = .receiver`
/// whose constructed type is this one.
fn dependentParent(document: semantic.Semantic, type_name: []const u8) ?[]const u8 {
    for (document.functions) |function| {
        if (!function.childOfReceiver()) continue;
        const constructor = semantic.constructorForInit(document.constructors, function) orelse continue;
        if (!std.mem.eql(u8, constructor.type, type_name)) continue;
        return function.receiver;
    }
    return null;
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

/// An accessor is named after its member type, and the session type declares
/// `Close` itself. A member spelled the same way would give the type two
/// methods with one name, so the declaration is refused rather than emitted
/// as Go that does not compile.
fn accessorIssue(allocator: std.mem.Allocator, session: semantic.Session) !?diagnostic.Diagnostic {
    const clashing = if (std.mem.eql(u8, session.primary, "Close")) session.primary else for (session.children) |child| {
        if (std.mem.eql(u8, child, "Close")) break child;
    } else null;
    const member = clashing orelse return null;
    return .{
        .severity = .@"error",
        .code = "ZIGO024",
        .message = try std.fmt.allocPrint(allocator, "public Go name `Close` collides between the accessor for `{s}` and the session's own Close method", .{member}),
        .site = .{ .path = "semantic.json", .declaration = session.name },
        .hint = "a session closes its members itself; name the type something else or leave it out of `.children`",
    };
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
