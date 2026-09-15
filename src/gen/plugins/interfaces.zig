//! Declared Go interfaces: the one file that spells them, and the signature
//! comparison that decides whether the listed handles can share them.
//!
//! A built-in plugin, and the one that adds a whole file rather than writing
//! next to something. `.interfaces` keeps its declaration key, its file name
//! and `ZIGO049`; the file itself is registered as the plugin's `files` entry.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const must = @import("must.zig");
const naming = @import("naming");
const plugin_api = @import("plugin");
const semantic = @import("semantic");
const interface_rules = plugin_api.interfaces;

pub const plugin: plugin_api.Plugin = .{
    .name = "INTERFACES",
    .validate = validateDocument,
    .requires = &.{"MUST"},
    .analyze = analyze,
    .go = .{ .source_files = &.{.{ .pathAlloc = interfacesPath, .render = renderInterfacesBody }} },
};

/// The declaration rules live with the other validation rules; the plugin is
/// what runs them, so `.interfaces` has one owner.
fn validateDocument(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    const document = context.document;
    if (try interface_rules.interfaceIssue(allocator, document, context.target)) |issue| try context.diagnose(issue);
}

/// The first method whose implementations disagree on their Go signature.
pub const Mismatch = struct {
    interface: []const u8,
    method: []const u8,
    first_type: []const u8,
    first_signature: []const u8,
    second_type: []const u8,
    second_signature: []const u8,
};

/// Compares the rendered signature of every interface method across its
/// types. Rendering, rather than a second structural rule, is what keeps
/// this from ever disagreeing with the file that spells the methods out.
/// The strings in the result live on `allocator`.
pub fn signatureMismatch(context: plugin_api.GoContext) !?Mismatch {
    const allocator = context.allocator;
    const program = context.program;
    for (program.interfaces) |interface| {
        for (interface.methods) |method| {
            const first = try comparableSignatureAlloc(context, method.functions[0].*);
            for (method.functions[1..], interface.types[1..]) |candidate, type_name| {
                const signature = try comparableSignatureAlloc(context, candidate.*);
                if (std.mem.eql(u8, first, signature)) {
                    allocator.free(signature);
                    continue;
                }
                return .{
                    .interface = interface.name,
                    .method = method.name,
                    .first_type = interface.types[0],
                    .first_signature = first,
                    .second_type = type_name,
                    .second_signature = signature,
                };
            }
            allocator.free(first);
        }
    }
    return null;
}

/// The signature two implementations have to share: parameter types, result,
/// and whether a `Must` variant accompanies it. Parameter names are left out
/// because Go does not read them when deciding whether a method matches.
fn comparableSignatureAlloc(context: plugin_api.GoContext, function: abi.AbiFn) ![]u8 {
    var buffer: std.Io.Writer.Allocating = .init(context.allocator);
    errdefer buffer.deinit();
    const go_name = (try context.functionInfo(function)).public_name;
    defer context.allocator.free(go_name);
    try buffer.writer.writeAll(go_name);
    try context.writeSignatureWith(&buffer.writer, function, .{ .parameter_names = false });
    if (try must.hasVariant(context, function)) try buffer.writer.writeAll(" +Must");
    return buffer.toOwnedSlice();
}

pub fn interfacesPath(context: plugin_api.GoContext) ![]u8 {
    const package = if (context.options.go_package.len != 0) try context.allocator.dupe(u8, context.options.go_package) else try naming.snakeAlloc(context.allocator, context.program.package);
    defer context.allocator.free(package);
    const filename = try std.fmt.allocPrint(context.allocator, "{s}_interfaces_gen.go", .{package});
    defer context.allocator.free(filename);
    return context.publicFilePathAlloc(filename);
}

fn analyze(context: plugin_api.AnalyzeContext) !void {
    const mismatch = try signatureMismatch(context.go.?) orelse return;
    try context.diagnose(.{
        .severity = .@"error",
        .code = "ZIGO049",
        .message = try std.fmt.allocPrint(context.render.allocator, "method `{s}` has signature `{s}` on `{s}` but `{s}` on `{s}`", .{ mismatch.method, mismatch.first_signature, mismatch.first_type, mismatch.second_signature, mismatch.second_type }),
        .site = plugin_api.site.documentSite(mismatch.interface),
        .hint = "give every listed type the same Go signature for the method, or drop the method or the type from the interface",
    });
}

