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

/// The one rule for the C symbol a bound function is exported under. The
/// header, the linker, `semantic.json` metadata and the collision check all
/// read the name from here. Backend decorations such as purego's `_purego_v2`
/// suffix are added by the lowering step, not by this rule.
pub fn functionSymbolAlloc(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    owner: ?[]const u8,
    function_name: []const u8,
) ![]u8 {
    const name = try snakeAlloc(allocator, function_name);
    defer allocator.free(name);
    const owner_path = owner orelse return std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, name });
    // An owner is a dotted path once a binding names a nested namespace, and
    // each segment converts on its own: `unicode.codepointWidth` under prefix
    // `zg` is `zg_unicode_codepoint_width`. A single segment is unchanged.
    var symbol: std.ArrayList(u8) = .empty;
    errdefer symbol.deinit(allocator);
    try symbol.appendSlice(allocator, prefix);
    var segments = std.mem.splitScalar(u8, owner_path, '.');
    while (segments.next()) |segment| {
        const owner_name = try snakeAlloc(allocator, segment);
        defer allocator.free(owner_name);
        try symbol.append(allocator, '_');
        try symbol.appendSlice(allocator, owner_name);
    }
    try symbol.append(allocator, '_');
    try symbol.appendSlice(allocator, name);
    return symbol.toOwnedSlice(allocator);
}

/// The symbol `semantic.json` carried before the rule was unified: the prefix
/// joined to the unconverted Zig function name, with the owning type dropped.
/// `abi_diff` uses it to tell a metadata correction from a real ABI change.
pub fn legacyFunctionSymbolAlloc(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    function_name: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, function_name });
}

test "function symbols carry the owning type and normalize to snake_case" {
    const cases = [_]struct { owner: ?[]const u8, name: []const u8, symbol: []const u8 }{
        .{ .owner = null, .name = "liveObjects", .symbol = "zg_live_objects" },
        .{ .owner = "Counter", .name = "deinit", .symbol = "zg_counter_deinit" },
        .{ .owner = "EventQueue", .name = "pushEvent", .symbol = "zg_event_queue_push_event" },
    };
    for (cases) |case| {
        const symbol = try functionSymbolAlloc(std.testing.allocator, "zg", case.owner, case.name);
        defer std.testing.allocator.free(symbol);
        try std.testing.expectEqualStrings(case.symbol, symbol);
    }
    // Two methods that share a name on different types must not collide, which
    // is exactly what the pre-correction metadata rule did.
    const legacy = try legacyFunctionSymbolAlloc(std.testing.allocator, "zg", "deinit");
    defer std.testing.allocator.free(legacy);
    try std.testing.expectEqualStrings("zg_deinit", legacy);
}

/// The C type name a declaration exports: `<prefix>_<snake_case_name>`.
/// A Go import path segment that may be absent. An empty or `.` base means the
/// module root, so it contributes neither a separator nor a component — the
/// alternative spells `"{module}/."`, which is not an import path.
pub const PathSegment = struct {
    separator: []const u8,
    value: []const u8,
};

pub fn optionalPathSegment(base: []const u8) PathSegment {
    if (base.len == 0 or std.mem.eql(u8, base, ".")) return .{ .separator = "", .value = "" };
    return .{ .separator = "/", .value = base };
}

pub fn cTypeNameAlloc(allocator: std.mem.Allocator, prefix: []const u8, type_name: []const u8) ![]u8 {
    const owner = try snakeAlloc(allocator, type_name);
    defer allocator.free(owner);
    return std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, owner });
}

pub fn projectionSymbolAlloc(allocator: std.mem.Allocator, prefix: []const u8, type_name: []const u8, projection: []const u8) ![]u8 {
    const owner = try snakeAlloc(allocator, type_name);
    defer allocator.free(owner);
    const name = try snakeAlloc(allocator, projection);
    defer allocator.free(name);
    return std.fmt.allocPrint(allocator, "{s}_{s}_project_{s}", .{ prefix, owner, name });
}

pub fn camelAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const snake = try snakeAlloc(allocator, input);
    defer allocator.free(snake);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var iterator = std.mem.splitScalar(u8, snake, '_');
    var first = true;
    while (iterator.next()) |word| {
        if (word.len == 0) continue;
        if (first) {
            try output.appendSlice(allocator, word);
            first = false;
        } else if (initialism(word)) |canonical| {
            try output.appendSlice(allocator, canonical);
        } else {
            try output.append(allocator, std.ascii.toUpper(word[0]));
            try output.appendSlice(allocator, word[1..]);
        }
    }
    return output.toOwnedSlice(allocator);
}

