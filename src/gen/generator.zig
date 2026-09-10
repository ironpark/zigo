const plugin = @import("plugin");
const output_manifest = @import("output_manifest");
const plugin_hooks = @import("emit/plugin_hooks.zig");
const std = @import("std");
const emit = @import("emit/emit.zig");
const emit_rust = @import("emit_rust/emit.zig");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const errors_lock = @import("errors_lock");
const lower = @import("lower");
const naming = @import("naming");
const semantic = @import("semantic");
const stream_return = @import("stream_return");
const validate = @import("validate/validate.zig");
const targets = @import("targets");

pub const prepareDocument = validate.prepareDocument;

pub const CgoTarget = emit.Options.CgoTarget;
pub const TargetLdflags = emit.Options.TargetLdflags;

pub const Options = struct {
    /// Which output language the public package is written in. The CLI and the
    /// build integration resolve it; every layer below reads it from here, so
    /// adding a language does not touch them. `cgo_targets` below is a build
    /// platform, an unrelated sense of the word.
    output_target: targets.Target = targets.default,
    /// Emit ownership metadata for CLI formatting, publishing and checking.
    write_manifest: bool = false,
    /// Optional failure details. Text is copied into the caller allocator;
    /// use an arena to release the list and its text together.
    diagnostics: ?*std.ArrayList(diagnostic.Diagnostic) = null,
    package: []const u8,
    prefix: []const u8,
    go_module: []const u8,
    cflags_override: ?[]const u8 = null,
    ldflags_override: ?[]const u8 = null,
    extra_ldflags: []const u8 = "",
    ldflags_external: bool = false,
    system_ldflags: []const u8 = "",
    pkg_config_libs: []const u8 = "",
    framework_ldflags: []const u8 = "",
    include_dir: []const u8 = "${SRCDIR}/../../../zig-out/include",
    library_dir: []const u8 = "${SRCDIR}/../../../zig-out/lib",
    header_name: []const u8 = "",
    raw_package_path: []const u8 = "internal/raw",
    raw_package_name: []const u8 = "raw",
    raw_colocated: bool = false,
    shared_lifecycle: bool = false,
    lifecycle_package_path: []const u8 = "internal/lifecycle",
    go_package: []const u8 = "",
    go_package_path: []const u8 = "",
    go_package_doc: []const u8 = "",
    /// Which added plugins run, by name. Null runs every plugin the generator
    /// was built with; naming a subset is how a golden case pins one plugin
    /// out of a binary that holds several.
    plugins: ?[]const []const u8 = null,
    configurations: []const @import("plugin").Configuration = @import("plugins/registry.zig").configurations,
    errors_lock_bytes: ?[]const u8 = null,
    backend: emit.Options.Backend = .cgo,
    link_mode: emit.Options.LinkMode = .static,
    cgo_targets: []const CgoTarget = &.{},
    target_ldflags: []const TargetLdflags = &.{},
    /// Windows constrains the purego callback ABI, so generation rejects a
    /// binding it could only produce a dispatcher that panics for.
    library_stem: []const u8 = "",
    library_search_paths: []const u8 = "",
    library_env_vars: ?[]const u8 = null,
    library_automatic: bool = false,
    library_exported_api: bool = true,
    library_platform_dirs: bool = false,
};

const PreparedFile = struct {
    verbatim: bool = false,
    source_kind: ?plugin.FileKind = null,
    source_directory: ?[]const u8 = null,
    owner: []const u8 = "generator",
    path: []const u8,
    contents: []const u8,
};

pub fn generate(allocator: std.mem.Allocator, io: std.Io, semantic_bytes: []const u8, output: std.Io.Dir, options: Options) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const scratch_allocator = scratch.allocator();

    var parsed = try semantic.Semantic.parse(scratch_allocator, semantic_bytes);
    defer parsed.deinit();
    var facts: plugin.Facts = .{};
    var preparation_issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    const transformed = prepareDocument(scratch_allocator, parsed.value, options.plugins, options.configurations, &facts, &preparation_issues, options.output_target) catch |err| {
        if (options.diagnostics) |issues| for (preparation_issues.items) |issue| try issues.append(allocator, try issue.clone(allocator));
        return err;
    };
    if (preparation_issues.items.len != 0) {
        if (options.diagnostics) |issues| for (preparation_issues.items) |issue| try issues.append(allocator, try issue.clone(allocator));
        return error.InvalidSemantic;
    }
    if (options.backend == .purego) if (validate.puregoCallbackIssue(transformed)) |issue| {
        if (options.diagnostics) |issues| try issues.append(allocator, try issue.clone(allocator));
        return error.InvalidSemantic;
    };
    // Validation judged the Zig surface the document records; everything below
    // works on the expansion, where a stream-returning method has become the
    // `Write`/`Flush`/`Read` operations that carry it. The error-set collection
    // below has to see them: their `WriteFailed`/`ReadFailed` need codes too.
    const document = try stream_return.expand(scratch_allocator, transformed);
    var baseline: ?errors_lock.ErrorsLock = if (options.errors_lock_bytes) |bytes| try errors_lock.ErrorsLock.parse(scratch_allocator, bytes) else null;
    defer if (baseline) |*value| value.deinit(scratch_allocator);
    var lock: errors_lock.ErrorsLock = if (options.errors_lock_bytes) |bytes| try errors_lock.ErrorsLock.parse(scratch_allocator, bytes) else .{};
    defer lock.deinit(scratch_allocator);
    const error_names = try lower.distinctErrorNamesAlloc(scratch_allocator, document);
    defer scratch_allocator.free(error_names);
    try lock.assign(scratch_allocator, error_names);
    if (baseline) |value| try lock.validateAgainst(value);
    const abi_codes = try scratch_allocator.alloc(abi.ErrorCode, lock.codes.items.len);
    for (lock.codes.items, 0..) |entry, index| abi_codes[index] = .{ .code = entry.code, .name = entry.name };
    std.mem.sort(abi.ErrorCode, abi_codes, {}, struct {
        fn lessThan(_: void, lhs: abi.ErrorCode, rhs: abi.ErrorCode) bool {
            return lhs.code < rhs.code;
        }
    }.lessThan);
    const program = try lower.semanticDocumentForBackend(scratch_allocator, document, options.package, options.prefix, abi_codes, switch (options.backend) {
        .cgo => .cgo,
        .purego => .purego,
    });
    var emitter_options: emit.Options = .{
        .target = options.output_target,
        .go_module = options.go_module,
        .cflags_override = options.cflags_override,
        .ldflags_override = options.ldflags_override,
        .extra_ldflags = options.extra_ldflags,
        .ldflags_external = options.ldflags_external,
        .system_ldflags = options.system_ldflags,
        .pkg_config_libs = options.pkg_config_libs,
        .framework_ldflags = options.framework_ldflags,
        .include_dir = options.include_dir,
        .library_dir = options.library_dir,
        .header_name = options.header_name,
        .raw_package_path = options.raw_package_path,
        .raw_package_name = options.raw_package_name,
        .raw_colocated = options.raw_colocated,
        .shared_lifecycle = options.shared_lifecycle or document.packages != null,
        .lifecycle_package_path = options.lifecycle_package_path,
        .go_package = options.go_package,
        .go_package_path = options.go_package_path,
        .go_package_doc = options.go_package_doc,
        .plugins = options.plugins,
        .configurations = options.configurations,
        .facts = &facts,
        .backend = options.backend,
        .link_mode = options.link_mode,
        .cgo_targets = options.cgo_targets,
        .target_ldflags = options.target_ldflags,
        .library_stem = options.library_stem,
        .library_search_paths = options.library_search_paths,
        .library_env_vars = options.library_env_vars,
        .library_automatic = options.library_automatic,
        .library_exported_api = options.library_exported_api,
        .library_platform_dirs = options.library_platform_dirs,
    };
    var analysis_issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    try plugin_hooks.analyze(scratch_allocator, program, emitter_options, &facts, &analysis_issues);
    if (analysis_issues.items.len != 0) {
        if (options.diagnostics) |issues| for (analysis_issues.items) |issue| try issues.append(allocator, try issue.clone(allocator));
        return error.InvalidSemantic;
    }
    var prepared: std.ArrayList(PreparedFile) = .empty;
    defer prepared.deinit(scratch_allocator);
    emitter_options.default_package_path = if (options.go_package_path.len != 0) options.go_package_path else if (options.go_package.len != 0) options.go_package else try naming.snakeAlloc(scratch_allocator, document.package);
    // The one place the output language picks its emitter table. Everything
    // above this line is language-neutral -- the same document, the same
    // error-code lock, the same lowered program -- and everything below is
    // the selected target's own tree. The two trees share
    // `emit.neutral_emitters` and nothing else.
    const backend = backendFor(options.output_target);
    if (backend.unsupportedIssues) |refuse| {
        var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
        try refuse(scratch_allocator, program, &issues);
        if (issues.items.len != 0) {
            if (options.diagnostics) |out| for (issues.items) |issue| try out.append(allocator, try issue.clone(allocator));
            return error.InvalidSemantic;
        }
    }
    try backend.appendTree(.{
        .scratch_allocator = scratch_allocator,
        .prepared = &prepared,
        .program = program,
        .emitter_options = emitter_options,
        .document = document,
    });
    const serialized_lock = try lock.serialize(scratch_allocator);
    try prepared.append(scratch_allocator, .{ .path = "errors.lock.json", .contents = serialized_lock });

    // Reserve metadata before validation so a plugin cannot overwrite it.
    if (options.write_manifest) try prepared.append(scratch_allocator, .{ .path = output_manifest.filename, .contents = "", .verbatim = true });
    if (try outputPathIssue(scratch_allocator, prepared.items, options.output_target)) |issue| {
        if (options.diagnostics) |issues| try issues.append(allocator, try issue.clone(allocator));
        return error.InvalidOutputPath;
    }

    if (options.write_manifest) {
        var files: std.ArrayList(output_manifest.File) = .empty;
        for (prepared.items[0 .. prepared.items.len - 1]) |file| {
            if (!file.verbatim and declaresNothing(file.path, file.contents)) continue;
            try files.append(scratch_allocator, .{ .path = file.path, .kind = if (file.verbatim) .artifact else if (options.output_target.isSource(file.path)) .go else .native });
        }
        prepared.items[prepared.items.len - 1].contents = try std.json.Stringify.valueAlloc(scratch_allocator, output_manifest.Document{ .files = files.items }, .{ .whitespace = .indent_2 });
    }

    // Do not mutate the output tree until parsing, validation, lowering, every
    // emitter, and lock serialization have completed successfully. The commit
    // loop deliberately performs no work with the caller-provided allocator.
    for (prepared.items) |file| {
        // A file the emitter had nothing to put in would reach the user as a
        // package clause and no declarations, indistinguishable from a failed
        // generation. Every path here belongs to this run, so an earlier run's
        // copy is removed rather than left for `zigo check` to call obsolete.
        if (!file.verbatim and declaresNothing(file.path, file.contents)) {
            output.deleteFile(io, file.path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
            continue;
        }
        if (std.fs.path.dirname(file.path)) |directory| try output.createDirPath(io, directory);
        try output.writeFile(io, .{ .sub_path = file.path, .data = file.contents });
    }
}

