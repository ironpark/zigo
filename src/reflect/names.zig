const std = @import("std");
const semantic = @import("semantic");

/// Enriches reflection-only IR with syntax-only names and doc comments.
/// This pass deliberately does not inspect or alter any type node.
pub fn apply(
    allocator: std.mem.Allocator,
    io: std.Io,
    document: *semantic.Semantic,
    bindings_path: []const u8,
    source_root_path: ?[]const u8,
    diagnostics: *std.Io.Writer,
) !void {
    const bindings_source = std.Io.Dir.cwd().readFileAlloc(io, bindings_path, allocator, .limited(8 * 1024 * 1024)) catch |err| {
        try writeReadError(diagnostics, bindings_path, err);
        return err;
    };
    if (document.doc == null) document.doc = try containerDocAlloc(allocator, bindings_source);
    const functions = try allocator.dupe(semantic.SemanticFn, document.functions);
    var has_errors = try scanSourceWithDiagnostics(allocator, bindings_source, functions, bindings_path, diagnostics);

    const directory = std.fs.path.dirname(bindings_path) orelse ".";
    const root_path = source_root_path orelse try std.fs.path.join(allocator, &.{ directory, "root.zig" });
    if (!std.mem.eql(u8, root_path, bindings_path)) {
        if (std.Io.Dir.cwd().readFileAlloc(io, root_path, allocator, .limited(8 * 1024 * 1024))) |root_source| {
            has_errors = try scanSourceWithDiagnostics(allocator, root_source, functions, root_path, diagnostics) or has_errors;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => {
                try writeReadError(diagnostics, root_path, err);
                has_errors = true;
            },
        }
    }

    var cursor: usize = 0;
    const marker = "@import(\"";
    while (std.mem.indexOfPos(u8, bindings_source, cursor, marker)) |start| {
        const value_start = start + marker.len;
        const end = std.mem.indexOfScalarPos(u8, bindings_source, value_start, '"') orelse break;
        cursor = end + 1;
        const referenced = bindings_source[value_start..end];
        if (!std.mem.endsWith(u8, referenced, ".zig")) continue;
        const path = try std.fs.path.join(allocator, &.{ directory, referenced });
        if (std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024))) |source| {
            has_errors = try scanSourceWithDiagnostics(allocator, source, functions, path, diagnostics) or has_errors;
        } else |err| {
            try writeReadError(diagnostics, path, err);
            has_errors = true;
        }
    }
    document.functions = functions;
    if (has_errors) return error.EnrichmentFailed;
}

pub fn writeWarnings(writer: *std.Io.Writer, document: semantic.Semantic) !void {
    for (document.functions) |function| {
        var uses_fallback = false;
        for (function.params) |parameter| if (parameter.name_source == .fallback) {
            uses_fallback = true;
            break;
        };
        if (uses_fallback) try writer.print("warning: zigo has no parameter names for {s}; using p0-style names\n", .{function.name});
    }
}

/// The `//!` block at the top of the bindings file documents the container the
/// bindings live in, which is exactly what the generated Go package doc says.
fn containerDocAlloc(allocator: std.mem.Allocator, source: []const u8) !?[]const u8 {
    var result: std.Io.Writer.Allocating = .init(allocator);
    errdefer result.deinit();
    var wrote = false;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) {
            if (wrote) break;
            continue;
        }
        if (!std.mem.startsWith(u8, line, "//!")) break;
        if (wrote) try result.writer.writeByte('\n');
        try result.writer.writeAll(std.mem.trimStart(u8, line[3..], " "));
        wrote = true;
    }
    if (!wrote) {
        result.deinit();
        return null;
    }
    return try result.toOwnedSlice();
}

fn scanSourceWithDiagnostics(
    allocator: std.mem.Allocator,
    source: []const u8,
    functions: []semantic.SemanticFn,
    path: []const u8,
    diagnostics: *std.Io.Writer,
) !bool {
    const parse_error_count = try scanSource(allocator, source, functions);
    if (parse_error_count != 0) {
        try diagnostics.print("error: zigo could not enrich names from {s}: {d} Zig parse error(s)\n", .{ path, parse_error_count });
        return true;
    }
    return false;
}

