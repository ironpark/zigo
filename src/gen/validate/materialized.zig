//! Materialized result trees: their field rules and their buffer release.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const lower = @import("lower");
const semantic = @import("semantic");
const site = @import("site.zig");
const types = @import("types.zig");
const validate = @import("validate.zig");

pub fn materializedReleaseIssue(_: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.functions) |function| if ((abi.materializedReturn(function.@"return") != null or abi.materializedOut(function) != null) and
        (function.ownership != .caller or function.release == null)) return .{
        .severity = .@"error",
        .code = "ZIGO048",
        .message = "materialized result has no caller-owned buffer release",
        .site = site.functionSite(function),
        .hint = "set `.returns = .caller` and `.release` to an exposed function that frees `[]u8` with the registered allocator",
    };
    return null;
}

pub fn materializedOutCount(function: semantic.SemanticFn) usize {
    var count: usize = 0;
    for (function.params) |parameter| count += @intFromBool(abi.materializedOutParameter(parameter) != null);
    return count;
}

pub fn materializedReleaseTargetIssue(document: semantic.Semantic, function: semantic.SemanticFn) ?diagnostic.Diagnostic {
    const missing: diagnostic.Diagnostic = .{
        .severity = .@"error",
        .code = "ZIGO048",
        .message = "materialized result has no matching buffer release function",
        .site = site.functionSite(function),
        .hint = "name an exposed `fn([]u8) void` release function that frees the serialized buffer with the registered allocator",
    };
    const target = lower.releaseTarget(document.functions, function.release orelse return missing) orelse return missing;
    const parameter = target.parameter;
    if (parameter.type != .slice or parameter.type.slice.element.* != .int or
        parameter.type.slice.element.int.bits != 8 or parameter.type.slice.element.int.signed) return missing;
    return null;
}

pub fn isMaterializedReleaseTarget(document: semantic.Semantic, candidate: semantic.SemanticFn) bool {
    for (document.functions) |function| {
        if ((abi.materializedReturn(function.@"return") != null or abi.materializedOut(function) != null) and function.release != null and
            std.mem.eql(u8, function.release.?, candidate.name)) return true;
    }
    return false;
}

pub fn containsMaterialized(node: semantic.TypeNode) bool {
    return switch (node) {
        .materialized => true,
        .slice => |value| containsMaterialized(value.element.*),
        .optional => |value| containsMaterialized(value.child.*),
        .error_union => |value| containsMaterialized(value.payload.*),
        .callback => |value| blk: {
            for (value.params) |parameter| if (containsMaterialized(parameter)) break :blk true;
            break :blk containsMaterialized(value.@"return".*);
        },
        else => false,
    };
}

const MaterializedProblem = struct { path: []const u8, reason: []const u8 };

pub fn materializedProblemAlloc(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    root: semantic.TypeDecl,
) !?MaterializedProblem {
    var ancestors: [128][]const u8 = undefined;
    ancestors[0] = root.name;
    for (root.fields) |field| {
        const node = field.type orelse return .{
            .path = try allocator.dupe(u8, field.name),
            .reason = "give every materialized field a reflected type",
        };
        if (try materializedNodeProblemAlloc(allocator, document, node, field.name, &ancestors, 1, false)) |problem| return problem;
    }
    return null;
}