/// The Go tree: the document-scoped core emitters, then one public package
/// per declared sub-package, then the document-scoped plugin outputs.
///
/// Lifted out of `generate` verbatim when the Rust branch arrived, so that the
/// dispatch above reads as two named alternatives rather than as one function
/// with a language-shaped `if` in the middle of it.
fn appendGoPackages(
    allocator: std.mem.Allocator,
    prepared: *std.ArrayList(PreparedFile),
    program: abi.Program,
    options: emit.Options,
    document: semantic.Semantic,
) !void {
    var emitter_options = options;
    try appendEmitters(allocator, prepared, program, emitter_options, &emit.core_emitters);
    if (document.packages) |packages| {
        emitter_options.active_package = "";
        try appendPublicPackage(allocator, prepared, program, emitter_options);
        const base_path = emitter_options.default_package_path;
        for (packages) |package| {
            var package_options = emitter_options;
            package_options.active_package = package.name;
            package_options.go_package = package.name;
            package_options.go_package_path = if (std.mem.eql(u8, base_path, "."))
                package.path
            else
                try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_path, package.path });
            package_options.go_package_doc = package.doc orelse "";
            try appendPublicPackage(allocator, prepared, program, package_options);
        }
    } else {
        try appendPublicPackage(allocator, prepared, program, emitter_options);
    }
    // Document outputs see the full program once. They never run in the
    // package helper-discovery passes or inherit the last package's options.
    var document_emitters: emit.PublicEmitters = .{ .scope = .document };
    while (document_emitters.next()) |emitter| try appendEmitters(allocator, prepared, program, emitter_options, &.{emitter});
    try appendArtifacts(allocator, prepared, program, emitter_options, .document);
}

/// One row per output language: how its tree is written, and how it refuses a
/// document it cannot render.
///
/// A table rather than a branch, so that a target added to `targets.all`
/// without a row here fails to compile instead of silently emitting Go. The
/// table cannot live on `Target.vtable`: `targets` is a leaf that both `emit`
/// and `emit_rust` import, so pointing it back at their emitter tables would
/// close a build-graph cycle. What `Target` owns is the language's naming and
/// file-shape rules, which need no emitter to answer.
const Backend = struct {
    target_name: []const u8,
    /// Null when the backend renders every document the validator accepts.
    /// Non-null for one whose scope is narrower than the IR: it names what it
    /// cannot render rather than emitting a tree with declarations missing.
    unsupportedIssues: ?*const fn (
        allocator: std.mem.Allocator,
        program: abi.Program,
        issues: *std.ArrayList(diagnostic.Diagnostic),
    ) anyerror!void = null,
    appendTree: *const fn (tree: Tree) anyerror!void,
};

/// What every backend needs to write its tree, so that one signature serves
/// the table and a backend takes only what it reads.
const Tree = struct {
    scratch_allocator: std.mem.Allocator,
    prepared: *std.ArrayList(PreparedFile),
    program: abi.Program,
    emitter_options: emit.Options,
    document: semantic.Semantic,
};

const backends = [_]Backend{
    .{ .target_name = targets.go.target.name, .appendTree = appendGoTree },
    .{
        .target_name = targets.rust.target.name,
        .unsupportedIssues = emit_rust.unsupportedIssues,
        .appendTree = appendRustTree,
    },
};

comptime {
    for (targets.all) |target| {
        var covered = false;
        for (backends) |backend| {
            if (std.mem.eql(u8, backend.target_name, target.name)) covered = true;
        }
        if (!covered) @compileError("target '" ++ target.name ++ "' has no backend row in generator.zig");
    }
}

fn backendFor(target: targets.Target) Backend {
    for (backends) |backend| if (std.mem.eql(u8, backend.target_name, target.name)) return backend;
    // The comptime block above proves every target in `targets.all` has a row,
    // and `Target` values come from there.
    unreachable;
}

fn appendGoTree(tree: Tree) !void {
    return appendGoPackages(tree.scratch_allocator, tree.prepared, tree.program, tree.emitter_options, tree.document);
}

/// The Rust tree: the shared neutral emitters plus the crate's own three
/// files. The refusal that keeps a declaration from being dropped silently
/// happens before this runs, in the backend table's `unsupportedIssues` slot.
fn appendRustTree(tree: Tree) !void {
    try appendEmitters(tree.scratch_allocator, tree.prepared, tree.program, tree.emitter_options, &emit_rust.core_emitters);
    // Plugin artifacts are byte blobs at plugin-supplied paths -- nothing
    // about them is Go-shaped -- and `registry.runs` already gates them on the
    // plugin's `output_targets`. Skipping the call here would drop a plugin's
    // files with no message rather than letting the contract decide.
    try appendArtifacts(tree.scratch_allocator, tree.prepared, tree.program, tree.emitter_options, .document);
}

/// Normalize before writing anything so aliases such as ./x and dir/../x
/// cannot silently replace a different emitter's output. All output paths
/// are portable module-relative paths, including on Windows.
fn normalizeOutputPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0 or path[0] == '/' or path[0] == '\\' or std.mem.indexOfScalar(u8, path, ':') != null or std.mem.indexOfScalar(u8, path, 0) != null)
        return error.InvalidOutputPath;
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(allocator);
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (parts.items.len == 0) return error.InvalidOutputPath;
            _ = parts.pop();
        } else try parts.append(allocator, part);
    }
    if (parts.items.len == 0) return error.InvalidOutputPath;
    return std.mem.join(allocator, "/", parts.items);
}

fn outputPathIssue(allocator: std.mem.Allocator, files: []PreparedFile, target: targets.Target) !?diagnostic.Diagnostic {
    var paths: std.StringHashMapUnmanaged(usize) = .empty;
    defer paths.deinit(allocator);
    for (files, 0..) |*file, index| {
        const normalized = normalizeOutputPath(allocator, file.path) catch |err| switch (err) {
            error.InvalidOutputPath => return .{
                .severity = .@"error",
                .code = "ZIGO059",
                .message = try std.fmt.allocPrint(allocator, "invalid output path `{s}` from {s}", .{ file.path, file.owner }),
                .site = .{ .path = file.path, .declaration = file.owner },
                .hint = "emit a file path inside the output directory; use plugin.publicFilePathAlloc for public files",
            },
            else => return err,
        };
        file.path = normalized;
        // Output trees must also be unambiguous on case-insensitive file
        // systems. Preserve spelling on disk, but compare portable path keys.
        const path_key = try std.ascii.allocLowerString(allocator, normalized);
        const entry = try paths.getOrPut(allocator, path_key);
        if (entry.found_existing) return .{
            .severity = .@"error",
            .code = "ZIGO059",
            .message = try std.fmt.allocPrint(allocator, "output path `{s}` is emitted by both {s} and {s}", .{ normalized, files[entry.value_ptr.*].owner, file.owner }),
            .site = .{ .path = normalized, .declaration = file.owner },
            .hint = "give each emitter a unique public file path; use plugin.publicFilePathAlloc to include the active package",
        };
        if (file.source_kind) |kind| {
            const expected_directory = file.source_directory.?;
            // Normalize a sentinel path so the root directory remains representable.
            const probe = try normalizeOutputPath(allocator, try std.fmt.allocPrint(allocator, "{s}/_{s}", .{ expected_directory, target.source_extension }));
            const directory = std.fs.path.dirname(probe) orelse ".";
            const actual_directory = std.fs.path.dirname(normalized) orelse ".";
            if (!target.fileNameMatchesKind(normalized, kind == .test_file) or
                !std.mem.eql(u8, directory, actual_directory)) return .{
                .severity = .@"error",
                .code = "ZIGO059",
                .message = try std.fmt.allocPrint(allocator, "{s} file `{s}` does not match its package directory or source/test kind", .{ target.display_name, normalized }),
                .site = .{ .path = normalized, .declaration = file.owner },
                .hint = try std.fmt.allocPrint(allocator, "use context.sourceFilePathAlloc and a {s} filename ({s} only for test_file); use artifacts for other formats", .{ target.source_extension, target.test_file_suffix orelse target.source_extension }),
            };
        }
        entry.value_ptr.* = index;
    }
    return null;
}

fn appendEmitters(allocator: std.mem.Allocator, prepared: *std.ArrayList(PreparedFile), program: abi.Program, options: emit.Options, emitters: []const emit.Emitter) !void {
    for (emitters) |emitter| {
        if (emitter.enabled) |enabled| if (!try enabled(allocator, program, options)) continue;
        const relative_path = try emitter.pathAlloc(allocator, program, options);
        var rendered: std.Io.Writer.Allocating = .init(allocator);
        defer rendered.deinit();
        // The writer only allocates, so a failed write is a failed allocation.
        emitter.render(allocator, &rendered.writer, program, options) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
            else => return err,
        };
        // One trailing newline on a framed source file. Asking the target
        // rather than testing `.go` keeps Go's answer identical -- its
        // `isSource` is that same suffix test -- while giving `.rs` the single
        // trailing newline `rustfmt` insists on.
        if (options.target.isSource(relative_path)) {
            rendered.shrinkRetainingCapacity(std.mem.trimEnd(u8, rendered.written(), "\n").len);
            rendered.writer.writeByte('\n') catch return error.OutOfMemory;
        }
        try prepared.append(allocator, .{
            .source_kind = if (emitter.source_file) |file| file.kind else null,
            .source_directory = if (emitter.source_file) |file| blk: {
                const example = try plugin.sourceFilePathAlloc(allocator, program, options, file.package, "_.go");
                break :blk std.fs.path.dirname(example) orelse ".";
            } else null,
            .path = relative_path,
            .contents = try rendered.toOwnedSlice(),
            .owner = try std.fmt.allocPrint(allocator, "{s} (package {s})", .{ emitter.owner, if (options.go_package.len != 0) options.go_package else program.package }),
        });
    }
}

fn appendArtifacts(allocator: std.mem.Allocator, prepared: *std.ArrayList(PreparedFile), program: abi.Program, options: emit.Options, scope: plugin.OutputScope) !void {
    const registry = @import("plugins/registry.zig");
    inline for (registry.plugins, 0..) |registered, index| {
        if (registry.runs(index, options.plugins, options.target)) inline for (registered.artifacts) |artifact| {
            if (artifact.scope == scope) {
                const context: plugin.ArtifactContext = .{ .allocator = allocator, .program = program, .options = options };
                if (artifact.enabled) |predicate| {
                    if (try predicate(context)) try appendArtifact(allocator, prepared, context, registered.name, artifact);
                } else try appendArtifact(allocator, prepared, context, registered.name, artifact);
            }
        };
    }
}

