//! Package selection, ownership assignment and transitive type closure.
const std = @import("std");
const naming = @import("naming");
const semantic = @import("semantic");
const Pairing = @import("pairing.zig").Pairing;

pub fn reflectPackages(
    allocator: std.mem.Allocator,
    comptime declaration: anytype,
    types: []semantic.TypeDecl,
    functions: []semantic.SemanticFn,
    pairings: []const Pairing,
) ![]const semantic.Package {
    if (!@hasField(@TypeOf(declaration), "packages")) return &.{};
    var packages: std.ArrayList(semantic.Package) = .empty;
    inline for (declaration.packages) |entry| {
        const name = if (@hasField(@TypeOf(entry), "name")) entry.name else blk: {
            const base = std.fs.path.basename(entry.path);
            break :blk try naming.snakeAlloc(allocator, base);
        };
        if (!semantic.validPackagePath(entry.path)) return packageIssue("invalid package path `{s}`", .{entry.path});
        if (!naming.isGoIdentifier(name)) return packageIssue("package name `{s}` is not a valid Go identifier", .{name});
        for (packages.items) |previous| {
            if (std.mem.eql(u8, previous.path, entry.path)) return packageIssue("duplicate package path `{s}`", .{entry.path});
            if (std.mem.eql(u8, previous.name, name)) return packageIssue("duplicate package name `{s}`", .{name});
        }
        try packages.append(allocator, .{
            .doc = if (@hasField(@TypeOf(entry), "doc")) entry.doc else null,
            .name = name,
            .path = entry.path,
        });
    }

    // Exact type names are resolved globally before any pattern. This makes an
    // exact assignment win even when the package carrying a matching pattern
    // appears first in the declaration.
    inline for (declaration.packages, 0..) |entry, package_index| {
        if (@hasField(@TypeOf(entry), "types")) inline for (entry.types) |selector| {
            if (comptime isPrefixPattern(selector)) continue;
            var found = false;
            for (types) |*type_decl| if (std.mem.eql(u8, type_decl.name, selector)) {
                if (type_decl.package != null) return packageIssue("type `{s}` is assigned to more than one package", .{selector});
                type_decl.package = packages.items[package_index].name;
                found = true;
            };
            if (!found) return packageIssue("package type selector `{s}` names no declaration", .{selector});
        };
    }

    // A type pattern uses longest-prefix precedence. Equal matching patterns
    // in different packages are ambiguous rather than declaration-order wins.
    for (types) |*type_decl| {
        if (type_decl.package != null) continue;
        var best_package: ?usize = null;
        var best_length: usize = 0;
        inline for (declaration.packages, 0..) |entry, package_index| {
            if (@hasField(@TypeOf(entry), "types")) inline for (entry.types) |selector| {
                if (comptime !isPrefixPattern(selector)) continue;
                const prefix = patternPrefix(selector);
                if (std.mem.startsWith(u8, type_decl.name, prefix)) {
                    if (best_package != null and prefix.len == best_length and best_package.? != package_index)
                        return packageIssue("type `{s}` is selected by patterns in more than one package", .{type_decl.name});
                    if (best_package == null or prefix.len > best_length) {
                        best_package = package_index;
                        best_length = prefix.len;
                    }
                }
            };
        }
        if (best_package) |package_index| type_decl.package = packages.items[package_index].name;
    }
    inline for (declaration.packages) |entry| {
        if (@hasField(@TypeOf(entry), "types")) inline for (entry.types) |selector| {
            if (comptime !isPrefixPattern(selector)) continue;
            var found = false;
            for (types) |type_decl| if (std.mem.startsWith(u8, type_decl.name, patternPrefix(selector))) {
                found = true;
            };
            if (!found) return packagePatternIssue("type", selector);
        };
    }

    // An explicitly listed function outranks both exact namespace selectors
    // and namespace patterns.
    inline for (declaration.packages, 0..) |entry, package_index| {
        if (@hasField(@TypeOf(entry), "functions")) inline for (entry.functions) |selector| {
            var found = false;
            for (functions) |*function| if (functionMatchesSelector(function.*, selector)) {
                const owned = function.receiver orelse function.goOwner();
                if (owned) |owner| if (semantic.typeDecl(types, owner)) |owner_decl| if (owner_decl.package) |owner_package| {
                    if (!std.mem.eql(u8, owner_package, packages.items[package_index].name))
                        return packageIssue("function `{s}` cannot be split from owning type `{s}`", .{ selector, owner });
                };
                if (function.package != null) return packageIssue("function `{s}` is assigned to more than one package", .{selector});
                function.package = packages.items[package_index].name;
                found = true;
            };
            if (!found) return packageIssue("package function selector `{s}` names no declaration", .{selector});
        };
    }

    // Exact namespaces retain their existing longest-prefix behavior. Pattern
    // selectors are considered only when no exact namespace selected a
    // function, then use the same longest-prefix rule.
    for (functions) |*function| {
        if (function.package != null or function.namespace == null) continue;
        var best_package: ?usize = null;
        var best_length: usize = 0;
        inline for (declaration.packages, 0..) |entry, package_index| {
            if (@hasField(@TypeOf(entry), "namespaces")) inline for (entry.namespaces) |selector| {
                if (comptime isPrefixPattern(selector)) continue;
                if (namespaceMatches(function.namespace.?, selector)) {
                    if (best_package != null and selector.len == best_length and best_package.? != package_index)
                        return packageIssue("namespace `{s}` is assigned to more than one package", .{selector});
                    if (best_package == null or selector.len > best_length) {
                        best_package = package_index;
                        best_length = selector.len;
                    }
                }
            };
        }
        if (best_package) |package_index| function.package = packages.items[package_index].name;
    }
    for (functions) |*function| {
        if (function.package != null or function.namespace == null) continue;
        var best_package: ?usize = null;
        var best_length: usize = 0;
        inline for (declaration.packages, 0..) |entry, package_index| {
            if (@hasField(@TypeOf(entry), "namespaces")) inline for (entry.namespaces) |selector| {
                if (comptime !isPrefixPattern(selector)) continue;
                const prefix = patternPrefix(selector);
                if (std.mem.startsWith(u8, function.namespace.?, prefix)) {
                    if (best_package != null and prefix.len == best_length and best_package.? != package_index)
                        return packageIssue("namespace `{s}` is selected by patterns in more than one package", .{function.namespace.?});
                    if (best_package == null or prefix.len > best_length) {
                        best_package = package_index;
                        best_length = prefix.len;
                    }
                }
            };
        }
        if (best_package) |package_index| function.package = packages.items[package_index].name;
    }
    inline for (declaration.packages) |entry| {
        if (@hasField(@TypeOf(entry), "namespaces")) inline for (entry.namespaces) |selector| {
            if (comptime !isPrefixPattern(selector)) continue;
            var found = false;
            for (functions) |function| if (function.namespace) |namespace| {
                if (std.mem.startsWith(u8, namespace, patternPrefix(selector))) found = true;
            };
            if (!found) return packagePatternIssue("namespace", selector);
        };
    }

    // Methods and generated accessors follow an already assigned owner before
    // closure roots are collected.
    try assignOwnerPackages(types, functions);

    // Compute every closure against the same explicit/pattern assignment
    // snapshot. Only after all candidates are known do we mutate the types.
    const closure_count = declaration.packages.len;
    const reachability = try allocator.alloc(bool, closure_count * types.len);
    defer allocator.free(reachability);
    @memset(reachability, false);
    inline for (declaration.packages, 0..) |entry, package_index| {
        if (@hasField(@TypeOf(entry), "closure") and entry.closure) {
            const row = reachability[package_index * types.len ..][0..types.len];
            findPackageClosure(types, functions, pairings, packages.items[package_index].name, row);
        }
    }
    for (types, 0..) |*type_decl, type_index| {
        if (type_decl.package != null) continue;
        var owner: ?usize = null;
        inline for (declaration.packages, 0..) |entry, package_index| {
            if (@hasField(@TypeOf(entry), "closure") and entry.closure and reachability[package_index * types.len + type_index]) {
                if (owner) |previous| return packageClosureIssue(type_decl.name, packages.items[previous].name, packages.items[package_index].name);
                owner = package_index;
            }
        }
        if (owner) |package_index| type_decl.package = packages.items[package_index].name;
    }

    // Types added by closure bring their methods with them just like an exact
    // or pattern assignment.
    try assignOwnerPackages(types, functions);
    return packages.toOwnedSlice(allocator);
}