/// `<package>_interfaces_gen.go`: every declared interface of the active
/// package with a compile-time assertion per implementing type. The
/// assertions are the safety net under the signature comparison: anything it
/// let through stops `go build` here rather than at a caller's type switch.
/// The declarations alone: the generated marker, the package clause and the
/// import block come from the public-file frame every plugin file renders
/// through, so this writes exactly what the file declares and no more.
pub fn renderInterfacesBody(context: plugin_api.GoContext, writer: *std.Io.Writer) !void {
    const program = context.program;
    const options = context.options;
    var written: usize = 0;
    for (program.interfaces) |interface| {
        if (!plugin_api.packageMatches(interface.package, options.active_package)) continue;
        if (written != 0) try writer.writeByte('\n');
        try renderInterface(context, writer, interface);
        written += 1;
    }
}

fn renderInterface(context: plugin_api.GoContext, writer: *std.Io.Writer, interface: abi.AbiInterface) !void {
    const allocator = context.allocator;
    const b = context.builder();

    // The binding's own words first, then the sentence naming the types that
    // implement it, which is what a reader of the interface needs.
    var doc: std.Io.Writer.Allocating = .init(allocator);
    defer doc.deinit();
    if (interface.doc) |text| try doc.writer.print("{s}\n", .{text});
    try doc.writer.print("{s} is implemented by ", .{interface.name});
    for (interface.types, 0..) |type_name, index| {
        if (index != 0) try doc.writer.writeAll(if (index + 1 == interface.types.len) " and " else ", ");
        try doc.writer.print("*{s}", .{type_name});
    }
    try doc.writer.writeByte('.');

    var methods: std.ArrayList(plugin_api.gobuild.InterfaceMethod) = .empty;
    defer methods.deinit(allocator);
    for (interface.methods) |method| {
        // The first type speaks for the interface: its method doc and its
        // parameter names are the ones the interface shows.
        const function = method.functions[0].*;
        const go_name = (try context.functionInfo(function)).public_name;
        var method_doc: plugin_api.gobuild.Doc = undefined;
        if (function.origin.doc) |text| {
            // The same doc the method itself gets, moved in one tab.
            var rendered: std.Io.Writer.Allocating = .init(allocator);
            context.writeDoc(&rendered.writer, go_name, function.origin.name, text) catch return error.OutOfMemory;
            method_doc = .{ .rendered = std.mem.trim(u8, rendered.written(), "\n") };
        } else {
            method_doc = .{ .text = try std.fmt.allocPrint(allocator, "{s} calls the Zig method {s} of the implementing handle.", .{ go_name, function.origin.name }) };
        }
        try methods.append(allocator, .{ .doc = method_doc, .name = go_name, .signature = .{ .function = .{ .function = function } } });
        if (try must.hasVariant(context, function)) try methods.append(allocator, .{
            .doc = .{ .text = try std.fmt.allocPrint(allocator, "Must{s} calls {s} and panics with its typed error on failure.", .{ go_name, go_name }) },
            .name = try std.fmt.allocPrint(allocator, "Must{s}", .{go_name}),
            .signature = .{ .function = .{ .function = function, .options = .{ .omit_error = true } } },
        });
    }

    try b.render(writer, &.{try b.interfaceDecl(.{
        .doc = .{ .text = doc.written() },
        .name = interface.name,
        .methods = methods.items,
        .embeds = if (interface.closer) &.{try b.selName("io", "Closer")} else &.{},
    })}, .{ .blank_after = true });

    // The assertions are the safety net under the signature comparison:
    // anything it let through stops `go build` here rather than at a caller.
    var assertions: std.ArrayList(plugin_api.gobuild.Decl) = .empty;
    defer assertions.deinit(allocator);
    for (interface.types) |type_name| try assertions.append(allocator, try b.assertImplements(.{
        .interface = b.ident(interface.name),
        .type_name = type_name,
    }));
    try b.render(writer, assertions.items, .{ .blank_between = false });
}
