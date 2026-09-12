const std = @import("std");
const semantic = @import("semantic");
const diagnostic = @import("diagnostic");
const targets = @import("targets");
pub const sessionIssue = @import("plugin").session.sessionIssue;

test "a session over the primary's dependent child is accepted" {
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try sessionIssue(scratch.allocator(), sessionDocument(.{}), targets.default));
}

/// A `Queue` with a dependent `Stream` child, and a `Session` over both. The
/// overrides let each test break exactly one rule.
pub const SessionOverrides = struct {
    /// Passed as a literal so the slice outlives the call.
    sessions: ?[]const semantic.Session = null,
    constructors: ?[]const semantic.Constructor = null,
    functions: ?[]const semantic.SemanticFn = null,
    packages: ?[]const semantic.Package = null,
    types: ?[]const semantic.TypeDecl = null,
};

pub fn sessionDocument(overrides: SessionOverrides) semantic.Semantic {
    return .{
        .constructors = overrides.constructors orelse &session_constructors,
        .functions = overrides.functions orelse &session_functions,
        .sessions = overrides.sessions orelse &session_declaration,
        .package = "sessions",
        .packages = overrides.packages,
        .prefix = "zg",
        .types = overrides.types orelse &session_types,
        .zig_version = "0.16.0",
    };
}

const session_declaration = [_]semantic.Session{.{ .children = &.{"Stream"}, .name = "Session", .primary = "Queue" }};

const session_types = [_]semantic.TypeDecl{
    .{ .kind = .@"opaque", .name = "Queue" },
    .{ .kind = .@"opaque", .name = "Stream" },
};

const session_constructors = [_]semantic.Constructor{
    .{ .deinit = "deinit", .init = "create", .type = "Queue" },
    .{ .deinit = "freeStream", .init = "newStream", .type = "Stream" },
};

var queue_ref: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Queue" } };
var stream_ref: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Stream" } };
const session_functions = [_]semantic.SemanticFn{
    .{ .name = "create", .namespace = "Queue", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &queue_ref } }, .symbol = "zg_queue_create" },
    .{ .name = "deinit", .receiver = "Queue", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_queue_deinit" },
    .{ .child_of_receiver = true, .go = .{ .owner = "Stream" }, .name = "newStream", .ownership = .caller, .receiver = "Queue", .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &stream_ref } }, .symbol = "zg_queue_new_stream" },
    .{ .name = "freeStream", .receiver = "Stream", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_stream_free" },
};

/// The one issue a document raises, with its code, message and hint checked.
pub fn expectSessionIssue(document: semantic.Semantic, code: []const u8, message_needle: []const u8, hint_needle: []const u8) !void {
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try sessionIssue(scratch.allocator(), document, targets.default)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings(code, issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, message_needle) != null);
    try std.testing.expect(std.mem.indexOf(u8, issue.hint, hint_needle) != null);
}

test "a session without children is refused" {
    const empty = [_]semantic.Session{.{ .children = &.{}, .name = "Session", .primary = "Queue" }};
    try expectSessionIssue(sessionDocument(.{ .sessions = &empty }), "ZIGO062", "lists no child handles", "dependent child");
}

test "a session listing the same child twice is refused" {
    const doubled = [_]semantic.Session{.{ .children = &.{ "Stream", "Stream" }, .name = "Session", .primary = "Queue" }};
    try expectSessionIssue(sessionDocument(.{ .sessions = &doubled }), "ZIGO062", "lists `Stream` twice", "once");
}

test "a session listing its primary as a child is refused" {
    const self_referential = [_]semantic.Session{.{ .children = &.{"Queue"}, .name = "Session", .primary = "Queue" }};
    try expectSessionIssue(sessionDocument(.{ .sessions = &self_referential }), "ZIGO062", "primary `Queue` as a child", "closes last");
}

test "a child that is not a dependent child of the primary is refused" {
    const other_ref: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Stream" } };
    var functions = session_functions;
    // The same child type, handed out by a second primary instead.
    functions[2].receiver = "Other";
    const overrides = [_]semantic.TypeDecl{
        .{ .kind = .@"opaque", .name = "Queue" },
        .{ .kind = .@"opaque", .name = "Other" },
        .{ .kind = .@"opaque", .name = "Stream" },
    };
    _ = other_ref;
    try expectSessionIssue(sessionDocument(.{ .functions = &functions, .types = &overrides }), "ZIGO062", "dependent child of `Other`, not of `Queue`", "hands out");
}