/// A method belongs wherever its owning type ended up; an explicit `package`
/// that disagrees is a declaration error rather than a split.
fn assignOwnerPackages(types: []semantic.TypeDecl, functions: []semantic.SemanticFn) !void {
    for (functions) |*function| {
        if (function.receiver orelse function.goOwner()) |owner| if (semantic.typeDecl(types, owner)) |owner_decl| if (owner_decl.package) |owner_package| {
            if (function.package) |explicit| if (!std.mem.eql(u8, explicit, owner_package))
                return packageIssue("function `{s}` cannot be split from owning type `{s}`", .{ function.name, owner });
            function.package = owner_package;
        };
    }
}

fn isPrefixPattern(selector: []const u8) bool {
    return selector.len != 0 and selector[selector.len - 1] == '*';
}

fn patternPrefix(selector: []const u8) []const u8 {
    return selector[0 .. selector.len - 1];
}

fn packagePatternIssue(kind: []const u8, selector: []const u8) error{PackageDeclaration} {
    if (!@import("builtin").is_test) std.debug.print(
        "error[ZIGO041]: package {s} pattern `{s}` matches no declaration\n" ++
            "  hint: trailing `*` matches a declaration-name prefix; remove or correct a pattern that selects nothing\n",
        .{ kind, selector },
    );
    return error.PackageDeclaration;
}

fn packageClosureIssue(type_name: []const u8, first: []const u8, second: []const u8) error{PackageDeclaration} {
    if (!@import("builtin").is_test) std.debug.print(
        "error[ZIGO042]: type `{s}` is reachable from closure packages `{s}` and `{s}`\n" ++
            "  hint: assign the type explicitly to one package, or remove one closure root\n",
        .{ type_name, first, second },
    );
    return error.PackageDeclaration;
}

