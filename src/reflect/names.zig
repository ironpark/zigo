const std = @import("std");
const semantic = @import("semantic");

/// Walks the `@import("....zig")` references in one source file. Both the
/// enrichment scan and the coverage traversal need the same reference list;
/// they differ only in what they do with it, so the parsing lives here once.
const source_limit: std.Io.Limit = .limited(8 * 1024 * 1024);

const ImportIterator = struct {
    source: []const u8,
    cursor: usize = 0,

    const marker = "@import(\"";

    fn next(self: *ImportIterator) ?[]const u8 {
        while (std.mem.indexOfPos(u8, self.source, self.cursor, marker)) |start| {
            const value_start = start + marker.len;
            const end = std.mem.indexOfScalarPos(u8, self.source, value_start, '"') orelse return null;
            self.cursor = end + 1;
            const referenced = self.source[value_start..end];
            if (std.mem.endsWith(u8, referenced, ".zig")) return referenced;
        }
        return null;
    }
};

/// Enriches reflection-only IR with syntax-only names and doc comments.
/// This pass deliberately does not inspect or alter any type node.
/// The files one enrichment pass has read, so a later pass over the same
/// binding neither reads nor parses any of them again. The root source is
/// kept because the coverage traversal starts from it.
const Scanned = struct {
    paths: std.StringHashMapUnmanaged(void) = .empty,
    root_source: ?[]const u8 = null,

    /// Whether this file has been read already. The key is the resolved path,
    /// not the spelling the import used: the same file is reached as
    /// `lib/a/../b/x.zig` from one directory and `lib/b/x.zig` from another,
    /// and comparing spellings makes each route a new file. In a dependency
    /// graph where files import across directories, that turns the walk from
    /// one pass over N files into one that re-walks every subtree per route.
    fn seen(self: *const Scanned, canonical: []const u8) bool {
        return self.paths.contains(canonical);
    }

    fn record(self: *Scanned, allocator: std.mem.Allocator, canonical: []const u8) !void {
        try self.paths.put(allocator, canonical, {});
    }
};

/// The path with `.` and `..` resolved, which is what identifies a file. The
/// result is absolute, so two spellings of one file collide as they should.
fn canonicalAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.fs.path.resolve(allocator, &.{path}) catch allocator.dupe(u8, path);
}

/// Whether any function still lacks something enrichment could supply. Once
/// every doc, source location and parameter name is filled, no later file can
/// change the document -- enrichment only fills absences -- so the walk stops
/// instead of parsing the rest of a dependency graph.
fn needsEnrichment(functions: []const semantic.SemanticFn) bool {
    for (functions) |function| {
        if (function.doc == null or function.source == null) return true;
        for (function.params) |parameter| {
            if (parameter.name_source == .fallback or parameter.source == null) return true;
        }
    }
    return false;
}

pub fn apply(
    allocator: std.mem.Allocator,
    io: std.Io,
    document: *semantic.Semantic,
    bindings_path: []const u8,
    source_root_path: ?[]const u8,
    dependency_roots: []const []const u8,
    diagnostics: *std.Io.Writer,
) !void {
    var scanned: Scanned = .{};
    defer scanned.paths.deinit(allocator);
    try applyRecording(allocator, io, document, bindings_path, source_root_path, diagnostics, &scanned);
    try applyRootImports(allocator, io, document, bindings_path, source_root_path, diagnostics, &scanned);
    try applyDependencyRoots(allocator, io, document, dependency_roots, diagnostics, &scanned);
}

