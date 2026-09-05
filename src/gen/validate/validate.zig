//! Validation of a semantic document: the public entry points and the
//! ordered rule list that decides which diagnostic a faulty document gets.
const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const lower = @import("lower");
const functions = @import("functions.zig");
const materialized = @import("materialized.zig");
const names = @import("names.zig");
const ownership = @import("ownership.zig");
const packages = @import("packages.zig");
const site = @import("site.zig");
const types = @import("types.zig");

/// Every rejection reaches the user as a rendered diagnostic, so this only
/// reports whether the document had one. Callers that want the text call
/// `findIssue` themselves; the scratch arena here owns the strings that
/// diagnostic built.
pub fn semanticDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    if (try findIssue(scratch.allocator(), document) != null) return error.InvalidSemantic;
}

pub fn mustVariantNames(allocator: std.mem.Allocator, document: semantic.Semantic) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    if (try findMustVariantIssue(scratch.allocator(), document) != null) return error.InvalidSemantic;
}

pub fn findMustVariantIssue(allocator: std.mem.Allocator, source_document: semantic.Semantic) !?diagnostic.Diagnostic {
    // The generator decides Must variants on the promoted functions, so the
    // collision check looks at the same shapes it will emit.
    var document = source_document;
    document.functions = try lower.promoteCheckedFunctions(allocator, source_document, source_document.functions);
    defer allocator.free(document.functions);
    // Every pair of functions compares public names, so they are spelled once.
    const public_names = try allocator.alloc([]const u8, document.functions.len);
    defer allocator.free(public_names);
    for (document.functions, public_names) |function, *name| name.* = try semantic.publicFunctionNameAlloc(allocator, document, function);
    defer for (public_names) |name| allocator.free(name);
    for (document.functions, public_names) |function, public_name| {
        if (!try lower.mustVariant(allocator, document, function)) continue;
        const must_name = try std.fmt.allocPrint(allocator, "Must{s}", .{public_name});
        defer allocator.free(must_name);
        if (function.receiver == null) for (document.types) |declaration| {
            if (!semantic.optionalStringEqual(declaration.package, function.package)) continue;
            if (!std.mem.eql(u8, declaration.name, must_name)) continue;
            const function_path = try site.functionDeclarationAlloc(allocator, function);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}` collides between type `{s}` and generated Must variant for `{s}`",
                    .{ must_name, declaration.zig_path orelse declaration.name, function_path },
                ),
                .site = site.functionSiteFor(function, function_path),
                .hint = "rename the function or conflicting type so the generated Must name is unique",
            };
        };
        for (document.functions, public_names) |other, other_name| {
            // The destructor of a constructor pair never reaches the public
            // API on its own -- generation emits a shared `zigoRelease` -- so
            // it takes no public Go name and drops out of the collision check.
            if (lower.constructorForDeinit(document.constructors, other) != null) continue;
            if (!std.mem.eql(u8, function.receiver orelse "", other.receiver orelse "")) continue;
            if (!semantic.optionalStringEqual(function.package, other.package)) continue;
            if (!std.mem.eql(u8, must_name, other_name)) continue;
            const function_path = try site.functionDeclarationAlloc(allocator, function);
            const other_path = try site.functionDeclarationAlloc(allocator, other);
            defer allocator.free(other_path);
            return .{
                .severity = .@"error",
                .code = "ZIGO024",
                .message = try std.fmt.allocPrint(
                    allocator,
                    "public Go name `{s}` collides between `{s}` and generated Must variant for `{s}`",
                    .{ must_name, other_path, function_path },
                ),
                .site = site.functionSiteFor(function, function_path),
                .hint = "rename one declaration so the generated Must name is unique",
            };
        }
    }
    return null;
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
            if (result == .void) continue;
            if (result == .int and result.int.signed and result.int.bits == 32) continue;
            return .{
                .severity = .@"error",
                .code = "ZIGO014",
                .message = "purego callback result must be void or a signed 32-bit integer",
                .site = site.functionSite(function),
                .hint = "return `void` or `i32` from the callback, or report the value through userdata",
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
};

pub fn findIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (rules) |check| if (try check(allocator, document)) |issue| return issue;
    return null;
}

/// The document itself: an IR version this generator reads and the names it
/// cannot do without.
fn documentHeaderIssue(_: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    if (document.ir_version != 1) return .{
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

test "generated Must names participate in ZIGO024 collision checks" {
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "ping",
                .params = &.{},
                .receiver = "Handle",
                .@"return" = .{ .void = {} },
                .symbol = "zg_handle_ping",
            },
            .{
                .name = "mustPing",
                .params = &.{},
                .receiver = "Handle",
                .@"return" = .{ .void = {} },
                .symbol = "zg_handle_must_ping",
            },
        },
        .package = "collision",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Handle" }},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const issue = (try findMustVariantIssue(arena.allocator(), document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO024", issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "MustPing") != null);
    try std.testing.expectError(error.InvalidSemantic, mustVariantNames(std.testing.allocator, document));
}

test "a callback signature flagged go_error elsewhere gives a free function a Must variant" {
    var status: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true, .is_usize = false } };
    const observer: semantic.TypeNode = .{ .callback = .{ .has_userdata = true, .params = &.{}, .@"return" = &status } };
    const usize_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .signed = false, .is_usize = true } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "run",
                .params = &.{
                    .{ .name = "observer", .type = observer },
                    .{ .name = "userdata", .type = usize_node },
                },
                .@"return" = .{ .void = {} },
                .symbol = "zg_run",
            },
            .{
                .name = "watch",
                .params = &.{
                    .{ .go_error = true, .name = "observer", .type = observer },
                    .{ .name = "userdata", .type = usize_node },
                },
                .@"return" = .{ .void = {} },
                .symbol = "zg_watch",
            },
            .{ .name = "mustRun", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_must_run" },
        },
        .package = "collision",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const issue = (try findMustVariantIssue(arena.allocator(), document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO024", issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "MustRun") != null);
}

test {
    _ = functions;
    _ = materialized;
    _ = types;
    _ = names;
    _ = packages;
    _ = @import("callbacks.zig");
    _ = site;
    _ = ownership;
    _ = @import("snapshot_tests.zig");
}
