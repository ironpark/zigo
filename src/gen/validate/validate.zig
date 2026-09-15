//! Validation of a semantic document: the public entry points and the
//! ordered rule list that decides which diagnostic a faulty document gets.
const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const lower = @import("lower");
const functions = @import("functions.zig");
const callbacks = @import("callbacks.zig");
const interfaces = @import("interfaces.zig");
const session = @import("session.zig");
const materialized = @import("materialized.zig");
const names = @import("names.zig");
const plugin = @import("plugin");
const registry = @import("../plugins/registry.zig");
const ownership = @import("ownership.zig");
const packages = @import("packages.zig");
const site = @import("site.zig");
const targets = @import("targets");
const types = @import("types.zig");

/// Every rejection reaches the user as a rendered diagnostic, so this only
/// reports whether the document had one. Callers that want the text call
/// `findIssue` themselves; the scratch arena here owns the strings that
/// diagnostic built.
pub fn semanticDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !void {
    return semanticDocumentWithPlugins(allocator, document, null);
}

/// The short entry points below take no target and judge the document against
/// `targets.default`. They are the convenience layer the tests and the
/// single-target tools use; generation and the CLI pass the target they
/// resolved, which is what makes the rules target-agnostic.
/// Validate core rules and only the selected external plugins; null selects all.
pub fn semanticDocumentWithPlugins(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    if (try findIssueWithPlugins(scratch.allocator(), document, selected, targets.default) != null) return error.InvalidSemantic;
}

/// Every purego callback dispatcher returns one pointer-sized integer, which is
/// what Windows' `syscall.NewCallback` demands and what the native side reads
/// back as `int32_t` or ignores. A callback that returns anything else -- a
/// float, a wider integer -- has nowhere to put its result: the dispatcher would
/// drop it and the native caller would read whatever the register held.
/// Generation refuses instead of emitting that silence.
///
/// Float *parameters* are no longer a rejection class. They cross as their
/// IEEE-754 bit pattern through an integer of the same width, converted by the
/// shim on both ends, so `compileCallback` never sees a floating-point argument
/// on any platform.
pub fn puregoCallbackIssue(document: semantic.Semantic) ?diagnostic.Diagnostic {
    for (document.functions) |function| {
        for (function.params) |parameter| {
            if (parameter.type != .callback) continue;
            const result = parameter.type.callback.@"return".*;
            if (result == .void or result == .bool) continue;
            if (result == .int and result.int.signed and result.int.bits == 32) continue;
            return .{
                .severity = .@"error",
                .code = "ZIGO014",
                .message = "purego callback result must be void, bool or a signed 32-bit integer",
                .site = site.functionSite(function),
                .hint = "return `void`, `bool` or `i32` from the callback, or report the value through userdata",
            };
        }
    }
    return null;
}

pub fn puregoCallbacks(document: semantic.Semantic) !void {
    if (puregoCallbackIssue(document) != null) return error.InvalidSemantic;
}

/// The single place a semantic document is judged. A returned diagnostic may
/// point at strings allocated from `allocator` -- the declaration and location
/// text is built from the document -- so pass a scratch arena and drop it once
/// the diagnostic is rendered.
/// One validation rule over the whole document. `findIssue` runs the rules
/// in order, and that order is the diagnostic priority: the first rule that
/// objects names the problem, so the sharper rules come before the general
/// ones and a document with several faults reports the same one each time.
const Rule = *const fn (std.mem.Allocator, semantic.Semantic, targets.Target) anyerror!?diagnostic.Diagnostic;

const rules = [_]Rule{
    documentHeaderIssue,
    packages.packageMetadataIssue,
    packages.packageCycleIssue,
    names.identifierIssue,
    functions.functionIssue,
    materialized.materializedReleaseIssue,
    types.typeIssue,
    names.cIdentifierIssue,
    names.generatedAccessorCollisionIssue,
    names.publicNameCollisionIssue,
    types.integrityIssue,
    functions.optionalOutIssue,
    types.abiTypeIssue,
    callbacks.callbackTypeRule,
    callbacks.callbackUserdataRule,
};

