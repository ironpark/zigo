//! Where the registered plugins get to write. The two hooks are additive and
//! Go-only: `method_hook` writes after a public method, into the file that
//! owns it, and `type_hook` writes after a handle, value struct or enum.
//! Neither can reach the shim, the header or the raw package.
const std = @import("std");
const abi = @import("abi");
const docs = @import("docs.zig");
const naming = @import("naming");
const common = @import("common.zig");
const emit = @import("emit.zig");
const plugin = @import("plugin");
const public = @import("public.zig");
const public_writers = @import("public_writers.zig");
const registry = @import("../plugins/registry.zig");
const semantic = @import("semantic");
const targets = @import("targets");

/// The writers table every context hands to a plugin. It is one value: the
/// functions read everything they need from the context they are given.
const writers: plugin.Writers = .{
    .writeTypeName = writeTypeName,
    .writeGoType = writeGoType,
    .receiverNameAlloc = receiverNameAlloc,
    .writeSignature = writeSignature,
    .writeValueType = writeValueType,
    .writeDoc = docs.writeGoDoc,
    .functionInfo = functionInfo,
    .writeParameters = writeParameters,
    .writeResultType = writeResultType,
    .writeCallArguments = writeCallArguments,
};

/// The context a `type_hook`, a `files` emitter or a validator sees.
pub fn context(allocator: std.mem.Allocator, program: abi.Program, options: emit.Options) plugin.Context {
    return .{ .allocator = allocator, .program = program, .options = options, .writers = &writers };
}

/// The context a `method_hook` sees: the same, plus the names the method the
/// hook is written after used, so a wrapper cannot spell the call differently.
pub fn methodContext(
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: emit.Options,
    method: plugin.Method,
) plugin.Context {
    var value = context(allocator, program, options);
    value.method = method;
    return value;
}

/// Runs every registered `method_hook`, in registration order.
pub fn runMethodHooks(value: plugin.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.method_hook) |hook| {
            if (registered.supports(.function) and runs(index, value.options)) try hook(value, writer, function);
        }
    }
}

/// Runs every registered `type_hook`, in registration order.
pub fn runTypeHooks(value: plugin.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.type_hook) |hook| {
            if (registered.supports(plugin.typeSubject(declaration.kind)) and runs(index, value.options)) try hook(value, writer, declaration);
        }
    }
}

/// Whether the plugin at `index` writes for this generation. The built-ins
/// always do -- they are the generator's own surface, not an opt-in -- and
/// anything the build added runs unless the options name a subset.
pub fn runs(comptime index: usize, options: emit.Options) bool {
    return registry.runs(index, options.plugins, options.target);
}

/// Whether any registered plugin declares this import. The caller still only
/// writes it when the rendered body spells the qualifier.
pub fn importPath(qualifier: []const u8) ?[]const u8 {
    inline for (registry.plugins) |registered| {
        inline for (registered.imports) |entry| {
            if (std.mem.eql(u8, entry.qualifier, qualifier)) return entry.path;
        }
    }
    return null;
}

/// Every import any registered plugin declares, in registration order. The
/// import block filters it down to the ones the body actually uses.
pub fn declaredImports() []const plugin.Import {
    comptime var all: []const plugin.Import = &.{};
    comptime {
        for (registry.plugins) |registered| all = all ++ registered.imports;
    }
    return all;
}

fn scopeOf(value: plugin.Context) public_writers.PublicScope {
    return .{ .program = value.program, .options = value.options };
}

fn writeTypeName(value: plugin.Context, writer: *std.Io.Writer, name: []const u8) anyerror!void {
    return scopeOf(value).writeTypeName(writer, name);
}

fn writeGoType(value: plugin.Context, writer: *std.Io.Writer, node: semantic.TypeNode) anyerror!void {
    return public_writers.writePublicGoType(scopeOf(value), writer, node);
}

fn receiverNameAlloc(value: plugin.Context, allocator: std.mem.Allocator, type_name: []const u8) anyerror![]u8 {
    return common.typeReceiverNameAlloc(allocator, value.program, type_name);
}

