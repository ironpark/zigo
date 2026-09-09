//! Validation of a semantic document: the public entry points and the
//! ordered rule list that decides which diagnostic a faulty document gets.
const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const lower = @import("lower");
const functions = @import("functions.zig");
const callbacks = @import("callbacks.zig");
const interfaces = @import("interfaces.zig");
const materialized = @import("materialized.zig");
const names = @import("names.zig");
const plugin = @import("plugin");
const registry = @import("../plugins/registry.zig");
const ownership = @import("ownership.zig");
const packages = @import("packages.zig");
const site = @import("site.zig");
const types = @import("types.zig");

/// Every rejection reaches the user as a rendered diagnostic, so this only
/// reports whether the document had one. Callers that want the text call
/// `findIssue` themselves; the scratch arena here owns the strings that
/// diagnostic built.
pub fn semanticDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !void {
    return semanticDocumentWithPlugins(allocator, document, null);
}

/// Validate core rules and only the selected external plugins; null selects all.
pub fn semanticDocumentWithPlugins(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    if (try findIssueWithPlugins(scratch.allocator(), document, selected) != null) return error.InvalidSemantic;
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
const Rule = *const fn (std.mem.Allocator, semantic.Semantic) anyerror!?diagnostic.Diagnostic;

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
    return findIssueWithPlugins(allocator, document, null);
}

/// Built-in rules always run, including when the external selection is empty.
pub fn findIssueWithPlugins(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8) !?diagnostic.Diagnostic {
    for (rules) |check| if (try check(allocator, document)) |issue| return issue;
    // Plugins judge last, so a plugin rule can never mask a document fault
    // the generator itself would have rejected.
    return pluginIssue(allocator, document, selected);
}