/// Removes a metadata group's shared Zig prefix and restores the ordinary
/// lower-camel spelling consumed by the rest of the naming pipeline.
pub fn stripFunctionPrefix(comptime input: []const u8, comptime prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, input, prefix) or input.len == prefix.len) return null;
    const suffix = input[prefix.len..];
    comptime var output: [suffix.len]u8 = suffix[0..suffix.len].*;
    if (output[0] >= 'A' and output[0] <= 'Z') output[0] += 'a' - 'A';
    const frozen = output;
    return &frozen;
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
    const cases = [_]struct { input: []const u8, snake: []const u8, pascal: []const u8, camel: []const u8 }{
        .{ .input = "lookupID", .snake = "lookup_id", .pascal = "LookupID", .camel = "lookupID" },
        .{ .input = "parseURL", .snake = "parse_url", .pascal = "ParseURL", .camel = "parseURL" },
        .{ .input = "validateUTF8", .snake = "validate_utf8", .pascal = "ValidateUTF8", .camel = "validateUTF8" },
        .{ .input = "HTTPClient", .snake = "http_client", .pascal = "HttpClient", .camel = "httpClient" },
    };
    for (cases) |case| {
        const snake = try snakeAlloc(std.testing.allocator, case.input);
        defer std.testing.allocator.free(snake);
        const pascal = try pascalAlloc(std.testing.allocator, case.input);
        defer std.testing.allocator.free(pascal);
        const camel = try camelAlloc(std.testing.allocator, case.input);
        defer std.testing.allocator.free(camel);
        try std.testing.expectEqualStrings(case.snake, snake);
        try std.testing.expectEqualStrings(case.pascal, pascal);
        try std.testing.expectEqualStrings(case.camel, camel);
    }
}

test "function group prefixes are stripped and lower-cased" {
    try std.testing.expectEqualStrings("selectAll", stripFunctionPrefix("screenSelectAll", "screen").?);
    try std.testing.expectEqualStrings("uRL", stripFunctionPrefix("screenURL", "screen").?);
    try std.testing.expect(stripFunctionPrefix("selectAll", "screen") == null);
    try std.testing.expect(stripFunctionPrefix("screen", "screen") == null);
}

/// Environment variable a generated purego package reads before the shared
/// `ZIGO_LIBRARY_PATH`, so two zigo packages in one process stay independent.
pub fn libraryPathEnvironmentAlloc(allocator: std.mem.Allocator, go_package: []const u8) ![]u8 {
    var name: std.ArrayList(u8) = .empty;
    errdefer name.deinit(allocator);
    try name.appendSlice(allocator, "ZIGO_");
    for (go_package) |character| try name.append(allocator, if (std.ascii.isAlphanumeric(character))
        std.ascii.toUpper(character)
    else
        '_');
    try name.appendSlice(allocator, "_LIBRARY_PATH");
    return name.toOwnedSlice(allocator);
}

test "library path environment names are derived from the Go package" {
    const name = try libraryPathEnvironmentAlloc(std.testing.allocator, "event_queue");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("ZIGO_EVENT_QUEUE_LIBRARY_PATH", name);
}

/// Names the generated Go bodies introduce, which a parameter must not shadow.
const reserved_locals = [_][]const u8{
    "code",           "result", "outResult", "outResultPtr",
    "outResultLen",   "self",   "err",       "handle",
    "callbackHandle",
};

pub fn isGoKeyword(value: []const u8) bool {
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

/// Rejects a name that cannot be a Go package identifier.
pub fn validateGoPackageName(name: []const u8) error{InvalidGoPackageName}!void {
    if (!isGoIdentifier(name)) return error.InvalidGoPackageName;
}

pub fn isGoIdentifier(value: []const u8) bool {
    if (value.len == 0 or std.mem.eql(u8, value, "_") or isGoKeyword(value) or
        !(std.ascii.isAlphabetic(value[0]) or value[0] == '_')) return false;
    for (value[1..]) |character| if (!(std.ascii.isAlphanumeric(character) or character == '_')) return false;
    return true;
}

/// Public Go names for one signature's parameters. Zig spells parameters in
/// snake_case, so they are camelCased, then escaped when the result is a Go
/// keyword, shadows a generated local, or repeats an earlier parameter.
pub fn goParamNamesAlloc(allocator: std.mem.Allocator, zig_names: []const []const u8) ![][]u8 {
    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }
    for (zig_names) |zig_name| {
        var candidate = try camelAlloc(allocator, zig_name);
        if (isGoKeyword(candidate) or isReservedLocal(candidate)) {
            const previous = candidate;
            defer allocator.free(previous);
            candidate = try std.fmt.allocPrint(allocator, "{s}_", .{previous});
        }
        var suffix: usize = 2;
        while (containsName(names.items, candidate)) : (suffix += 1) {
            const previous = candidate;
            defer allocator.free(previous);
            candidate = try std.fmt.allocPrint(allocator, "{s}{d}", .{ previous, suffix });
        }
        try names.append(allocator, candidate);
    }
    return names.toOwnedSlice(allocator);
}

pub fn freeParamNames(allocator: std.mem.Allocator, names: [][]u8) void {
    for (names) |name| allocator.free(name);
    allocator.free(names);
}

fn isReservedLocal(value: []const u8) bool {
    for (reserved_locals) |reserved| if (std.mem.eql(u8, value, reserved)) return true;
    return false;
}

fn containsName(names: []const []const u8, value: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, value)) return true;
    return false;
}