fn writeReadError(writer: *std.Io.Writer, path: []const u8, err: anyerror) !void {
    try writer.print("error: zigo could not read enrichment source {s}: {s}\n", .{ path, @errorName(err) });
}

fn scanSource(allocator: std.mem.Allocator, source: []const u8, functions: []semantic.SemanticFn) !usize {
    const terminated = try allocator.dupeZ(u8, source);
    defer allocator.free(terminated);
    var tree = try std.zig.Ast.parse(allocator, terminated, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) return tree.errors.len;

    const visited = try allocator.alloc(bool, tree.nodes.len);
    defer allocator.free(visited);
    @memset(visited, false);
    const matched = try allocator.alloc(bool, functions.len);
    defer allocator.free(matched);
    @memset(matched, false);

    try scanMembers(allocator, tree, tree.rootDecls(), null, functions, visited, matched);

    // Generic type factories contain methods in anonymous containers rather
    // than a named source-level owner. Give those remaining declarations a
    // signature-based fallback after all owner-qualified matches are fixed.
    for (0..tree.nodes.len) |raw_index| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(raw_index);
        if (visited[raw_index]) continue;
        var buffer: [1]std.zig.Ast.Node.Index = undefined;
        const proto = tree.fullFnProto(&buffer, node) orelse continue;
        const doc = try declDocAlloc(allocator, tree, proto.firstToken());
        defer if (doc) |value| allocator.free(value);
        try enrichMatches(allocator, tree, proto, null, functions, matched, false, doc);
    }
    return 0;
}

fn scanMembers(
    allocator: std.mem.Allocator,
    tree: std.zig.Ast,
    members: []const std.zig.Ast.Node.Index,
    owner: ?[]const u8,
    functions: []semantic.SemanticFn,
    visited: []bool,
    matched: []bool,
) !void {
    // A run of declarations written with no blank line between them reads as
    // one documented group in Zig source, so an undocumented member of the run
    // inherits the doc the run opened with.
    var group_doc: ?[]const u8 = null;
    defer if (group_doc) |doc| allocator.free(doc);
    var group_end: ?usize = null;
    for (members) |node| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        if (tree.fullFnProto(&fn_buffer, node)) |proto| {
            visited[@intFromEnum(node)] = true;
            const first_token = proto.firstToken();
            const own_doc = try declDocAlloc(allocator, tree, first_token);
            const adjacent = if (group_end) |end|
                !hasBlankLine(tree.source[end..tree.tokenStart(first_token)])
            else
                false;
            if (own_doc) |doc| {
                if (group_doc) |previous| allocator.free(previous);
                group_doc = doc;
            } else if (!adjacent) {
                if (group_doc) |previous| allocator.free(previous);
                group_doc = null;
            }
            try enrichMatches(allocator, tree, proto, owner, functions, matched, true, group_doc);
            group_end = declarationEnd(tree, node);
            continue;
        }
        if (group_doc) |previous| allocator.free(previous);
        group_doc = null;
        group_end = null;

        const variable = tree.fullVarDecl(node) orelse continue;
        const init_node = variable.ast.init_node.unwrap() orelse continue;
        var container_buffer: [2]std.zig.Ast.Node.Index = undefined;
        const container = tree.fullContainerDecl(&container_buffer, init_node) orelse continue;
        const declaration_name = tree.tokenSlice(variable.ast.mut_token + 1);
        // A namespace inside a namespace owns its functions under the joined
        // lexical path, which is exactly what the binding recorded as the
        // reflected owner, so the two still compare as equal.
        const nested_owner = if (owner) |parent|
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ parent, declaration_name })
        else
            try allocator.dupe(u8, declaration_name);
        defer allocator.free(nested_owner);
        try scanMembers(allocator, tree, container.ast.members, nested_owner, functions, visited, matched);
    }
}

