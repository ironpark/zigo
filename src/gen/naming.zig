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

/// One entry of an initialism table: the lowercased word, and the spelling a
/// language's style guide wants for it.
pub const Initialism = struct { lower: []const u8, canonical: []const u8 };

/// Go's table. `id` -> `ID` is a Go convention, not a property of the bound
/// Zig library, which is why it is a parameter of the transform below rather
/// than a constant inside it: Rust's style guide asks for `Id`, `Url` and
/// `Utf8`, so a Rust target passes `&.{}` and gets them. Go's own callers keep
/// calling `pascalAlloc` and `camelAlloc`, so no call site had to move for the
/// table to become a parameter.
pub const go_initialisms: []const Initialism = &.{
    .{ .lower = "id", .canonical = "ID" },
    .{ .lower = "url", .canonical = "URL" },
    .{ .lower = "utf8", .canonical = "UTF8" },
};

pub fn pascalAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return pascalWithInitialismsAlloc(allocator, input, go_initialisms);
}

/// `pascalAlloc` with the initialism table named by the caller. An empty table
/// title-cases every word, which is what a language without Go's acronym rule
/// wants.
pub fn pascalWithInitialismsAlloc(
    allocator: std.mem.Allocator,
    input: []const u8,
    initialisms: []const Initialism,
) ![]u8 {
    const snake = try snakeAlloc(allocator, input);
    defer allocator.free(snake);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var iterator = std.mem.splitScalar(u8, snake, '_');
    while (iterator.next()) |word| {
        if (word.len == 0) continue;
        if (initialism(word, initialisms)) |canonical| {
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

/// Environment variable a generated binding reads before the shared
/// `ZIGO_LIBRARY_PATH`, so two zigo bindings in one process stay independent.
///
/// One definition, not one per target: the variable names a deployment
/// artifact rather than a language construct, so two targets binding the same
/// library have to agree on it. Agreement is structural here; two copies with
/// a test hoping they match would drift on the next edit to either.
pub fn libraryPathEnvironmentAlloc(allocator: std.mem.Allocator, package: []const u8) ![]u8 {
    var name: std.ArrayList(u8) = .empty;
    errdefer name.deinit(allocator);
    try name.appendSlice(allocator, "ZIGO_");
    for (package) |character| try name.append(allocator, if (std.ascii.isAlphanumeric(character))
        std.ascii.toUpper(character)
    else
        '_');
    try name.appendSlice(allocator, "_LIBRARY_PATH");
    return name.toOwnedSlice(allocator);
}

test "library path environment names are derived from the package" {
    const name = try libraryPathEnvironmentAlloc(std.testing.allocator, "event_queue");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("ZIGO_EVENT_QUEUE_LIBRARY_PATH", name);
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
        } else if (initialism(word, go_initialisms)) |canonical| {
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

fn initialism(word: []const u8, table: []const Initialism) ?[]const u8 {
    for (table) |entry| if (std.mem.eql(u8, word, entry.lower)) return entry.canonical;
    return null;
}

test "an empty initialism table title-cases every word" {
    // What a Rust target asks for: `Id`, not Go's `ID`. Only the Pascal path
    // takes a table -- Rust reaches it for error-variant names, and its
    // function names take the snake_case path, which has no table at all.
    const cases = [_]struct { input: []const u8, pascal: []const u8 }{
        .{ .input = "lookupID", .pascal = "LookupId" },
        .{ .input = "parseURL", .pascal = "ParseUrl" },
        .{ .input = "validateUTF8", .pascal = "ValidateUtf8" },
        // A name with no initialism word in it is spelled the same either way.
        .{ .input = "HTTPClient", .pascal = "HttpClient" },
    };
    for (cases) |case| {
        const pascal = try pascalWithInitialismsAlloc(std.testing.allocator, case.input, &.{});
        defer std.testing.allocator.free(pascal);
        try std.testing.expectEqualStrings(case.pascal, pascal);
    }
}

test "naming normalizes symbols and initialisms" {
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

/// Whether a spelling cannot be a C parameter name: the C keywords through
/// C23, plus the `<stdint.h>`/`<stddef.h>` typedefs the generated header
/// includes, which a parameter of that name would shadow mid-declaration.
/// The Go side escapes its keywords by appending `_`, but a C name is part of
/// the public header and the ABI report, so it is rejected instead of
/// mangled.
pub fn isCKeyword(value: []const u8) bool {
    const keywords = [_][]const u8{
        "alignas",      "alignof",     "auto",           "bool",          "break",
        "case",         "char",        "const",          "constexpr",     "continue",
        "default",      "do",          "double",         "else",          "enum",
        "extern",       "false",       "float",          "for",           "goto",
        "if",           "inline",      "int",            "long",          "nullptr",
        "register",     "restrict",    "return",         "short",         "signed",
        "sizeof",       "static",      "static_assert",  "struct",        "switch",
        "thread_local", "true",        "typedef",        "typeof",        "typeof_unqual",
        "union",        "unsigned",    "void",           "volatile",      "while",
        "_Alignas",     "_Alignof",    "_Atomic",        "_BitInt",       "_Bool",
        "_Complex",     "_Decimal128", "_Decimal32",     "_Decimal64",    "_Generic",
        "_Imaginary",   "_Noreturn",   "_Static_assert", "_Thread_local", "size_t",
        "ptrdiff_t",    "intptr_t",    "uintptr_t",      "intmax_t",      "uintmax_t",
        "int8_t",       "int16_t",     "int32_t",        "int64_t",       "uint8_t",
        "uint16_t",     "uint32_t",    "uint64_t",
    };
    for (keywords) |keyword| if (std.mem.eql(u8, value, keyword)) return true;
    return false;
}

/// Releases a derived name list. Which names a target derives is its own
/// rule; releasing the list is not, so it lives here.
pub fn freeParamNames(allocator: std.mem.Allocator, names: [][]u8) void {
    for (names) |name| allocator.free(name);
    allocator.free(names);
}

/// Whether a derived name is already taken. Every name rule that resolves a
/// clash asks this, including the target's own rules in `targets/go.zig`.
pub fn containsName(names: []const []const u8, value: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, value)) return true;
    return false;
}

test "C keywords and header typedefs are recognised, ordinary names are not" {
    for ([_][]const u8{ "double", "int", "register", "bool", "_Bool", "uint8_t", "size_t", "typeof" }) |name|
        try std.testing.expect(isCKeyword(name));
    for ([_][]const u8{ "dst", "value", "double_", "Double", "count", "" }) |name|
        try std.testing.expect(!isCKeyword(name));
}

/// The Pascal spelling of a dotted owner path: `foo.bar` becomes `FooBar`. A
/// nested declaration reaches the generated surface as one flat identifier, so
/// every segment is pascal-cased and joined.
pub fn ownerPascalAlloc(allocator: std.mem.Allocator, owner: []const u8) ![]u8 {
    var name: std.ArrayList(u8) = .empty;
    errdefer name.deinit(allocator);
    var segments = std.mem.splitScalar(u8, owner, '.');
    while (segments.next()) |segment| {
        const word = try pascalAlloc(allocator, segment);
        defer allocator.free(word);
        try name.appendSlice(allocator, word);
    }
    return name.toOwnedSlice(allocator);
}

pub const OptionsNames = struct {
    type_name: []const u8,
    prefix: []const u8,

    pub fn deinit(self: OptionsNames, allocator: std.mem.Allocator) void {
        allocator.free(self.type_name);
        allocator.free(self.prefix);
    }

    pub fn withNameAlloc(self: OptionsNames, allocator: std.mem.Allocator, field_name: []const u8) ![]u8 {
        const field_pascal = try pascalAlloc(allocator, field_name);
        defer allocator.free(field_pascal);
        return if (self.prefix.len == 0)
            std.fmt.allocPrint(allocator, "With{s}", .{field_pascal})
        else
            std.fmt.allocPrint(allocator, "With{s}{s}", .{ self.prefix, field_pascal });
    }
};

pub fn resolveOptionsPrefixAlloc(
    allocator: std.mem.Allocator,
    explicit_prefix: ?[]const u8,
    owner: ?[]const u8,
    function_name: []const u8,
) ![]u8 {
    if (explicit_prefix) |p| return allocator.dupe(u8, p);
    if (owner) |o| {
        if (o.len > 0) return ownerPascalAlloc(allocator, o);
    }
    return pascalAlloc(allocator, function_name);
}

pub fn resolveOptionTypeNameAlloc(
    allocator: std.mem.Allocator,
    explicit_type_name: ?[]const u8,
    prefix: []const u8,
) ![]u8 {
    if (explicit_type_name) |t| return allocator.dupe(u8, t);
    return if (prefix.len == 0) allocator.dupe(u8, "Option") else std.fmt.allocPrint(allocator, "{s}Option", .{prefix});
}

pub fn resolveOptionsNamesAlloc(
    allocator: std.mem.Allocator,
    explicit_prefix: ?[]const u8,
    explicit_type_name: ?[]const u8,
    owner: ?[]const u8,
    function_name: []const u8,
) !OptionsNames {
    const prefix = try resolveOptionsPrefixAlloc(allocator, explicit_prefix, owner, function_name);
    errdefer allocator.free(prefix);
    const type_name = try resolveOptionTypeNameAlloc(allocator, explicit_type_name, prefix);
    errdefer allocator.free(type_name);
    return .{
        .type_name = type_name,
        .prefix = prefix,
    };
}

test "functional options naming creates expected type and With* function names" {
    // 1. Default declaration on Terminal -> TerminalOption, WithTerminalRows
    {
        const names = try resolveOptionsNamesAlloc(std.testing.allocator, null, null, "Terminal", "init");
        defer names.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings("TerminalOption", names.type_name);
        const with_rows = try names.withNameAlloc(std.testing.allocator, "rows");
        defer std.testing.allocator.free(with_rows);
        try std.testing.expectEqualStrings("WithTerminalRows", with_rows);
    }

    // 2. Explicit prefix = "" -> Option, WithRows
    {
        const names = try resolveOptionsNamesAlloc(std.testing.allocator, "", null, "Terminal", "init");
        defer names.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings("Option", names.type_name);
        const with_rows = try names.withNameAlloc(std.testing.allocator, "rows");
        defer std.testing.allocator.free(with_rows);
        try std.testing.expectEqualStrings("WithRows", with_rows);
    }

    // 3. Free function without owner -> OpenOption, WithOpenRows
    {
        const names = try resolveOptionsNamesAlloc(std.testing.allocator, null, null, null, "open");
        defer names.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings("OpenOption", names.type_name);
        const with_rows = try names.withNameAlloc(std.testing.allocator, "rows");
        defer std.testing.allocator.free(with_rows);
        try std.testing.expectEqualStrings("WithOpenRows", with_rows);
    }

    // 4. Explicit type_name and prefix
    {
        const names = try resolveOptionsNamesAlloc(std.testing.allocator, "Terminal", "TerminalConfig", null, "init");
        defer names.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings("TerminalConfig", names.type_name);
        const with_rows = try names.withNameAlloc(std.testing.allocator, "rows");
        defer std.testing.allocator.free(with_rows);
        try std.testing.expectEqualStrings("WithTerminalRows", with_rows);
    }
}
