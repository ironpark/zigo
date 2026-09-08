//! External fixture exercising only public modules and the complete lifecycle.
const std = @import("std");
const api = @import("plugin");
const abi = @import("abi");
const semantic = @import("semantic");

pub var validation_runs: usize = 0;
pub var analysis_runs: usize = 0;
pub var package_renders: usize = 0;
pub const plugin: api.Plugin = .{
    .name = "CONTRACT",
    .Config = struct { label: []const u8 = "default" },
    .Facts = struct { validated: bool },
    .validate = validate,
    .analyze = analyze,
    .method_hook = methodHook,
    .type_hook = typeHook,
    .file_hook = fileHook,
    .package_hook = packageHook,
    .imports = &.{.{ .qualifier = "fmt", .path = "fmt" }},
};

fn validate(context: api.ValidateContext) !void {
    validation_runs += 1;
    try context.facts.put(context.allocator, plugin, .{ .kind = .document, .name = "" }, .{ .validated = true });
}

fn analyze(context: api.AnalyzeContext) !void {
    analysis_runs += 1;
    const fact = (try context.facts.get(plugin, .{ .kind = .document, .name = "" })) orelse return error.MissingValidationFact;
    if (!fact.validated) return error.InvalidValidationFact;
    for (context.render.program.functions) |function|
        try context.facts.put(context.render.allocator, plugin, .function(function.origin.*), fact);
}

fn methodHook(context: api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    _ = (try context.options.facts.get(plugin, .function(function.origin.*))) orelse return error.MissingAnalysisFact;
    try writer.writeAll("\n// ContractAnalyzed\n");
}

fn typeHook(_: api.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    try writer.print("// ContractType {s} {s}\n", .{ @tagName(declaration.kind), declaration.name });
}

fn fileHook(_: api.Context, writer: *std.Io.Writer, file: api.FileInfo, phase: api.FilePhase) !void {
    try writer.print("// ContractFile {s} {s}\n", .{ @tagName(phase), file.path });
    if (phase == .end) try writer.writeAll("var _ = fmt.Sprint\n");
}

fn packageHook(context: api.Context, writer: *std.Io.Writer) !void {
    package_renders += 1;
    const config = try context.config(plugin);
    try writer.print("const ContractConfig = \"{s}\"\n", .{config.label});
}
