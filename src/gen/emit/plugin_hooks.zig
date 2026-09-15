//! Where the registered plugins get to write. One hook, `visit`, is offered
//! every node of the program in document order, and what it builds is flushed
//! at that node's insertion point: after a public method, after a handle,
//! value struct or enum, at a file body's boundaries, or in the package's own
//! plugin file. Every contribution is additive and Go-only; none of them can
//! reach the shim, the header or the raw package.
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
    .identifierAlloc = plugin.format.identifierAlloc,
};

/// The context a `type` node, a `files` emitter or a validator sees.
pub fn context(allocator: std.mem.Allocator, program: abi.Program, options: emit.Options) plugin.GoContext {
    return .{ .allocator = allocator, .program = program, .options = options.view(), .facts = options.facts, .writers = &writers };
}

/// The context the nodes inside a method see: the same, plus the names the
/// method they are written after used, so a wrapper cannot spell the call
/// differently.
pub fn methodContext(
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: emit.Options,
    method: plugin.Method,
) plugin.GoContext {
    var value = context(allocator, program, options);
    value.method = method;
    return value;
}

/// Offers one node to every registered plugin that attaches to it, in
/// registration order, and flushes what each built into `writer`. `options`
/// is the emitter's own copy, which knows which added plugins are selected;
/// the context only carries the view a hook may read.
fn visitNode(options: emit.Options, value: plugin.GoContext, writer: *std.Io.Writer, node: plugin.Node) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (comptime goSlot(registered).visit) |hook| {
            if (attaches(registered, node) and runs(index, options)) {
                var builder = value.builder();
                builder.out = writer;
                try hook(value, node, &builder);
            }
        }
    }
}

/// The plugin's Go render slot, or an empty one when it renders no Go. The
/// walks below read the slot rather than branching on its presence, so a
/// plugin that fills only the `rust` slot simply has nothing in every list.
pub fn goSlot(comptime registered: plugin.Plugin) plugin.GoRender {
    return registered.go orelse .{};
}

/// Whether `registered` declared the subject this node belongs to. A file or
/// package boundary has no subject, so every plugin sees it.
fn attaches(comptime registered: plugin.Plugin, node: plugin.Node) bool {
    return registered.supports(node.subject() orelse return true);
}

/// A public function or method: the function itself, then each of its
/// parameters, then its result. The three share one insertion point -- the
/// place the method's body ended -- so they are written in that order.
pub fn visitFunction(options: emit.Options, value: plugin.GoContext, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    try visitNode(options, value, writer, .{ .function = function });
    for (function.origin.params, 0..) |_, index|
        try visitNode(options, value, writer, .{ .param = .{ .function = function, .index = index } });
    try visitNode(options, value, writer, .{ .result = function });
}

/// A type declaration and the members inside it, after the generator wrote
/// the type. A registered enum's members are tags; every other kind's are
/// fields.
pub fn visitType(options: emit.Options, value: plugin.GoContext, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    try visitNode(options, value, writer, .{ .type = declaration });
    for (declaration.fields, 0..) |_, index| {
        const member: plugin.Node.Member = .{ .declaration = declaration, .index = index };
        try visitNode(options, value, writer, if (declaration.kind == .@"enum")
            .{ .enum_tag = member }
        else
            .{ .field = member });
    }
}

/// The unexported name the generated body takes when a plugin claims this
/// declaration's public surface. It is in the reserved `zigo` namespace, so it
/// cannot collide with anything the binding or a plugin names.
pub fn checkedNameAlloc(allocator: std.mem.Allocator, public_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "zigoChecked{s}", .{public_name});
}

/// Whether a plugin claimed this declaration's public surface. Two claims on
/// one declaration are refused in `analyze`, so the first answer is the only
/// one.
pub fn claimed(options: emit.Options, value: plugin.GoContext, function: abi.AbiFn) !bool {
    const node: plugin.Node = .{ .function = function };
    inline for (registry.plugins, 0..) |registered, index| {
        if (comptime goSlot(registered).claims) |claims| {
            if (registered.supports(.function) and runs(index, options) and try claims(value, node)) return true;
        }
    }
    return false;
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
        inline for (comptime goSlot(registered).imports) |entry| {
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
        for (registry.plugins) |registered| all = all ++ goSlot(registered).imports;
    }
    return all;
}

fn scopeOf(value: plugin.GoContext) public_writers.PublicScope {
    return .{ .program = value.program, .active_package = value.options.active_package };
}

