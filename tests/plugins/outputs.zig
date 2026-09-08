//! External output fixture; knows only the public contract.
const std = @import("std");
const api = @import("plugin");
pub var document_runs: usize = 0;
pub var package_runs: usize = 0;
pub var raw_runs: usize = 0;
pub var document_go_runs: usize = 0;
pub var path_runs: usize = 0;
pub const plugin: api.Plugin = .{
    .name = "OUTPUTS",
    .Config = struct { enabled: bool = false, artifact_path: ?[]const u8 = null, go_path: ?[]const u8 = null, fail: bool = false },
    .go_files = &.{
        .{ .enabled = enabledGo, .imports = publicImports, .pathAlloc = publicPath, .render = renderPublic },
        .{ .enabled = enabledGo, .scope = .document, .pathAlloc = documentGoPath, .render = renderDocumentGo },
        .{ .enabled = enabledGo, .scope = .document, .package = .raw, .pathAlloc = rawPath, .render = renderRaw },
        .{ .enabled = enabledGo, .scope = .document, .package = .raw, .kind = .test_file, .imports = testImports, .pathAlloc = rawTestPath, .render = renderRawTest },
        .{ .enabled = enabledGo, .kind = .test_file, .imports = testImports, .pathAlloc = internalTestPath, .render = renderInternalTest },
        .{ .enabled = enabledGo, .package = .external_test, .kind = .test_file, .imports = externalImports, .pathAlloc = externalTestPath, .render = renderExternalTest },
        .{ .enabled = enabledGo, .build_constraint = "!zigo_output_disabled", .pathAlloc = taggedPath, .render = renderTagged },
        .{ .enabled = enabledGo, .build_constraint = "zigo_output_never", .pathAlloc = excludedPath, .render = renderExcluded },
    },
    .artifacts = &.{
        .{ .enabled = enabledArtifact, .pathAlloc = markdownPath, .render = renderMarkdown },
        artifact("schema.proto", "syntax = \"proto3\";"),
        artifact("types.d.ts", "export interface API {}\r\n\r\n"),
        artifact("go.mod.fragment", "require example.com/extra v1.0.0\n"),
        artifact("build_tag.go", "//go:build ignore\n\n"),
        artifact("empty.bin", ""),
        artifact("opaque.bin", "a\x00\xff\n\n"),
        .{ .enabled = enabledArtifact, .scope = .package, .pathAlloc = packagePath, .render = renderPackage },
    },
};
fn enabledGo(context: api.Context) !bool {
    return (try context.config(plugin)).enabled;
}
fn enabledArtifact(context: api.ArtifactContext) !bool {
    return (try context.config(plugin)).enabled;
}
fn publicPath(context: api.Context) ![]u8 {
    path_runs += 1;
    if ((try context.config(plugin)).go_path) |path| return context.allocator.dupe(u8, path);
    return context.goFilePathAlloc("zigo_output_gen.go");
}
fn documentGoPath(context: api.Context) ![]u8 {
    return context.goFilePathAlloc("zigo_document_gen.go");
}
fn rawPath(context: api.Context) ![]u8 {
    return context.goFilePathAlloc("zigo_raw_extra.go");
}
fn rawTestPath(context: api.Context) ![]u8 {
    return context.goFilePathAlloc("zigo_raw_extra_test.go");
}
fn internalTestPath(context: api.Context) ![]u8 {
    return context.goFilePathAlloc("zigo_internal_test.go");
}
fn externalTestPath(context: api.Context) ![]u8 {
    return context.goFilePathAlloc("zigo_external_test.go");
}
fn taggedPath(context: api.Context) ![]u8 {
    return context.goFilePathAlloc("zigo_tagged.go");
}
fn excludedPath(context: api.Context) ![]u8 {
    return context.goFilePathAlloc("zigo_excluded.go");
}
fn renderPublic(_: api.Context, writer: *std.Io.Writer) !void {
    try writer.writeAll("const PluginPublicAnswer = 42\n//go:embed api.md\nvar PluginDoc string\n");
}
fn renderDocumentGo(context: api.Context, writer: *std.Io.Writer) !void {
    document_go_runs += 1;
    try writer.print("const DocumentFunctionCount = {d}\n", .{context.program.functions.len});
}
fn renderRaw(_: api.Context, writer: *std.Io.Writer) !void {
    raw_runs += 1;
    try writer.writeAll("const PluginRawAnswer = 42\n");
}
fn renderRawTest(_: api.Context, writer: *std.Io.Writer) !void {
    try writer.writeAll("func TestRawPlugin(t *testing.T) { if PluginRawAnswer != 42 { t.Fatal(PluginRawAnswer) } }\n");
}
fn renderInternalTest(_: api.Context, writer: *std.Io.Writer) !void {
    try writer.writeAll("func ExamplePluginPublicAnswer() {\nfmt.Println(PluginPublicAnswer)\n// Output: 42\n}\n");
}
fn renderExternalTest(_: api.Context, writer: *std.Io.Writer) !void {
    try writer.writeAll("func TestExternalPlugin(t *testing.T) { if bindings.PluginPublicAnswer != 42 || bindings.PluginDoc == \"\" { t.Fatal(bindings.PluginPublicAnswer) } }\n");
}
fn renderTagged(_: api.Context, writer: *std.Io.Writer) !void {
    try writer.writeAll("const PluginTaggedAnswer = 7\n");
}
fn renderExcluded(_: api.Context, writer: *std.Io.Writer) !void {
    try writer.writeAll("var excludedBuildTag MustNotCompileWithoutBuildConstraint\n");
}
fn publicImports(_: api.Context) ![]const api.Import {
    return &.{.{ .qualifier = "_", .path = "embed" }};
}
fn testImports(_: api.Context) ![]const api.Import {
    return &.{ .{ .qualifier = "testing", .path = "testing" }, .{ .qualifier = "fmt", .path = "fmt" } };
}
fn externalImports(context: api.Context) ![]const api.Import {
    const directory = std.mem.trimEnd(u8, try context.publicFilePathAlloc(""), "/");
    const imports = try context.allocator.alloc(api.Import, 2);
    imports[0] = .{ .qualifier = "testing", .path = "testing" };
    imports[1] = .{ .qualifier = "bindings", .path = if (directory.len == 0) context.options.go_module else try std.fmt.allocPrint(context.allocator, "{s}/{s}", .{ context.options.go_module, directory }) };
    return imports;
}
fn artifact(comptime path: []const u8, comptime bytes: []const u8) api.Artifact {
    return .{ .enabled = enabledArtifact, .pathAlloc = struct {
        fn alloc(context: api.ArtifactContext) ![]u8 {
            return context.allocator.dupe(u8, path);
        }
    }.alloc, .render = struct {
        fn render(_: api.ArtifactContext, writer: *std.Io.Writer) !void {
            try writer.writeAll(bytes);
        }
    }.render };
}
fn markdownPath(context: api.ArtifactContext) ![]u8 {
    path_runs += 1;
    return context.allocator.dupe(u8, (try context.config(plugin)).artifact_path orelse "API_INDEX.md");
}
fn renderMarkdown(context: api.ArtifactContext, writer: *std.Io.Writer) !void {
    document_runs += 1;
    if ((try context.config(plugin)).fail) return error.ArtifactFailed;
    try writer.print("# API\r\nFunctions: {d}\r\nzigoMust(false)\r\n\r\n", .{context.program.functions.len});
}
fn packagePath(context: api.ArtifactContext) ![]u8 {
    return context.publicFilePathAlloc("api.md");
}
fn renderPackage(context: api.ArtifactContext, writer: *std.Io.Writer) !void {
    package_runs += 1;
    try writer.print("package={s};functions={d}", .{ context.options.active_package orelse "", context.program.functions.len });
}