pub fn findIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    return findIssueWithPlugins(allocator, document, null, targets.default);
}

/// Built-in rules always run, including when the external selection is empty.
pub fn findIssueWithPlugins(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8, target: targets.Target) !?diagnostic.Diagnostic {
    for (rules) |check| if (try check(allocator, document, target)) |issue| return issue;
    // Plugins judge last, so a plugin rule can never mask a document fault
    // the generator itself would have rejected.
    return pluginIssue(allocator, document, selected, target);
}

/// Every registered plugin, in registration order: first its options are
/// checked against the type it declared for them, then whatever rule it
/// wrote of its own.
fn pluginIssue(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8, target: targets.Target) !?diagnostic.Diagnostic {
    inline for (registry.plugins, 0..) |registered, index| {
        if (registry.runs(index, selected, target)) {
            var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
            defer issues.deinit(allocator);
            try appendPluginIssues(registered, allocator, document, registry.configurations, &issues);
            if (issues.items.len != 0) return issues.items[0];
        }
    }
    return null;
}

/// Collect independent plugin diagnostics in registration/callback order.
/// Core structural rules remain a gate: plugins never see a malformed core
/// document. Returned data belongs to allocator and the input document; use
/// an arena that outlives rendering, or clone diagnostics for longer storage.
pub fn findIssuesWithPlugins(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8) ![]const diagnostic.Diagnostic {
    return findIssuesConfigured(allocator, document, selected, registry.configurations);
}

pub fn findIssuesForTarget(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8, target: targets.Target) ![]const diagnostic.Diagnostic {
    var facts: plugin.Facts = .{};
    return findIssuesWithFacts(allocator, document, selected, registry.configurations, &facts, target);
}

pub fn findIssuesConfigured(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8, configurations: []const plugin.Configuration) ![]const diagnostic.Diagnostic {
    var facts: plugin.Facts = .{};
    return findIssuesWithFacts(allocator, document, selected, configurations, &facts, targets.default);
}

/// Shared entry point for generation and reports. The caller owns the arena,
/// diagnostics and facts. A document with diagnostics must not be lowered.
pub fn prepareDocument(allocator: std.mem.Allocator, input: semantic.Semantic, selected: ?[]const []const u8, configurations: []const plugin.Configuration, facts: *plugin.Facts, issues: *std.ArrayList(diagnostic.Diagnostic), target: targets.Target) !semantic.Semantic {
    const document = try transformDocument(allocator, input, selected, configurations, issues, target);
    if (issues.items.len != 0) return document;
    try issues.appendSlice(allocator, try findIssuesWithFacts(allocator, document, selected, configurations, facts, target));
    return document;
}