test "a child no handle hands out is refused" {
    var loose_ref: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Loose" } };
    const loose = [_]semantic.SemanticFn{
        .{ .name = "create", .namespace = "Queue", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &queue_ref } }, .symbol = "zg_queue_create" },
        .{ .name = "deinit", .receiver = "Queue", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_queue_deinit" },
        .{ .name = "open", .namespace = "Loose", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &loose_ref } }, .symbol = "zg_loose_open" },
        .{ .name = "close", .receiver = "Loose", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_loose_close" },
    };
    const constructors = [_]semantic.Constructor{
        .{ .deinit = "deinit", .init = "create", .type = "Queue" },
        .{ .deinit = "close", .init = "open", .type = "Loose" },
    };
    const types = [_]semantic.TypeDecl{
        .{ .kind = .@"opaque", .name = "Queue" },
        .{ .kind = .@"opaque", .name = "Loose" },
    };
    const loose_session = [_]semantic.Session{.{ .children = &.{"Loose"}, .name = "Session", .primary = "Queue" }};
    try expectSessionIssue(
        sessionDocument(.{ .constructors = &constructors, .functions = &loose, .sessions = &loose_session, .types = &types }),
        "ZIGO062",
        "`Loose` is not a dependent child of any handle",
        ".parent = .receiver",
    );
}

test "a child without a destructor is refused" {
    const view = [_]semantic.SemanticFn{
        .{ .name = "create", .namespace = "Queue", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &queue_ref } }, .symbol = "zg_queue_create" },
        .{ .name = "deinit", .receiver = "Queue", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_queue_deinit" },
        .{ .borrowed_return = true, .name = "view", .receiver = "Queue", .params = &.{}, .@"return" = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "View" } }, .symbol = "zg_queue_view" },
    };
    const constructors = [_]semantic.Constructor{.{ .deinit = "deinit", .init = "create", .type = "Queue" }};
    const types = [_]semantic.TypeDecl{
        .{ .kind = .@"opaque", .name = "Queue" },
        .{ .kind = .@"opaque", .name = "View" },
    };
    const view_session = [_]semantic.Session{.{ .children = &.{"View"}, .name = "Session", .primary = "Queue" }};
    try expectSessionIssue(
        sessionDocument(.{ .constructors = &constructors, .functions = &view, .sessions = &view_session, .types = &types }),
        "ZIGO062",
        "`View` has no Close method",
        "borrowed views",
    );
}

test "session members in different packages are refused" {
    const packages = [_]semantic.Package{
        .{ .name = "queues", .path = "queues" },
        .{ .name = "streams", .path = "streams" },
    };
    const types = [_]semantic.TypeDecl{
        .{ .kind = .@"opaque", .name = "Queue", .package = "queues" },
        .{ .kind = .@"opaque", .name = "Stream", .package = "streams" },
    };
    try expectSessionIssue(
        sessionDocument(.{ .packages = &packages, .types = &types }),
        "ZIGO062",
        "different public packages",
        "one package",
    );
}

test "a session name colliding with a registered type is refused" {
    const colliding = [_]semantic.Session{.{ .children = &.{"Stream"}, .name = "Queue", .primary = "Queue" }};
    try expectSessionIssue(sessionDocument(.{ .sessions = &colliding }), "ZIGO024", "collides between session `Queue` and type `Queue`", "different Go identifier");
}

test "a constructor name colliding with a package function is refused" {
    const colliding = [_]semantic.SemanticFn{
        .{ .name = "create", .namespace = "Queue", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &queue_ref } }, .symbol = "zg_queue_create" },
        .{ .name = "deinit", .receiver = "Queue", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_queue_deinit" },
        .{ .child_of_receiver = true, .go = .{ .owner = "Stream" }, .name = "newStream", .ownership = .caller, .receiver = "Queue", .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &stream_ref } }, .symbol = "zg_queue_new_stream" },
        .{ .name = "freeStream", .receiver = "Stream", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_stream_free" },
        // A free function that already answers to the constructor's name.
        .{ .name = "newSession", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_new_session" },
    };
    try expectSessionIssue(
        sessionDocument(.{ .functions = &colliding }),
        "ZIGO024",
        "collides between the constructor `NewSession` and function `newSession`",
        "different Go identifier",
    );
}

