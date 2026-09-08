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
    .Config = struct { label: []const u8 = "default", customize: bool = false, invalid_order: bool = false, invalid_adapter: bool = false, invalid_name: bool = false, collision: bool = false },
    .transform = transform,
    .map_type = mapType,
    .name_function = nameFunction,
    .name_type = nameType,
    .Facts = struct { validated: bool },
    .validate = validate,
    .analyze = analyze,
    .method_hook = methodHook,
    .type_hook = typeHook,
    .file_hook = fileHook,
    .package_hook = packageHook,
    .imports = &.{ .{ .qualifier = "fmt", .path = "fmt" }, .{ .qualifier = "time", .path = "time" } },
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
    if (config.customize) try writer.writeAll("func unixTimeFromRaw(v uint64) time.Time { return time.Unix(int64(v), 0) }\nfunc unixTimeToRaw(v time.Time) uint64 { return uint64(v.Unix()) }\n");
    try writer.print("const ContractConfig = \"{s}\"\n", .{config.label});
}

pub var transform_runs: usize = 0;
fn transform(context: api.TransformContext) !semantic.Semantic {
    transform_runs += 1;
    const config = try context.config(plugin);
    if (!config.customize) return context.document;
    var functions: std.ArrayList(semantic.SemanticFn) = .empty;
    for (context.document.functions) |original| {
        if (std.mem.eql(u8, original.name, "hidden")) continue;
        var function = original;
        if (std.mem.eql(u8, original.name, "combine")) {
            function = try context.reorderParameters(original, &.{ 1, 0 });
            if (config.invalid_order) {
                const params = try context.allocator.dupe(semantic.Parameter, function.params);
                params[0].native_index = 0;
                function.params = params;
            }
        }
        try functions.append(context.allocator, function);
        if (std.mem.eql(u8, original.name, "combine")) {
            var derived = original;
            derived.zig_path = try semantic.zigCallPathAlloc(context.allocator, original);
            derived.name = "derived";
            try functions.append(context.allocator, derived);
        }
    }
    var document = context.document;
    document.functions = try functions.toOwnedSlice(context.allocator);
    return document;
}

fn mapType(context: api.TransformContext, use: api.TypeUse) !?semantic.GoAdapter {
    const config = try context.config(plugin);
    if (!config.customize) return null;
    const node = switch (use) {
        .declaration => return null,
        .parameter => |value| value.function.params[value.index].type,
        .result => |function| function.@"return".errorPayload(),
    };
    if (node != .int and !config.invalid_adapter) return null;
    return .{ .type = "time.Time", .import = "time", .from_raw = "unixTimeFromRaw", .to_raw = "unixTimeToRaw" };
}

fn nameFunction(context: api.TransformContext, function: semantic.SemanticFn) !?[]const u8 {
    const config = try context.config(plugin);
    if (!config.customize) return null;
    if (config.invalid_name) return "bad-name";
    if (config.collision) return "SameName";
    if (std.mem.eql(u8, function.name, "combine")) return "HTTPCombine";
    if (std.mem.eql(u8, function.name, "derived")) return "HTTPDerived";
    return null;
}

fn nameType(context: api.TransformContext, declaration: semantic.TypeDecl) !?[]const u8 {
    if (!(try context.config(plugin)).customize) return null;
    if (std.mem.eql(u8, declaration.name, "State")) return "HTTPState";
    return null;
}