fn writeSignature(value: plugin.Context, writer: *std.Io.Writer, function: abi.AbiFn, options: plugin.SignatureOptions) anyerror!void {
    const allocated = if (options.parameter_names and value.method == null) try common.goParamNamesForAlloc(value.allocator, function.origin.params) else null;
    defer if (allocated) |names| naming.freeParamNames(value.allocator, names);
    const names = if (!options.parameter_names) null else if (value.method) |method| method.param_names else allocated;
    try writer.writeByte('(');
    try public.writePublicParameters(scopeOf(value), value.allocator, writer, function, names);
    try writer.writeByte(')');
    _ = try writeResultType(value, writer, function, .{ .omit_error = options.omit_error });
}

fn writeParameters(value: plugin.Context, writer: *std.Io.Writer, function: abi.AbiFn) anyerror!void {
    const allocated = if (value.method == null) try common.goParamNamesForAlloc(value.allocator, function.origin.params) else null;
    defer if (allocated) |names| naming.freeParamNames(value.allocator, names);
    const names = if (value.method) |method| method.param_names else allocated.?;
    try writer.writeByte('(');
    try public.writePublicParameters(scopeOf(value), value.allocator, writer, function, names);
    try writer.writeByte(')');
}

fn writeResultType(value: plugin.Context, writer: *std.Io.Writer, function: abi.AbiFn, options: plugin.ResultOptions) anyerror!usize {
    return public.writePublicResults(scopeOf(value), writer, function, common.constructorForInit(value.program, function.origin.*), options);
}

fn writeCallArguments(value: plugin.Context, writer: *std.Io.Writer, function: abi.AbiFn) anyerror!void {
    const allocated = if (value.method == null) try common.goParamNamesForAlloc(value.allocator, function.origin.params) else null;
    defer if (allocated) |names| naming.freeParamNames(value.allocator, names);
    return public.writePublicCallArguments(value.allocator, writer, function, if (value.method) |method| method.param_names else allocated.?);
}

fn writeValueType(value: plugin.Context, writer: *std.Io.Writer, function: abi.AbiFn) anyerror!void {
    const origin = function.origin.*;
    if (common.constructorForInit(value.program, origin)) |constructor| return writer.print("*{s}", .{constructor.type});
    const result = origin.@"return".errorPayload();
    const node = if (result == .optional) result.optional.child.* else result;
    if (node == .opaque_ptr and docs.returnsBorrowedView(origin)) return writer.print("*{s}", .{node.opaque_ptr.ref});
    if (node == .opaque_ptr and docs.returnsBorrowedOpaque(origin)) return writer.print("*{s}Ref", .{node.opaque_ptr.ref});
    if (semantic.isStringSlice(node, origin.return_semantic)) return writer.writeAll("string");
    if (public_writers.codepointTypeName(node, origin.return_semantic)) |name| return writer.writeAll(name);
    if (origin.returnGoAdapter()) |adapter| return writer.writeAll(adapter.type);
    return public_writers.writePublicGoType(scopeOf(value), writer, node);
}

fn functionInfo(value: plugin.Context, function: abi.AbiFn) anyerror!plugin.FunctionInfo {
    const origin = function.origin.*;
    const document: semantic.Semantic = .{ .constructors = value.program.constructors, .package = value.program.package, .prefix = value.program.prefix, .zig_version = "" };
    return .{
        .public_name = try targets.go.publicFunctionNameAlloc(value.allocator, document, origin),
        .is_public = public.emitsPublicFunction(value.program, function),
        .has_error = common.constructorForInit(value.program, origin) != null or origin.@"return" == .error_union or public.signatureShape(function).needs_check,
    };
}

pub fn analyze(allocator: std.mem.Allocator, program: abi.Program, options: emit.Options, facts: *plugin.Facts, diagnostics: *std.ArrayList(@import("diagnostic").Diagnostic)) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.analyze) |check| {
            if (runs(index, options)) try check(.{ .render = context(allocator, program, options), .facts = facts, .diagnostics = diagnostics });
        }
    }
}