/// Parse establishes the IR shape; transforms may repair or remove declarations
/// that core rules would reject. Only the final document reaches core rules,
/// validation facts and lowering. Every hook runs in registry dependency order.
pub fn transformDocument(allocator: std.mem.Allocator, input: semantic.Semantic, selected: ?[]const []const u8, configurations: []const plugin.Configuration, issues: *std.ArrayList(diagnostic.Diagnostic), target: targets.Target) !semantic.Semantic {
    try checkPluginSelection(selected, configurations, target);
    inline for (registry.plugins, 0..) |registered, index| {
        if (registry.runs(index, selected, target)) {
            _ = plugin.readConfig(registered, allocator, configurations) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => {
                    try issues.append(allocator, .{ .severity = .@"error", .code = registered.name ++ "001", .message = "invalid plugin build configuration", .site = .{ .path = "build.zig", .declaration = registered.name }, .hint = "provide fields matching the plugin Config type" });
                },
            };
        }
    }
    if (issues.items.len != 0) return input;
    var document = input;
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.transform) |hook| if (registry.runs(index, selected, target)) {
            document = try hook(.{ .allocator = allocator, .document = document, .configurations = configurations, .diagnostics = issues, .target = target });
            if (issues.items.len != 0) return document;
        };
    }
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.name_type) |hook| if (registry.runs(index, selected, target)) {
            const context: plugin.TransformContext = .{ .allocator = allocator, .document = document, .configurations = configurations, .diagnostics = issues, .target = target };
            var changes: std.ArrayList(plugin.rename.Rename) = .empty;
            for (document.types) |declaration| {
                if (registered.supports(plugin.typeSubject(declaration.kind))) {
                    if (try hook(context, declaration)) |name| {
                        if (!std.mem.eql(u8, name, declaration.name)) try changes.append(allocator, .{ .from = declaration.name, .to = name });
                    }
                }
            }
            if (issues.items.len != 0) return document;
            document = try plugin.rename.types(allocator, document, changes.items);
        };
    }
    // Each policy sees a stable snapshot including earlier plugins' results.
    // All structural transforms finish first, so synthesized declarations also
    // receive every plugin's adapter and naming policy.
    inline for (registry.plugins, 0..) |registered, index| {
        if (registry.runs(index, selected, target) and (registered.map_type != null or registered.name_function != null)) {
            const context: plugin.TransformContext = .{ .allocator = allocator, .document = document, .configurations = configurations, .diagnostics = issues, .target = target };
            const functions_copy = try allocator.dupe(semantic.SemanticFn, document.functions);
            const types_copy = try allocator.dupe(semantic.TypeDecl, document.types);
            if (registered.map_type) |hook| {
                for (types_copy) |*declaration| {
                    if (registered.supports(plugin.typeSubject(declaration.kind))) {
                        if (try hook(context, .{ .declaration = declaration.* })) |adapter| declaration.go = semantic.TypeGo.withAdapter(adapter);
                    }
                }
                if (registered.supports(.function)) for (functions_copy) |*function| {
                    const params = try allocator.dupe(semantic.Parameter, function.params);
                    for (params, 0..) |*param, param_index| {
                        if (try hook(context, .{ .parameter = .{ .function = function.*, .index = param_index } })) |adapter| param.setGoAdapter(adapter);
                    }
                    if (try hook(context, .{ .result = function.* })) |adapter| function.setReturnGoAdapter(adapter);
                    function.params = params;
                };
            }
            if (registered.name_function) |hook| {
                if (registered.supports(.function)) for (functions_copy) |*function| {
                    if (try hook(context, function.*)) |name| target.setNameOverride(function, name);
                };
            }
            document.functions = functions_copy;
            document.types = types_copy;
            if (issues.items.len != 0) return document;
        }
    }
    return document;
}

fn checkPluginSelection(selected: ?[]const []const u8, configurations: []const plugin.Configuration, target: targets.Target) !void {
    for (configurations, 0..) |entry, i| {
        var known = false;
        inline for (registry.plugins) |registered| if (std.mem.eql(u8, registered.name, entry.name)) {
            known = true;
        };
        for (configurations[0..i]) |previous| if (std.mem.eql(u8, previous.name, entry.name)) return error.DuplicatePluginConfig;
        if (!known) return error.UnknownPluginConfig;
    }
    if (selected) |names_selected| for (names_selected) |name| {
        var known = false;
        inline for (registry.plugins) |registered| if (std.mem.eql(u8, registered.name, name)) {
            known = true;
        };
        if (!known) return error.UnknownPlugin;
    };
    inline for (registry.plugins, 0..) |registered, index| {
        if (registry.runs(index, selected, target)) inline for (registered.requires) |required| {
            inline for (registry.plugins, 0..) |dependency, dependency_index| {
                if (comptime std.mem.eql(u8, dependency.name, required)) {
                    if (!registry.runs(dependency_index, selected, target)) return error.DisabledPluginDependency;
                }
            }
        };
    }
}

pub fn findIssuesWithFacts(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8, configurations: []const plugin.Configuration, facts: *plugin.Facts, target: targets.Target) ![]const diagnostic.Diagnostic {
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    errdefer issues.deinit(allocator);
    for (rules) |check| if (try check(allocator, document, target)) |issue| {
        try issues.append(allocator, issue);
        return issues.toOwnedSlice(allocator);
    };
    try checkPluginSelection(selected, configurations, target);
    inline for (registry.plugins, 0..) |registered, index| {
        if (registry.runs(index, selected, target)) {
            try appendPluginIssuesWithFacts(registered, allocator, document, configurations, &issues, facts, target);
        }
    }
    return issues.toOwnedSlice(allocator);
}