fn appendArtifact(allocator: std.mem.Allocator, prepared: *std.ArrayList(PreparedFile), context: plugin.ArtifactContext, owner: []const u8, artifact: plugin.Artifact) !void {
    const path = try artifact.pathAlloc(context);
    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();
    artifact.render(context, &body.writer) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        else => return err,
    };
    try prepared.append(allocator, .{ .path = path, .contents = try body.toOwnedSlice(), .owner = owner, .verbatim = true });
}

/// The public-package emitters, the built-in files and the plugin files
/// alike. They are walked rather than indexed because how many files the
/// registered plugins add is decided at comptime, not written in a table.
fn appendPublicEmitters(allocator: std.mem.Allocator, prepared: *std.ArrayList(PreparedFile), program: abi.Program, options: emit.Options) !void {
    var emitters = emit.publicEmitters();
    while (emitters.next()) |emitter| try appendEmitters(allocator, prepared, program, options, &.{emitter});
}

fn appendPublicPackage(allocator: std.mem.Allocator, prepared: *std.ArrayList(PreparedFile), full_program: abi.Program, options: emit.Options) !void {
    var functions: std.ArrayList(abi.AbiFn) = .empty;
    for (full_program.functions) |function| if (emit.packageMatches(function.origin.package, options.active_package)) try functions.append(allocator, function);
    var program = full_program;
    program.functions = try functions.toOwnedSlice(allocator);
    // Which helpers the package needs is read off a rendering of it, so the
    // files below are written with that answer in hand.
    var referenced = try emit.references.referencedHelpersAlloc(allocator, program, options);
    defer referenced.deinit(allocator);
    var package_options = options;
    package_options.helpers = &referenced;
    try appendPublicEmitters(allocator, prepared, program, package_options);
    try appendArtifacts(allocator, prepared, program, package_options, .package);
    // The tagged-union files are not in the emitter table: how many there are
    // depends on the bindings, so they are rendered per union.
    for (try emit.unionFilesAlloc(allocator, program, package_options)) |file| {
        const body_len = std.mem.trimEnd(u8, file.contents, "\n").len;
        const contents = try allocator.realloc(file.contents, body_len + 1);
        contents[body_len] = '\n';
        try prepared.append(allocator, .{ .path = file.path, .contents = contents });
    }
}

test "split documents emit package directories shared lifecycle and cross imports" {
    const fixture =
        \\{"functions":[{"name":"useMode","package":"text","ownership":"borrowed","params":[{"direction":"in","name":"mode","name_source":"fallback","retention":"borrowed","type":{"kind":"enum","ref":"Mode"}}],"return":{"kind":"void"},"symbol":"zg_use_mode"}],"ir_version":1,"package":"sample","packages":[{"name":"text","path":"text"}],"prefix":"zg","types":[{"exhaustive":true,"fields":[{"name":"plain","value":0}],"kind":"enum","name":"Mode","tag_type":{"bits":32,"is_usize":false,"kind":"int","signed":false}}],"zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "sample",
        .prefix = "zg",
        .go_module = "example.com/sample",
    });
    const lifecycle = try temporary.dir.readFileAlloc(std.testing.io, "internal/lifecycle/lifecycle_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(lifecycle);
    try std.testing.expect(std.mem.indexOf(u8, lifecycle, "package lifecycle") != null);
    const child = try temporary.dir.readFileAlloc(std.testing.io, "sample/text/text_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(child);
    try std.testing.expect(std.mem.indexOf(u8, child, "zigo_default \"example.com/sample/sample\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, child, "mode zigo_default.Mode") != null);
    _ = try temporary.dir.statFile(std.testing.io, "sample/sample_enums_gen.go", .{});
}

/// The one interface rule that has to see the generated surface: every
/// implementation of a method spells the same Go signature. The CLI renders
/// it as a ZIGO049 diagnostic; `generate` only refuses.
fn analysisIssueForTest(allocator: std.mem.Allocator, document: semantic.Semantic, options: Options) !?diagnostic.Diagnostic {
    if (document.interfaces == null) return null;
    // Signatures do not depend on which code an error got, only on the
    // error set existing, so any assignment will do for this rendering.
    const codes = try lower.provisionalErrorCodesAlloc(allocator, document);
    defer allocator.free(codes);
    const program = try lower.semanticDocumentForBackend(allocator, document, options.package, options.prefix, codes, switch (options.backend) {
        .cgo => .cgo,
        .purego => .purego,
    });
    var facts: plugin.Facts = .{};
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    try plugin_hooks.analyze(allocator, program, .{ .go_module = options.go_module, .configurations = options.configurations, .facts = &facts }, &facts, &issues);
    return if (issues.items.len != 0) issues.items[0] else null;
}

/// True for a Go file that got no further than its own prelude. Every emitter
/// writes the marker and the `package` clause before deciding it has nothing to
/// declare, so this is the shape that decision leaves behind.
fn declaresNothing(path: []const u8, contents: []const u8) bool {
    if (!std.mem.endsWith(u8, path, ".go")) return false;
    if (std.mem.trim(u8, contents, "\r\n\t ").len == 0) return true;
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, contents, "\n"), '\n');
    if (!std.mem.startsWith(u8, lines.first(), "// Code generated by zigo.")) return false;
    // The prelude may carry blank lines and a package doc before the clause.
    var has_package_doc = false;
    const package_line = while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "// Package ")) has_package_doc = true;
        if (line.len == 0 or std.mem.startsWith(u8, line, "//")) continue;
        break line;
    } else return false;
    if (!std.mem.startsWith(u8, package_line, "package ")) return false;
    return !has_package_doc and lines.next() == null;
}