fn enrichMatches(
    allocator: std.mem.Allocator,
    tree: std.zig.Ast,
    proto: std.zig.Ast.full.FnProto,
    source_owner: ?[]const u8,
    functions: []semantic.SemanticFn,
    matched: []bool,
    qualified: bool,
    doc: ?[]const u8,
) !void {
    const name_token = proto.name_token orelse return;
    const declaration_name = tree.tokenSlice(name_token);
    var iterator = proto.iterate(&tree);
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(allocator);
    while (iterator.next()) |parameter| {
        if (parameter.name_token) |token| try names.append(allocator, tree.tokenSlice(token));
    }

    for (functions, 0..) |*function, index| {
        if (matched[index] or !std.mem.eql(u8, function.name, declaration_name)) continue;
        if (qualified and !optionalStringEqual(functionOwner(function.*), source_owner)) continue;
        const receiver_count: usize = @intFromBool(function.receiver != null);
        if (names.items.len != function.params.len + receiver_count) continue;

        var needs_names = false;
        for (function.params) |parameter| if (parameter.name_source == .fallback) {
            needs_names = true;
            break;
        };
        if (needs_names) {
            const updated_params = try allocator.dupe(semantic.Parameter, function.params);
            for (updated_params, 0..) |*parameter, parameter_index| {
                if (parameter.name_source != .fallback) continue;
                parameter.name = try allocator.dupe(u8, names.items[parameter_index + receiver_count]);
                parameter.name_source = .ast;
            }
            function.params = updated_params;
        }
        if (function.doc == null) {
            if (doc) |value| function.doc = try allocator.dupe(u8, value);
        }
        matched[index] = true;
    }
}

fn functionOwner(function: semantic.SemanticFn) ?[]const u8 {
    return function.receiver orelse function.namespace;
}

fn optionalStringEqual(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if (lhs == null or rhs == null) return lhs == null and rhs == null;
    return std.mem.eql(u8, lhs.?, rhs.?);
}

/// The doc a declaration carries in its own right: the `///` block Zig
/// attaches to it, or failing that the ordinary `//` lines written directly
/// above it with no blank line in between. Plain comments are not tokens, so
/// the second form has to be read back out of the source bytes.
fn declDocAlloc(allocator: std.mem.Allocator, tree: std.zig.Ast, first_token: std.zig.Ast.TokenIndex) !?[]const u8 {
    if (try docCommentAlloc(allocator, tree, first_token)) |doc| return doc;
    return groupCommentAlloc(allocator, tree, first_token);
}

fn docCommentAlloc(allocator: std.mem.Allocator, tree: std.zig.Ast, first_token: std.zig.Ast.TokenIndex) !?[]const u8 {
    if (first_token == 0) return null;
    var token = first_token;
    var count: usize = 0;
    while (token > 0 and tree.tokenTag(token - 1) == .doc_comment) : (token -= 1) count += 1;
    if (count == 0) return null;
    var result: std.Io.Writer.Allocating = .init(allocator);
    errdefer result.deinit();
    for (token..first_token) |comment_token| {
        if (comment_token != token) try result.writer.writeByte('\n');
        const raw = tree.tokenSlice(@intCast(comment_token));
        try result.writer.writeAll(std.mem.trimStart(u8, raw[3..], " "));
    }
    return try result.toOwnedSlice();
}

fn groupCommentAlloc(allocator: std.mem.Allocator, tree: std.zig.Ast, first_token: std.zig.Ast.TokenIndex) !?[]const u8 {
    const start = if (first_token == 0) 0 else tokenEnd(tree, first_token - 1);
    const region = tree.source[start..tree.tokenStart(first_token)];
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);
    var iterator = std.mem.splitScalar(u8, region, '\n');
    while (iterator.next()) |line| try lines.append(allocator, std.mem.trim(u8, line, " \t\r"));
    // The last split is the indentation on the declaration's own line, and the
    // first is whatever trailed the previous declaration; neither is a comment.
    if (lines.items.len < 2) return null;
    var index = lines.items.len - 1;
    while (index > 0 and isGroupComment(lines.items[index - 1])) index -= 1;
    if (index == lines.items.len - 1) return null;
    var result: std.Io.Writer.Allocating = .init(allocator);
    errdefer result.deinit();
    for (lines.items[index .. lines.items.len - 1], 0..) |line, offset| {
        if (offset != 0) try result.writer.writeByte('\n');
        try result.writer.writeAll(std.mem.trimStart(u8, line[2..], " "));
    }
    return try result.toOwnedSlice();
}