pub fn findIssues(allocator: std.mem.Allocator, document: semantic.Semantic) ![]const diagnostic.Diagnostic {
    return findIssuesWithPlugins(allocator, document, null);
}

fn appendPluginIssues(comptime registered: plugin.Plugin, allocator: std.mem.Allocator, document: semantic.Semantic, configurations: []const plugin.Configuration, issues: *std.ArrayList(diagnostic.Diagnostic)) !void {
    var facts: plugin.Facts = .{};
    return appendPluginIssuesWithFacts(registered, allocator, document, configurations, issues, &facts, targets.default);
}

fn appendPluginIssuesWithFacts(comptime registered: plugin.Plugin, allocator: std.mem.Allocator, document: semantic.Semantic, configurations: []const plugin.Configuration, issues: *std.ArrayList(diagnostic.Diagnostic), facts: *plugin.Facts, target: targets.Target) !void {
    const context: plugin.ValidateContext = .{ .allocator = allocator, .document = document, .configurations = configurations, .diagnostics = issues, .facts = facts, .target = target };
    if (try pluginOptionsIssue(registered, context)) |issue| {
        try issues.append(allocator, issue);
        return;
    }
    _ = plugin.readConfig(registered, allocator, configurations) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try issues.append(allocator, .{ .severity = .@"error", .code = registered.name ++ "001", .message = "invalid plugin build configuration", .site = .{ .path = "build.zig", .declaration = registered.name }, .hint = "provide fields matching the plugin Config type" });
            return;
        },
    };
    if (registered.validate) |check| try check(context);
}

/// A hand-written `semantic.json` can carry anything under a plugin's key.
/// Reading it through the plugin's target-specific option type is what turns that into
/// a `<NAME>001` diagnostic instead of a panic inside a hook.
fn pluginOptionsIssue(comptime registered: plugin.Plugin, context: plugin.ValidateContext) !?diagnostic.Diagnostic {
    const allocator = context.allocator;
    const document = context.document;
    for (document.functions) |function| {
        if (function.ext) |attached| {
            if (attached.get(registered.name) != null and !registered.supports(.function)) {
                const declaration = try site.functionDeclarationAlloc(allocator, function);
                return try pluginOptionsDiagnostic(registered, allocator, site.functionSiteFor(function, declaration), declaration);
            }
            _ = context.optionsOf(registered, .function, function.ext) catch {
                const declaration = try site.functionDeclarationAlloc(allocator, function);
                return try pluginOptionsDiagnostic(registered, allocator, site.functionSiteFor(function, declaration), declaration);
            };
            if (comptime plugin.ref.mentionsRef(plugin.Options(registered, .function))) {
                const declaration = try site.functionDeclarationAlloc(allocator, function);
                if (try refIssue(registered, .function, context, function.ext, site.functionSiteFor(function, declaration), declaration)) |issue| return issue;
            }
        }
        for (function.params, 0..) |parameter, index| {
            if (try nodeOptionsIssue(registered, context, .param, parameter.ext, site.paramSite(function, index))) |issue| return issue;
        }
        if (try nodeOptionsIssue(registered, context, .result, function.result_ext, site.resultSite(function))) |issue| return issue;
    }
    for (document.types) |declaration| {
        if (declaration.ext) |attached| {
            if (attached.get(registered.name) != null and !registered.supports(plugin.typeSubject(declaration.kind)))
                return try pluginOptionsDiagnostic(registered, allocator, site.typeSite(declaration), declaration.name);
            _ = context.optionsOf(registered, .type, declaration.ext) catch {
                return try pluginOptionsDiagnostic(registered, allocator, site.typeSite(declaration), declaration.name);
            };
            if (try refIssue(registered, .type, context, declaration.ext, site.typeSite(declaration), declaration.name)) |issue| return issue;
        }
        // Tags and fields are the same IR node, so which of the two option
        // types reads it is decided by the container's kind alone.
        for (declaration.fields, 0..) |field, index| {
            if (field.ext == null) continue;
            const where = try site.fieldSite(declaration, allocator, index);
            if (declaration.kind == .@"enum") {
                if (try nodeOptionsIssue(registered, context, .enum_tag, field.ext, where)) |issue| return issue;
            } else {
                if (try nodeOptionsIssue(registered, context, .field, field.ext, where)) |issue| return issue;
            }
        }
    }
    return null;
}

