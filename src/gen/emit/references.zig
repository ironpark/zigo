//! Which generated helpers the public package references, read off its own
//! rendered text. A helper such as `zigoPointToRaw` or `boolToUint8` is
//! emitted only when some rendered body names it, the way the import block
//! is derived from the body rather than from a parallel set of predicates.
const std = @import("std");
const abi = @import("abi");
const emit = @import("emit.zig");

/// The identifiers a rendering of the public package used. Selectors
/// (`x.Name`) are not identifiers of this package and are skipped.
pub const Referenced = struct {
    names: std.StringHashMapUnmanaged(void) = .empty,

    pub fn contains(self: *const Referenced, name: []const u8) bool {
        return self.names.contains(name);
    }

    pub fn deinit(self: *Referenced, allocator: std.mem.Allocator) void {
        var keys = self.names.keyIterator();
        while (keys.next()) |key| allocator.free(key.*);
        self.names.deinit(allocator);
    }

    fn add(self: *Referenced, allocator: std.mem.Allocator, name: []const u8) !void {
        if (self.names.contains(name)) return;
        const owned = try allocator.dupe(u8, name);
        errdefer allocator.free(owned);
        try self.names.put(allocator, owned, {});
    }
};

/// Records every identifier of a Go body: comments and string literals are
/// skipped, and so is the name after a `.`, which belongs to another package
/// or to a field.
pub fn scanBody(allocator: std.mem.Allocator, set: *Referenced, body: []const u8) !void {
    var index: usize = 0;
    var after_dot = false;
    while (index < body.len) {
        const byte = body[index];
        if (byte == '/' and index + 1 < body.len and body[index + 1] == '/') {
            index = std.mem.indexOfScalarPos(u8, body, index, '\n') orelse body.len;
            after_dot = false;
            continue;
        }
        if (byte == '`') {
            index = 1 + (std.mem.indexOfScalarPos(u8, body, index + 1, '`') orelse body.len - 1);
            after_dot = false;
            continue;
        }
        if (byte == '"' or byte == '\'') {
            index += 1;
            while (index < body.len and body[index] != byte) : (index += 1) {
                if (body[index] == '\\') index += 1;
            }
            index += 1;
            after_dot = false;
            continue;
        }
        if (!isIdentifierStart(byte)) {
            after_dot = byte == '.';
            index += 1;
            continue;
        }
        const begin = index;
        while (index < body.len and isIdentifierByte(body[index])) index += 1;
        if (!after_dot) try set.add(allocator, body[begin..index]);
        after_dot = false;
    }
}

fn isIdentifierStart(byte: u8) bool {
    return byte == '_' or std.ascii.isAlphabetic(byte);
}

pub fn isIdentifierByte(byte: u8) bool {
    return byte == '_' or std.ascii.isAlphanumeric(byte);
}

/// The helpers one public package needs, found by rendering it. The first
/// rendering emits no gated helper, so its identifiers are exactly what the
/// functions and types reference; each further rendering adds the helpers
/// found so far, whose bodies may name more. The set only grows, so the
/// first rendering that adds nothing is the answer.
pub fn referencedHelpersAlloc(allocator: std.mem.Allocator, program: abi.Program, options: emit.Options) !Referenced {
    var set: Referenced = .{};
    errdefer set.deinit(allocator);
    while (true) {
        var trial = options;
        trial.helpers = &set;
        var next: Referenced = .{};
        errdefer next.deinit(allocator);
        for (emit.public_emitters) |emitter| {
            var rendered: std.Io.Writer.Allocating = .init(allocator);
            defer rendered.deinit();
            try emitter.render(allocator, &rendered.writer, program, trial);
            try scanBody(allocator, &next, rendered.written());
        }
        const files = try emit.unionFilesAlloc(allocator, program, trial);
        defer {
            for (files) |file| {
                allocator.free(file.path);
                allocator.free(file.contents);
            }
            allocator.free(files);
        }
        for (files) |file| try scanBody(allocator, &next, file.contents);
        if (next.names.count() == set.names.count()) {
            next.deinit(allocator);
            return set;
        }
        set.deinit(allocator);
        set = next;
    }
}

test "scanBody skips comments, strings and selectors" {
    var set: Referenced = .{};
    defer set.deinit(std.testing.allocator);
    try scanBody(std.testing.allocator, &set,
        \\// zigoIgnored is a comment
        \\func use(value Point) { _ = "zigoQuoted"; _ = raw.Selector; result := zigoPointToRaw(value) }
    );
    try std.testing.expect(set.contains("zigoPointToRaw"));
    try std.testing.expect(set.contains("Point"));
    try std.testing.expect(set.contains("raw"));
    try std.testing.expect(!set.contains("Selector"));
    try std.testing.expect(!set.contains("zigoIgnored"));
    try std.testing.expect(!set.contains("zigoQuoted"));
}