/// The root modules of everything the bound module imports. A binding whose
/// library is a Zig module of its own reaches that library's declarations only
/// here: neither the bindings file nor the root module names those sources by
/// path, so without this pass they keep `p0`-style names and no doc comments.
fn applyDependencyRoots(
    allocator: std.mem.Allocator,
    io: std.Io,
    document: *semantic.Semantic,
    dependency_roots: []const []const u8,
    diagnostics: *std.Io.Writer,
    scanned: *Scanned,
) !void {
    if (dependency_roots.len == 0) return;
    const functions = try allocator.dupe(semantic.SemanticFn, document.functions);
    var has_errors = false;
    for (dependency_roots) |root_path| {
        // A dependency graph can be thousands of files; there is nothing left
        // to learn from them once every name and doc is in place.
        if (!needsEnrichment(functions)) break;
        const canonical = try canonicalAlloc(allocator, root_path);
        if (scanned.seen(canonical)) continue;
        const source = std.Io.Dir.cwd().readFileAlloc(io, root_path, allocator, source_limit) catch |err| {
            try writeReadError(diagnostics, root_path, err);
            has_errors = true;
            continue;
        };
        try scanned.record(allocator, canonical);
        // A dependency lives outside the binding's tree -- usually in the
        // package cache -- so its own directory, not the bindings directory,
        // is what its recorded paths stay relative to.
        const directory = std.fs.path.dirname(root_path) orelse ".";
        has_errors = try scanSourceWithDiagnostics(allocator, source, functions, try recordedPathAlloc(allocator, directory, root_path), diagnostics) or has_errors;
        has_errors = try scanImportedSources(allocator, io, source, directory, functions, scanned, diagnostics) or has_errors;
    }
    document.functions = functions;
    if (has_errors) return error.EnrichmentFailed;
}

/// The root module may be split across files. `applyRecording` reads the
/// bindings file, its direct imports and `root.zig`; this reads what the root
/// imports in turn, so a declaration's doc comment and parameter names reach
/// the generated code from whichever file it was written in.
fn applyRootImports(
    allocator: std.mem.Allocator,
    io: std.Io,
    document: *semantic.Semantic,
    bindings_path: []const u8,
    source_root_path: ?[]const u8,
    diagnostics: *std.Io.Writer,
    scanned: *Scanned,
) !void {
    // The same fallback `applyRecording` uses: a binding that does not declare
    // its root still has one, next to the bindings file.
    const root_path = source_root_path orelse try std.fs.path.join(
        allocator,
        &.{ std.fs.path.dirname(bindings_path) orelse ".", "root.zig" },
    );
    // A recorded root source means the first pass already read and listed
    // `root_path`; only a root it never opened has to be read here.
    const root_source = scanned.root_source orelse blk: {
        const source = std.Io.Dir.cwd().readFileAlloc(io, root_path, allocator, source_limit) catch |err| switch (err) {
            // The fallback guesses at a root next to the bindings file. A
            // binding whose root is the bindings file itself has none, and
            // that is not an error.
            error.FileNotFound => return,
            else => {
                try writeReadError(diagnostics, root_path, err);
                return err;
            },
        };
        try scanned.record(allocator, try canonicalAlloc(allocator, root_path));
        break :blk source;
    };
    const functions = try allocator.dupe(semantic.SemanticFn, document.functions);
    const has_errors = try scanImportedSources(
        allocator,
        io,
        root_source,
        std.fs.path.dirname(root_path) orelse ".",
        functions,
        scanned,
        diagnostics,
    );
    document.functions = functions;
    if (has_errors) return error.EnrichmentFailed;
}

/// `apply`, then the coverage traversal of everything the root module imports,
/// reading each source file once between the two.
///
/// Coverage catalogs declarations that semantic reflection deliberately
/// omits, including methods declared in `.zig` files imported by the root.
/// The traversal is coverage-only: ordinary semantic enrichment retains its
/// established source set and byte-for-byte output.
pub fn applyWithCoverageImports(
    allocator: std.mem.Allocator,
    io: std.Io,
    document: *semantic.Semantic,
    bindings_path: []const u8,
    source_root_path: ?[]const u8,
    dependency_roots: []const []const u8,
    diagnostics: *std.Io.Writer,
) !void {
    var scanned: Scanned = .{};
    defer scanned.paths.deinit(allocator);
    try applyRecording(allocator, io, document, bindings_path, source_root_path, diagnostics, &scanned);
    try applyRootImports(allocator, io, document, bindings_path, source_root_path, diagnostics, &scanned);
    try applyDependencyRoots(allocator, io, document, dependency_roots, diagnostics, &scanned);
}