/// The same two checks the declaration-level loops make -- a subject the
/// plugin never declared, and options its type cannot read -- for one node
/// inside a declaration. A hand-written `semantic.json` is the only way an
/// `ext` reaches here that `use` did not already refuse.
fn nodeOptionsIssue(
    comptime registered: plugin.Plugin,
    context: plugin.ValidateContext,
    comptime attachment: plugin.Attachment,
    ext: ?semantic.Extensions,
    where: diagnostic.Site,
) !?diagnostic.Diagnostic {
    const attached = ext orelse return null;
    if (attached.get(registered.name) == null) return null;
    if (!registered.supports(plugin.attachmentSubject(attachment).?))
        return try pluginOptionsDiagnostic(registered, context.allocator, where, where.declaration);
    _ = context.optionsOf(registered, attachment, ext) catch {
        return try pluginOptionsDiagnostic(registered, context.allocator, where, where.declaration);
    };
    return refIssue(registered, attachment, context, ext, where, where.declaration);
}

/// Every reference-typed option, on every attachment, checked against the
/// document it was written for. A plugin never resolves its own references to
/// find out whether they resolve at all: the walk is reflective over the
/// option type, so a plugin gains the check by declaring the field.
fn refIssue(
    comptime registered: plugin.Plugin,
    comptime attachment: plugin.Attachment,
    context: plugin.ValidateContext,
    ext: ?semantic.Extensions,
    where: diagnostic.Site,
    declaration: []const u8,
) !?diagnostic.Diagnostic {
    const Options = plugin.Options(registered, attachment);
    if (comptime !plugin.ref.mentionsRef(Options)) return null;
    const read = context.optionsOf(registered, attachment, ext) catch return null;
    const options = read orelse return null;
    const missing = plugin.ref.unresolvedIn(Options, options, context.document) orelse return null;
    return .{
        .severity = .@"error",
        .code = comptime plugin.refCode(registered),
        .message = try std.fmt.allocPrint(
            context.allocator,
            "unresolved {s} reference `{s}` in the `{s}` options of `{s}`",
            .{ @tagName(missing.kind), missing.path, registered.name, declaration },
        ),
        .site = where,
        .hint = "reference a declaration this binding registers: `api.typeRef(...)`, `api.ref(...)`, or the entry `zigo.interface(...)` returned",
    };
}

fn pluginOptionsDiagnostic(
    comptime registered: plugin.Plugin,
    allocator: std.mem.Allocator,
    where: diagnostic.Site,
    declaration: []const u8,
) !diagnostic.Diagnostic {
    return .{
        .severity = .@"error",
        .code = comptime plugin.optionsCode(registered),
        .message = try std.fmt.allocPrint(
            allocator,
            "`{s}` carries options the `{s}` plugin cannot read",
            .{ declaration, registered.name },
        ),
        .site = where,
        .hint = "attach the options with `use`, which checks them against the plugin's option type at the declaration",
    };
}

