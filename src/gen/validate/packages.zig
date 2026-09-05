//! Package metadata: declared sub-packages and the cycles between them.
const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const naming = @import("naming");
const site = @import("site.zig");
const validate = @import("validate.zig");

pub fn packageMetadataIssue(_: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    const packages = document.packages orelse return null;
    for (packages, 0..) |package, index| {
        if (!naming.isGoIdentifier(package.name) or !semantic.validPackagePath(package.path)) return .{
            .severity = .@"error",
            .code = "ZIGO031",
            .message = "semantic document contains an invalid public package declaration",
            .site = .{ .path = "semantic.json", .declaration = package.name },
            .hint = "use a unique Go identifier and a portable relative package path",
        };
        for (packages[0..index]) |previous| if (std.mem.eql(u8, previous.name, package.name) or std.mem.eql(u8, previous.path, package.path)) return .{
            .severity = .@"error",
            .code = "ZIGO031",
            .message = "semantic document contains duplicate public packages",
            .site = .{ .path = "semantic.json", .declaration = package.name },
            .hint = "give every public package a unique name and path",
        };
    }
    for (document.types) |declaration| if (declaration.package) |name| if (!hasPackage(packages, name)) return unknownPackage(name);
    for (document.functions) |function| if (function.package) |name| {
        if (!hasPackage(packages, name)) return unknownPackage(name);
        const owner = function.receiver orelse function.goOwner() orelse continue;
        for (document.types) |declaration| if (std.mem.eql(u8, declaration.name, owner)) {
            if (!semantic.optionalStringEqual(declaration.package, function.package)) return .{
                .severity = .@"error",
                .code = "ZIGO031",
                .message = "a function is split from its owning type",
                .site = site.functionSite(function),
                .hint = "assign a type and all of its methods, constructors, destructor, and projections to the same package",
            };
        };
    };
    return null;
}

fn hasPackage(packages: []const semantic.Package, name: []const u8) bool {
    for (packages) |package| if (std.mem.eql(u8, package.name, name)) return true;
    return false;
}

fn unknownPackage(name: []const u8) diagnostic.Diagnostic {
    return .{
        .severity = .@"error",
        .code = "ZIGO031",
        .message = "declaration references an unknown public package",
        .site = .{ .path = "semantic.json", .declaration = name },
        .hint = "add the package to `packages`, or omit the declaration's `package` field",
    };
}

pub fn packageCycleIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    const packages = document.packages orelse return null;
    const count = packages.len + 1;
    const edges = try allocator.alloc(?[]const u8, count * count);
    @memset(edges, null);
    for (document.functions) |function| {
        const from = packageIndex(packages, function.package);
        for (function.params) |parameter| addTypeEdges(document, packages, edges, count, from, parameter.type, function.name);
        addTypeEdges(document, packages, edges, count, from, function.@"return", function.name);
    }
    for (document.types) |declaration| {
        const from = packageIndex(packages, declaration.package);
        if (declaration.tag_type) |node| addTypeEdges(document, packages, edges, count, from, node, declaration.name);
        for (declaration.fields) |field| if (field.type) |node| addTypeEdges(document, packages, edges, count, from, node, declaration.name);
    }
    const state = try allocator.alloc(u8, count);
    @memset(state, 0);
    const stack = try allocator.alloc(usize, count);
    for (0..count) |index| if (state[index] == 0) if (try visitPackage(allocator, packages, edges, count, state, stack, 0, index)) |issue| return issue;
    return null;
}

