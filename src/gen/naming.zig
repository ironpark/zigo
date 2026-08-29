const std = @import("std");

pub fn snakeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    for (input, 0..) |character, index| {
        if (character == '-' or character == ' ' or character == '.') {
            if (output.items.len != 0 and output.items[output.items.len - 1] != '_') try output.append(allocator, '_');
            continue;
        }
        if (std.ascii.isUpper(character)) {
            const previous_is_lower = index != 0 and (std.ascii.isLower(input[index - 1]) or std.ascii.isDigit(input[index - 1]));
            const acronym_end = index != 0 and index + 1 < input.len and std.ascii.isUpper(input[index - 1]) and std.ascii.isLower(input[index + 1]);
            if ((previous_is_lower or acronym_end) and output.items.len != 0 and output.items[output.items.len - 1] != '_') try output.append(allocator, '_');
            try output.append(allocator, std.ascii.toLower(character));
        } else {
            try output.append(allocator, character);
        }
    }
    return output.toOwnedSlice(allocator);
}

pub fn pascalAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const snake = try snakeAlloc(allocator, input);
    defer allocator.free(snake);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var iterator = std.mem.splitScalar(u8, snake, '_');
    while (iterator.next()) |word| {
        if (word.len == 0) continue;
        if (initialism(word)) |canonical| {
            try output.appendSlice(allocator, canonical);
        } else {
            try output.append(allocator, std.ascii.toUpper(word[0]));
            try output.appendSlice(allocator, word[1..]);
        }
    }
    return output.toOwnedSlice(allocator);
}

fn initialism(word: []const u8) ?[]const u8 {
    const table = [_]struct { lower: []const u8, canonical: []const u8 }{
        .{ .lower = "id", .canonical = "ID" },
        .{ .lower = "url", .canonical = "URL" },
        .{ .lower = "utf8", .canonical = "UTF8" },
    };
    inline for (table) |entry| if (std.mem.eql(u8, word, entry.lower)) return entry.canonical;
    return null;
}

test "naming normalizes symbols and Go initialisms" {
    const cases = [_]struct { input: []const u8, snake: []const u8, pascal: []const u8 }{
        .{ .input = "lookupID", .snake = "lookup_id", .pascal = "LookupID" },
        .{ .input = "parseURL", .snake = "parse_url", .pascal = "ParseURL" },
        .{ .input = "validateUTF8", .snake = "validate_utf8", .pascal = "ValidateUTF8" },
    };
    for (cases) |case| {
        const snake = try snakeAlloc(std.testing.allocator, case.input);
        defer std.testing.allocator.free(snake);
        const pascal = try pascalAlloc(std.testing.allocator, case.input);
        defer std.testing.allocator.free(pascal);
        try std.testing.expectEqualStrings(case.snake, snake);
        try std.testing.expectEqualStrings(case.pascal, pascal);
    }
}