fn applyRecording(
    allocator: std.mem.Allocator,
    io: std.Io,
    document: *semantic.Semantic,
    bindings_path: []const u8,
    source_root_path: ?[]const u8,
    diagnostics: *std.Io.Writer,
    scanned: *Scanned,
) !void {
    const bindings_source = std.Io.Dir.cwd().readFileAlloc(io, bindings_path, allocator, source_limit) catch |err| {
        try writeReadError(diagnostics, bindings_path, err);
        return err;
    };
    try scanned.record(allocator, try canonicalAlloc(allocator, bindings_path));
    const functions = try allocator.dupe(semantic.SemanticFn, document.functions);
    const directory = std.fs.path.dirname(bindings_path) orelse ".";
    var has_errors = try scanSourceWithDiagnostics(allocator, bindings_source, functions, try recordedPathAlloc(allocator, directory, bindings_path), diagnostics);

    // The bindings file is the one file the binding's author owns, so its
    // `//!` speaks to Go readers. The root module's `//!` is only reached when
    // the bindings file has none -- for a library someone else wrote, that
    // text addresses Zig users and the author is expected to say something
    // better in `bindings.zig`.
    if (document.doc == null) document.doc = try containerDocAlloc(allocator, bindings_source);

    const root_path = source_root_path orelse try std.fs.path.join(allocator, &.{ directory, "root.zig" });
    if (std.mem.eql(u8, root_path, bindings_path)) {
        scanned.root_source = bindings_source;
    } else {
        if (std.Io.Dir.cwd().readFileAlloc(io, root_path, allocator, source_limit)) |root_source| {
            scanned.root_source = root_source;
            try scanned.record(allocator, try canonicalAlloc(allocator, root_path));
            if (document.doc == null) document.doc = try containerDocAlloc(allocator, root_source);
            has_errors = try scanSourceWithDiagnostics(allocator, root_source, functions, try recordedPathAlloc(allocator, directory, root_path), diagnostics) or has_errors;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => {
                try writeReadError(diagnostics, root_path, err);
                has_errors = true;
            },
        }
    }

    // Enrichment deliberately scans only the bindings file's direct imports,
    // and records them under their bindings-relative path.
    var imports: ImportIterator = .{ .source = bindings_source };
    while (imports.next()) |referenced| {
        const path = try std.fs.path.join(allocator, &.{ directory, referenced });
        if (std.Io.Dir.cwd().readFileAlloc(io, path, allocator, source_limit)) |source| {
            try scanned.record(allocator, try canonicalAlloc(allocator, path));
            has_errors = try scanSourceWithDiagnostics(allocator, source, functions, try recordedPathAlloc(allocator, directory, path), diagnostics) or has_errors;
        } else |err| {
            try writeReadError(diagnostics, path, err);
            has_errors = true;
        }
    }
    document.functions = functions;
    if (has_errors) return error.EnrichmentFailed;
}

fn scanImportedSources(
    allocator: std.mem.Allocator,
    io: std.Io,
    source: []const u8,
    directory: []const u8,
    functions: []semantic.SemanticFn,
    scanned: *Scanned,
    diagnostics: *std.Io.Writer,
) !bool {
    return scanImportedSourcesFrom(allocator, io, source, directory, directory, functions, scanned, diagnostics);
}

/// `root` is the directory every recorded path is written relative to, so a
/// split root module records `stream.zig` rather than an absolute path and the
/// document stays the same on every machine. `directory` is where this
/// source's own imports resolve from, which differs once the walk descends.
fn scanImportedSourcesFrom(
    allocator: std.mem.Allocator,
    io: std.Io,
    source: []const u8,
    directory: []const u8,
    root: []const u8,
    functions: []semantic.SemanticFn,
    scanned: *Scanned,
    diagnostics: *std.Io.Writer,
) !bool {
    var has_errors = false;
    var imports: ImportIterator = .{ .source = source };
    while (imports.next()) |referenced| {
        if (!needsEnrichment(functions)) return has_errors;
        const path = try std.fs.path.join(allocator, &.{ directory, referenced });
        const canonical = try canonicalAlloc(allocator, path);
        if (scanned.seen(canonical)) continue;
        try scanned.record(allocator, canonical);
        if (std.Io.Dir.cwd().readFileAlloc(io, path, allocator, source_limit)) |imported| {
            // Recorded from the resolved path, so a file reached through
            // `../` is written the same way as one reached directly.
            const recorded = try recordedPathAlloc(allocator, try canonicalAlloc(allocator, root), canonical);
            has_errors = try scanSourceWithDiagnostics(allocator, imported, functions, recorded, diagnostics) or has_errors;
            has_errors = try scanImportedSourcesFrom(
                allocator,
                io,
                imported,
                std.fs.path.dirname(path) orelse ".",
                root,
                functions,
                scanned,
                diagnostics,
            ) or has_errors;
        } else |err| {
            try writeReadError(diagnostics, path, err);
            has_errors = true;
        }
    }
    return has_errors;
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

/// The `//!` block at the top of a Zig file, joined into one paragraph run.
/// `apply` reads it from the bindings file first and from the library's root
/// module only as a fallback.
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
    const parse_error_count = try scanSource(allocator, source, functions, path);
    if (parse_error_count != 0) {
        try diagnostics.print("error: zigo could not enrich names from {s}: {d} Zig parse error(s)\n", .{ path, parse_error_count });
        return true;
    }
    return false;
}

