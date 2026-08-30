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
        try enrichMatches(allocator, tree, proto, null, functions, matched, false);
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
    for (members) |node| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        if (tree.fullFnProto(&fn_buffer, node)) |proto| {
            visited[@intFromEnum(node)] = true;
            try enrichMatches(allocator, tree, proto, owner, functions, matched, true);
            continue;
        }

        const variable = tree.fullVarDecl(node) orelse continue;
        const init_node = variable.ast.init_node.unwrap() orelse continue;
        var container_buffer: [2]std.zig.Ast.Node.Index = undefined;
        const container = tree.fullContainerDecl(&container_buffer, init_node) orelse continue;
        const declaration_name = tree.tokenSlice(variable.ast.mut_token + 1);
        try scanMembers(allocator, tree, container.ast.members, declaration_name, functions, visited, matched);
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
        if (function.doc == null) function.doc = try docCommentAlloc(allocator, tree, proto.firstToken());
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