/// The document itself: an IR version this generator reads and the names it
/// cannot do without.
fn documentHeaderIssue(_: std.mem.Allocator, document: semantic.Semantic, _: targets.Target) !?diagnostic.Diagnostic {
    if (document.ir_version != semantic.current_ir_version) return .{
        .severity = .@"error",
        .code = "ZIGO020",
        .message = "semantic document uses an unsupported IR version",
        .site = .{ .path = "semantic.json", .declaration = "ir_version" },
        .hint = "regenerate semantic.json with a matching zigo version",
    };
    if (document.package.len == 0) return .{
        .severity = .@"error",
        .code = "ZIGO021",
        .message = "semantic document has an empty package name",
        .site = .{ .path = "semantic.json", .declaration = "package" },
        .hint = "give the binding a package name",
    };
    if (document.prefix.len == 0) return .{
        .severity = .@"error",
        .code = "ZIGO021",
        .message = "semantic document has an empty symbol prefix",
        .site = .{ .path = "semantic.json", .declaration = "prefix" },
        .hint = "give the binding a symbol prefix",
    };
    return null;
}

test {
    _ = functions;
    _ = interfaces;
    _ = session;
    _ = materialized;
    _ = types;
    _ = names;
    _ = packages;
    _ = @import("callbacks.zig");
    _ = site;
    _ = ownership;
    _ = @import("snapshot_tests.zig");
}

test "context validators collect independent issues and skip unreadable options" {
    const fake = struct {
        fn all(context: plugin.ValidateContext) !void {
            for ([_][]const u8{ "MULTI002", "MULTI003" }) |code| try context.diagnose(.{ .severity = .@"error", .code = code, .message = "invalid", .site = .{ .path = "semantic.json", .declaration = "sample" }, .hint = "fix" });
        }
    };
    const p: plugin.Plugin = .{ .name = "MULTI", .FunctionOptions = struct { enabled: bool }, .validate = fake.all };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const document: semantic.Semantic = .{ .package = "sample", .prefix = "zg", .zig_version = "0.16.0" };
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    try appendPluginIssues(p, allocator, document, &.{}, &issues);
    try std.testing.expectEqual(@as(usize, 2), issues.items.len);
    try std.testing.expectEqualStrings("MULTI002", issues.items[0].code);
    try std.testing.expectEqualStrings("MULTI003", issues.items[1].code);
    const invalid =
        \\{"package":"sample","prefix":"zg","zig_version":"0.16.0","functions":[{"name":"run","params":[],"return":{"kind":"void"},"symbol":"zg_run","ext":{"MULTI":{"enabled":"bad"}}}]}
    ;
    var parsed = try semantic.Semantic.parse(allocator, invalid);
    defer parsed.deinit();
    issues.clearRetainingCapacity();
    try appendPluginIssues(p, allocator, parsed.value, &.{}, &issues);
    try std.testing.expectEqual(@as(usize, 1), issues.items.len);
    try std.testing.expectEqualStrings("MULTI001", issues.items[0].code);
}

test "driver collects plugin diagnostics but gates them behind core validation" {
    const testing_plugin = @import("../plugins/testing.zig");
    testing_plugin.validation_enabled = true;
    defer testing_plugin.validation_enabled = false;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const valid: semantic.Semantic = .{ .package = "sample", .prefix = "zg", .zig_version = "0.16.0" };
    const issues = try findIssues(allocator, valid);
    try std.testing.expectEqual(@as(usize, 2), issues.len);
    try std.testing.expectEqualStrings("TEST002", issues[0].code);
    try std.testing.expectEqualStrings("TEST003", issues[1].code);
    try std.testing.expectEqualStrings("TEST002", (try findIssue(allocator, valid)).?.code);
    try std.testing.expectEqual(@as(usize, 0), (try findIssuesWithPlugins(allocator, valid, &.{})).len);
    const invalid =
        \\{"package":"sample","prefix":"zg","zig_version":"0.16.0","functions":[{"name":"run","params":[],"return":{"kind":"enum","ref":"Missing"},"symbol":"zg_run"}]}
    ;
    var parsed = try semantic.Semantic.parse(allocator, invalid);
    defer parsed.deinit();
    const structural = try findIssues(allocator, parsed.value);
    try std.testing.expectEqual(@as(usize, 1), structural.len);
    try std.testing.expect(std.mem.startsWith(u8, structural[0].code, "ZIGO"));
}