test "the Rust target writes a crate and reuses the neutral outputs verbatim" {
    const fixture =
        \\{"functions":[{"doc":"Adds two integers.","name":"add","params":[{"name":"a","type":{"bits":32,"kind":"int","signed":true}},{"name":"b","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"zg_add"}],"package":"calc","prefix":"zg","zig_version":"0.16.0"}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var go_tree = std.testing.tmpDir(.{ .iterate = true });
    defer go_tree.cleanup();
    var rust_tree = std.testing.tmpDir(.{ .iterate = true });
    defer rust_tree.cleanup();
    try generate(arena.allocator(), std.testing.io, fixture, go_tree.dir, .{
        .package = "calc",
        .prefix = "zg",
        .go_module = "example.com/zigo/calc",
    });
    try generate(arena.allocator(), std.testing.io, fixture, rust_tree.dir, .{
        .output_target = targets.rust.target,
        .package = "calc",
        .prefix = "zg",
        .go_module = "unused-by-rust",
    });
    // The pivot every target shares. If one of these ever differs between two
    // targets for the same document, the seam is in the wrong place: the shim
    // and the header describe the bound library, not the language binding it.
    for ([_][]const u8{ "shim.zig", "panic.c", "zigo_calc.h", "errors.lock.json" }) |name| {
        const from_go = try go_tree.dir.readFileAlloc(std.testing.io, name, arena.allocator(), .limited(1024 * 1024));
        const from_rust = try rust_tree.dir.readFileAlloc(std.testing.io, name, arena.allocator(), .limited(1024 * 1024));
        try std.testing.expectEqualStrings(from_go, from_rust);
    }
    const lib = try rust_tree.dir.readFileAlloc(std.testing.io, "src/lib.rs", arena.allocator(), .limited(64 * 1024));
    try std.testing.expect(std.mem.indexOf(u8, lib, "/// Adds two integers.\npub fn add(a: i32, b: i32) -> i32 {") != null);
    const raw_module = try rust_tree.dir.readFileAlloc(std.testing.io, "src/raw.rs", arena.allocator(), .limited(64 * 1024));
    try std.testing.expect(std.mem.indexOf(u8, raw_module, "pub fn zg_add(a: i32, b: i32) -> i32;") != null);
    // No error codes, so no error module and no `mod error;` naming a file
    // the generator did not write.
    try std.testing.expect(std.mem.indexOf(u8, lib, "mod error;") == null);
    try std.testing.expectError(error.FileNotFound, rust_tree.dir.access(std.testing.io, "src/error.rs", .{}));
    // And no Go anywhere in the tree.
    try std.testing.expectError(error.FileNotFound, rust_tree.dir.access(std.testing.io, "calc/calc_gen.go", .{}));
}

test "a caller-owned buffer is owned rather than copied" {
    const fixture =
        \\{"functions":[{"name":"takeDigits","ownership":"caller","release":"freeDigits","params":[],"return":{"kind":"slice","const":true,"element":{"bits":32,"kind":"int","signed":true}},"symbol":"zg_take_digits"},{"name":"freeDigits","params":[{"name":"values","type":{"kind":"slice","const":true,"element":{"bits":32,"kind":"int","signed":true}}}],"return":{"kind":"void"},"symbol":"zg_free_digits"}],"package":"buffers","prefix":"zg","types":[],"zig_version":"0.16.0"}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tree = std.testing.tmpDir(.{ .iterate = true });
    defer tree.cleanup();
    try generate(arena.allocator(), std.testing.io, fixture, tree.dir, .{
        .output_target = targets.rust.target,
        .package = "buffers",
        .prefix = "zg",
        .go_module = "unused-by-rust",
    });
    const lib = try tree.dir.readFileAlloc(std.testing.io, "src/lib.rs", arena.allocator(), .limited(64 * 1024));
    // The point of the phase: the pointer and the length go straight into a
    // value that owns them, so nothing is copied. Go's binding for the same
    // function copies the payload and releases it before returning, because
    // its collector cannot own a Zig pointer.
    try std.testing.expect(std.mem.indexOf(u8, lib, "pub fn take_digits() -> OwnedSlice<i32> {") != null);
    try std.testing.expect(std.mem.indexOf(u8, lib, "OwnedSlice::from_raw(result_ptr, result_len, raw::zg_free_digits)") != null);
    try std.testing.expect(std.mem.indexOf(u8, lib, "to_vec") == null);
    try std.testing.expect(std.mem.indexOf(u8, lib, "from_utf8_lossy") == null);
    // The release half is not published. `OwnedSlice`'s `Drop` owns it, so a
    // public `free_digits` beside it would be a double free waiting to be
    // written -- Go publishes both and documents the hazard instead.
    try std.testing.expect(std.mem.indexOf(u8, lib, "pub fn free_digits") == null);
    const buffer = try tree.dir.readFileAlloc(std.testing.io, "src/buffer.rs", arena.allocator(), .limited(64 * 1024));
    try std.testing.expect(std.mem.indexOf(u8, buffer, "impl<T> Drop for OwnedSlice<T> {") != null);
    // One generic type, not one per release function.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, buffer, "pub struct OwnedSlice"));
}

test "the Rust target refuses every handle shape it does not own" {
    // The four the plan names, plus the callback shape that used to panic.
    //
    // A callback parameter is not an *ABI* parameter under the cgo convention
    // -- only its `userdata` token crosses -- so plan 188's check on ABI
    // scalars never saw one, and every callback document reached
    // `type_spelling.semanticScalar` and its `unreachable`. The refusal is a
    // whitelist over semantic kinds now, so a shape the backend has never met
    // is refused rather than crashing.
    const cases = [_]struct { fixture: []const u8, names: []const u8 }{
        .{ .fixture =
        \\{"package":"sample","prefix":"zg","types":[{"kind":"enum","name":"Level","exhaustive":true,"fields":[{"name":"low","value":0}],"tag_type":{"bits":8,"kind":"int","signed":false}}],"zig_version":"0.16.0","functions":[{"name":"label","receiver":"Level","receiver_kind":"value","params":[],"return":{"bits":8,"kind":"int","signed":true},"symbol":"zg_level_label"}]}
        , .names = "value receiver" },
        .{ .fixture =
        \\{"package":"sample","prefix":"zg","types":[{"kind":"opaque","name":"Counter"}],"zig_version":"0.16.0","functions":[{"name":"count","receiver":"Counter","params":[],"return":{"bits":8,"kind":"int","signed":true},"symbol":"zg_counter_count"}]}
        , .names = "no bound constructor and destructor pair" },
        .{ .fixture =
        \\{"package":"sample","prefix":"zg","types":[],"zig_version":"0.16.0","functions":[{"name":"filter","params":[{"name":"predicate","type":{"kind":"callback","c_callconv":true,"has_userdata":true,"params":[{"bits":64,"kind":"int","is_usize":true,"signed":false}],"return":{"kind":"bool"}}},{"name":"userdata","type":{"bits":64,"kind":"int","is_usize":true,"signed":false}}],"return":{"kind":"void"},"symbol":"zg_filter"}]}
        , .names = "callback" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var tree = std.testing.tmpDir(.{ .iterate = true });
        defer tree.cleanup();
        var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
        try std.testing.expectError(error.InvalidSemantic, generate(arena.allocator(), std.testing.io, case.fixture, tree.dir, .{
            .output_target = targets.rust.target,
            .diagnostics = &issues,
            .package = "sample",
            .prefix = "zg",
            .go_module = "unused-by-rust",
        }));
        try std.testing.expect(issues.items.len != 0);
        try std.testing.expectEqualStrings("ZIGO060", issues.items[0].code);
        try std.testing.expect(std.mem.indexOf(u8, issues.items[0].message, case.names) != null);
    }
}

test "a handle becomes a struct that frees itself" {
    const fixture =
        \\{"package":"sample","prefix":"zg","types":[{"kind":"opaque","name":"Counter"}],"zig_version":"0.16.0","constructors":[{"deinit":"deinit","init":"create","type":"Counter"}],"functions":[{"name":"create","namespace":"Counter","ownership":"caller","params":[],"return":{"kind":"error_union","error_set":["OutOfMemory"],"payload":{"kind":"opaque_ptr","ref":"Counter","const":false,"nullable":false}},"symbol":"zg_counter_create"},{"name":"bump","receiver":"Counter","params":[],"return":{"bits":64,"kind":"int","signed":true},"symbol":"zg_counter_bump"},{"name":"peek","receiver":"Counter","receiver_by_value":true,"params":[],"return":{"bits":64,"kind":"int","signed":true},"symbol":"zg_counter_peek"},{"name":"deinit","receiver":"Counter","params":[],"return":{"kind":"void"},"symbol":"zg_counter_deinit"}]}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tree = std.testing.tmpDir(.{ .iterate = true });
    defer tree.cleanup();
    try generate(arena.allocator(), std.testing.io, fixture, tree.dir, .{
        .output_target = targets.rust.target,
        .package = "sample",
        .prefix = "zg",
        .go_module = "unused-by-rust",
    });
    const handle = try tree.dir.readFileAlloc(std.testing.io, "src/handle.rs", arena.allocator(), .limited(64 * 1024));
    // The whole point: the destructor is reached through `Drop`, so there is
    // no close call to publish and no closed state to guard.
    try std.testing.expect(std.mem.indexOf(u8, handle, "impl Drop for Counter {") != null);
    try std.testing.expect(std.mem.indexOf(u8, handle, "raw::counter_deinit(self.handle)") != null);
    try std.testing.expect(std.mem.indexOf(u8, handle, "pub fn close") == null);
    try std.testing.expect(std.mem.indexOf(u8, handle, "is_closed") == null);
    // The constructor is `new`, not Go's `NewCounter`: the path already names
    // the type.
    try std.testing.expect(std.mem.indexOf(u8, handle, "pub fn new() -> Result<Self, Error> {") != null);
    // A pointer receiver borrows mutably and a by-value receiver borrows
    // shared -- a distinction Go cannot make, since every Go receiver is
    // `*Counter`.
    try std.testing.expect(std.mem.indexOf(u8, handle, "pub fn bump(&mut self) -> i64 {") != null);
    try std.testing.expect(std.mem.indexOf(u8, handle, "pub fn peek(&self) -> i64 {") != null);
    // `bump` is infallible in Zig but has a status channel, so it reports a
    // native defect by panicking rather than by returning a `Result`.
    try std.testing.expect(std.mem.indexOf(u8, handle, "raw::panic_native(\"bump\", code)") != null);
    // None of the handle's surface leaks into the crate root as a free
    // function; the destructor appears nowhere public at all.
    const lib = try tree.dir.readFileAlloc(std.testing.io, "src/lib.rs", arena.allocator(), .limited(64 * 1024));
    try std.testing.expect(std.mem.indexOf(u8, lib, "mod handle;") != null);
    try std.testing.expect(std.mem.indexOf(u8, lib, "pub fn ") == null);
    try std.testing.expect(std.mem.indexOf(u8, handle, "pub fn deinit") == null);
}

test "the Rust target refuses the shapes it would otherwise flatten silently" {
    // Namespaces and sub-packages must not flatten silently. Scalar enums
    // now have a real mapping, but enum aggregates still need conversion.
    const cases = [_]struct { fixture: []const u8, names: []const u8 }{
        .{ .fixture =
        \\{"package":"sample","prefix":"zg","types":[{"kind":"enum","name":"Level","exhaustive":true,"fields":[{"name":"low","value":0}],"tag_type":{"bits":8,"kind":"int","signed":false}}],"zig_version":"0.16.0","functions":[{"name":"echo","params":[{"name":"value","type":{"kind":"slice","const":true,"element":{"kind":"enum","ref":"Level"}}}],"return":{"kind":"void"},"symbol":"zg_echo"}]}
        , .names = "enum" },
        .{ .fixture =
        \\{"package":"sample","prefix":"zg","types":[],"zig_version":"0.16.0","functions":[{"name":"width","namespace":"unicode","params":[],"return":{"bits":8,"kind":"int","signed":true},"symbol":"zg_unicode_width"}]}
        , .names = "namespaced" },
        .{ .fixture =
        \\{"package":"sample","prefix":"zg","types":[],"zig_version":"0.16.0","functions":[{"name":"width","package":"text","params":[],"return":{"bits":8,"kind":"int","signed":true},"symbol":"zg_width"}],"packages":[{"name":"text","path":"text"}]}
        , .names = "sub-packages" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var tree = std.testing.tmpDir(.{ .iterate = true });
        defer tree.cleanup();
        var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
        try std.testing.expectError(error.InvalidSemantic, generate(arena.allocator(), std.testing.io, case.fixture, tree.dir, .{
            .output_target = targets.rust.target,
            .diagnostics = &issues,
            .package = "sample",
            .prefix = "zg",
            .go_module = "unused-by-rust",
        }));
        try std.testing.expect(issues.items.len != 0);
        try std.testing.expectEqualStrings("ZIGO060", issues.items[0].code);
        try std.testing.expect(std.mem.indexOf(u8, issues.items[0].message, case.names) != null);
        // Refused before the tree is touched, like every other generation
        // failure.
        try std.testing.expectError(error.FileNotFound, tree.dir.access(std.testing.io, "src/lib.rs", .{}));
    }
}

test "a status channel with no declared errors returns its payload and panics" {
    // The crate this used to produce did not compile. A narrow-integer
    // parameter makes `lower.promoteCheckedFunctions` rewrite the return into
    // an error union with an *empty* error set, so that a native panic has a
    // channel; the Rust backend read that as "declares errors", spelled the
    // signature `Result<i8, Error>`, and emitted no `error.rs` to define
    // `Error` -- because no error code exists to define one from.
    const fixture =
        \\{"functions":[{"doc":"Infallible in Zig.","name":"width","params":[{"name":"cp","type":{"bits":21,"kind":"int","signed":false}}],"return":{"bits":8,"kind":"int","signed":true},"symbol":"zg_width"}],"package":"text","prefix":"zg","types":[],"zig_version":"0.16.0"}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tree = std.testing.tmpDir(.{ .iterate = true });
    defer tree.cleanup();
    try generate(arena.allocator(), std.testing.io, fixture, tree.dir, .{
        .output_target = targets.rust.target,
        .package = "text",
        .prefix = "zg",
        .go_module = "unused-by-rust",
    });
    const lib = try tree.dir.readFileAlloc(std.testing.io, "src/lib.rs", arena.allocator(), .limited(64 * 1024));
    // The payload, not a `Result`, and the non-zero code is a panic.
    try std.testing.expect(std.mem.indexOf(u8, lib, "pub fn width(cp: u32) -> i8 {") != null);
    try std.testing.expect(std.mem.indexOf(u8, lib, "raw::panic_native(\"width\", code);") != null);
    // Nothing names an error type, and no module claims to define one.
    try std.testing.expect(std.mem.indexOf(u8, lib, "Error") == null);
    try std.testing.expect(std.mem.indexOf(u8, lib, "mod error;") == null);
    try std.testing.expectError(error.FileNotFound, tree.dir.access(std.testing.io, "src/error.rs", .{}));
}

test "the Rust target refuses a shape it cannot render, naming the declaration" {
    // A NUL-terminated C-string parameter: out of the minimal backend's scope,
    // and the kind of shape that would otherwise produce a crate that compiles
    // and silently omits half the binding.
    const fixture =
        \\{"functions":[{"name":"label","params":[{"name":"text","semantic":"c_string","type":{"kind":"slice","const":true,"sentinel":0,"element":{"bits":8,"kind":"int","signed":false}}}],"return":{"bits":64,"kind":"int","is_usize":true,"signed":false},"symbol":"zg_label"}],"package":"docs","prefix":"zg","types":[],"zig_version":"0.16.0"}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    try std.testing.expectError(error.InvalidSemantic, generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .output_target = targets.rust.target,
        .diagnostics = &issues,
        .package = "docs",
        .prefix = "zg",
        .go_module = "unused-by-rust",
    }));
    try std.testing.expect(issues.items.len != 0);
    try std.testing.expectEqualStrings("ZIGO060", issues.items[0].code);
    try std.testing.expect(std.mem.indexOf(u8, issues.items[0].message, "`label`") != null);
    try std.testing.expect(std.mem.indexOf(u8, issues.items[0].message, "C-string") != null);
    // Nothing was written: the refusal happens before the output tree is
    // touched, the same as every other generation failure.
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "src/lib.rs", .{}));
}

test "bool is lowered to uint8 at the ABI boundary" {
    const fixture =
        \\{"functions":[{"name":"negate","params":[{"name":"p0","type":{"kind":"bool"}}],"return":{"kind":"bool"},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{ .package = "scalar", .prefix = "zg", .go_module = "example.com/zigo/scalar" });
    const header = try temporary.dir.readFileAlloc(std.testing.io, "zigo_scalar.h", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(header);
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "uint8_t zg_negate(uint8_t p0)"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "scalar/scalar_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "func zigoBoolToUint8") == null);
    const runtime_file = try temporary.dir.readFileAlloc(std.testing.io, "scalar/scalar_runtime_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(runtime_file);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        runtime_file,
        1,
        "func zigoBoolToUint8(value bool) uint8 {\n" ++
            "\tif value {\n" ++
            "\t\treturn 1\n" ++
            "\t}\n" ++
            "\treturn 0\n" ++
            "}\n",
    ));
}

test "public Go filename uses the normalized package name" {
    const fixture =
        \\{"functions":[],"package":"HTTPClient","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "HTTPClient",
        .prefix = "zg",
        .go_module = "example.com/http-client",
    });
    try temporary.dir.access(std.testing.io, "http_client/http_client_gen.go", .{});
    try temporary.dir.access(std.testing.io, "internal/raw/raw_gen.go", .{});
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "http_client/generated.go", .{}));
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "internal/raw/cgo.go", .{}));
    // This binding declares no enum, struct, handle, union, error, or runtime
    // helper, so none of the concern-scoped files are written at all.
    for ([_][]const u8{
        "http_client/http_client_enums_gen.go",
        "http_client/http_client_structs_gen.go",
        "http_client/http_client_handles_gen.go",
        "http_client/http_client_runtime_gen.go",
        "http_client/http_client_type_gen.go",
        "http_client/http_client_errors_gen.go",
        "http_client/http_client_helpers_gen.go",
    }) |path| {
        try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, path, .{}));
    }
}