fn writeTypeName(value: plugin.GoContext, writer: *std.Io.Writer, name: []const u8) anyerror!void {
    return scopeOf(value).writeTypeName(writer, name);
}

fn writeGoType(value: plugin.GoContext, writer: *std.Io.Writer, node: semantic.TypeNode) anyerror!void {
    return public_writers.writePublicGoType(scopeOf(value), writer, node);
}

fn receiverNameAlloc(value: plugin.GoContext, allocator: std.mem.Allocator, type_name: []const u8) anyerror![]u8 {
    return common.typeReceiverNameAlloc(allocator, value.program, type_name);
}

fn writeSignature(value: plugin.GoContext, writer: *std.Io.Writer, function: abi.AbiFn, options: plugin.SignatureOptions) anyerror!void {
    const allocated = if (options.parameter_names and value.method == null) try common.goParamNamesForAlloc(value.allocator, function.origin.params) else null;
    defer if (allocated) |names| naming.freeParamNames(value.allocator, names);
    const names = if (!options.parameter_names) null else if (value.method) |method| method.param_names else allocated;
    try writer.writeByte('(');
    try public.writePublicParameters(scopeOf(value), value.allocator, writer, function, names);
    try writer.writeByte(')');
    _ = try writeResultType(value, writer, function, .{ .omit_error = options.omit_error });
}

fn writeParameters(value: plugin.GoContext, writer: *std.Io.Writer, function: abi.AbiFn) anyerror!void {
    const allocated = if (value.method == null) try common.goParamNamesForAlloc(value.allocator, function.origin.params) else null;
    defer if (allocated) |names| naming.freeParamNames(value.allocator, names);
    const names = if (value.method) |method| method.param_names else allocated.?;
    try writer.writeByte('(');
    try public.writePublicParameters(scopeOf(value), value.allocator, writer, function, names);
    try writer.writeByte(')');
}

fn writeResultType(value: plugin.GoContext, writer: *std.Io.Writer, function: abi.AbiFn, options: plugin.ResultOptions) anyerror!usize {
    return public.writePublicResults(scopeOf(value), writer, function, common.constructorForInit(value.program, function.origin.*), options);
}

fn writeCallArguments(value: plugin.GoContext, writer: *std.Io.Writer, function: abi.AbiFn) anyerror!void {
    const allocated = if (value.method == null) try common.goParamNamesForAlloc(value.allocator, function.origin.params) else null;
    defer if (allocated) |names| naming.freeParamNames(value.allocator, names);
    return public.writePublicCallArguments(value.allocator, writer, function, if (value.method) |method| method.param_names else allocated.?);
}

fn writeValueType(value: plugin.GoContext, writer: *std.Io.Writer, function: abi.AbiFn) anyerror!void {
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

fn functionInfo(value: plugin.GoContext, function: abi.AbiFn) anyerror!plugin.FunctionInfo {
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
            if (runs(index, options)) {
                const value = context(allocator, program, options);
                try check(.{ .render = value.base(), .go = value, .facts = facts, .diagnostics = diagnostics });
            }
        }
    }
    // After the analyses, which is where a plugin decides what it claims.
    try checkClaims(allocator, program, options, diagnostics);
}

/// What `claims` is allowed to answer for. One declaration has one public
/// surface, so two plugins cannot both replace it: whichever wrote second
/// would give the Go type two methods of one name. And only a function node
/// has a public method at all, so a claim on any other node is refused rather
/// than quietly ignored.
fn checkClaims(
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: emit.Options,
    diagnostics: *std.ArrayList(@import("diagnostic").Diagnostic),
) !void {
    const value = context(allocator, program, options);
    for (program.functions) |function| {
        var claimant: ?[]const u8 = null;
        const node: plugin.Node = .{ .function = function };
        inline for (registry.plugins, 0..) |registered, index| {
            if (comptime goSlot(registered).claims) |claims| {
                if (registered.supports(.function) and runs(index, options) and try claims(value, node)) {
                    if (claimant) |first| {
                        const path = try plugin.site.functionDeclarationAlloc(allocator, function.origin.*);
                        try diagnostics.append(allocator, .{
                            .severity = .@"error",
                            .code = "ZIGO024",
                            .message = try std.fmt.allocPrint(allocator, "plugins `{s}` and `{s}` both replace the public Go surface of `{s}`", .{ first, registered.name, path }),
                            .site = plugin.site.functionSiteFor(function.origin.*, path),
                            .hint = "one declaration has one public method; disable one of the plugins for it",
                        });
                    } else claimant = registered.name;
                }
            }
        }
        for (function.origin.params, 0..) |_, index|
            try refuseClaim(allocator, value, options, diagnostics, .{ .param = .{ .function = function, .index = index } });
        try refuseClaim(allocator, value, options, diagnostics, .{ .result = function });
    }
    for (program.types) |declaration| {
        try refuseClaim(allocator, value, options, diagnostics, .{ .type = declaration });
        for (declaration.fields, 0..) |_, index| {
            const member: plugin.Node.Member = .{ .declaration = declaration, .index = index };
            try refuseClaim(allocator, value, options, diagnostics, if (declaration.kind == .@"enum")
                .{ .enum_tag = member }
            else
                .{ .field = member });
        }
    }
}