/// The path recorded in `semantic.json` and shown in diagnostics. It is
/// relative to the bindings file's directory with `/` separators, so the
/// generated metadata does not depend on where the generator was invoked or
/// on the host's path separator -- CI regenerates every example on Linux and
/// Windows and compares bytes.
fn recordedPathAlloc(allocator: std.mem.Allocator, directory: []const u8, path: []const u8) ![]const u8 {
    var relative = path;
    if (std.mem.startsWith(u8, path, directory)) {
        const rest = path[directory.len..];
        if (rest.len > 0 and (rest[0] == '/' or rest[0] == '\\')) relative = rest[1..];
    }
    const recorded = try allocator.dupe(u8, relative);
    std.mem.replaceScalar(u8, recorded, '\\', '/');
    return recorded;
}

fn writeReadError(writer: *std.Io.Writer, path: []const u8, err: anyerror) !void {
    try writer.print("error: zigo could not read enrichment source {s}: {s}\n", .{ path, @errorName(err) });
}

fn scanSource(allocator: std.mem.Allocator, source: []const u8, functions: []semantic.SemanticFn, path: []const u8) !usize {
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

    // Every container this file spells out by name. The unqualified fallback
    // below consults it, so a declaration in an anonymous container is never
    // handed to a function whose owner this very file declares elsewhere.
    var owners: std.ArrayList([]const u8) = .empty;
    defer {
        for (owners.items) |owner| allocator.free(owner);
        owners.deinit(allocator);
    }

    try scanMembers(allocator, tree, tree.rootDecls(), null, functions, visited, matched, path, &owners);

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
        try enrichMatches(allocator, tree, proto, null, functions, matched, false, doc, path, owners.items);
    }
    return 0;
}

/// The declaration a binding named, which is not always the name Go sees: a
/// `.name` rename or a receiver group's `strip_prefix` renames the Go surface
/// while `zig_path` keeps spelling the Zig declaration out. Enrichment has to
/// match the latter, or two unrelated declarations that happen to share one Go
/// name trade parameter names with each other.
const Declaration = struct {
    name: []const u8,
    owner: ?[]const u8,
};

fn declarationOf(function: semantic.SemanticFn) Declaration {
    if (function.zig_path) |path| {
        // `zig_path` is the lexical path inside the bound module, so whatever
        // precedes the last segment is the container the declaration sits in
        // and a bare segment means the module root. Neither has to agree with
        // the receiver or namespace Go groups the function under.
        if (std.mem.lastIndexOfScalar(u8, path, '.')) |index|
            return .{ .name = path[index + 1 ..], .owner = path[0..index] };
        return .{ .name = path, .owner = null };
    }
    return .{ .name = function.name, .owner = functionOwner(function) };
}

