//! Rename registered IR types as one operation, preserving native Zig paths.
//! This changes generated type identities (including ABI names), not layouts.
const std = @import("std");
const semantic = @import("semantic");
pub const Rename = struct { from: []const u8, to: []const u8 };

pub fn types(allocator: std.mem.Allocator, input: semantic.Semantic, changes: []const Rename) !semantic.Semantic {
    if (changes.len == 0) return input;
    const rewriter: Rewriter = .{ .allocator = allocator, .changes = changes };
    var result = input;
    const declarations = try allocator.dupe(semantic.TypeDecl, input.types);
    for (declarations) |*decl| {
        decl.native_name = decl.native_name orelse decl.name;
        decl.name = rewriter.name(decl.name);
        const fields = try allocator.dupe(semantic.TypeField, decl.fields);
        for (fields) |*field| if (field.type) |node| {
            field.type = try rewriter.node(node);
        };
        decl.fields = fields;
        if (decl.tag_type) |node| decl.tag_type = try rewriter.node(node);
        if (decl.backing_type) |node| decl.backing_type = try rewriter.node(node);
    }
    result.types = declarations;
    const functions = try allocator.dupe(semantic.SemanticFn, input.functions);
    for (functions) |*function| {
        function.zig_path = try semantic.zigCallPathAlloc(allocator, function.*);
        function.receiver = rewriter.optionalName(function.receiver);
        function.namespace = rewriter.optionalName(function.namespace);
        function.setGoOwner(rewriter.optionalName(function.goOwnerOverride()));
        function.@"return" = try rewriter.node(function.@"return");
        const params = try allocator.dupe(semantic.Parameter, function.params);
        for (params) |*param| {
            param.type = try rewriter.node(param.type);
            if (param.flatten) |original| {
                const fields = try allocator.dupe(semantic.FlattenedField, original);
                for (fields) |*field| field.type = try rewriter.node(field.type);
                param.flatten = fields;
            }
        }
        function.params = params;
    }
    result.functions = functions;
    const constructors = try allocator.dupe(semantic.Constructor, input.constructors);
    for (constructors) |*constructor| constructor.type = rewriter.name(constructor.type);
    result.constructors = constructors;
    if (input.interfaces) |original| {
        const interfaces = try allocator.dupe(semantic.Interface, original);
        for (interfaces) |*interface| {
            const names = try allocator.dupe([]const u8, interface.types);
            for (names) |*name| name.* = rewriter.name(name.*);
            interface.types = names;
        }
        result.interfaces = interfaces;
    }
    return result;
}

const Rewriter = struct {
    allocator: std.mem.Allocator,
    changes: []const Rename,
    fn name(self: Rewriter, input: []const u8) []const u8 {
        for (self.changes) |change| if (std.mem.eql(u8, change.from, input)) return change.to;
        return input;
    }
    fn optionalName(self: Rewriter, input: ?[]const u8) ?[]const u8 {
        return if (input) |value| self.name(value) else null;
    }
    fn pointer(self: Rewriter, input: *semantic.TypeNode) error{OutOfMemory}!*semantic.TypeNode {
        const result = try self.allocator.create(semantic.TypeNode);
        result.* = try self.node(input.*);
        return result;
    }
    fn node(self: Rewriter, input: semantic.TypeNode) error{OutOfMemory}!semantic.TypeNode {
        var result = input;
        switch (result) {
            .@"enum", .value_struct => |*ref| ref.ref = self.name(ref.ref),
            .opaque_ptr => |*ref| ref.ref = self.name(ref.ref),
            .materialized => |*ref| ref.ref = self.name(ref.ref),
            .slice => |*value| value.element = try self.pointer(value.element),
            .optional => |*value| value.child = try self.pointer(value.child),
            .atomic_ptr => |*value| value.child = try self.pointer(value.child),
            .error_union => |*value| value.payload = try self.pointer(value.payload),
            .callback => |*value| {
                value.ref = self.optionalName(value.ref);
                value.@"return" = try self.pointer(value.@"return");
                const params = try self.allocator.dupe(semantic.TypeNode, value.params);
                for (params) |*param| param.* = try self.node(param.*);
                value.params = params;
            },
            .bool, .cancel_flag, .float, .int, .io_stream, .void => {},
        }
        return result;
    }
};