test "raw Go package can use a custom relative path" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"p0","type":{"bits":32,"kind":"int","signed":true}},{"name":"p1","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/zigo/scalar",
        .raw_package_path = "support/ffi",
        .raw_package_name = "ffi",
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "support/ffi/ffi_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "package ffi"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "scalar/scalar_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "import raw \"example.com/zigo/scalar/support/ffi\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "return raw.Add(p0, p1)"));
}

test "public Go package can be published at the module root" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"p0","type":{"bits":32,"kind":"int","signed":true}},{"name":"p1","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/zigo/scalar",
        .go_package_path = ".",
    });
    const public = try temporary.dir.readFileAlloc(std.testing.io, "scalar_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "package scalar"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "\"example.com/zigo/scalar/internal/raw\""));
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "scalar/scalar_gen.go", .{}));
}

test "public Go package can be published at a nested path independent of its name" {
    const fixture =
        \\{"functions":[{"name":"add","params":[],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/zigo/scalar",
        .go_package = "mathapi",
        .go_package_path = "api/v1",
    });
    const public = try temporary.dir.readFileAlloc(std.testing.io, "api/v1/mathapi_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "package mathapi"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "\"example.com/zigo/scalar/internal/raw\""));
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "mathapi/mathapi_gen.go", .{}));
}

test "raw Go bindings colocate at the public package path without public name collisions" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"p0","type":{"bits":32,"kind":"int","signed":true}},{"name":"p1","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/zigo/scalar",
        .raw_package_path = "api/v1",
        .raw_package_name = "scalar",
        .raw_colocated = true,
        .go_package_path = "api/v1",
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "api/v1/scalar_cgo_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "package scalar"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func zigoRawAdd("));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func zigoRawLastErrorMessage()"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "api/v1/scalar_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "import ") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "return zigoRawAdd(p0, p1)"));
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "api/v1/scalar_runtime_gen.go", .{}));
    // The build-tagged loader halves belong to the purego backend alone.
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "api/v1/scalar_cgo_load_posix_gen.go", .{}));
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "api/v1/scalar_cgo_load_windows_gen.go", .{}));
}

test "cgo flag overrides and observed link flags are emitted" {
    const fixture =
        \\{"functions":[],"package":"flags","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
        .cflags_override = "-I/opt/flags/include",
        .ldflags_override = "-L/opt/flags/lib -lflags_zigo",
        .extra_ldflags = "-Wl,--as-needed",
        .system_ldflags = "-lz",
        .framework_ldflags = "-framework CoreFoundation",
        .header_name = "flags_native.h",
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "#cgo CFLAGS: -I/opt/flags/include") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "#cgo LDFLAGS: -L/opt/flags/lib -lflags_zigo -Wl,--as-needed -lz") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "#cgo darwin LDFLAGS: -framework CoreFoundation") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "#include \"flags_native.h\"") != null);
}

test "pkg-config libraries, search paths, and weak frameworks reach the cgo block" {
    const fixture =
        \\{"functions":[],"package":"flags","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
        .library_stem = "flags_zigo",
        .pkg_config_libs = "libcurl zlib",
        .system_ldflags = "-L/opt/flags/lib -lm",
        .framework_ldflags = "-weak_framework Metal",
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(raw);
    // pkg-config comes first so its own -I and -l results join the same block.
    try std.testing.expect(std.mem.indexOf(u8, raw, "#cgo pkg-config: libcurl zlib\n#cgo CFLAGS: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "-L/opt/flags/lib -lm") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "#cgo darwin LDFLAGS: -weak_framework Metal") != null);
}

test "the pkg-config line is omitted when no library asks for it" {
    const fixture =
        \\{"functions":[],"package":"flags","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
        .library_stem = "flags_zigo",
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "pkg-config") == null);
}

test "static cgo links its archive by path and dynamic cgo keeps the search path" {
    const fixture =
        \\{"functions":[],"package":"flags","prefix":"zg","zig_version":"0.16.0"}
    ;
    var static_output = std.testing.tmpDir(.{ .iterate = true });
    defer static_output.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, static_output.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
        .library_stem = "flags_zigo",
        .system_ldflags = "-lz",
    });
    const static_raw = try static_output.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(static_raw);
    // A dynamic artifact of the same name in the install directory must not be
    // able to satisfy this link.
    try std.testing.expect(std.mem.containsAtLeast(u8, static_raw, 1, "#cgo LDFLAGS: ${SRCDIR}/../../../zig-out/lib/libflags_zigo.a -lz"));

    var dynamic_output = std.testing.tmpDir(.{ .iterate = true });
    defer dynamic_output.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, dynamic_output.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
        .library_stem = "flags_zigo",
        .link_mode = .dynamic,
    });
    const dynamic_raw = try dynamic_output.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(dynamic_raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, dynamic_raw, 1, "#cgo LDFLAGS: -L${SRCDIR}/../../../zig-out/lib -lflags_zigo"));

    // Without an explicit stem the package name still derives the artifact.
    var default_output = std.testing.tmpDir(.{ .iterate = true });
    defer default_output.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, default_output.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
    });
    const default_raw = try default_output.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(default_raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, default_raw, 1, "${SRCDIR}/../../../zig-out/lib/libflags_zigo.a"));
}

test "errors enums and slices share one lowered ABI" {
    const fixture =
        \\{
        \\  "functions": [
        \\    {"name":"divide","params":[{"name":"p0","type":{"bits":64,"kind":"float"}},{"name":"p1","type":{"bits":64,"kind":"float"}}],"return":{"error_set":["DivideByZero"],"kind":"error_union","payload":{"bits":64,"kind":"float"}},"symbol":"ignored"},
        \\    {"name":"sum","params":[{"name":"p0","type":{"const":true,"element":{"bits":64,"kind":"float"},"kind":"slice"}}],"return":{"bits":64,"kind":"float"},"symbol":"ignored"},
        \\    {"name":"fill","params":[{"direction":"out","name":"p0","type":{"const":false,"element":{"bits":64,"kind":"float"},"kind":"slice"}}],"return":{"kind":"void"},"symbol":"ignored"},
        \\    {"name":"normalizeFormat","params":[{"name":"p0","type":{"kind":"enum","ref":"Format"}}],"return":{"kind":"enum","ref":"Format"},"symbol":"ignored"}
        \\  ],
        \\  "package":"features",
        \\  "prefix":"zg",
        \\  "types":[{"fields":[{"name":"pcm","value":0},{"name":"flac","value":1}],"kind":"enum","name":"Format","tag_type":{"bits":32,"kind":"int","signed":false}}],
        \\  "zig_version":"0.16.0"
        \\}
    ;
    const lock =
        \\{"ir_version":1,"next_code":2,"codes":{"DivideByZero":1},"reserved":{"0":"OK","-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle"}}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "features",
        .prefix = "zg",
        .go_module = "example.com/features",
        .errors_lock_bytes = lock,
    });
    const header = try temporary.dir.readFileAlloc(std.testing.io, "zigo_features.h", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(header);
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "int32_t zg_divide(double p0, double p1, double * out_result)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "const double * p0_ptr, size_t p0_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "size_t * p0_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "#define ZG_FORMAT_FLAC 1"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "features/features_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "ErrDivideByZero") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "type Format") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Sum(p0 []float64) float64"));
    try std.testing.expect(std.mem.indexOf(u8, public, "func zigoBoolToUint8") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "zigoActiveCallbackHandles") == null);
    const public_types = try temporary.dir.readFileAlloc(std.testing.io, "features/features_enums_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public_types);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type Format"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "func (value Format) String() string"));
    const public_errors = try temporary.dir.readFileAlloc(std.testing.io, "features/features_errors_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public_errors);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "ErrDivideByZero"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "func zigoErrorForCode(operation string, code int32) error"));
    // The error file also converts an unrecognized code, so its imports are a block.
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "\t\"strconv\"\n\n\t\"example.com/features/internal/raw\""));
    const shim = try temporary.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(shim);
    try std.testing.expect(std.mem.containsAtLeast(u8, shim, 1, "p0_ptr: [*c]f64, p0_len: usize, p0_written: *usize"));
    try std.testing.expect(std.mem.containsAtLeast(u8, shim, 1, "p0_written.* = p0_len"));
}