fn scanMembers(
    allocator: std.mem.Allocator,
    tree: std.zig.Ast,
    members: []const std.zig.Ast.Node.Index,
    owner: ?[]const u8,
    functions: []semantic.SemanticFn,
    visited: []bool,
    matched: []bool,
    path: []const u8,
    owners: *std.ArrayList([]const u8),
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
            try enrichMatches(allocator, tree, proto, owner, functions, matched, true, group_doc, path, &.{});
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
        try owners.append(allocator, try allocator.dupe(u8, nested_owner));
        try scanMembers(allocator, tree, container.ast.members, nested_owner, functions, visited, matched, path, owners);
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
    path: []const u8,
    /// Containers this file declares by name. Only the unqualified pass reads
    /// it; the qualified one already knows the owner it is standing in.
    declared_owners: []const []const u8,
) !void {
    const name_token = proto.name_token orelse return;
    const declaration_name = tree.tokenSlice(name_token);
    var iterator = proto.iterate(&tree);
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(allocator);
    var name_tokens: std.ArrayList(std.zig.Ast.TokenIndex) = .empty;
    defer name_tokens.deinit(allocator);
    while (iterator.next()) |parameter| {
        if (parameter.name_token) |token| {
            try names.append(allocator, tree.tokenSlice(token));
            try name_tokens.append(allocator, token);
        }
    }

    for (functions, 0..) |*function, index| {
        if (matched[index]) continue;
        const declaration = declarationOf(function.*);
        if (!std.mem.eql(u8, declaration.name, declaration_name)) continue;
        if (qualified) {
            if (!semantic.optionalStringEqual(declaration.owner, source_owner)) continue;
        } else if (declaration.owner) |owner| {
            // A declaration in an anonymous container cannot be the one this
            // function names when the same file writes that owner out.
            var contradicted = false;
            for (declared_owners) |declared| {
                if (std.mem.eql(u8, declared, owner)) {
                    contradicted = true;
                    break;
                }
            }
            if (contradicted) continue;
        }
        const receiver_count: usize = @intFromBool(function.receiver != null);
        if (names.items.len != function.params.len + receiver_count) continue;

        var needs_update = false;
        for (function.params) |parameter| if (parameter.name_source == .fallback or parameter.source == null) {
            needs_update = true;
            break;
        };
        if (needs_update) {
            const updated_params = try allocator.dupe(semantic.Parameter, function.params);
            for (updated_params, 0..) |*parameter, parameter_index| {
                if (parameter.name_source == .fallback) {
                    parameter.name = try allocator.dupe(u8, names.items[parameter_index + receiver_count]);
                    parameter.name_source = .ast;
                }
                if (parameter.source == null) {
                    const token = name_tokens.items[parameter_index + receiver_count];
                    const location = tree.tokenLocation(0, token);
                    parameter.source = .{ .line = @intCast(location.line + 1), .column = @intCast(location.column + 1) };
                }
            }
            function.params = updated_params;
        }
        if (function.doc == null) {
            if (doc) |value| function.doc = try allocator.dupe(u8, value);
        }
        if (function.source == null) {
            const location = tree.tokenLocation(0, name_token);
            function.source = .{ .path = try allocator.dupe(u8, path), .line = @intCast(location.line + 1), .column = @intCast(location.column + 1) };
        }
        matched[index] = true;
    }
}

fn functionOwner(function: semantic.SemanticFn) ?[]const u8 {
    return function.receiver orelse function.namespace;
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
    try std.testing.expectEqual(@as(usize, 0), try scanSource(std.testing.allocator, source, functions, "bindings.zig"));
    document.functions = functions;
    const ast_name = document.functions[0].params[0].name;
    defer std.testing.allocator.free(document.functions[0].params);
    defer std.testing.allocator.free(ast_name);
    defer std.testing.allocator.free(document.functions[0].doc.?);
    defer std.testing.allocator.free(document.functions[0].source.?.path);
    try std.testing.expectEqual(.ast, document.functions[0].params[0].name_source);
    try std.testing.expectEqualStrings("left", document.functions[0].params[0].name);
    try std.testing.expectEqualStrings("chosen", document.functions[0].params[1].name);
    try std.testing.expectEqualStrings("Adds two values.", document.functions[0].doc.?);
    try std.testing.expectEqualStrings("bindings.zig", document.functions[0].source.?.path);
    try std.testing.expectEqual(@as(u32, 2), document.functions[0].source.?.line);
    try std.testing.expectEqual(@as(u32, 8), document.functions[0].source.?.column);
    try std.testing.expectEqual(@as(u32, 2), document.functions[0].params[0].source.?.line);
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
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions, "bindings.zig"));
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
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions, "bindings.zig"));
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
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions, "bindings.zig"));
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
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions, "bindings.zig"));
    try std.testing.expectEqualStrings("value", functions[0].params[0].name);
    try std.testing.expectEqualStrings("value", functions[1].params[0].name);
    try std.testing.expectEqual(.ast, functions[0].params[0].name_source);
    try std.testing.expectEqual(.ast, functions[1].params[0].name_source);
}

