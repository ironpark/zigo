const std = @import("std");
const diagnostic = @import("diagnostic");
const naming = @import("naming");
const semantic = @import("semantic");
const targets = @import("targets");

/// `targets.default`, not a threaded target: the plugin contract still
/// declares its interfaces in Go's terms (`GoFile`, `GoPackage`,
/// `writeGoType`), so parameterizing this check would promise something the
/// contract cannot keep. Making the contract target-generic is its own plan.
pub fn interfaceIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    const interfaces = document.interfaces orelse return null;
    for (interfaces, 0..) |interface, index| {
        if (!targets.default.isIdentifier(interface.name)) return issue(interface, "interface name is not a Go identifier", "give the interface a `.name` that is a valid exported Go identifier");
        if (try collisionIssue(allocator, document, interfaces[0..index], interface)) |found| return found;
        if (interface.types.len == 0) return issue(interface, "interface lists no types", "list at least one registered opaque type in `.types`");
        if (interface.methods.len == 0) return issue(interface, "interface lists no methods", "list at least one Zig method name in `.methods`");
        for (interface.types, 0..) |type_name, type_index| {
            if ((semantic.typeDecl(document.types, type_name) orelse return try issueFmt(allocator, interface, "interface lists `{s}`, which is not a registered handle", .{type_name}, "list only types registered with `.handle`")).kind != .@"opaque") return try issueFmt(allocator, interface, "interface lists `{s}`, which is not a registered handle", .{type_name}, "list only types registered with `.handle`");
            for (interface.types[0..type_index]) |previous| if (std.mem.eql(u8, previous, type_name))
                return try issueFmt(allocator, interface, "interface lists `{s}` twice", .{type_name}, "list each implementing type once");
        }
        for (interface.methods, 0..) |method, method_index| {
            for (interface.methods[0..method_index]) |previous| if (std.mem.eql(u8, previous, method))
                return try issueFmt(allocator, interface, "interface lists method `{s}` twice", .{method}, "list each method once");
            for (interface.types) |type_name| {
                if (methodOf(document, type_name, method) == null)
                    return try issueFmt(allocator, interface, "type `{s}` has no exposed method `{s}`", .{ type_name, method }, "expose the method on every listed type, or drop it from `.methods`");
            }
        }
        if (interface.closer) for (interface.types) |type_name| {
            if (semantic.constructorForType(document.constructors, type_name) == null)
                return try issueFmt(allocator, interface, "interface includes io.Closer but `{s}` has no constructor pair", .{type_name}, "pair the type with a constructor and destructor, or set `.closer = false`");
        };
        if (document.packages != null) for (interface.types) |type_name| {
            if (!semantic.optionalStringEqual((semantic.typeDecl(document.types, type_name) orelse continue).package, interface.package))
                return try issueFmt(allocator, interface, "interface and `{s}` are in different public packages", .{type_name}, "assign the interface's types to one package");
        };
    }
    return null;
}

/// The exposed method `name` of `type_name`, when it has one. Constructors
/// and destructors are functions too, but an interface is about what a live
/// handle can do, so the destructor is not a method here.
pub fn methodOf(document: semantic.Semantic, type_name: []const u8, name: []const u8) ?semantic.SemanticFn {
    for (document.functions) |function| {
        const receiver = function.receiver orelse continue;
        if (!std.mem.eql(u8, receiver, type_name) or !std.mem.eql(u8, function.name, name)) continue;
        if (semantic.constructorForType(document.constructors, type_name)) |constructor| {
            if (std.mem.eql(u8, constructor.deinit, name)) return null;
        }
        return function;
    }
    return null;
}

/// An interface name reaches Go as a `type` declaration in its package, so
/// it collides with the same things a registered type name does.
fn collisionIssue(allocator: std.mem.Allocator, document: semantic.Semantic, previous: []const semantic.Interface, interface: semantic.Interface) !?diagnostic.Diagnostic {
    for (previous) |other| {
        if (!std.mem.eql(u8, other.name, interface.name) or !semantic.optionalStringEqual(other.package, interface.package)) continue;
        return try collision(allocator, interface, "two interfaces");
    }
    for (document.types) |declaration| {
        if (!std.mem.eql(u8, declaration.name, interface.name) or !semantic.optionalStringEqual(declaration.package, interface.package)) continue;
        return try collision(allocator, interface, try std.fmt.allocPrint(allocator, "interface `{s}` and type `{s}`", .{ interface.name, declaration.zig_path orelse declaration.name }));
    }
    for (document.functions) |function| {
        if (function.receiver != null or !semantic.optionalStringEqual(function.package, interface.package)) continue;
        const function_name = try targets.default.publicFunctionNameAlloc(allocator, document, function);
        defer allocator.free(function_name);
        if (!std.mem.eql(u8, function_name, interface.name)) continue;
        return try collision(allocator, interface, try std.fmt.allocPrint(allocator, "interface `{s}` and function `{s}`", .{ interface.name, function.name }));
    }
    return null;
}

fn collision(allocator: std.mem.Allocator, interface: semantic.Interface, between: []const u8) !diagnostic.Diagnostic {
    return .{
        .severity = .@"error",
        .code = "ZIGO024",
        .message = try std.fmt.allocPrint(allocator, "public Go name `{s}` collides between {s}", .{ interface.name, between }),
        .site = .{ .path = "semantic.json", .declaration = interface.name },
        .hint = "give the interface a `.name` that resolves to a different Go identifier",
    };
}

fn issue(interface: semantic.Interface, message: []const u8, hint: []const u8) diagnostic.Diagnostic {
    return .{
        .severity = .@"error",
        .code = "ZIGO049",
        .message = message,
        .site = .{ .path = "semantic.json", .declaration = interface.name },
        .hint = hint,
    };
}

fn issueFmt(allocator: std.mem.Allocator, interface: semantic.Interface, comptime format: []const u8, args: anytype, hint: []const u8) !diagnostic.Diagnostic {
    return issue(interface, try std.fmt.allocPrint(allocator, format, args), hint);
}