test "a declared callback type names every parameter of its signature once" {
    const fixture =
        \\{
        \\  "functions":[
        \\    {"name":"apply","params":[{"name":"callback","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"ref":"Observer","return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"zg_apply"},
        \\    {"name":"watch","params":[{"name":"observer","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"ref":"Observer","return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"zg_watch"}
        \\  ],
        \\  "package":"observers","prefix":"zg","types":[{"kind":"callback","name":"Observer","zig_path":"*const fn (i32, usize) callconv(.c) i32"}],"zig_version":"0.16.0"
        \\}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "observers",
        .prefix = "zg",
        .go_module = "example.com/observers",
    });
    const public = try temporary.dir.readFileAlloc(std.testing.io, "observers/observers_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Apply(callback Observer) int32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Watch(observer Observer)"));
    try std.testing.expect(std.mem.indexOf(u8, public, "ApplyCallback") == null);
    const public_types = try temporary.dir.readFileAlloc(std.testing.io, "observers/observers_runtime_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public_types);
    // One type and one handle helper, at the first use; the second parameter
    // reuses them.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, public_types, "type Observer func(int32) int32"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, public_types, "func zigoNewObserverHandle(value Observer) zigoCallbackHandle"));
    try std.testing.expect(std.mem.indexOf(u8, public_types, "WatchObserver") == null);
}

test "callbacks use role-specific public types and typed handle helpers" {
    const fixture =
        \\{
        \\  "functions":[
        \\    {"name":"subscribe","params":[{"name":"handler","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"zg_subscribe"},
        \\    {"name":"install","namespace":"Registry","params":[{"name":"handler","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":64,"kind":"int","signed":false},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"zg_registry_install"},
        \\    {"name":"replace","namespace":"Registry","params":[{"name":"handler","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":8,"kind":"int","signed":false},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"zg_registry_replace"}
        \\  ],
        \\  "package":"callbacks","prefix":"zg","zig_version":"0.16.0"
        \\}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "callbacks",
        .prefix = "zg",
        .go_module = "example.com/callbacks",
    });
    const public = try temporary.dir.readFileAlloc(std.testing.io, "callbacks/callbacks_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "type SubscribeHandlerCallback") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Subscribe(handler SubscribeHandlerCallback)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "defer zigoDeleteCallbackHandle(handlerHandle)"));
    const public_types = try temporary.dir.readFileAlloc(std.testing.io, "callbacks/callbacks_runtime_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public_types);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type SubscribeHandlerCallback func(int32) int32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type RegistryInstallHandler func(uint64) int32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type RegistryReplaceHandler func(uint8) int32"));
    // The callback signature types and the handle helpers that wrap them are
    // one concern, so the runtime file carries both.
    const helpers = public_types;
    try std.testing.expect(std.mem.containsAtLeast(u8, helpers, 1, "func zigoNewSubscribeHandlerCallbackHandle(value SubscribeHandlerCallback) zigoCallbackHandle"));
    try std.testing.expect(std.mem.containsAtLeast(u8, helpers, 1, "stored := (func(int32) int32)(value)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, helpers, 1, "stored := (func(uint64) int32)(value)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, helpers, 1, "stored := (func(uint8) int32)(value)"));
    try std.testing.expect(std.mem.indexOf(u8, helpers, "value any") == null);
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "state.Fn.(func(int32) int32)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "state.Fn.(func(uint64) int32)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "state.Fn.(func(uint8) int32)"));
}

test "opt-in cleanup isolates state stops explicitly and keeps owners alive" {
    const fixture =
        \\{
        \\  "constructors":[{"deinit":"deinit","init":"create","type":"Context"}],
        \\  "functions":[
        \\    {"name":"create","namespace":"Context","ownership":"caller","params":[{"name":"callback","retention":"retained","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"error_set":["OutOfMemory"],"kind":"error_union","payload":{"const":false,"kind":"opaque_ptr","nullable":false,"ref":"Context"}},"symbol":"zg_context_create"},
        \\    {"name":"touch","params":[],"receiver":"Context","return":{"kind":"void"},"symbol":"zg_context_touch"},
        \\    {"name":"use","params":[{"name":"context","type":{"const":false,"kind":"opaque_ptr","nullable":false,"ref":"Context"}}],"return":{"kind":"void"},"symbol":"zg_use"},
        \\    {"name":"deinit","params":[],"receiver":"Context","return":{"kind":"void"},"symbol":"zg_context_deinit"}
        \\  ],
        \\  "package":"opaque","prefix":"zg","types":[{"kind":"opaque","name":"Context","zig_path":"root.Context"}],"zig_version":"0.16.0"
        \\}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "opaque",
        .prefix = "zg",
        .go_module = "example.com/opaque",
        .raw_package_path = "opaque",
        .raw_package_name = "opaque",
        .raw_colocated = true,
    });
    const shim = try temporary.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(shim);
    try std.testing.expect(std.mem.containsAtLeast(u8, shim, 1, "target.Context.create("));
    try std.testing.expect(std.mem.containsAtLeast(u8, shim, 1, "target.Context.deinit(self)"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "opaque/opaque_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(public);
    // No thread pin: the panic message travels with the status code, so the
    // public function file has no reason left to import runtime.
    try std.testing.expect(std.mem.indexOf(u8, public, "import \"runtime\"") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func NewContext(callback ContextCallback) (*Context, error)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "zigoRawContextCreate("));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "return zigoNewContext(result, []zigoCallbackHandle{callbackHandle}), nil"));
    // The handle check's `defer x.zigoRelease()` keeps a handle alive for the
    // whole call, so no method defers a KeepAlive on the receiver or a handle
    // parameter.
    try std.testing.expect(std.mem.indexOf(u8, public, "defer runtime.KeepAlive(") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "ptr, err := zigoCheckedPointer(\"Context.Touch receiver\", c)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "contextPtr, err := zigoCheckedPointer(\"Use parameter context\", context)"));
    try std.testing.expect(std.mem.indexOf(u8, public, "c.ptr") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "context.ptr") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "type Context struct") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "zigoRawLastErrorMessage()") == null);
    const public_types = try temporary.dir.readFileAlloc(std.testing.io, "opaque/opaque_handles_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(public_types);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type Context struct"));
    // Nothing hands out a borrowed Context, so no Ref type is generated for it.
    try std.testing.expect(std.mem.indexOf(u8, public_types, "type ContextRef struct") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "cleanup         runtime.Cleanup"));
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        public_types,
        1,
        "type zigoContextCleanupState struct {\n" ++
            "\tptr             unsafe.Pointer\n" ++
            "\tcallbackHandles []zigoCallbackHandle\n" ++
            "}\n",
    ));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "callbackHandles []zigoCallbackHandle"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "runtime.AddCleanup(value, zigoCleanupContext, state)"));
    try std.testing.expect(std.mem.indexOf(u8, public_types, "runtime.AddCleanup(value, zigoCleanupContext, value)") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "func zigoCleanupContext(state zigoContextCleanupState)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "zigoRawContextDeinit(state.ptr)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "zigoDeleteCallbackHandle(handle)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "c.mu.Lock()\n\tif c.closed {\n\t\tc.mu.Unlock()\n\t\treturn nil\n\t}\n\tc.closed = true\n\tc.cleanup.Stop()\n"));
    try std.testing.expect(std.mem.indexOf(u8, public_types, "sync.Once") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "c.cleanup.Stop()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "runtime.KeepAlive(c)"));
    const public_errors = try temporary.dir.readFileAlloc(std.testing.io, "opaque/opaque_errors_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(public_errors);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "zigoRawPanicMessage(code)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "\t\"errors\"\n\t\"fmt\"\n\t\"strconv\"\n"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "type HandleError struct"));
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "opaque/opaque_cgo_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func zigoRawContextCreate("));
}

test "ZIGO003 validation failure leaves the output tree untouched" {
    const fixture =
        \\{"functions":[{"name":"configure","params":[{"name":"config","type":{"kind":"value_struct","ref":"Config"}}],"return":{"kind":"void"},"symbol":"zg_configure"}],"package":"bad","prefix":"zg","types":[{"kind":"value_struct","name":"Config"}],"zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    const existing = [_]struct { path: []const u8, content: []const u8 }{
        .{ .path = "shim.zig", .content = "old shim" },
        .{ .path = "zigo_bad.h", .content = "old header" },
        .{ .path = "internal/raw/raw_gen.go", .content = "old raw" },
        .{ .path = "bad/bad_gen.go", .content = "old public" },
        .{ .path = "bad/bad_type_gen.go", .content = "old public types" },
        .{ .path = "bad/bad_enums_gen.go", .content = "old public enums" },
        .{ .path = "bad/bad_handles_gen.go", .content = "old public handles" },
        .{ .path = "bad/bad_runtime_gen.go", .content = "old public runtime" },
        .{ .path = "bad/bad_errors_gen.go", .content = "old public errors" },
        .{ .path = "bad/bad_helpers_gen.go", .content = "old public helpers" },
        .{ .path = "errors.lock.json", .content = "old lock" },
    };
    for (existing) |file| {
        if (std.fs.path.dirname(file.path)) |directory| try temporary.dir.createDirPath(std.testing.io, directory);
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = file.path, .data = file.content });
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidSemantic, generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "bad",
        .prefix = "zg",
        .go_module = "example.com/bad",
    }));
    for (existing) |file| {
        const actual = try temporary.dir.readFileAlloc(std.testing.io, file.path, std.testing.allocator, .limited(64));
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(file.content, actual);
    }
}

test "ZIGO010 validation failure leaves the output tree untouched" {
    const fixture =
        \\{"functions":[{"name":"normalize","params":[],"return":{"kind":"enum","ref":"MissingMode"},"symbol":"zg_normalize"}],"package":"bad","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "shim.zig", .data = "old shim" });
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidSemantic, generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "bad",
        .prefix = "zg",
        .go_module = "example.com/bad",
    }));
    const actual = try temporary.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("old shim", actual);
}

fn expectAllocationFailureLeavesOutputUntouched(allocator: std.mem.Allocator) !void {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"left","type":{"bits":32,"kind":"int","signed":true}},{"name":"right","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"zg_add"}],"package":"atomic","prefix":"zg","zig_version":"0.16.0"}
    ;
    // `rewritten` is false for a file this binding has nothing to declare in:
    // a successful run removes the earlier copy instead of overwriting it.
    const existing = [_]struct { path: []const u8, content: []const u8, rewritten: bool = true }{
        .{ .path = "shim.zig", .content = "old shim" },
        .{ .path = "zigo_atomic.h", .content = "old header" },
        .{ .path = "internal/raw/raw_gen.go", .content = "old raw" },
        .{ .path = "atomic/atomic_gen.go", .content = "old public" },
        .{ .path = "atomic/atomic_enums_gen.go", .content = "old public enums", .rewritten = false },
        .{ .path = "atomic/atomic_handles_gen.go", .content = "old public handles", .rewritten = false },
        .{ .path = "atomic/atomic_runtime_gen.go", .content = "old public runtime", .rewritten = false },
        .{ .path = "atomic/atomic_errors_gen.go", .content = "old public errors", .rewritten = false },
        .{ .path = "errors.lock.json", .content = "old lock" },
    };
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    for (existing) |file| {
        if (std.fs.path.dirname(file.path)) |directory| try temporary.dir.createDirPath(std.testing.io, directory);
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = file.path, .data = file.content });
    }

    generate(allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "atomic",
        .prefix = "zg",
        .go_module = "example.com/atomic",
    }) catch |err| {
        if (err != error.OutOfMemory) return err;
        for (existing) |file| {
            const actual = try temporary.dir.readFileAlloc(std.testing.io, file.path, std.testing.allocator, .limited(64));
            defer std.testing.allocator.free(actual);
            try std.testing.expectEqualStrings(file.content, actual);
        }
        return err;
    };

    for (existing) |file| {
        if (!file.rewritten) {
            try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, file.path, .{}));
            continue;
        }
        const actual = try temporary.dir.readFileAlloc(std.testing.io, file.path, std.testing.allocator, .limited(64 * 1024));
        defer std.testing.allocator.free(actual);
        try std.testing.expect(!std.mem.eql(u8, file.content, actual));
    }
}