fn materializedNodeProblemAlloc(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    node: semantic.TypeNode,
    path: []const u8,
    ancestors: *[128][]const u8,
    depth: usize,
    in_slice: bool,
) !?MaterializedProblem {
    switch (node) {
        .bool => return null,
        .int => |value| if (types.integerSupported(value)) return null,
        .float => |value| if (types.floatSupported(value)) return null,
        .@"enum" => return null,
        .slice => |value| {
            const element = value.element.*;
            if (element == .slice) {
                const inner = element.slice.element.*;
                if (inner == .int and inner.int.bits == 8 and !inner.int.signed) return null;
                return .{ .path = try allocator.dupe(u8, path), .reason = "slices may contain scalars, strings, or materialized structs" };
            }
            return materializedNodeProblemAlloc(allocator, document, element, path, ancestors, depth, true);
        },
        .materialized => |value| {
            if (in_slice and value.pointer) return .{ .path = try allocator.dupe(u8, path), .reason = "slices may contain materialized struct values, not pointers" };
            for (ancestors[0..depth]) |ancestor| if (std.mem.eql(u8, ancestor, value.ref)) return .{
                .path = try allocator.dupe(u8, path),
                .reason = "materialized trees cannot contain cycles",
            };
            const declaration = semantic.typeDecl(document.types, value.ref) orelse return .{
                .path = try allocator.dupe(u8, path),
                .reason = "register the referenced struct with `.repr = .materialized`",
            };
            if (declaration.kind != .materialized or depth == ancestors.len) return .{
                .path = try allocator.dupe(u8, path),
                .reason = "register the referenced struct with `.repr = .materialized`",
            };
            ancestors[depth] = value.ref;
            for (declaration.fields) |field| {
                const child_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ path, field.name });
                const child = field.type orelse return .{ .path = child_path, .reason = "give every materialized field a reflected type" };
                if (try materializedNodeProblemAlloc(allocator, document, child, child_path, ancestors, depth + 1, false)) |problem| return problem;
            }
            return null;
        },
        else => {},
    }
    return .{
        .path = try allocator.dupe(u8, path),
        .reason = "use scalars, bool, registered enums, strings, supported slices, or materialized structs and pointers",
    };
}

test "materialized validation reports nested unsupported field paths and cycles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var callback_return: semantic.TypeNode = .{ .void = {} };
    const callback: semantic.TypeNode = .{ .callback = .{ .has_userdata = false, .params = &.{}, .@"return" = &callback_return } };
    const bad_leaf = semantic.TypeDecl{
        .fields = &.{.{ .name = "visit", .type = callback }},
        .kind = .materialized,
        .name = "Leaf",
    };
    const leaf_node: semantic.TypeNode = .{ .materialized = .{ .ref = "Leaf", .pointer = true } };
    const root = semantic.TypeDecl{
        .fields = &.{.{ .name = "child", .type = leaf_node }},
        .kind = .materialized,
        .name = "Root",
    };
    const bad_document: semantic.Semantic = .{
        .package = "tree",
        .prefix = "zg",
        .types = &.{ root, bad_leaf },
        .zig_version = "0.16.0",
    };
    const unsupported = (try validate.findIssue(allocator, bad_document)).?;
    try std.testing.expectEqualStrings("ZIGO048", unsupported.code);
    try std.testing.expect(std.mem.indexOf(u8, unsupported.message, "child.visit") != null);

    const root_node: semantic.TypeNode = .{ .materialized = .{ .ref = "Root", .pointer = true, .nullable = true } };
    const cyclic_leaf = semantic.TypeDecl{
        .fields = &.{.{ .name = "parent", .type = root_node }},
        .kind = .materialized,
        .name = "Leaf",
    };
    const cyclic_document: semantic.Semantic = .{
        .package = "tree",
        .prefix = "zg",
        .types = &.{ root, cyclic_leaf },
        .zig_version = "0.16.0",
    };
    const cycle = (try validate.findIssue(allocator, cyclic_document)).?;
    try std.testing.expectEqualStrings("ZIGO048", cycle.code);
    try std.testing.expect(std.mem.indexOf(u8, cycle.message, "child.parent") != null);
}

test "a materialized release target may take the allocator zigo injects" {
    // ZIGO048 resolves the release function through the same rule ZIGO016
    // does, so an injected allocator is invisible to both.
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const bytes: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    const fields = [_]semantic.TypeField{.{ .name = "value", .type = .{ .int = .{ .bits = 32, .signed = true } } }};
    const document: semantic.Semantic = .{
        .allocator = "std.heap.smp_allocator",
        .functions = &.{
            .{ .name = "snapshot", .ownership = .caller, .params = &.{}, .release = "release", .@"return" = .{ .materialized = .{ .ref = "Node" } }, .symbol = "zg_snapshot" },
            .{
                .name = "release",
                .params = &.{
                    .{ .injected = .allocator, .name = "allocator", .type = .{ .void = {} } },
                    .{ .name = "buffer", .type = bytes },
                },
                .@"return" = .{ .void = {} },
                .symbol = "zg_release",
            },
        },
        .package = "tree",
        .prefix = "zg",
        .types = &.{.{ .fields = &fields, .kind = .materialized, .materialized_version = 1, .name = "Node", .zig_path = "Node" }},
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(std.testing.allocator, document));
}