/// `///` is a token the parser already handed us, `////` is a plain separator
/// rule and `//!` documents the container, so only bare `//` lines count here.
fn isGroupComment(line: []const u8) bool {
    if (!std.mem.startsWith(u8, line, "//")) return false;
    if (std.mem.startsWith(u8, line, "///")) return false;
    if (std.mem.startsWith(u8, line, "//!")) return false;
    return true;
}

fn hasBlankLine(gap: []const u8) bool {
    var newlines: usize = 0;
    for (gap) |character| switch (character) {
        '\n' => {
            newlines += 1;
            if (newlines > 1) return true;
        },
        ' ', '\t', '\r' => {},
        else => newlines = 0,
    };
    return false;
}

fn tokenEnd(tree: std.zig.Ast, token: std.zig.Ast.TokenIndex) usize {
    return tree.tokenStart(token) + tree.tokenSlice(token).len;
}

fn declarationEnd(tree: std.zig.Ast, node: std.zig.Ast.Node.Index) usize {
    return tokenEnd(tree, tree.lastToken(node));
}

test "AST names and docs enrich only fallback metadata" {
    const source =
        \\/// Adds two values.
        \\pub fn add(left: i32, right: i32) i32 { return left + right; }
    ;
    var document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "add",
            .params = &.{
                .{ .name = "p0", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                .{ .name = "chosen", .name_source = .sidecar, .type = .{ .int = .{ .bits = 32, .signed = true } } },
            },
            .@"return" = .{ .int = .{ .bits = 32, .signed = true } },
            .symbol = "zg_add",
        }},
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const functions = try std.testing.allocator.dupe(semantic.SemanticFn, document.functions);
    defer std.testing.allocator.free(functions);
    try std.testing.expectEqual(@as(usize, 0), try scanSource(std.testing.allocator, source, functions));
    document.functions = functions;
    const ast_name = document.functions[0].params[0].name;
    defer std.testing.allocator.free(document.functions[0].params);
    defer std.testing.allocator.free(ast_name);
    defer std.testing.allocator.free(document.functions[0].doc.?);
    try std.testing.expectEqual(.ast, document.functions[0].params[0].name_source);
    try std.testing.expectEqualStrings("left", document.functions[0].params[0].name);
    try std.testing.expectEqualStrings("chosen", document.functions[0].params[1].name);
    try std.testing.expectEqualStrings("Adds two values.", document.functions[0].doc.?);
}

test "docs come from `///`, from a plain `//` group, and from the run above" {
    const source =
        \\pub const Flags = struct {
        \\    /// Reports whether the flag is set.
        \\    pub fn isSet(self: *Flags) bool { _ = self; return true; }
        \\    // The selection flag bits shared by the setters below.
        \\    pub fn select(self: *Flags) void { _ = self; }
        \\    pub fn selectSilent(self: *Flags) void { _ = self; }
        \\    pub fn selectLoud(self: *Flags) void { _ = self; }
        \\
        \\    pub fn detached(self: *Flags) void { _ = self; }
        \\};
    ;
    const names = [_][]const u8{ "isSet", "select", "selectSilent", "selectLoud", "detached" };
    var functions: [names.len]semantic.SemanticFn = undefined;
    for (&functions, names) |*function, name| function.* = .{
        .name = name,
        .params = &.{},
        .receiver = "Flags",
        .@"return" = .{ .void = {} },
        .symbol = "zg_flags",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions));
    try std.testing.expectEqualStrings("Reports whether the flag is set.", functions[0].doc.?);
    const group = "The selection flag bits shared by the setters below.";
    try std.testing.expectEqualStrings(group, functions[1].doc.?);
    // The two undocumented setters continue the run, so they share its doc.
    try std.testing.expectEqualStrings(group, functions[2].doc.?);
    try std.testing.expectEqualStrings(group, functions[3].doc.?);
    // The blank line closes the run, so nothing carries past it.
    try std.testing.expect(functions[4].doc == null);
}