test "plugin configuration reaches validation and malformed config skips callback" {
    const fake = struct {
        const p: plugin.Plugin = .{ .name = "CONFIG", .Config = struct { enabled: bool = false }, .validate = check };
        fn check(context: plugin.ValidateContext) !void {
            if ((try context.config(p)).enabled) try context.diagnose(.{ .severity = .@"error", .code = "CONFIG002", .message = "enabled", .site = .{ .path = "build.zig", .declaration = "CONFIG" }, .hint = "test" });
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    const document: semantic.Semantic = .{ .package = "sample", .prefix = "zg", .zig_version = "0.16.0" };
    try appendPluginIssues(fake.p, arena.allocator(), document, &.{.{ .name = "CONFIG", .json = "{\"enabled\":true}" }}, &issues);
    try std.testing.expectEqualStrings("CONFIG002", issues.items[0].code);
    issues.clearRetainingCapacity();
    try appendPluginIssues(fake.p, arena.allocator(), document, &.{.{ .name = "CONFIG", .json = "{\"enabled\":7}" }}, &issues);
    try std.testing.expectEqual(@as(usize, 1), issues.items.len);
    try std.testing.expectEqualStrings("CONFIG001", issues.items[0].code);
}

test "options a plugin cannot read are its own diagnostic, not a panic" {
    const fixture =
        \\{"functions":[{"ext":{"TEST":{"mode":"c"}},"name":"bump","params":[],"receiver":"Counter","return":{"kind":"void"},"symbol":"zg_counter_bump"}],"ir_version":1,"package":"meter","prefix":"zg","types":[{"kind":"opaque","name":"Counter"}],"zig_version":"0.16.0"}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parsed = try semantic.Semantic.parse(arena.allocator(), fixture);
    defer parsed.deinit();
    const issue = (try findIssue(arena.allocator(), parsed.value)) orelse return error.MissingDiagnostic;
    // The plugin's own prefix, never a ZIGO code: the fault is the plugin's
    // option type, and the message has to say whose.
    try std.testing.expectEqualStrings("TEST001", issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "`TEST` plugin") != null);
    try std.testing.expectError(error.InvalidSemantic, semanticDocument(std.testing.allocator, parsed.value));
}

test "a reference no declaration answers is the plugin's own 002 diagnostic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // The same document twice: once with the reference the binding would
    // have written, once with a path nothing declares.
    const template =
        \\{"functions":[],"ir_version":1,"package":"meter","prefix":"zg","types":[{"kind":"opaque","name":"Context","zig_path":"meter.Context"},{"ext":{"TEST":{"target":"PATH"}},"kind":"opaque","name":"Counter","zig_path":"meter.Counter"}],"zig_version":"0.16.0"}
    ;
    const resolved = try std.mem.replaceOwned(u8, allocator, template, "PATH", "meter.Context");
    var parsed = try semantic.Semantic.parse(allocator, resolved);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try findIssue(allocator, parsed.value));

    const unresolved = try std.mem.replaceOwned(u8, allocator, template, "PATH", "meter.Gone");
    var missing = try semantic.Semantic.parse(allocator, unresolved);
    defer missing.deinit();
    const issue = (try findIssue(allocator, missing.value)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("TEST002", issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "unresolved type reference `meter.Gone`") != null);
    try std.testing.expectEqualStrings("Counter", issue.site.declaration);
}