test "allocation failures before commit leave the output tree untouched" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expectAllocationFailureLeavesOutputUntouched, .{});
}

test "invalid errors lock leaves the output tree untouched" {
    const fixture =
        \\{"functions":[],"package":"locked","prefix":"zg","zig_version":"0.16.0"}
    ;
    const invalid_lock =
        \\{"codes":{},"ir_version":1,"next_code":1,"reserved":{"-1":"Changed","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "errors.lock.json", .data = "old output" });

    try std.testing.expectError(error.ReservedMappingChanged, generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "locked",
        .prefix = "zg",
        .go_module = "example.com/locked",
        .errors_lock_bytes = invalid_lock,
    }));
    const actual = try temporary.dir.readFileAlloc(std.testing.io, "errors.lock.json", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("old output", actual);
}

test "generated errors lock produces an identical second generation" {
    const fixture =
        \\{"functions":[{"name":"run","params":[],"return":{"error_set":["Zulu","Alpha"],"kind":"error_union","payload":{"kind":"void"}},"symbol":"zg_run"}],"package":"repeatable","prefix":"zg","zig_version":"0.16.0"}
    ;
    var first = std.testing.tmpDir(.{ .iterate = true });
    defer first.cleanup();
    var second = std.testing.tmpDir(.{ .iterate = true });
    defer second.cleanup();

    try generate(std.testing.allocator, std.testing.io, fixture, first.dir, .{
        .package = "repeatable",
        .prefix = "zg",
        .go_module = "example.com/repeatable",
    });
    const lock = try first.dir.readFileAlloc(std.testing.io, "errors.lock.json", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(lock);
    try generate(std.testing.allocator, std.testing.io, fixture, second.dir, .{
        .package = "repeatable",
        .prefix = "zg",
        .go_module = "example.com/repeatable",
        .errors_lock_bytes = lock,
    });

    const paths = [_][]const u8{
        "errors.lock.json",
        "repeatable/repeatable_gen.go",
        "repeatable/repeatable_errors_gen.go",
        "internal/raw/raw_gen.go",
        "panic.c",
        "shim.zig",
        "zigo_repeatable.h",
    };
    for (paths) |path| {
        const first_bytes = try first.dir.readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(64 * 1024));
        defer std.testing.allocator.free(first_bytes);
        const second_bytes = try second.dir.readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(64 * 1024));
        defer std.testing.allocator.free(second_bytes);
        try std.testing.expectEqualStrings(first_bytes, second_bytes);
    }
}

test "the public package name can be overridden without moving the artifacts" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"a","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"event_queue","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "event_queue",
        .prefix = "zg",
        .go_module = "example.com/eq",
        .go_package = "eventqueue",
    });
    const public = try temporary.dir.readFileAlloc(std.testing.io, "eventqueue/eventqueue_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.startsWith(u8, public, "// Code generated by zigo. DO NOT EDIT.\n\n// Package eventqueue provides Go bindings generated by zigo.\npackage eventqueue\n"));
    // The C header keeps the binding name, so the native artifacts do not move.
    const header = try temporary.dir.readFileAlloc(std.testing.io, "zigo_event_queue.h", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(header);
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "zg_add"));
}

test "Go parameter names escape keywords, generated locals and duplicates" {
    const fixture =
        \\{"functions":[{"name":"pick","params":[{"name":"type","type":{"bits":32,"kind":"int","signed":true}},{"name":"range","type":{"bits":32,"kind":"int","signed":true}},{"name":"code","type":{"bits":32,"kind":"int","signed":true}},{"name":"result","type":{"bits":32,"kind":"int","signed":true}},{"name":"source_len","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"error_set":["Failed"],"kind":"error_union","payload":{"bits":32,"kind":"int","signed":true}},"symbol":"ignored"}],"package":"kw","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "kw",
        .prefix = "zg",
        .go_module = "example.com/kw",
    });
    const public = try temporary.dir.readFileAlloc(std.testing.io, "kw/kw_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(public);
    // Keywords and the locals the generated bodies declare would not compile.
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Pick(type_ int32, range_ int32, code_ int32, result_ int32, sourceLen uint) (int32, error)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "result, code := raw.Pick(type_, range_, code_, result_, sourceLen)"));
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func Pick(type_ int32, range_ int32, code_ int32, result_ int32, sourceLen uint)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "code := int32(C.zg_pick("));
}

test "purego loading policy shapes the generated candidate order" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"a","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var default_output = std.testing.tmpDir(.{ .iterate = true });
    defer default_output.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, default_output.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
    });
    const default_raw = try default_output.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(default_raw);
    // The package-specific name keeps two zigo packages in one process apart.
    try std.testing.expect(std.mem.containsAtLeast(u8, default_raw, 1, "var libraryEnvVars = []string{\"ZIGO_SCALAR_LIBRARY_PATH\", \"ZIGO_LIBRARY_PATH\"}"));
    try std.testing.expect(std.mem.indexOf(u8, default_raw, "librarySearchPaths") == null);
    try std.testing.expect(std.mem.indexOf(u8, default_raw, "path/filepath") == null);

    var configured = std.testing.tmpDir(.{ .iterate = true });
    defer configured.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, configured.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
        .library_search_paths = "${EXECUTABLE_DIR}/../lib:/opt/app/lib",
        .library_env_vars = "APP_LIBRARY",
    });
    const configured_raw = try configured.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(configured_raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "var libraryEnvVars = []string{\"APP_LIBRARY\"}"));
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "var librarySearchPaths = []string{\"${EXECUTABLE_DIR}/../lib\", \"/opt/app/lib\"}"));
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "os.Executable()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "\"path/filepath\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "\"strings\""));

    // An empty environment list removes the lookup and its import.
    var bare = std.testing.tmpDir(.{ .iterate = true });
    defer bare.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, bare.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
        .library_env_vars = "",
    });
    const bare_raw = try bare.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(bare_raw);
    try std.testing.expect(std.mem.indexOf(u8, bare_raw, "libraryEnvVars") == null);
    try std.testing.expect(std.mem.indexOf(u8, bare_raw, "\t\"os\"\n") == null);
}

test "automatic loading and loader visibility shape the generated packages" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"a","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var automatic = std.testing.tmpDir(.{ .iterate = true });
    defer automatic.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, automatic.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
        .library_search_paths = "/opt/app/lib",
        .library_automatic = true,
        .library_exported_api = false,
    });
    const raw = try automatic.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(raw);
    // The first binding call attempts the candidates exactly once.
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func ensureLoaded() {"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "if loadedBindings.Load() != nil || automaticLoadAttempted { return }"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "panic(automaticLoadError)"));
    const public = try automatic.dir.readFileAlloc(std.testing.io, "scalar/scalar_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "LoadLibrary") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "LibraryLoaded") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "DefaultLibraryName") == null);
    // The bound API is unchanged by the policy.
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Add("));

    var explicit = std.testing.tmpDir(.{ .iterate = true });
    defer explicit.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, explicit.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
    });
    const explicit_raw = try explicit.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(explicit_raw);
    try std.testing.expect(std.mem.indexOf(u8, explicit_raw, "ensureLoaded") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, explicit_raw, 1, "call LoadLibrary first"));
    const explicit_public = try explicit.dir.readFileAlloc(std.testing.io, "scalar/scalar_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(explicit_public);
    try std.testing.expect(std.mem.containsAtLeast(u8, explicit_public, 1, "func LoadLibrary(path string) error"));
}

