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
    .Config = struct { label: []const u8 = "default", customize: bool = false, invalid_order: bool = false, invalid_adapter: bool = false, invalid_name: bool = false, collision: bool = false, replace: []const u8 = "", claim_node: bool = false },
    .transform = transform,
    .map_type = mapType,
    .name_function = nameFunction,
    .name_type = nameType,
    .Facts = struct { validated: bool },
    .validate = validate,
    .analyze = analyze,
    .go = .{
        .visit = visit,
        .claims = claims,
        .imports = &.{ .{ .qualifier = "fmt", .path = "fmt" }, .{ .qualifier = "time", .path = "time" } },
    },
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

/// Every node kind the contract offers, so the fixture proves the whole walk
/// reaches an external plugin module.
fn visit(context: api.GoContext, node: api.Node, b: *api.Builder) !void {
    const writer = try b.output();
    switch (node) {
        .function => |function| try renderMethod(context, writer, function),
        .type => |declaration| try writer.print("// ContractType {s} {s}\n", .{ @tagName(declaration.kind), declaration.name }),
        .file_begin => |file| try writer.print("// ContractFile begin {s}\n", .{file.path}),
        .file_end => |file| {
            try writer.print("// ContractFile end {s}\n", .{file.path});
            try writer.writeAll("var _ = fmt.Sprint\n");
        },
        .package_begin => {
            package_renders += 1;
            const config = try context.config(plugin);
            if (config.customize) try writer.writeAll("func unixTimeFromRaw(v uint64) time.Time { return time.Unix(int64(v), 0) }\nfunc unixTimeToRaw(v time.Time) uint64 { return uint64(v.Unix()) }\n");
            try writer.print("const ContractConfig = \"{s}\"\n", .{config.label});
        },
        else => {},
    }
}

fn renderMethod(context: api.GoContext, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    _ = (try context.facts.get(plugin, .function(function.origin.*))) orelse return error.MissingAnalysisFact;
    try writer.writeAll("\n// ContractAnalyzed\n");
    if (!try claims(context, .{ .function = function })) return;
    // The whole Go surface of a claimed declaration: the exported name, with
    // the generated body called under the name it was written with.
    const method = context.method.?;
    try writer.print("\n// {s} is the ContractReplacement.\nfunc ", .{method.public_name});
    if (method.receiver) |receiver| try writer.print("({s} *{s}) ", .{ method.receiver_name.?, receiver });
    try writer.print("{s}", .{method.public_name});
    try context.writeParameters(writer, function);
    const count = try context.writeResultType(writer, function, .{ .omit_error = true });
    try writer.writeAll(" { ");
    try writer.writeAll(switch (count) {
        0 => "_ = zigoMust(struct{}{}, ",
        1 => "return zigoMust(",
        else => "return zigoMustMatch(",
    });
    if (method.receiver_name) |receiver| try writer.print("{s}.", .{receiver});
    try writer.print("{s}(", .{method.checked_name});
    try context.writeCallArguments(writer, function);
    try writer.writeAll(")) }\n");
}

fn claims(context: api.GoContext, node: api.Node) !bool {
    const config = try context.config(plugin);
    // Only a function node has a public method to take over; claiming any
    // other node is what the generator has to refuse, so the fixture can ask
    // for it.
    if (node != .function) return config.claim_node;
    return config.replace.len != 0 and std.mem.eql(u8, config.replace, node.function.origin.name);
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