test "a session whose primary accessor is named Close is refused" {
    // The primary's accessor is its type name, so a handle actually called
    // `Close` is the one shape that clashes with the session's own `Close`.
    // A child cannot: its accessor carries the plural `s`.
    var close_ref: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Close" } };
    const functions = [_]semantic.SemanticFn{
        .{ .name = "create", .namespace = "Close", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &close_ref } }, .symbol = "zg_close_create" },
        .{ .name = "deinit", .receiver = "Close", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_close_deinit" },
        .{ .child_of_receiver = true, .go = .{ .owner = "Stream" }, .name = "newStream", .ownership = .caller, .receiver = "Close", .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &stream_ref } }, .symbol = "zg_close_new_stream" },
        .{ .name = "freeStream", .receiver = "Stream", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_stream_free" },
    };
    const constructors = [_]semantic.Constructor{
        .{ .deinit = "deinit", .init = "create", .type = "Close" },
        .{ .deinit = "freeStream", .init = "newStream", .type = "Stream" },
    };
    const types = [_]semantic.TypeDecl{
        .{ .kind = .@"opaque", .name = "Close" },
        .{ .kind = .@"opaque", .name = "Stream" },
    };
    const sessions = [_]semantic.Session{.{ .children = &.{"Stream"}, .name = "Session", .primary = "Close" }};
    try expectSessionIssue(
        sessionDocument(.{ .constructors = &constructors, .functions = &functions, .sessions = &sessions, .types = &types }),
        "ZIGO024",
        "collides between the accessor for `Close`",
        "one accessor per member",
    );
}

test "a session primary without a destructor is refused" {
    // The primary is closed last, so it needs a `Close` as much as a child
    // does. A borrowed view has none, and emitting the call anyway would
    // produce Go that does not compile.
    var box_ref: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Box" } };
    const functions = [_]semantic.SemanticFn{
        .{ .name = "create", .namespace = "Box", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &box_ref } }, .symbol = "zg_box_create" },
        .{ .name = "deinit", .receiver = "Box", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_box_deinit" },
        .{ .borrowed_return = true, .name = "view", .receiver = "Box", .params = &.{}, .@"return" = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "View" } }, .symbol = "zg_box_view" },
        .{ .child_of_receiver = true, .go = .{ .owner = "Stream" }, .name = "newStream", .ownership = .caller, .receiver = "View", .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &stream_ref } }, .symbol = "zg_view_new_stream" },
        .{ .name = "freeStream", .receiver = "Stream", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_stream_free" },
    };
    const constructors = [_]semantic.Constructor{
        .{ .deinit = "deinit", .init = "create", .type = "Box" },
        .{ .deinit = "freeStream", .init = "newStream", .type = "Stream" },
    };
    const types = [_]semantic.TypeDecl{
        .{ .kind = .@"opaque", .name = "Box" },
        .{ .kind = .@"opaque", .name = "View" },
        .{ .kind = .@"opaque", .name = "Stream" },
    };
    const sessions = [_]semantic.Session{.{ .children = &.{"Stream"}, .name = "Session", .primary = "View" }};
    try expectSessionIssue(
        sessionDocument(.{ .constructors = &constructors, .functions = &functions, .sessions = &sessions, .types = &types }),
        "ZIGO062",
        "primary `View` has no Close method",
        "borrowed views",
    );
}

test "a child two handles hand out is accepted through either primary" {
    // Nothing stops two handles from each handing out the same child type.
    // Answering with whichever constructor the document lists first would
    // refuse a session over the other one.
    var other_ref: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Other" } };
    const functions = [_]semantic.SemanticFn{
        .{ .name = "create", .namespace = "Other", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &other_ref } }, .symbol = "zg_other_create" },
        .{ .name = "deinitOther", .receiver = "Other", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_other_deinit" },
        // Listed before the queue's, so a first-match answer would name `Other`.
        .{ .child_of_receiver = true, .go = .{ .owner = "Stream" }, .name = "otherStream", .ownership = .caller, .receiver = "Other", .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &stream_ref } }, .symbol = "zg_other_new_stream" },
        .{ .name = "create", .namespace = "Queue", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &queue_ref } }, .symbol = "zg_queue_create" },
        .{ .name = "deinit", .receiver = "Queue", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_queue_deinit" },
        .{ .child_of_receiver = true, .go = .{ .owner = "Stream" }, .name = "newStream", .ownership = .caller, .receiver = "Queue", .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &stream_ref } }, .symbol = "zg_queue_new_stream" },
        .{ .name = "freeStream", .receiver = "Stream", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_stream_free" },
    };
    const constructors = [_]semantic.Constructor{
        .{ .deinit = "deinitOther", .init = "create", .type = "Other" },
        .{ .deinit = "freeStream", .init = "otherStream", .type = "Stream" },
        .{ .deinit = "deinit", .init = "create", .type = "Queue" },
        .{ .deinit = "freeStream", .init = "newStream", .type = "Stream" },
    };
    const types = [_]semantic.TypeDecl{
        .{ .kind = .@"opaque", .name = "Other" },
        .{ .kind = .@"opaque", .name = "Queue" },
        .{ .kind = .@"opaque", .name = "Stream" },
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const document = sessionDocument(.{ .constructors = &constructors, .functions = &functions, .types = &types });
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try sessionIssue(scratch.allocator(), document, targets.default));
}
