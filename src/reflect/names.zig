const std = @import("std");
const semantic = @import("semantic");

/// Enriches reflection-only IR with syntax-only names and doc comments.
/// This pass deliberately does not inspect or alter any type node.
pub fn apply(
    allocator: std.mem.Allocator,
    io: std.Io,
    document: *semantic.Semantic,
    bindings_path: []const u8,
) !void {
    const functions = try allocator.dupe(semantic.SemanticFn, document.functions);
    const bindings_source = std.Io.Dir.cwd().readFileAlloc(io, bindings_path, allocator, .limited(8 * 1024 * 1024)) catch return;
    try scanSource(allocator, bindings_source, functions);

    const directory = std.fs.path.dirname(bindings_path) orelse ".";
    const root_path = try std.fs.path.join(allocator, &.{ directory, "root.zig" });
    if (!std.mem.eql(u8, root_path, bindings_path)) {
        if (std.Io.Dir.cwd().readFileAlloc(io, root_path, allocator, .limited(8 * 1024 * 1024))) |root_source| {
            try scanSource(allocator, root_source, functions);
        } else |_| {}
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
            try scanSource(allocator, source, functions);
        } else |_| {}
    }
    document.functions = functions;
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

fn scanSource(allocator: std.mem.Allocator, source: []const u8, functions: []semantic.SemanticFn) !void {
    const terminated = try allocator.dupeZ(u8, source);
    var tree = try std.zig.Ast.parse(allocator, terminated, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) return;

    for (0..tree.nodes.len) |raw_index| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(raw_index);
        var buffer: [1]std.zig.Ast.Node.Index = undefined;
        const proto = tree.fullFnProto(&buffer, node) orelse continue;
        const name_token = proto.name_token orelse continue;
        const declaration_name = tree.tokenSlice(name_token);
        for (functions) |*function| {
            if (!std.mem.eql(u8, function.name, declaration_name)) continue;
            var iterator = proto.iterate(&tree);
            var names: std.ArrayList([]const u8) = .empty;
            defer names.deinit(allocator);
            while (iterator.next()) |parameter| {
                if (parameter.name_token) |token| try names.append(allocator, tree.tokenSlice(token));
            }
            const receiver_count: usize = @intFromBool(function.receiver != null);
            if (names.items.len != function.params.len + receiver_count) continue;
            const updated_params = try allocator.dupe(semantic.Parameter, function.params);
            for (updated_params, 0..) |*parameter, index| {
                if (parameter.name_source != .fallback) continue;
                parameter.name = try allocator.dupe(u8, names.items[index + receiver_count]);
                parameter.name_source = .ast;
            }
            function.params = updated_params;
            if (function.doc == null) function.doc = try docCommentAlloc(allocator, tree, proto.firstToken());
            break;
        }
    }
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
    try scanSource(std.testing.allocator, source, functions);
    document.functions = functions;
    defer std.testing.allocator.free(document.functions[0].params[0].name);
    defer std.testing.allocator.free(document.functions[0].params);
    defer std.testing.allocator.free(document.functions[0].doc.?);
    try std.testing.expectEqual(.ast, document.functions[0].params[0].name_source);
    try std.testing.expectEqualStrings("left", document.functions[0].params[0].name);
    try std.testing.expectEqualStrings("chosen", document.functions[0].params[1].name);
    try std.testing.expectEqualStrings("Adds two values.", document.functions[0].doc.?);
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