fn findPackageClosure(
    types: []const semantic.TypeDecl,
    functions: []const semantic.SemanticFn,
    pairings: []const Pairing,
    package_name: []const u8,
    reachable: []bool,
) void {
    for (types, 0..) |type_decl, index| {
        if (type_decl.package) |assigned| {
            if (std.mem.eql(u8, assigned, package_name)) reachable[index] = true;
        }
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (functions, 0..) |function, function_index| {
            var visit = if (function.package) |assigned| std.mem.eql(u8, assigned, package_name) else false;
            if (!visit) {
                if (function.receiver) |owner| visit = reachableType(types, reachable, owner);
                if (!visit) {
                    if (function.goOwner()) |owner| visit = reachableType(types, reachable, owner);
                }
            }
            if (!visit) continue;
            if (function.receiver) |owner| changed = markClosureType(types, reachable, package_name, owner) or changed;
            if (function.goOwner()) |owner| changed = markClosureType(types, reachable, package_name, owner) or changed;
            for (function.params) |parameter| changed = markClosureNode(types, reachable, package_name, parameter.type) or changed;
            changed = markClosureNode(types, reachable, package_name, function.@"return") or changed;
            for (pairings) |pairing| if (pairing.index == function_index) {
                changed = markClosureType(types, reachable, package_name, pairing.type) or changed;
            };
        }
        for (types, 0..) |type_decl, index| {
            if (!reachable[index]) continue;
            if (type_decl.backing_type) |node| changed = markClosureNode(types, reachable, package_name, node) or changed;
            if (type_decl.tag_type) |node| changed = markClosureNode(types, reachable, package_name, node) or changed;
            for (type_decl.fields) |field| if (field.type) |node| {
                changed = markClosureNode(types, reachable, package_name, node) or changed;
            };
        }
    }
}

fn reachableType(types: []const semantic.TypeDecl, reachable: []const bool, name: []const u8) bool {
    for (types, 0..) |type_decl, index| if (std.mem.eql(u8, type_decl.name, name)) return reachable[index];
    return false;
}

fn markClosureType(types: []const semantic.TypeDecl, reachable: []bool, package_name: []const u8, name: []const u8) bool {
    for (types, 0..) |type_decl, index| {
        if (!std.mem.eql(u8, type_decl.name, name)) continue;
        if (type_decl.package) |assigned| if (!std.mem.eql(u8, assigned, package_name)) return false;
        if (reachable[index]) return false;
        reachable[index] = true;
        return true;
    }
    return false;
}

fn markClosureNode(types: []const semantic.TypeDecl, reachable: []bool, package_name: []const u8, node: semantic.TypeNode) bool {
    return switch (node) {
        .@"enum" => |value| markClosureType(types, reachable, package_name, value.ref),
        .opaque_ptr => |value| markClosureType(types, reachable, package_name, value.ref),
        .materialized => |value| markClosureType(types, reachable, package_name, value.ref),
        .value_struct => |value| markClosureType(types, reachable, package_name, value.ref),
        .slice => |value| markClosureNode(types, reachable, package_name, value.element.*),
        .optional => |value| markClosureNode(types, reachable, package_name, value.child.*),
        .error_union => |value| markClosureNode(types, reachable, package_name, value.payload.*),
        .callback => |value| blk: {
            var changed = if (value.ref) |name| markClosureType(types, reachable, package_name, name) else false;
            for (value.params) |parameter| changed = markClosureNode(types, reachable, package_name, parameter) or changed;
            changed = markClosureNode(types, reachable, package_name, value.@"return".*) or changed;
            break :blk changed;
        },
        else => false,
    };
}

fn packageIssue(comptime detail: []const u8, args: anytype) error{PackageDeclaration} {
    if (!@import("builtin").is_test) std.debug.print("error[ZIGO031]: " ++ detail ++ "\n  hint: each `.packages` entry must uniquely select existing declarations and keep owned functions with their type\n", args);
    return error.PackageDeclaration;
}

fn namespaceMatches(namespace: []const u8, prefix: []const u8) bool {
    return std.mem.eql(u8, namespace, prefix) or (std.mem.startsWith(u8, namespace, prefix) and namespace.len > prefix.len and namespace[prefix.len] == '.');
}

fn functionMatchesSelector(function: semantic.SemanticFn, selector: []const u8) bool {
    if (function.zig_path) |path| if (std.mem.eql(u8, path, selector)) return true;
    if (function.receiver orelse function.namespace) |owner| {
        if (selector.len == owner.len + function.name.len + 1 and std.mem.startsWith(u8, selector, owner) and selector[owner.len] == '.' and std.mem.endsWith(u8, selector, function.name)) return true;
        if (selector.len == owner.len + function.name.len + 6 and std.mem.startsWith(u8, selector, "root.") and std.mem.endsWith(u8, selector, function.name)) return true;
        return false;
    }
    return (std.mem.eql(u8, selector, function.name) or (std.mem.startsWith(u8, selector, "root.") and std.mem.eql(u8, selector[5..], function.name)));
}