/// A claim on a node that has no public Go surface of its own.
fn refuseClaim(
    allocator: std.mem.Allocator,
    value: plugin.GoContext,
    options: emit.Options,
    diagnostics: *std.ArrayList(@import("diagnostic").Diagnostic),
    node: plugin.Node,
) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (comptime goSlot(registered).claims) |claims| {
            if (attaches(registered, node) and runs(index, options) and try claims(value, node)) {
                const site = try node.site(value.base());
                try diagnostics.append(allocator, .{
                    .severity = .@"error",
                    .code = "ZIGO065",
                    .message = try std.fmt.allocPrint(allocator, "plugin `{s}` claims the `{s}` node `{s}`, which has no public Go surface of its own", .{ registered.name, @tagName(node), site.declaration }),
                    .site = site,
                    .hint = "`claims` answers for a function node; leave every other node to `visit`",
                });
            }
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

    // The builder keeps what a hook hands it, so rendering runs on the arena
    // the generator backs a run with.
    const rendered = try renderAllPublicFiles(arena.allocator(), program);

    // The function node's visit wrote next to the bound method, with the
    // names the method itself used.
    try std.testing.expect(std.mem.indexOf(u8, rendered, "func (c *Counter) BumpTestHook() string { return \"a\" }") != null);
    // The type node was visited for the handle and for the enum.
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

test "a visit reads the typed options the declaration attached" {
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

test "a visit is offered the parameter, result, field and tag nodes with their options" {
    const fixture =
        \\{"functions":[{"name":"bump","params":[{"ext":{"TEST":{"tag":"step"}},"name":"by","type":{"bits":32,"kind":"int","signed":true}}],"receiver":"Counter","result_ext":{"TEST":{"tag":"total"}},"return":{"kind":"value_struct","ref":"Point"},"symbol":"zg_counter_bump"}],"ir_version":1,"package":"meter","prefix":"zg","types":[{"kind":"opaque","name":"Counter"},{"fields":[{"ext":{"TEST":{"tag":"zero"}},"name":"idle","value":0}],"kind":"enum","name":"Mode","tag_type":{"bits":8,"kind":"int","signed":false}},{"fields":[{"ext":{"TEST":{"tag":"across"}},"name":"x","type":{"bits":32,"kind":"int","signed":true}}],"kind":"value_struct","layout":"extern","name":"Point"}],"zig_version":"0.16.0"}
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

    const rendered = try renderAllPublicFiles(allocator, program);
    // Each of the four node kinds was visited and read its own `ext`.
    try std.testing.expect(std.mem.indexOf(u8, rendered, "// zigoTestHook param by at 0: step.") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "// zigoTestHook result of bump: total.") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "// zigoTestHook tag Mode.idle: zero.") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "// zigoTestHook field Point.x: across.") != null);
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
        const ctx = methodContext(allocator, program, .{ .go_module = "example.com/sample" }, .{ .public_name = "Call", .checked_name = "Call", .param_names = names });
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

/// A public file's body boundaries, inside the package/import frame. A file
/// the emitter gave no `FileInfo` has no boundary to offer.
pub fn visitFileBegin(options: emit.Options, value: plugin.GoContext, writer: *std.Io.Writer) !void {
    const file = value.options.file orelse return;
    return visitNode(options, value, writer, .{ .file_begin = file });
}

pub fn visitFileEnd(options: emit.Options, value: plugin.GoContext, writer: *std.Io.Writer) !void {
    const file = value.options.file orelse return;
    return visitNode(options, value, writer, .{ .file_end = file });
}

/// The package's own plugin file, `zigo_plugins_gen.go`: both boundaries in
/// one body, since nothing of the generator's sits between them.
pub fn visitPackage(options: emit.Options, value: plugin.GoContext, writer: *std.Io.Writer) !void {
    try visitNode(options, value, writer, .package_begin);
    try visitNode(options, value, writer, .package_end);
}
