//! Validate a single Go //go:build expression, without interpreting build tags.
const std = @import("std");
pub fn valid(text: []const u8) bool {
    // Reject source injection and excessive nesting before recursive parsing.
    if (text.len == 0 or text.len > 4096 or std.mem.indexOfAny(u8, text, "\r\n") != null) return false;
    var parser: Parser = .{ .text = text };
    return parser.expression(0) and parser.atEnd();
}
const Parser = struct {
    text: []const u8,
    index: usize = 0,
    fn skip(self: *Parser) void {
        while (self.index < self.text.len and (self.text[self.index] == ' ' or self.text[self.index] == '\t')) self.index += 1;
    }
    fn atEnd(self: *Parser) bool {
        self.skip();
        return self.index == self.text.len;
    }
    fn take(self: *Parser, token: []const u8) bool {
        self.skip();
        if (!std.mem.startsWith(u8, self.text[self.index..], token)) return false;
        self.index += token.len;
        return true;
    }
    fn expression(self: *Parser, depth: usize) bool {
        if (!self.conjunction(depth)) return false;
        while (self.take("||")) if (!self.conjunction(depth)) return false;
        return true;
    }
    fn conjunction(self: *Parser, depth: usize) bool {
        if (!self.atom(depth)) return false;
        while (self.take("&&")) if (!self.atom(depth)) return false;
        return true;
    }
    fn atom(self: *Parser, depth: usize) bool {
        if (depth > 64) return false;
        if (self.take("!")) {
            // Go's constraint grammar does not permit a double negation.
            self.skip();
            if (std.mem.startsWith(u8, self.text[self.index..], "!")) return false;
            return self.atom(depth + 1);
        }
        if (self.take("(")) return self.expression(depth + 1) and self.take(")");
        self.skip();
        const start = self.index;
        while (self.index < self.text.len) {
            const byte = self.text[self.index];
            if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.') break;
            self.index += 1;
        }
        return self.index != start;
    }
};

test "build constraints accept expressions and reject malformed or injected source" {
    for ([_][]const u8{ "linux", "go1.24 && (linux || darwin)", "!windows", "!(linux || windows)", "a || b && c" }) |text| try std.testing.expect(valid(text));
    for ([_][]const u8{ "", " ", "a b", "a & b", "a ||", "()", "(a", "!!a", "a\npackage evil", "a // comment" }) |text| try std.testing.expect(!valid(text));
}