test "AST enrichment follows the declaration a receiver group renamed" {
    // The shape libghostty-vt hit: a `strip_prefix` group presents
    // `searchFeed` as `Search.feed`, and an unrelated generic `Stream(...)`
    // in another file declares a `feed` of exactly the same arity.
    const stream_source =
        \\pub fn Stream(comptime Handler: type) type {
        \\    return struct {
        \\        /// Feeds raw bytes.
        \\        pub fn feed(self: *@This(), bytes: []const u8) void { _ = self; _ = bytes; }
        \\    };
        \\}
    ;
    const search_source =
        \\/// Feeds one byte to the search.
        \\pub fn searchFeed(search: *Search, byte: u8) void { _ = search; _ = byte; }
    ;
    var functions = [_]semantic.SemanticFn{.{
        .name = "feed",
        .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 8, .signed = false } } }},
        .receiver = "Search",
        .@"return" = .{ .void = {} },
        .symbol = "zg_search_feed",
        .zig_path = "searchFeed",
    }};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), stream_source, &functions, "stream.zig"));
    try std.testing.expectEqual(.fallback, functions[0].params[0].name_source);
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), search_source, &functions, "search.zig"));
    try std.testing.expectEqualStrings("byte", functions[0].params[0].name);
    try std.testing.expectEqualStrings("Feeds one byte to the search.", functions[0].doc.?);
    try std.testing.expectEqualStrings("search.zig", functions[0].source.?.path);
}

test "AST enrichment follows the declaration an explicit `.name` renamed" {
    const source =
        \\pub const Alpha = struct {
        \\    /// Scales the alpha.
        \\    pub fn compute(self: *Alpha, ratio: f64) void { _ = self; _ = ratio; }
        \\};
    ;
    var functions = [_]semantic.SemanticFn{.{
        .name = "Calculate",
        .params = &.{.{ .name = "p0", .type = .{ .float = .{ .bits = 64 } } }},
        .receiver = "Alpha",
        .@"return" = .{ .void = {} },
        .symbol = "zg_alpha_calculate",
        .zig_path = "Alpha.compute",
    }};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions, "bindings.zig"));
    try std.testing.expectEqualStrings("ratio", functions[0].params[0].name);
    try std.testing.expectEqualStrings("Scales the alpha.", functions[0].doc.?);
}

test "the anonymous-container fallback refuses an owner the source contradicts" {
    const source =
        \\pub const Alpha = struct {
        \\    pub fn reset(self: *Alpha) void { _ = self; }
        \\};
        \\pub fn Factory(comptime T: type) type {
        \\    return struct {
        \\        pub fn update(self: *@This(), scale: T) void { _ = self; _ = scale; }
        \\    };
        \\}
    ;
    var functions = [_]semantic.SemanticFn{.{
        .name = "update",
        .params = &.{.{ .name = "p0", .type = .{ .float = .{ .bits = 64 } } }},
        .receiver = "Alpha",
        .@"return" = .{ .void = {} },
        .symbol = "zg_alpha_update",
    }};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), try scanSource(arena.allocator(), source, &functions, "bindings.zig"));
    try std.testing.expectEqual(.fallback, functions[0].params[0].name_source);
    try std.testing.expectEqualStrings("p0", functions[0].params[0].name);
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
        &.{},
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
    try std.testing.expectError(error.EnrichmentFailed, apply(arena.allocator(), std.testing.io, &document, bindings_path, null, &.{}, &diagnostics.writer));

    try std.testing.expect(std.mem.indexOf(u8, diagnostics.written(), "broken.zig: 1 Zig parse error(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.written(), "missing.zig: FileNotFound") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.written(), "root.zig") == null);
    try std.testing.expectEqual(.fallback, document.functions[0].params[0].name_source);
}

test "the coverage traversal parses a source the enrichment pass already read only once" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "bindings.zig", .data = "const shared = @import(\"shared.zig\");\n" });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "root.zig",
        .data = "const shared = @import(\"shared.zig\");\nconst bindings = @import(\"bindings.zig\");\n",
    });
    // A parse error is reported once per parse, which counts the parses.
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "shared.zig", .data = "pub fn (\n" });
    const bindings_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/bindings.zig", .{temporary.sub_path});
    defer std.testing.allocator.free(bindings_path);
    const root_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/root.zig", .{temporary.sub_path});
    defer std.testing.allocator.free(root_path);

    var document: semantic.Semantic = .{ .package = "names", .prefix = "zg", .zig_version = "0.16.0" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diagnostics: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();
    try std.testing.expectError(error.EnrichmentFailed, applyWithCoverageImports(arena.allocator(), std.testing.io, &document, bindings_path, root_path, &.{}, &diagnostics.writer));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, diagnostics.written(), "shared.zig: 1 Zig parse error(s)"));
}

