//! Return ownership: borrowed views, caller-owned handles and release targets.
const std = @import("std");
const diagnostic = @import("diagnostic");
const lower = @import("lower");
const semantic = @import("semantic");
const site = @import("site.zig");
const types = @import("types.zig");
const validate = @import("validate.zig");

/// The registered opaque type behind a borrowed result. Optional pointers are
/// represented by `opaque_ptr.nullable`; error unions wrap the same node.
pub fn borrowedOpaqueReturn(document: semantic.Semantic, function: semantic.SemanticFn) ?[]const u8 {
    const payload = function.@"return".errorPayload();
    if (payload != .opaque_ptr or !types.hasTypeKind(document, payload.opaque_ptr.ref, .@"opaque")) return null;
    return payload.opaque_ptr.ref;
}

/// Whether a `.returns = .caller` result can become an owned Go handle. Only a
/// pointer to a type the binding constructs has a `newX` helper to wrap it and a
/// destructor for the cleanup to call; anything else would emit a raw pointer
/// against a typed signature, which does not compile. The rule is the one
/// lowering records as a `handle`.
pub fn ownedReturnIsWrappable(document: semantic.Semantic, function: semantic.SemanticFn) bool {
    return lower.ownedOpaqueReturn(document.constructors, function) != null;
}

/// The count a `.written = .return` parameter reads back from. An error union
/// reports it through its payload; the error path writes zero instead.
pub fn returnsCount(node: semantic.TypeNode) bool {
    const payload = if (node == .error_union) node.error_union.payload.* else node;
    return payload == .int and payload.int.is_usize;
}

/// A slice return is the one non-handle result zigo can hand over: generated Go
/// copies it and then calls the declared release function. A fallible slice
/// return hands over the same buffer, so `![]T` qualifies on the same terms.
pub fn isReleasableSliceReturn(function: semantic.SemanticFn) bool {
    return lower.releasableSliceReturnElement(function) != null;
}

/// The release target must exist and take exactly the returned slice, otherwise
/// the generated free call would pass a pointer the library cannot interpret.
pub fn releaseTargetIssue(document: semantic.Semantic, function: semantic.SemanticFn) ?diagnostic.Diagnostic {
    const missing: diagnostic.Diagnostic = .{
        .severity = .@"error",
        .code = "ZIGO016",
        .message = "caller-owned slice return has no matching release function",
        .site = site.functionSite(function),
        .hint = "add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type",
    };
    const target = lower.releaseTarget(document.functions, function.release orelse return missing) orelse return missing;
    const parameter = target.parameter;
    if (parameter.direction != .in or parameter.type != .slice) return missing;
    if (!typeNodeEqual(parameter.type.slice.element.*, lower.releasableSliceReturnElement(function).?)) return missing;
    return null;
}

fn typeNodeEqual(lhs: semantic.TypeNode, rhs: semantic.TypeNode) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .void, .bool => true,
        .int => |value| value.bits == rhs.int.bits and value.signed == rhs.int.signed and value.is_usize == rhs.int.is_usize,
        .float => |value| value.bits == rhs.float.bits,
        .@"enum" => |value| std.mem.eql(u8, value.ref, rhs.@"enum".ref),
        .materialized => |value| value.pointer == rhs.materialized.pointer and value.nullable == rhs.materialized.nullable and std.mem.eql(u8, value.ref, rhs.materialized.ref),
        .value_struct => |value| std.mem.eql(u8, value.ref, rhs.value_struct.ref),
        .slice => |value| value.@"const" == rhs.slice.@"const" and typeNodeEqual(value.element.*, rhs.slice.element.*),
        else => false,
    };
}

pub fn hasConstructorInit(document: semantic.Semantic, constructor: semantic.Constructor) bool {
    for (document.functions) |function| {
        if (!std.mem.eql(u8, function.name, constructor.init) or
            !std.mem.eql(u8, function.goOwner() orelse "", constructor.type)) continue;
        if (function.ownership != .caller or function.@"return" != .error_union) return false;
        const payload = function.@"return".error_union.payload.*;
        if (payload != .opaque_ptr) return false;
        return !payload.opaque_ptr.nullable and std.mem.eql(u8, payload.opaque_ptr.ref, constructor.type);
    }
    return false;
}

pub fn hasConstructorDeinit(document: semantic.Semantic, constructor: semantic.Constructor) bool {
    for (document.functions) |function| {
        if (!std.mem.eql(u8, function.name, constructor.deinit) or
            !std.mem.eql(u8, function.receiver orelse "", constructor.type)) continue;
        // An injected parameter is not part of the C signature, so a
        // destructor that takes the allocator back is still a destructor.
        for (function.params) |parameter| if (parameter.injected == null) return false;
        return function.@"return" == .void;
    }
    return false;
}

test "a release target may take the allocator zigo injects" {
    var byte_element: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const document: semantic.Semantic = .{
        .allocator = "std.heap.smp_allocator",
        .functions = &.{
            .{
                .name = "render",
                .ownership = .caller,
                .params = &.{},
                .release = "freeString",
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &byte_element } },
                .symbol = "zg_render",
            },
            .{
                .name = "freeString",
                .params = &.{
                    .{ .injected = .allocator, .name = "allocator", .type = .{ .void = {} } },
                    .{ .name = "str", .type = .{ .slice = .{ .@"const" = true, .element = &byte_element } } },
                },
                .@"return" = .{ .void = {} },
                .symbol = "zg_free_string",
            },
        },
        .package = "render",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(scratch.allocator(), document));
}

test "caller-owned optional slices use the underlying slice release contract" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var bytes: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    var c_string: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte, .sentinel = 0 } };
    var optional_bytes: semantic.TypeNode = .{ .optional = .{ .child = &bytes } };
    var optional_c_string: semantic.TypeNode = .{ .optional = .{ .child = &c_string } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "takeBytes",
                .ownership = .caller,
                .params = &.{},
                .release = "freeBytes",
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &optional_bytes } },
                .symbol = "zg_take_bytes",
            },
            .{
                .name = "takeCString",
                .ownership = .caller,
                .params = &.{},
                .release = "freeCString",
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &optional_c_string } },
                .return_semantic = .c_string,
                .symbol = "zg_take_c_string",
            },
            .{
                .name = "freeBytes",
                .params = &.{.{ .name = "value", .type = bytes }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_free_bytes",
            },
            .{
                .name = "freeCString",
                .params = &.{.{ .name = "value", .type = c_string }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_free_c_string",
            },
        },
        .package = "good",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try validate.semanticDocument(std.testing.allocator, document);
}

test "a written hint is accepted on an out slice of a counting function" {
    var element: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var count: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    const slice: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &element } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "fill",
                .params = &.{.{ .direction = .out, .name = "dst", .type = slice, .written = .@"return" }},
                .@"return" = count,
                .symbol = "zg_fill",
            },
            .{
                .name = "fillChecked",
                .params = &.{.{ .direction = .out, .name = "dst", .type = slice, .written = .@"return" }},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &count } },
                .symbol = "zg_fill_checked",
            },
            .{
                .name = "fillAll",
                .params = &.{.{ .direction = .out, .name = "dst", .type = slice }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_fill_all",
            },
        },
        .package = "written",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(std.testing.allocator, document));
}