test "Go parameter names are camelCase and escape keywords, locals and duplicates" {
    const zig_names = [_][]const u8{ "source_len", "type", "range", "code", "result", "new_name", "newName", "p0" };
    const names = try goParamNamesAlloc(std.testing.allocator, &zig_names);
    defer freeParamNames(std.testing.allocator, names);
    const expected = [_][]const u8{ "sourceLen", "type_", "range_", "code_", "result_", "newName", "newName2", "p0" };
    for (expected, names) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "Go package names reject keywords and non-identifiers" {
    try validateGoPackageName("native_api");
    try std.testing.expectError(error.InvalidGoPackageName, validateGoPackageName("type"));
    try std.testing.expectError(error.InvalidGoPackageName, validateGoPackageName("123"));
}

test "Go identifier and keyword checks cover boundaries" {
    for ([_][]const u8{ "raw", "native_api", "_private", "x9" }) |name| try std.testing.expect(isGoIdentifier(name));
    for ([_][]const u8{ "", "_", "type", "9raw", "raw-name" }) |name| try std.testing.expect(!isGoIdentifier(name));
}

/// The Go type name for one tagged-union variant: `<Union><PascalVariant>`.
///
/// A derived name that another generated identifier already claims takes a
/// `Variant` suffix, then a numeric one, so a clash resolves the same way on
/// every run instead of emitting two Go declarations with one name. A variant
/// whose name carries no identifier characters has no derivation at all and is
/// reported as `error.InvalidName`.
pub fn variantTypeNameAlloc(
    allocator: std.mem.Allocator,
    union_name: []const u8,
    variant_name: []const u8,
    taken: []const []const u8,
) error{ InvalidName, OutOfMemory }![]u8 {
    const variant = try pascalAlloc(allocator, variant_name);
    defer allocator.free(variant);
    if (variant.len == 0) return error.InvalidName;
    var candidate = try std.fmt.allocPrint(allocator, "{s}{s}", .{ union_name, variant });
    errdefer allocator.free(candidate);
    if (!containsName(taken, candidate)) return candidate;
    {
        const previous = candidate;
        defer allocator.free(previous);
        candidate = try std.fmt.allocPrint(allocator, "{s}Variant", .{previous});
    }
    var suffix: usize = 2;
    while (containsName(taken, candidate)) : (suffix += 1) {
        const previous = candidate;
        defer allocator.free(previous);
        candidate = try std.fmt.allocPrint(allocator, "{s}Variant{d}", .{ union_name, suffix });
    }
    return candidate;
}

/// File-name stem for one tagged union's generated file. The caller places it
/// in `<package>_union_<stem>_gen.go`, so the `union` segment already keeps a
/// union named `type` or `errors` clear of the concern-scoped files; only two
/// unions normalizing to the same stem need resolving, and a numeric suffix
/// does that in declaration order.
pub fn unionFileStemAlloc(
    allocator: std.mem.Allocator,
    union_name: []const u8,
    taken: []const []const u8,
) error{ InvalidName, OutOfMemory }![]u8 {
    const base = try snakeAlloc(allocator, union_name);
    errdefer allocator.free(base);
    if (base.len == 0) return error.InvalidName;
    if (!containsName(taken, base)) return base;
    defer allocator.free(base);
    var suffix: usize = 2;
    while (true) : (suffix += 1) {
        const candidate = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ base, suffix });
        if (!containsName(taken, candidate)) return candidate;
        allocator.free(candidate);
    }
}

test "variant type names derive from the union and resolve clashes deterministically" {
    const taken = [_][]const u8{ "ValueTag", "ValueTagVariant", "ValueVariant2" };
    const cases = [_]struct { variant: []const u8, expected: []const u8 }{
        .{ .variant = "integer", .expected = "ValueInteger" },
        .{ .variant = "mutableSamples", .expected = "ValueMutableSamples" },
        // `ValueTag` is the tag enum and `ValueTagVariant` is already spoken
        // for, so the numeric suffix settles it.
        .{ .variant = "tag", .expected = "ValueVariant3" },
    };
    for (cases) |case| {
        const name = try variantTypeNameAlloc(std.testing.allocator, "Value", case.variant, &taken);
        defer std.testing.allocator.free(name);
        try std.testing.expectEqualStrings(case.expected, name);
    }
    try std.testing.expectError(error.InvalidName, variantTypeNameAlloc(std.testing.allocator, "Value", "_", &taken));
}

test "union file stems normalize and resolve clashes deterministically" {
    const first = try unionFileStemAlloc(std.testing.allocator, "HTTPResult", &.{});
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualStrings("http_result", first);

    // A union named like a reserved concern is safe: the caller's `union`
    // segment separates `<pkg>_union_type_gen.go` from `<pkg>_type_gen.go`.
    const reserved = try unionFileStemAlloc(std.testing.allocator, "Type", &.{});
    defer std.testing.allocator.free(reserved);
    try std.testing.expectEqualStrings("type", reserved);

    // Two unions can normalize to the same stem; the later one is suffixed.
    const taken = [_][]const u8{ "http_result", "http_result_2" };
    const clash = try unionFileStemAlloc(std.testing.allocator, "httpResult", &taken);
    defer std.testing.allocator.free(clash);
    try std.testing.expectEqualStrings("http_result_3", clash);
}
