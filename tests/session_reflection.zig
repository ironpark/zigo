//! The authoring surface of a session. Reflecting one all the way into the
//! document is `src/reflect/walk.zig`'s job, one layer below where the authoring
//! entry has already been resolved; what this pins is that the entry a binding
//! writes compiles and carries what it was given.
const std = @import("std");
const zigo = @import("zigo");
const session_api = @import("fixtures/session_api.zig");

const api = zigo.scope(session_api);
const Queue = api.handle("Queue", .{}).context();
const Stream = api.handle("Stream", .{}).context();

test "zigo.session takes a primary and its dependent children" {
    const entry = zigo.session(.{
        .name = "Session",
        .primary = Queue.typeRef(),
        .children = &.{Stream.typeRef()},
        .doc = "Session owns a Queue and every Stream it handed out.",
    });
    try std.testing.expectEqual(zigo.Entry.session, std.meta.activeTag(entry));
    try std.testing.expectEqualStrings("Session", entry.session.name);
    try std.testing.expectEqualStrings("root.Stream", entry.session.children[0].path);
    try std.testing.expectEqualStrings("Session owns a Queue and every Stream it handed out.", entry.session.doc.?);
}

test "zigo.session defaults its doc" {
    const entry = zigo.session(.{
        .name = "Session",
        .primary = Queue.typeRef(),
        .children = &.{Stream.typeRef()},
    });
    try std.testing.expectEqual(@as(?[]const u8, null), entry.session.doc);
}
