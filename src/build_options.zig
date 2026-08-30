const std = @import("std");

pub const RawPackageError = error{
    InvalidPath,
    InvalidComponent,
    InvalidCharacter,
};

pub fn validateRawPackagePath(path: []const u8) RawPackageError!void {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, '\\') != null)
        return error.InvalidPath;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, ".."))
            return error.InvalidComponent;
        for (component) |character| {
            if (!(std.ascii.isAlphanumeric(character) or character == '_' or character == '-' or character == '.'))
                return error.InvalidCharacter;
        }
    }
}

pub fn validateRawPackageName(name: []const u8) error{InvalidGoPackageName}!void {
    if (!isGoIdentifier(name)) return error.InvalidGoPackageName;
}

pub fn isGoIdentifier(value: []const u8) bool {
    if (value.len == 0 or std.mem.eql(u8, value, "_") or isGoKeyword(value) or !(std.ascii.isAlphabetic(value[0]) or value[0] == '_')) return false;
    for (value[1..]) |character| if (!(std.ascii.isAlphanumeric(character) or character == '_')) return false;
    return true;
}

fn isGoKeyword(value: []const u8) bool {
    const keywords = [_][]const u8{
        "break",    "default",     "func",   "interface", "select",
        "case",     "defer",       "go",     "map",       "struct",
        "chan",     "else",        "goto",   "package",   "switch",
        "const",    "fallthrough", "if",     "range",     "type",
        "continue", "for",         "import", "return",    "var",
    };
    for (keywords) |keyword| if (std.mem.eql(u8, value, keyword)) return true;
    return false;
}

test "raw package paths accept portable relative components" {
    for ([_][]const u8{ "internal/raw", "bridge/cgo", "vendor-ffi/v1.2" }) |path|
        try validateRawPackagePath(path);
}

test "raw package paths reject unsafe forms and components" {
    const cases = [_]struct { path: []const u8, expected: RawPackageError }{
        .{ .path = "", .expected = error.InvalidPath },
        .{ .path = "/absolute", .expected = error.InvalidPath },
        .{ .path = "internal\\raw", .expected = error.InvalidPath },
        .{ .path = "internal//raw", .expected = error.InvalidComponent },
        .{ .path = "./raw", .expected = error.InvalidComponent },
        .{ .path = "../raw", .expected = error.InvalidComponent },
        .{ .path = "internal/raw!", .expected = error.InvalidCharacter },
    };
    for (cases) |case| try std.testing.expectError(case.expected, validateRawPackagePath(case.path));
}

test "raw package names reject Go keywords" {
    try validateRawPackageName("native_api");
    try std.testing.expectError(error.InvalidGoPackageName, validateRawPackageName("type"));
    try std.testing.expectError(error.InvalidGoPackageName, validateRawPackageName("123"));
}

test "Go identifier validation covers keywords and boundaries" {
    for ([_][]const u8{ "raw", "native_api", "_private", "x9" }) |name| try std.testing.expect(isGoIdentifier(name));
    for ([_][]const u8{ "", "_", "type", "9raw", "raw-name" }) |name| try std.testing.expect(!isGoIdentifier(name));
}
