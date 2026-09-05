//! Declared Go interfaces: the names, the types they list and the methods
//! those types have to expose. Whether the methods agree on one Go signature
//! is judged after lowering, on the rendered signature, by generation.
const std = @import("std");
const diagnostic = @import("diagnostic");
const lower = @import("lower");
const naming = @import("naming");
const semantic = @import("semantic");
const types = @import("types.zig");
const validate = @import("validate.zig");

pub fn interfaceIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    const interfaces = document.interfaces orelse return null;
    for (interfaces, 0..) |interface, index| {
        if (!naming.isGoIdentifier(interface.name)) return issue(interface, "interface name is not a Go identifier", "give the interface a `.name` that is a valid exported Go identifier");
        if (try collisionIssue(allocator, document, interfaces[0..index], interface)) |found| return found;
        if (interface.types.len == 0) return issue(interface, "interface lists no types", "list at least one registered opaque type in `.types`");
        if (interface.methods.len == 0) return issue(interface, "interface lists no methods", "list at least one Zig method name in `.methods`");
        for (interface.types, 0..) |type_name, type_index| {
            if (!types.hasTypeKind(document, type_name, .@"opaque")) return try issueFmt(allocator, interface, "interface lists `{s}`, which is not a registered opaque handle", .{type_name}, "list only types registered with `.repr = .opaque`");
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
            if (lower.constructorForType(document.constructors, type_name) == null)
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
        if (lower.constructorForType(document.constructors, type_name)) |constructor| {
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
        const function_name = try semantic.publicFunctionNameAlloc(allocator, document, function);
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

test "an interface over two constructed handles with shared methods is accepted" {
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(scratch.allocator(), batchDocument(.{})));
}

/// Two `Batch` handles with `len`, constructors and a destructor. The
/// overrides let each test break exactly one rule.
pub const BatchOverrides = struct {
    /// Passed as a literal so the slice outlives the call.
    interfaces: ?[]const semantic.Interface = null,
    extra_types: []const semantic.TypeDecl = &.{},
    packages: ?[]const semantic.Package = null,
    constructors: ?[]const semantic.Constructor = null,
    functions: ?[]const semantic.SemanticFn = null,
};

pub fn batchDocument(overrides: BatchOverrides) semantic.Semantic {
    return .{
        .constructors = overrides.constructors orelse &.{
            .{ .deinit = "deinit", .init = "create", .type = "IntBatch" },
            .{ .deinit = "deinit", .init = "create", .type = "FloatBatch" },
        },
        .functions = overrides.functions orelse &batch_functions,
        .interfaces = overrides.interfaces orelse &batch_interface,
        .package = "batches",
        .packages = overrides.packages,
        .prefix = "zg",
        .types = if (overrides.extra_types.len == 0) &batch_types else overrides.extra_types,
        .zig_version = "0.16.0",
    };
}

const batch_interface = [_]semantic.Interface{.{ .methods = &.{"len"}, .name = "Batch", .types = &.{ "IntBatch", "FloatBatch" } }};

const batch_types = [_]semantic.TypeDecl{
    .{ .kind = .@"opaque", .name = "IntBatch" },
    .{ .kind = .@"opaque", .name = "FloatBatch" },
};

var int_batch: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "IntBatch" } };
var float_batch: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "FloatBatch" } };
const count: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
pub const batch_functions = [_]semantic.SemanticFn{
    .{ .name = "create", .namespace = "IntBatch", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &int_batch } }, .symbol = "zg_int_batch_create" },
    .{ .name = "len", .receiver = "IntBatch", .params = &.{}, .@"return" = count, .symbol = "zg_int_batch_len" },
    .{ .name = "deinit", .receiver = "IntBatch", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_int_batch_deinit" },
    .{ .name = "create", .namespace = "FloatBatch", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &float_batch } }, .symbol = "zg_float_batch_create" },
    .{ .name = "len", .receiver = "FloatBatch", .params = &.{}, .@"return" = count, .symbol = "zg_float_batch_len" },
    .{ .name = "deinit", .receiver = "FloatBatch", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_float_batch_deinit" },
};