test "a registered plugin adds a method next to a bound one, a line after a type, and a file" {
    const document: semantic.Semantic = .{
        .package = "meter",
        .prefix = "zg",
        .functions = &.{
            .{
                .name = "bump",
                .params = &.{},
                .receiver = "Counter",
                .@"return" = .{ .void = {} },
                .symbol = "zg_counter_bump",
            },
        },
        .types = &.{
            .{ .kind = .@"opaque", .name = "Counter" },
            .{
                .fields = &.{.{ .name = "plain", .value = 0 }},
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocument(arena.allocator(), document, "meter", "zg", &.{});

    const testing_plugin = @import("../plugins/testing.zig");
    testing_plugin.enabled = true;
    defer testing_plugin.enabled = false;

    const rendered = try renderAllPublicFiles(std.testing.allocator, program);
    defer std.testing.allocator.free(rendered);

    // The method hook wrote next to the bound method, with the names the
    // method itself used.
    try std.testing.expect(std.mem.indexOf(u8, rendered, "func (c *Counter) BumpTestHook() string { return \"a\" }") != null);
    // The type hook ran for the handle and for the enum.
    try std.testing.expect(std.mem.indexOf(u8, rendered, "// zigoTestHook saw Counter.") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "// zigoTestHook saw Mode.") != null);
    // The plugin's own file came out framed: the plugin wrote declarations,
    // and the marker and package clause were added around them.
    try std.testing.expect(std.mem.indexOf(u8, rendered, "const ZigoTestPluginName = \"TEST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "// Code generated by zigo. DO NOT EDIT.\n\npackage meter\n\n// ZigoTestPluginName") != null);

    testing_plugin.enabled = false;
    const inert = try renderAllPublicFiles(std.testing.allocator, program);
    defer std.testing.allocator.free(inert);
    try std.testing.expect(std.mem.indexOf(u8, inert, "TestHook") == null);
    try std.testing.expect(std.mem.indexOf(u8, inert, "ZigoTestPluginName") == null);
}

/// Every public file of a program concatenated, plugin files included, which
/// is what a test needs to see the whole Go surface at once.
fn renderAllPublicFiles(allocator: std.mem.Allocator, program: abi.Program) ![]u8 {
    const options: emit.Options = .{ .go_module = "example.com/meter" };
    var referenced = try emit.references.referencedHelpersAlloc(allocator, program, options);
    defer referenced.deinit(allocator);
    var with_helpers = options;
    with_helpers.helpers = &referenced;
    var joined: std.Io.Writer.Allocating = .init(allocator);
    defer joined.deinit();
    var emitters = emit.publicEmitters();
    while (emitters.next()) |emitter| {
        const path = try emitter.pathAlloc(allocator, program, with_helpers);
        allocator.free(path);
        try emitter.render(allocator, &joined.writer, program, with_helpers);
    }
    return joined.toOwnedSlice();
}

test "a hook reads the typed options the declaration attached" {
    const fixture =
        \\{"functions":[{"ext":{"TEST":{"mode":"b"}},"name":"bump","params":[],"receiver":"Counter","return":{"kind":"void"},"symbol":"zg_counter_bump"}],"ir_version":1,"package":"meter","prefix":"zg","types":[{"kind":"opaque","name":"Counter"}],"zig_version":"0.16.0"}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parsed = try semantic.Semantic.parse(allocator, fixture);
    defer parsed.deinit();
    const program = try @import("lower").semanticDocument(allocator, parsed.value, "meter", "zg", &.{});

    const testing_plugin = @import("../plugins/testing.zig");
    testing_plugin.enabled = true;
    defer testing_plugin.enabled = false;

    var rendered: std.Io.Writer.Allocating = .init(allocator);
    try public.renderPublic(allocator, &rendered.writer, program, .{ .go_module = "example.com/meter" });
    // `.mode = .b` travelled through `extend`, the document and the parse.
    try std.testing.expect(std.mem.indexOf(u8, rendered.written(), "func (c *Counter) BumpTestHook() string { return \"b\" }") != null);
}

test "plugin public paths follow root and split package options" {
    const program: abi.Program = .{ .package = "MyLibrary", .prefix = "zg", .functions = &.{} };
    const cases = [_]struct { options: emit.Options, expected: []const u8 }{
        .{ .options = .{ .go_module = "m" }, .expected = "my_library/helpers.go" },
        .{ .options = .{ .go_module = "m", .go_package = "api" }, .expected = "api/helpers.go" },
        .{ .options = .{ .go_module = "m", .go_package = "api", .go_package_path = "." }, .expected = "helpers.go" },
        .{ .options = .{ .go_module = "m", .go_package = "input", .go_package_path = "api/input" }, .expected = "api/input/helpers.go" },
    };
    for (cases) |case| {
        const path = try context(std.testing.allocator, program, case.options).publicFilePathAlloc("helpers.go");
        defer std.testing.allocator.free(path);
        try std.testing.expectEqualStrings(case.expected, path);
    }
}

test "plugin result and parameter writers avoid parsing checked signatures" {
    var integer: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var optional: semantic.TypeNode = .{ .optional = .{ .child = &integer } };
    var nothing: semantic.TypeNode = .void;
    const document: semantic.Semantic = .{
        .package = "sample",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .functions = &.{
            .{ .name = "optional", .symbol = "zg_optional", .params = &.{.{ .name = "value", .type = integer }}, .@"return" = .{ .error_union = .{ .payload = &optional, .error_set = &.{"Failure"} } } },
            .{ .name = "empty", .symbol = "zg_empty", .params = &.{}, .@"return" = .{ .error_union = .{ .payload = &nothing, .error_set = &.{"Failure"} } } },
        },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const program = try @import("lower").semanticDocument(allocator, document, "sample", "zg", &.{.{ .name = "Failure", .code = 1 }});
    for (program.functions, 0..) |function, index| {
        const names = try common.goParamNamesForAlloc(allocator, function.origin.params);
        const ctx = methodContext(allocator, program, .{ .go_module = "example.com/sample" }, .{ .public_name = "Call", .param_names = names });
        var output: std.Io.Writer.Allocating = .init(allocator);
        try ctx.writeParameters(&output.writer, function);
        const count = try ctx.writeResultType(&output.writer, function, .{ .omit_error = true });
        try std.testing.expectEqual(@as(usize, if (index == 0) 2 else 0), count);
        try std.testing.expectEqualStrings(if (index == 0) "(value int32) (int32, bool)" else "()", output.written());
        var results: std.Io.Writer.Allocating = .init(allocator);
        try std.testing.expectEqual(count + 1, try ctx.writeResultType(&results.writer, function, .{}));
        try std.testing.expectEqualStrings(if (index == 0) " (int32, bool, error)" else " error", results.written());
        var args: std.Io.Writer.Allocating = .init(allocator);
        try ctx.writeCallArguments(&args.writer, function);
        try std.testing.expectEqualStrings(if (index == 0) "value" else "", args.written());
        var missing = ctx;
        missing.method = null;
        var standalone: std.Io.Writer.Allocating = .init(allocator);
        defer standalone.deinit();
        try missing.writeParameters(&standalone.writer, function);
        try std.testing.expectEqualStrings(if (index == 0) "(value int32)" else "()", standalone.written());
    }
}

pub fn runFileHooks(value: plugin.Context, writer: *std.Io.Writer, phase: plugin.FilePhase) !void {
    const file = value.options.file orelse return;
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.file_hook) |hook| {
            if (runs(index, value.options)) try hook(value, writer, file, phase);
        }
    }
}

pub fn runPackageHooks(value: plugin.Context, writer: *std.Io.Writer) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.package_hook) |hook| {
            if (runs(index, value.options)) try hook(value, writer);
        }
    }
}