/// Every registered plugin, in registration order: first its options are
/// checked against the type it declared for them, then whatever rule it
/// wrote of its own.
fn pluginIssue(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8) !?diagnostic.Diagnostic {
    inline for (registry.plugins, 0..) |registered, index| {
        if (registry.runs(index, selected)) {
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

pub fn findIssuesConfigured(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8, configurations: []const plugin.Configuration) ![]const diagnostic.Diagnostic {
    var facts: plugin.Facts = .{};
    return findIssuesWithFacts(allocator, document, selected, configurations, &facts);
}

/// Shared entry point for generation and reports. The caller owns the arena,
/// diagnostics and facts. A document with diagnostics must not be lowered.
pub fn prepareDocument(allocator: std.mem.Allocator, input: semantic.Semantic, selected: ?[]const []const u8, configurations: []const plugin.Configuration, facts: *plugin.Facts, issues: *std.ArrayList(diagnostic.Diagnostic)) !semantic.Semantic {
    const document = try transformDocument(allocator, input, selected, configurations, issues);
    if (issues.items.len != 0) return document;
    try issues.appendSlice(allocator, try findIssuesWithFacts(allocator, document, selected, configurations, facts));
    return document;
}

/// Parse establishes the IR shape; transforms may repair or remove declarations
/// that core rules would reject. Only the final document reaches core rules,
/// validation facts and lowering. Every hook runs in registry dependency order.
pub fn transformDocument(allocator: std.mem.Allocator, input: semantic.Semantic, selected: ?[]const []const u8, configurations: []const plugin.Configuration, issues: *std.ArrayList(diagnostic.Diagnostic)) !semantic.Semantic {
    try checkPluginSelection(selected, configurations);
    inline for (registry.plugins, 0..) |registered, index| {
        if (registry.runs(index, selected)) {
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
        if (registered.transform) |hook| if (registry.runs(index, selected)) {
            document = try hook(.{ .allocator = allocator, .document = document, .configurations = configurations, .diagnostics = issues });
            if (issues.items.len != 0) return document;
        };
    }
    inline for (registry.plugins, 0..) |registered, index| {
        if (registered.name_type) |hook| if (registry.runs(index, selected)) {
            const context: plugin.TransformContext = .{ .allocator = allocator, .document = document, .configurations = configurations, .diagnostics = issues };
            var changes: std.ArrayList(plugin.rename.Rename) = .empty;
            for (document.types) |declaration| {
                if (registered.supports(plugin.typeTarget(declaration.kind))) {
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
        if (registry.runs(index, selected) and (registered.map_type != null or registered.name_function != null)) {
            const context: plugin.TransformContext = .{ .allocator = allocator, .document = document, .configurations = configurations, .diagnostics = issues };
            const functions_copy = try allocator.dupe(semantic.SemanticFn, document.functions);
            const types_copy = try allocator.dupe(semantic.TypeDecl, document.types);
            if (registered.map_type) |hook| {
                for (types_copy) |*declaration| {
                    if (registered.supports(plugin.typeTarget(declaration.kind))) {
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
                    if (try hook(context, function.*)) |name| function.setGoName(name);
                };
            }
            document.functions = functions_copy;
            document.types = types_copy;
            if (issues.items.len != 0) return document;
        }
    }
    return document;
}

fn checkPluginSelection(selected: ?[]const []const u8, configurations: []const plugin.Configuration) !void {
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
        if (registry.runs(index, selected)) inline for (registered.requires) |required| {
            inline for (registry.plugins, 0..) |dependency, dependency_index| {
                if (comptime std.mem.eql(u8, dependency.name, required)) {
                    if (!registry.runs(dependency_index, selected)) return error.DisabledPluginDependency;
                }
            }
        };
    }
}

pub fn findIssuesWithFacts(allocator: std.mem.Allocator, document: semantic.Semantic, selected: ?[]const []const u8, configurations: []const plugin.Configuration, facts: *plugin.Facts) ![]const diagnostic.Diagnostic {
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    errdefer issues.deinit(allocator);
    for (rules) |check| if (try check(allocator, document)) |issue| {
        try issues.append(allocator, issue);
        return issues.toOwnedSlice(allocator);
    };
    try checkPluginSelection(selected, configurations);
    inline for (registry.plugins, 0..) |registered, index| {
        if (registry.runs(index, selected)) {
            try appendPluginIssuesWithFacts(registered, allocator, document, configurations, &issues, facts);
        }
    }
    return issues.toOwnedSlice(allocator);
}

pub fn findIssues(allocator: std.mem.Allocator, document: semantic.Semantic) ![]const diagnostic.Diagnostic {
    return findIssuesWithPlugins(allocator, document, null);
}

fn appendPluginIssues(comptime registered: plugin.Plugin, allocator: std.mem.Allocator, document: semantic.Semantic, configurations: []const plugin.Configuration, issues: *std.ArrayList(diagnostic.Diagnostic)) !void {
    var facts: plugin.Facts = .{};
    return appendPluginIssuesWithFacts(registered, allocator, document, configurations, issues, &facts);
}

fn appendPluginIssuesWithFacts(comptime registered: plugin.Plugin, allocator: std.mem.Allocator, document: semantic.Semantic, configurations: []const plugin.Configuration, issues: *std.ArrayList(diagnostic.Diagnostic), facts: *plugin.Facts) !void {
    if (try pluginOptionsIssue(registered, allocator, document)) |issue| {
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
    if (registered.validate) |check| try check(.{ .allocator = allocator, .document = document, .configurations = configurations, .diagnostics = issues, .facts = facts });
}

/// A hand-written `semantic.json` can carry anything under a plugin's key.
/// Reading it through the plugin's target-specific option type is what turns that into
/// a `<NAME>001` diagnostic instead of a panic inside a hook.
fn pluginOptionsIssue(
    comptime registered: plugin.Plugin,
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
) !?diagnostic.Diagnostic {
    for (document.functions) |function| {
        if (function.ext == null) continue;
        if (function.ext.?.get(registered.name) != null and !registered.supports(.function)) {
            const declaration = try site.functionDeclarationAlloc(allocator, function);
            return try pluginOptionsDiagnostic(registered, allocator, site.functionSiteFor(function, declaration), declaration);
        }
        _ = plugin.readOptions(registered, .function, allocator, function.ext) catch {
            const declaration = try site.functionDeclarationAlloc(allocator, function);
            return try pluginOptionsDiagnostic(registered, allocator, site.functionSiteFor(function, declaration), declaration);
        };
    }
    for (document.types) |declaration| {
        if (declaration.ext == null) continue;
        if (declaration.ext.?.get(registered.name) != null and !registered.supports(plugin.typeTarget(declaration.kind)))
            return try pluginOptionsDiagnostic(registered, allocator, .{ .path = "semantic.json", .declaration = declaration.name }, declaration.name);
        _ = plugin.readOptions(registered, .type, allocator, declaration.ext) catch {
            return try pluginOptionsDiagnostic(
                registered,
                allocator,
                .{ .path = "semantic.json", .declaration = declaration.name },
                declaration.name,
            );
        };
    }
    return null;
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
fn documentHeaderIssue(_: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
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