test "a dependency module's sources enrich from its own root" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "bindings.zig", .data = "const x = 0;\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "root.zig", .data = "const library = @import(\"library\");\n" });
    try temporary.dir.createDirPath(std.testing.io, "library");
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "library/main.zig",
        .data = "pub const Search = @import(\"search.zig\").Search;\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "library/search.zig",
        .data =
        \\pub const Search = struct {
        \\    /// Feeds one byte to the search.
        \\    pub fn feed(self: *Search, byte: u8) void { _ = self; _ = byte; }
        \\};
        ,
    });
    const directory = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{temporary.sub_path});
    defer std.testing.allocator.free(directory);
    const bindings_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/bindings.zig", .{directory});
    defer std.testing.allocator.free(bindings_path);
    const root_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/root.zig", .{directory});
    defer std.testing.allocator.free(root_path);
    const dependency_root = try std.fmt.allocPrint(std.testing.allocator, "{s}/library/main.zig", .{directory});
    defer std.testing.allocator.free(dependency_root);

    var functions = [_]semantic.SemanticFn{.{
        .name = "feed",
        .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 8, .signed = false } } }},
        .receiver = "Search",
        .@"return" = .{ .void = {} },
        .symbol = "zg_search_feed",
    }};
    var document: semantic.Semantic = .{
        .functions = &functions,
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diagnostics: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();
    try apply(arena.allocator(), std.testing.io, &document, bindings_path, root_path, &.{dependency_root}, &diagnostics.writer);

    try std.testing.expectEqualStrings("byte", document.functions[0].params[0].name);
    try std.testing.expectEqualStrings("Feeds one byte to the search.", document.functions[0].doc.?);
    // Recorded relative to the dependency's own root, so the document does not
    // carry the package cache path of whichever machine generated it.
    try std.testing.expectEqualStrings("search.zig", document.functions[0].source.?.path);
}

test "the bindings file's own block is the package doc" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "bindings.zig",
        .data = "//! Bindings for the terminal library, written for Go readers.\nconst x = 0;\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "root.zig",
        .data = "//! Library root documentation.\n//! Second line.\npub fn add(a: i32) i32 {\n    return a;\n}\n",
    });
    const bindings_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/bindings.zig", .{temporary.sub_path});
    defer std.testing.allocator.free(bindings_path);

    var document: semantic.Semantic = .{
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diagnostics: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();
    try apply(arena.allocator(), std.testing.io, &document, bindings_path, null, &.{}, &diagnostics.writer);

    // The bindings file is what the binding's author owns; the root module
    // belongs to whoever wrote the library being bound.
    try std.testing.expectEqualStrings("Bindings for the terminal library, written for Go readers.", document.doc.?);
}

test "the root module block is the package doc when the bindings file has none" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "bindings.zig", .data = "const x = 0;\n" });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "root.zig",
        .data = "//! Library root documentation.\n//! Second line.\npub fn add(a: i32) i32 {\n    return a;\n}\n",
    });
    const bindings_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/bindings.zig", .{temporary.sub_path});
    defer std.testing.allocator.free(bindings_path);

    var document: semantic.Semantic = .{
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diagnostics: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();
    try apply(arena.allocator(), std.testing.io, &document, bindings_path, null, &.{}, &diagnostics.writer);

    try std.testing.expectEqualStrings("Library root documentation.\nSecond line.", document.doc.?);
}

test "an explicit package doc wins over both container blocks" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "bindings.zig", .data = "//! Bindings block.\nconst x = 0;\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "root.zig", .data = "//! Library root documentation.\n" });
    const bindings_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/bindings.zig", .{temporary.sub_path});
    defer std.testing.allocator.free(bindings_path);

    var document: semantic.Semantic = .{
        .doc = "Configured package doc.",
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diagnostics: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();
    try apply(arena.allocator(), std.testing.io, &document, bindings_path, null, &.{}, &diagnostics.writer);

    try std.testing.expectEqualStrings("Configured package doc.", document.doc.?);
}