test "a multi-line `//` group keeps its lines and ignores `//!` and `////`" {
    const source =
        \\//! Container documentation, not a declaration doc.
        \\
        \\////////////////////////////////////////
        \\// Splits the input.
        \\// The second line stays attached.
        \\pub fn split(value: i32) void { _ = value; }
    ;
    var functions = [_]semantic.SemanticFn{.{
        .name = "split",
        .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_split",
    }};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions));
    try std.testing.expectEqualStrings("Splits the input.\nThe second line stays attached.", functions[0].doc.?);
}

test "AST enrichment distinguishes methods by lexical owner" {
    const source =
        \\pub const Alpha = struct {
        \\    /// Uses an alpha amount.
        \\    pub fn update(self: *Alpha, alpha_amount: i32) void { _ = self; _ = alpha_amount; }
        \\};
        \\pub const Beta = struct {
        \\    /// Uses a beta amount.
        \\    pub fn update(self: *Beta, beta_amount: i32) void { _ = self; _ = beta_amount; }
        \\};
    ;
    var functions = [_]semantic.SemanticFn{
        .{
            .name = "update",
            .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
            .receiver = "Alpha",
            .@"return" = .{ .void = {} },
            .symbol = "zg_alpha_update",
        },
        .{
            .name = "update",
            .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
            .receiver = "Beta",
            .@"return" = .{ .void = {} },
            .symbol = "zg_beta_update",
        },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions));
    try std.testing.expectEqualStrings("alpha_amount", functions[0].params[0].name);
    try std.testing.expectEqualStrings("Uses an alpha amount.", functions[0].doc.?);
    try std.testing.expectEqualStrings("beta_amount", functions[1].params[0].name);
    try std.testing.expectEqualStrings("Uses a beta amount.", functions[1].doc.?);
}

test "AST enrichment applies a generic factory method to every specialization" {
    const source =
        \\pub fn Batch(comptime T: type) type {
        \\    return struct {
        \\        pub fn push(self: *@This(), value: T) void { _ = self; _ = value; }
        \\    };
        \\}
    ;
    var functions = [_]semantic.SemanticFn{
        .{
            .name = "push",
            .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
            .receiver = "IntBatch",
            .@"return" = .{ .void = {} },
            .symbol = "zg_int_batch_push",
        },
        .{
            .name = "push",
            .params = &.{.{ .name = "p0", .type = .{ .float = .{ .bits = 64 } } }},
            .receiver = "FloatBatch",
            .@"return" = .{ .void = {} },
            .symbol = "zg_float_batch_push",
        },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions));
    try std.testing.expectEqualStrings("value", functions[0].params[0].name);
    try std.testing.expectEqualStrings("value", functions[1].params[0].name);
    try std.testing.expectEqual(.ast, functions[0].params[0].name_source);
    try std.testing.expectEqual(.ast, functions[1].params[0].name_source);
}

test "fallback names emit a concise warning" {
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "fallback",
            .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_fallback",
        }},
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try writeWarnings(&output.writer, document);
    try std.testing.expectEqualStrings("warning: zigo has no parameter names for fallback; using p0-style names\n", output.written());
}

test "missing primary binding source is fatal" {
    var document: semantic.Semantic = .{
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var diagnostics: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();
    try std.testing.expectError(error.FileNotFound, apply(
        std.testing.allocator,
        std.testing.io,
        &document,
        ".zig-cache/zigo-missing-bindings.zig",
        null,
        &diagnostics.writer,
    ));
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.written(), "zigo-missing-bindings.zig: FileNotFound") != null);
}

test "auxiliary read and parse failures identify their source paths" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "bindings.zig",
        .data = "const broken = @import(\"broken.zig\");\nconst missing = @import(\"missing.zig\");\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "broken.zig", .data = "pub fn (\n" });
    const bindings_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/bindings.zig", .{temporary.sub_path});
    defer std.testing.allocator.free(bindings_path);

    var document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "fallback",
            .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_fallback",
        }},
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diagnostics: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();
    try std.testing.expectError(error.EnrichmentFailed, apply(arena.allocator(), std.testing.io, &document, bindings_path, null, &diagnostics.writer));

    try std.testing.expect(std.mem.indexOf(u8, diagnostics.written(), "broken.zig: 1 Zig parse error(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.written(), "missing.zig: FileNotFound") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.written(), "root.zig") == null);
    try std.testing.expectEqual(.fallback, document.functions[0].params[0].name_source);
}
