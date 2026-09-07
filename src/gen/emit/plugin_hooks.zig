//! Where the registered plugins get to write. The two hooks are additive and
//! Go-only: `method_hook` writes after a public method, into the file that
//! owns it, and `type_hook` writes after a handle, value struct or enum.
//! Neither can reach the shim, the header or the raw package.
const std = @import("std");
const abi = @import("abi");
const common = @import("common.zig");
const emit = @import("emit.zig");
const plugin = @import("plugin");
const public = @import("public.zig");
const public_writers = @import("public_writers.zig");
const registry = @import("../plugins/registry.zig");
const semantic = @import("semantic");

/// The writers table every context hands to a plugin. It is one value: the
/// functions read everything they need from the context they are given.
const writers: plugin.Writers = .{
    .writeTypeName = writeTypeName,
    .writeGoType = writeGoType,
    .receiverNameAlloc = receiverNameAlloc,
    .writeSignature = writeSignature,
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
            if (runs(index, value.options)) try hook(value, writer, function);
        }
    }
}

/// Runs every registered `type_hook`, in registration order.
pub fn runTypeHooks(value: plugin.Context, writer: *std.Io.Writer, declaration: semantic.TypeDecl) !void {
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.type_hook) |hook| {
            if (runs(index, value.options)) try hook(value, writer, declaration);
        }
    }
}

/// Whether the plugin at `index` writes for this generation. The built-ins
/// always do -- they are the generator's own surface, not an opt-in -- and
/// anything the build added runs unless the options name a subset.
pub fn runs(comptime index: usize, options: emit.Options) bool {
    if (index < registry.builtins.len) return true;
    return options.runsPlugin(registry.plugins[index].name);
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

fn writeSignature(value: plugin.Context, writer: *std.Io.Writer, function: abi.AbiFn) anyerror!void {
    const method = value.method orelse return error.NoMethodInContext;
    return public.writePublicSignature(
        scopeOf(value),
        value.allocator,
        writer,
        function,
        method.param_names,
        common.constructorForInit(value.program, function.origin.*),
    );
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