fn visitPackage(allocator: std.mem.Allocator, packages: []const semantic.Package, edges: []const ?[]const u8, count: usize, state: []u8, stack: []usize, depth: usize, current: usize) !?diagnostic.Diagnostic {
    state[current] = 1;
    stack[depth] = current;
    for (0..count) |next| {
        const declaration = edges[current * count + next] orelse continue;
        if (state[next] == 1) {
            var start: usize = 0;
            while (stack[start] != next) : (start += 1) {}
            var path: std.Io.Writer.Allocating = .init(allocator);
            for (stack[start .. depth + 1], 0..) |item, offset| {
                if (offset != 0) try path.writer.writeAll(" -> ");
                try path.writer.writeAll(packageName(packages, item));
            }
            try path.writer.print(" -> {s}", .{packageName(packages, next)});
            return .{
                .severity = .@"error",
                .code = "ZIGO032",
                .message = try std.fmt.allocPrint(allocator, "public package import cycle involves declaration `{s}`", .{declaration}),
                .site = .{ .path = "semantic.json", .declaration = declaration },
                .hint = try std.fmt.allocPrint(allocator, "move the declarations so the package graph is acyclic: {s}", .{path.written()}),
            };
        }
        if (state[next] == 0) if (try visitPackage(allocator, packages, edges, count, state, stack, depth + 1, next)) |issue| return issue;
    }
    state[current] = 2;
    return null;
}

fn packageIndex(packages: []const semantic.Package, package: ?[]const u8) usize {
    const name = package orelse return 0;
    for (packages, 0..) |entry, index| if (std.mem.eql(u8, entry.name, name)) return index + 1;
    return 0;
}

fn packageName(packages: []const semantic.Package, index: usize) []const u8 {
    return if (index == 0) "default" else packages[index - 1].name;
}

fn addTypeEdges(document: semantic.Semantic, packages: []const semantic.Package, edges: []?[]const u8, count: usize, from: usize, node: semantic.TypeNode, declaration: []const u8) void {
    switch (node) {
        .@"enum" => |value| addNamedEdge(document, packages, edges, count, from, value.ref, declaration),
        .opaque_ptr => |value| addNamedEdge(document, packages, edges, count, from, value.ref, declaration),
        .materialized => |value| addNamedEdge(document, packages, edges, count, from, value.ref, declaration),
        .value_struct => |value| addNamedEdge(document, packages, edges, count, from, value.ref, declaration),
        .slice => |value| addTypeEdges(document, packages, edges, count, from, value.element.*, declaration),
        .optional => |value| addTypeEdges(document, packages, edges, count, from, value.child.*, declaration),
        .error_union => |value| addTypeEdges(document, packages, edges, count, from, value.payload.*, declaration),
        .callback => |value| {
            for (value.params) |parameter| addTypeEdges(document, packages, edges, count, from, parameter, declaration);
            addTypeEdges(document, packages, edges, count, from, value.@"return".*, declaration);
        },
        else => {},
    }
}

fn addNamedEdge(document: semantic.Semantic, packages: []const semantic.Package, edges: []?[]const u8, count: usize, from: usize, name: []const u8, declaration: []const u8) void {
    for (document.types) |type_decl| if (std.mem.eql(u8, type_decl.name, name)) {
        const to = packageIndex(packages, type_decl.package);
        if (from != to) edges[from * count + to] = declaration;
        return;
    };
}

test "cross-package type cycles are diagnosed with the package path" {
    const a_ref = semantic.TypeNode{ .value_struct = .{ .ref = "A" } };
    const b_ref = semantic.TypeNode{ .value_struct = .{ .ref = "B" } };
    const document: semantic.Semantic = .{
        .package = "cycle",
        .packages = &.{
            .{ .name = "a", .path = "a" },
            .{ .name = "b", .path = "b" },
        },
        .prefix = "zg",
        .types = &.{
            .{ .fields = &.{.{ .name = "b", .type = b_ref }}, .kind = .value_struct, .name = "A", .package = "a" },
            .{ .fields = &.{.{ .name = "a", .type = a_ref }}, .kind = .value_struct, .name = "B", .package = "b" },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const issue = (try validate.findIssue(arena.allocator(), document)).?;
    const rendered = try issue.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        "error[ZIGO032]: public package import cycle involves declaration `B`\n" ++
            "  --> semantic.json (B)\n" ++
            "  hint: move the declarations so the package graph is acyclic: a -> b -> a\n",
        rendered,
    );
}