test "no container block anywhere leaves the package doc to the default sentence" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "bindings.zig",
        .data = "const x = 0;\n",
    });
    const bindings_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/bindings.zig", .{temporary.sub_path});
    defer std.testing.allocator.free(bindings_path);

    var document: semantic.Semantic = .{
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diagnostics: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();
    try apply(arena.allocator(), std.testing.io, &document, bindings_path, null, &.{}, &diagnostics.writer);

    try std.testing.expect(document.doc == null);
}

test "recorded source paths are relative to the bindings directory with slash separators" {
    const allocator = std.testing.allocator;
    const cases = [_]struct { directory: []const u8, path: []const u8, expected: []const u8 }{
        .{ .directory = "/home/runner/work/zigo/examples/04-callback/src", .path = "/home/runner/work/zigo/examples/04-callback/src/root.zig", .expected = "root.zig" },
        .{ .directory = "./examples/04-callback/src", .path = "./examples/04-callback/src/sub/extra.zig", .expected = "sub/extra.zig" },
        .{ .directory = "C:\\work\\zigo\\src", .path = "C:\\work\\zigo\\src\\root.zig", .expected = "root.zig" },
        .{ .directory = ".", .path = "bindings.zig", .expected = "bindings.zig" },
        .{ .directory = "/a/src", .path = "/elsewhere/root.zig", .expected = "/elsewhere/root.zig" },
    };
    for (cases) |case| {
        const recorded = try recordedPathAlloc(allocator, case.directory, case.path);
        defer allocator.free(recorded);
        try std.testing.expectEqualStrings(case.expected, recorded);
    }
}

test "a dependency graph that reaches one file by two routes is walked once" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "bindings.zig", .data = "const x = 0;\n" });
    try temporary.dir.createDirPath(std.testing.io, "library/left");
    try temporary.dir.createDirPath(std.testing.io, "library/right");
    // `main` reaches `search.zig` directly and again through `right/echo.zig`,
    // which spells it `../left/search.zig`, and `echo.zig` imports back into
    // `left`. Before the walk resolved paths, each spelling counted as a new
    // file and the cycle re-walked the graph until the process was killed.
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "library/main.zig",
        .data =
        \\pub const Search = @import("left/search.zig").Search;
        \\pub const Echo = @import("right/echo.zig").Echo;
        ,
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "library/left/search.zig",
        .data =
        \\const echo = @import("../right/echo.zig");
        \\pub const Search = struct {
        \\    /// Feeds one byte to the search.
        \\    pub fn feed(self: *Search, byte: u8) void { _ = self; _ = byte; }
        \\};
        ,
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "library/right/echo.zig",
        .data =
        \\const search = @import("../left/search.zig");
        \\pub const Echo = struct {
        \\    /// Repeats one byte.
        \\    pub fn repeat(self: *Echo, count: u8) void { _ = self; _ = count; }
        \\};
        ,
    });
    const directory = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{temporary.sub_path});
    defer std.testing.allocator.free(directory);
    const bindings_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/bindings.zig", .{directory});
    defer std.testing.allocator.free(bindings_path);
    const dependency_root = try std.fmt.allocPrint(std.testing.allocator, "{s}/library/main.zig", .{directory});
    defer std.testing.allocator.free(dependency_root);

    var functions = [_]semantic.SemanticFn{
        .{
            .name = "feed",
            .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 8, .signed = false } } }},
            .receiver = "Search",
            .@"return" = .{ .void = {} },
            .symbol = "zg_search_feed",
        },
        .{
            .name = "repeat",
            .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 8, .signed = false } } }},
            .receiver = "Echo",
            .@"return" = .{ .void = {} },
            .symbol = "zg_echo_repeat",
        },
    };
    var document: semantic.Semantic = .{
        .functions = &functions,
        .package = "names",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diagnostics: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();
    try apply(arena.allocator(), std.testing.io, &document, bindings_path, bindings_path, &.{dependency_root}, &diagnostics.writer);

    try std.testing.expectEqualStrings("byte", document.functions[0].params[0].name);
    try std.testing.expectEqualStrings("count", document.functions[1].params[0].name);
    // Recorded from the resolved path, so the route taken does not show.
    try std.testing.expectEqualStrings("left/search.zig", document.functions[0].source.?.path);
    try std.testing.expectEqualStrings("right/echo.zig", document.functions[1].source.?.path);
}