test "purego generation emits an atomic retryable loader and explicit callback ABI" {
    const scalar_fixture =
        \\{"functions":[{"name":"add","params":[{"name":"a","type":{"bits":32,"kind":"int","signed":true}},{"name":"b","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"},{"name":"accept","params":[{"name":"value","type":{"const":true,"kind":"opaque_ptr","nullable":true,"ref":"Handle"}}],"return":{"kind":"void"},"symbol":"ignored"}],"package":"scalar","prefix":"zg","types":[{"kind":"opaque","name":"Handle"}],"zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, scalar_fixture, temporary.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "import \"C\"") == null);
    // A uintptr round-trip is what `go vet` reports as a possible stale pointer.
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "lastError func() unsafe.Pointer"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "unsafe.Add(p, length)"));
    try std.testing.expect(std.mem.indexOf(u8, raw, "unsafe.Pointer(p") == null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "runtime/cgo") == null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "github.com/ebitengine/purego") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "type LibraryError struct") != null);
    // The committed loader must be identical on every supported host, so the
    // platform basename is selected at run time instead of at generation time.
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "map[string]string{\"darwin\": \"libscalar_zigo.dylib\", \"linux\": \"libscalar_zigo.so\", \"windows\": \"scalar_zigo.dll\"}[runtime.GOOS]"));
    try std.testing.expect(std.mem.indexOf(u8, raw, "loadedBindings.Store(&next)") != null);
    // The OS-specific primitives live in the build-tagged companions, so the
    // shared file names them but never names a platform loader.
    try std.testing.expect(std.mem.indexOf(u8, raw, "closeLibrary(handle)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "purego.Dlopen") == null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "purego.Dlsym") == null);
    const posix_loader = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_load_posix_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(posix_loader);
    try std.testing.expect(std.mem.containsAtLeast(u8, posix_loader, 1, "//go:build !windows"));
    try std.testing.expect(std.mem.containsAtLeast(u8, posix_loader, 1, "purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)"));
    const windows_loader = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_load_windows_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(windows_loader);
    try std.testing.expect(std.mem.containsAtLeast(u8, windows_loader, 1, "//go:build windows"));
    try std.testing.expect(std.mem.containsAtLeast(u8, windows_loader, 1, "syscall.LoadLibrary(path)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, windows_loader, 1, "syscall.GetProcAddress(syscall.Handle(handle), symbol)"));
    // Both halves must publish exactly the same internal contract.
    for ([_][]const u8{ "func openLibrary(path string) (uintptr, error)", "func closeLibrary(handle uintptr)", "func resolveSymbol(handle uintptr, symbol string) (uintptr, error)" }) |declaration| {
        try std.testing.expect(std.mem.indexOf(u8, posix_loader, declaration) != null);
        try std.testing.expect(std.mem.indexOf(u8, windows_loader, declaration) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, raw, "different library is already loaded") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "fnAdd func(int32, int32) int32") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "func Accept(value unsafe.Pointer)") != null);

    const callback_fixture =
        \\{"functions":[{"name":"install","params":[{"name":"callback","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"ignored"},{"name":"apply","params":[{"name":"callback","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"ignored"},{"name":"process","params":[],"return":{"error_set":["Failed"],"kind":"error_union","payload":{"bits":64,"is_usize":true,"kind":"int","signed":false}},"symbol":"ignored"}],"package":"callbacks","prefix":"zg","zig_version":"0.16.0"}
    ;
    var rejected = std.testing.tmpDir(.{ .iterate = true });
    defer rejected.cleanup();
    try generate(std.testing.allocator, std.testing.io, callback_fixture, rejected.dir, .{
        .package = "callbacks",
        .prefix = "zg",
        .go_module = "example.com/callbacks",
        .backend = .purego,
    });
    const callback_header = try rejected.dir.readFileAlloc(std.testing.io, "zigo_callbacks.h", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(callback_header);
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_header, 1, "void zg_install_purego_v2(int32_t (*callback)(int32_t, size_t), size_t userdata)"));
    const callback_shim = try rejected.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(callback_shim);
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_shim, 1, "callback: *const fn (i32, usize) callconv(.c) i32, userdata: usize"));
    try std.testing.expect(std.mem.indexOf(u8, callback_shim, "extern fn zg_install_go_callback_callback") == null);
    const callback_raw = try rejected.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(callback_raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_raw, 1, "var callbackPointers [1]uintptr"));
    try std.testing.expect(std.mem.indexOf(u8, callback_raw, "CallbackPointer1") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_raw, 1, "var outResult uintptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_raw, 1, "return uint(outResult), code"));

    var legacy = std.testing.tmpDir(.{ .iterate = true });
    defer legacy.cleanup();
    try generate(std.testing.allocator, std.testing.io, callback_fixture, legacy.dir, .{
        .package = "callbacks",
        .prefix = "zg",
        .go_module = "example.com/callbacks",
        .backend = .cgo,
    });
    const legacy_header = try legacy.dir.readFileAlloc(std.testing.io, "zigo_callbacks.h", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(legacy_header);
    try std.testing.expect(std.mem.containsAtLeast(u8, legacy_header, 1, "void zg_install(size_t userdata)"));
    try std.testing.expect(std.mem.indexOf(u8, legacy_header, "zg_install_purego_v2") == null);
    const legacy_shim = try legacy.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(legacy_shim);
    try std.testing.expect(std.mem.containsAtLeast(u8, legacy_shim, 1, "extern fn zg_install_go_callback_callback"));
}

test "an interface whose implementations disagree on a signature is a ZIGO049" {
    var int_batch: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "IntBatch" } };
    var float_batch: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "FloatBatch" } };
    const document: semantic.Semantic = .{
        .constructors = &.{
            .{ .deinit = "deinit", .init = "create", .type = "IntBatch" },
            .{ .deinit = "deinit", .init = "create", .type = "FloatBatch" },
        },
        .functions = &.{
            .{ .name = "create", .namespace = "IntBatch", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &int_batch } }, .symbol = "zg_int_batch_create" },
            .{ .name = "push", .receiver = "IntBatch", .params = &.{.{ .name = "value", .type = .{ .int = .{ .bits = 32, .signed = true } } }}, .@"return" = .{ .void = {} }, .symbol = "zg_int_batch_push" },
            .{ .name = "deinit", .receiver = "IntBatch", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_int_batch_deinit" },
            .{ .name = "create", .namespace = "FloatBatch", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &float_batch } }, .symbol = "zg_float_batch_create" },
            .{ .name = "push", .receiver = "FloatBatch", .params = &.{.{ .name = "value", .type = .{ .float = .{ .bits = 64 } } }}, .@"return" = .{ .void = {} }, .symbol = "zg_float_batch_push" },
            .{ .name = "deinit", .receiver = "FloatBatch", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_float_batch_deinit" },
        },
        .interfaces = &.{.{ .methods = &.{"push"}, .name = "Batch", .types = &.{ "IntBatch", "FloatBatch" } }},
        .package = "batches",
        .prefix = "zg",
        .types = &.{
            .{ .kind = .@"opaque", .name = "IntBatch" },
            .{ .kind = .@"opaque", .name = "FloatBatch" },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Structural validation lets it through: both types have `push`.
    try validate.semanticDocument(arena.allocator(), document);
    const options: Options = .{ .package = "batches", .prefix = "zg", .go_module = "example.com/batches" };
    const issue = (try analysisIssueForTest(arena.allocator(), document, options)) orelse return error.MissingDiagnostic;
    const rendered = try issue.renderAlloc(arena.allocator());
    try std.testing.expectEqualStrings(
        "error[ZIGO049]: method `push` has signature `Push(int32) error` on `IntBatch` but `Push(float64) error` on `FloatBatch`\n" ++
            "  --> semantic.json (Batch)\n" ++
            "  hint: give every listed type the same Go signature for the method, or drop the method or the type from the interface\n",
        rendered,
    );
    const bytes = try document.serialize(arena.allocator());
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try std.testing.expectError(error.InvalidSemantic, generate(arena.allocator(), std.testing.io, bytes, temporary.dir, options));
}

test "disabled plugin options do not prevent generation but selected and builtin options are validated" {
    const fixture =
        \\{"functions":[],"types":[{"kind":"opaque","name":"Counter","ext":{"TEST":{"mode":"invalid"}}}],"package":"meter","prefix":"zg","zig_version":"0.16.0"}
    ;
    var output = std.testing.tmpDir(.{ .iterate = true });
    defer output.cleanup();
    const options: Options = .{ .package = "meter", .prefix = "zg", .go_module = "example.com/meter", .plugins = &.{} };
    try generate(std.testing.allocator, std.testing.io, fixture, output.dir, options);
    var selected = options;
    selected.plugins = &.{"TEST"};
    try std.testing.expectError(error.InvalidSemantic, generate(std.testing.allocator, std.testing.io, fixture, output.dir, selected));
    selected.plugins = null;
    try std.testing.expectError(error.InvalidSemantic, generate(std.testing.allocator, std.testing.io, fixture, output.dir, selected));
    const builtin_fixture =
        \\{"functions":[],"types":[{"kind":"opaque","name":"Counter","ext":{"MUST":{"unknown":true}}}],"package":"meter","prefix":"zg","zig_version":"0.16.0"}
    ;
    try std.testing.expectError(error.InvalidSemantic, generate(std.testing.allocator, std.testing.io, builtin_fixture, output.dir, options));
}

test "normalized output collisions report both owners before mutation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var files = [_]PreparedFile{
        .{ .path = "input/../shared.go", .contents = "first", .owner = "FIRST (package input)" },
        .{ .path = "./shared.go", .contents = "last", .owner = "SECOND (package root)" },
    };
    const issue = (try outputPathIssue(allocator, &files, targets.default)).?;
    try std.testing.expectEqualStrings("ZIGO059", issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "FIRST") != null);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "SECOND") != null);
    for ([_][]const u8{ "../escape.go", "/absolute.go", "C:\\absolute.go", "a/../../escape.go", "." }) |path|
        try std.testing.expectError(error.InvalidOutputPath, normalizeOutputPath(allocator, path));
    try std.testing.expectEqualStrings("input/file.go", try normalizeOutputPath(allocator, "input\\.\\file.go"));
}

test "output collision leaves existing generated files untouched" {
    const testing_plugin = @import("plugins/testing.zig");
    testing_plugin.enabled = true;
    testing_plugin.path_override = "./shim.zig";
    defer {
        testing_plugin.enabled = false;
        testing_plugin.path_override = null;
    }
    const fixture =
        \\{"functions":[],"package":"collision","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "shim.zig", .data = "keep original" });
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    try std.testing.expectError(error.InvalidOutputPath, generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "collision",
        .prefix = "zg",
        .go_module = "example.com/collision",
        .diagnostics = &issues,
    }));
    try std.testing.expectEqual(@as(usize, 1), issues.items.len);
    try std.testing.expect(std.mem.indexOf(u8, issues.items[0].message, "TEST") != null);
    const actual = try temporary.dir.readFileAlloc(std.testing.io, "shim.zig", arena.allocator(), .limited(64));
    try std.testing.expectEqualStrings("keep original", actual);
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "errors.lock.json", .{}));
}

test "library caller receives all diagnostics without mutating output" {
    const testing_plugin = @import("plugins/testing.zig");
    testing_plugin.validation_enabled = true;
    defer testing_plugin.validation_enabled = false;
    const fixture =
        \\{"package":"sample","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "shim.zig", .data = "unchanged" });
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    try std.testing.expectError(error.InvalidSemantic, generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "sample",
        .prefix = "zg",
        .go_module = "example.com/sample",
        .diagnostics = &issues,
    }));
    try std.testing.expectEqual(@as(usize, 2), issues.items.len);
    try std.testing.expectEqualStrings("TEST002", issues.items[0].code);
    try std.testing.expectEqualStrings("TEST003", issues.items[1].code);
    const actual = try temporary.dir.readFileAlloc(std.testing.io, "shim.zig", arena.allocator(), .limited(64));
    try std.testing.expectEqualStrings("unchanged", actual);
}

test "materialized release identity survives package filtering and declaration order" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const fields = [_]semantic.TypeField{.{ .name = "value", .type = byte }};
    const release: semantic.SemanticFn = .{
        .name = "freeBuffer",
        .params = &.{.{ .name = "buffer", .type = .{ .slice = .{ .@"const" = false, .element = &byte } } }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_free_buffer",
    };
    const snapshot: semantic.SemanticFn = .{
        .name = "snapshot",
        .ownership = .caller,
        .release = "freeBuffer",
        .params = &.{},
        .@"return" = .{ .materialized = .{ .ref = "Node" } },
        .symbol = "zg_snapshot",
    };
    const child: semantic.SemanticFn = .{ .name = "child", .package = "child", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_child" };
    const other: semantic.SemanticFn = .{ .name = "other", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_other" };
    // The original index is either out of bounds or points to Other after filtering.
    for ([_][4]semantic.SemanticFn{ .{ child, snapshot, other, release }, .{ child, release, other, snapshot } }) |functions| {
        for ([_]@FieldType(Options, "backend"){ .cgo, .purego }) |backend| {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const allocator = arena.allocator();
            const document: semantic.Semantic = .{
                .allocator = "std.heap.smp_allocator",
                .package = "tree",
                .prefix = "zg",
                .zig_version = "0.16.0",
                .packages = &.{.{ .name = "child", .path = "child" }},
                .functions = &functions,
                .types = &.{.{ .name = "Node", .zig_path = "Node", .kind = .materialized, .materialized_version = 1, .fields = &fields }},
            };
            const json = try std.json.Stringify.valueAlloc(allocator, document, .{});
            var temporary = std.testing.tmpDir(.{ .iterate = true });
            defer temporary.cleanup();
            try generate(allocator, std.testing.io, json, temporary.dir, .{ .package = "tree", .prefix = "zg", .go_module = "example.com/tree", .backend = backend });
            const source = try temporary.dir.readFileAlloc(std.testing.io, "tree/tree_gen.go", allocator, .limited(1024 * 1024));
            try std.testing.expect(std.mem.indexOf(u8, source, "defer raw.FreeBuffer(result)") != null);
            try std.testing.expect(std.mem.indexOf(u8, source, "defer raw.Other(result)") == null);
        }
    }
}