test "node options a plugin cannot read or does not subscribe to are diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // Each fixture injects one node-level `ext` a `use` would have refused:
    // three carry a value outside the plugin's option type, and the last
    // names a subject `NARROW` never declared.
    const cases = [_]struct { json: []const u8, declaration: []const u8 }{
        .{ .json =
        \\{"functions":[{"name":"bump","params":[{"ext":{"TEST":{"tag":7}},"name":"by","type":{"bits":32,"kind":"int","signed":true}}],"receiver":"Counter","return":{"kind":"void"},"symbol":"zg_counter_bump"}],"ir_version":1,"package":"meter","prefix":"zg","types":[{"kind":"opaque","name":"Counter"}],"zig_version":"0.16.0"}
        , .declaration = "by" },
        .{ .json =
        \\{"functions":[{"name":"bump","params":[],"receiver":"Counter","result_ext":{"TEST":{}},"return":{"kind":"void"},"symbol":"zg_counter_bump"}],"ir_version":1,"package":"meter","prefix":"zg","types":[{"kind":"opaque","name":"Counter"}],"zig_version":"0.16.0"}
        , .declaration = "bump" },
        .{ .json =
        \\{"functions":[{"name":"bump","params":[],"receiver":"Counter","return":{"kind":"void"},"symbol":"zg_counter_bump"}],"ir_version":1,"package":"meter","prefix":"zg","types":[{"kind":"opaque","name":"Counter"},{"fields":[{"ext":{"TEST":{"tag":false}},"name":"idle","value":0}],"kind":"enum","name":"Mode","tag_type":{"bits":8,"kind":"int","signed":false}}],"zig_version":"0.16.0"}
        , .declaration = "Mode.idle" },
    };
    for (cases) |case| {
        var parsed = try semantic.Semantic.parse(allocator, case.json);
        defer parsed.deinit();
        const issue = (try findIssue(allocator, parsed.value)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("TEST001", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, case.declaration) != null);
    }

    // A plugin that never declared `.field` is refused the options outright,
    // the way a declaration kind outside `subjects` already is.
    const narrow: plugin.Plugin = .{ .name = "NARROW", .FieldOptions = struct { tag: []const u8 }, .subjects = &.{.function} };
    const fixture =
        \\{"functions":[],"ir_version":1,"package":"meter","prefix":"zg","types":[{"fields":[{"ext":{"NARROW":{"tag":"across"}},"name":"x","type":{"bits":32,"kind":"int","signed":true}}],"kind":"value_struct","layout":"extern","name":"Point"}],"zig_version":"0.16.0"}
    ;
    var parsed = try semantic.Semantic.parse(allocator, fixture);
    defer parsed.deinit();
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    try appendPluginIssues(narrow, allocator, parsed.value, &.{}, &issues);
    try std.testing.expectEqual(@as(usize, 1), issues.items.len);
    try std.testing.expectEqualStrings("NARROW001", issues.items[0].code);
    try std.testing.expect(std.mem.indexOf(u8, issues.items[0].message, "Point.x") != null);
}

test "options a plugin can read leave the document valid" {
    const fixture =
        \\{"functions":[{"ext":{"TEST":{"mode":"b"}},"name":"bump","params":[],"receiver":"Counter","return":{"kind":"void"},"symbol":"zg_counter_bump"}],"ir_version":1,"package":"meter","prefix":"zg","types":[{"kind":"opaque","name":"Counter"}],"zig_version":"0.16.0"}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parsed = try semantic.Semantic.parse(arena.allocator(), fixture);
    defer parsed.deinit();
    try std.testing.expect(try findIssue(arena.allocator(), parsed.value) == null);
}

// A plugin that filled no render slot for the resolved target contributes
// nothing to it: not a transform, not a diagnostic, not an output file. That
// is the mechanism that lets `GoContext.writeGoType` and its siblings stay
// Go's while the contract itself stays honest about which language a plugin
// renders. Every plugin the in-tree registry carries fills the `go` slot
// alone, so none of them runs here.
test "a plugin that fills no slot for the target does not run" {
    const rust: targets.Target = .{
        .name = "rust",
        .display_name = "Rust",
        .source_extension = ".rs",
        .generated_suffix = "_gen",
        .test_file_suffix = null,
        .formatter = null,
        .vtable = targets.go.target.vtable,
    };
    const document: semantic.Semantic = .{
        .package = "sample",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .functions = &.{.{ .name = "run", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_run" }},
    };

    inline for (registry.plugins, 0..) |registered, index| {
        try std.testing.expect(!registry.runs(index, null, rust));
        try std.testing.expect(!registered.rendersFor(rust));
        try std.testing.expect(registered.rendersFor(targets.default));
    }

    // With every plugin gated out, plugin validation has nothing to report.
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try pluginIssue(std.testing.allocator, document, null, rust));
}
