const std = @import("std");
const semantic = @import("semantic");

pub const ChangeKind = enum { breaking, added, compatible };
pub const Change = struct {
    kind: ChangeKind,
    subject: []const u8,
    detail: []const u8,
};

pub const Report = struct {
    changes: std.ArrayList(Change) = .empty,

    pub fn deinit(self: *Report, allocator: std.mem.Allocator) void {
        for (self.changes.items) |change| {
            allocator.free(change.subject);
            allocator.free(change.detail);
        }
        self.changes.deinit(allocator);
    }

    pub fn hasBreaking(self: Report) bool {
        for (self.changes.items) |change| if (change.kind == .breaking) return true;
        return false;
    }

    pub fn renderText(self: Report, writer: *std.Io.Writer) !void {
        for (self.changes.items) |change| {
            const label = switch (change.kind) {
                .breaking => "BREAKING",
                .added => "ADDED",
                .compatible => "ABI COMPATIBLE",
            };
            try writer.print("{s}: {s}: {s}\n", .{ label, change.subject, change.detail });
        }
    }

    pub fn renderJson(self: Report, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
        const rendered = try std.json.Stringify.valueAlloc(allocator, .{ .changes = self.changes.items }, .{ .whitespace = .indent_2 });
        defer allocator.free(rendered);
        try writer.writeAll(rendered);
        try writer.writeByte('\n');
    }
};

pub fn diff(allocator: std.mem.Allocator, base: semantic.Semantic, current: semantic.Semantic) !Report {
    var report: Report = .{};
    errdefer report.deinit(allocator);

    for (base.functions) |old| {
        const new = findFunction(current.functions, old) orelse {
            const identity = try functionIdentity(allocator, old);
            defer allocator.free(identity);
            try add(allocator, &report, .breaking, identity, "function removed");
            continue;
        };
        const identity = try functionIdentity(allocator, old);
        defer allocator.free(identity);
        if (!signatureEqual(old, new)) try add(allocator, &report, .breaking, identity, "signature changed");
        if (old.ownership != new.ownership or !optionalHintEqual(old.return_semantic, new.return_semantic))
            try add(allocator, &report, .breaking, identity, "return ownership or semantics changed");
        if (!retentionEqual(old.params, new.params))
            try add(allocator, &report, .breaking, identity, "parameter retention changed");
        try compareErrors(allocator, &report, identity, old.@"return", new.@"return");
    }
    for (current.functions) |new| if (findFunction(base.functions, new) == null) {
        const identity = try functionIdentity(allocator, new);
        defer allocator.free(identity);
        try add(allocator, &report, .added, identity, "function added");
    };

    for (base.types) |old| {
        const new = findType(current.types, old.name) orelse {
            try add(allocator, &report, .breaking, old.name, "type removed");
            continue;
        };
        if (!typeDeclEqual(old, new)) try add(allocator, &report, .breaking, old.name, "type definition changed");
    }
    for (current.types) |new| if (findType(base.types, new.name) == null)
        try add(allocator, &report, .added, new.name, "type added");

    return report;
}

fn add(allocator: std.mem.Allocator, report: *Report, kind: ChangeKind, subject: []const u8, detail: []const u8) !void {
    try report.changes.append(allocator, .{
        .kind = kind,
        .subject = try allocator.dupe(u8, subject),
        .detail = try allocator.dupe(u8, detail),
    });
}

fn findFunction(functions: []const semantic.SemanticFn, wanted: semantic.SemanticFn) ?semantic.SemanticFn {
    for (functions) |function| {
        if (std.mem.eql(u8, function.name, wanted.name) and
            optionalStringEqual(function.receiver, wanted.receiver) and
            optionalStringEqual(function.namespace, wanted.namespace)) return function;
    }
    return null;
}

fn functionIdentity(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]u8 {
    const owner = function.receiver orelse function.namespace;
    return if (owner) |value|
        std.fmt.allocPrint(allocator, "{s}.{s}", .{ value, function.name })
    else
        allocator.dupe(u8, function.name);
}

fn signatureEqual(lhs: semantic.SemanticFn, rhs: semantic.SemanticFn) bool {
    if (lhs.params.len != rhs.params.len or !typeEqual(lhs.@"return", rhs.@"return")) return false;
    for (lhs.params, rhs.params) |a, b| {
        if (a.direction != b.direction or !typeEqual(a.type, b.type)) return false;
    }
    return true;
}

fn retentionEqual(lhs: []const semantic.Parameter, rhs: []const semantic.Parameter) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |a, b| if (a.retention != b.retention) return false;
    return true;
}

fn compareErrors(allocator: std.mem.Allocator, report: *Report, subject: []const u8, old_node: semantic.TypeNode, new_node: semantic.TypeNode) !void {
    if (old_node != .error_union or new_node != .error_union) return;
    const old = old_node.error_union.error_set;
    const new = new_node.error_union.error_set;
    if (new.len < old.len) {
        try add(allocator, report, .breaking, subject, "error removed or error code reassigned");
        return;
    }
    for (old, 0..) |name, index| {
        if (!std.mem.eql(u8, name, new[index])) {
            try add(allocator, report, .breaking, subject, "error removed or error code reassigned");
            return;
        }
    }
    if (new.len > old.len) try add(allocator, report, .compatible, subject, "error appended");
}

fn typeDeclEqual(lhs: semantic.TypeDecl, rhs: semantic.TypeDecl) bool {
    if (lhs.kind != rhs.kind or lhs.layout != rhs.layout or lhs.exhaustive != rhs.exhaustive or lhs.fields.len != rhs.fields.len) return false;
    if ((lhs.tag_type == null) != (rhs.tag_type == null)) return false;
    if (lhs.tag_type) |tag| if (!typeEqual(tag, rhs.tag_type.?)) return false;
    for (lhs.fields, rhs.fields) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or a.value != b.value or (a.type == null) != (b.type == null)) return false;
        if (a.type) |node| if (!typeEqual(node, b.type.?)) return false;
    }
    return true;
}

fn typeEqual(lhs: semantic.TypeNode, rhs: semantic.TypeNode) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .void, .bool => true,
        .int => |a| a.bits == rhs.int.bits and a.signed == rhs.int.signed and a.is_usize == rhs.int.is_usize,
        .float => |a| a.bits == rhs.float.bits,
        .@"enum" => |a| std.mem.eql(u8, a.ref, rhs.@"enum".ref),
        .value_struct => |a| std.mem.eql(u8, a.ref, rhs.value_struct.ref),
        .opaque_ptr => |a| a.@"const" == rhs.opaque_ptr.@"const" and a.nullable == rhs.opaque_ptr.nullable and std.mem.eql(u8, a.ref, rhs.opaque_ptr.ref),
        .slice => |a| a.@"const" == rhs.slice.@"const" and typeEqual(a.element.*, rhs.slice.element.*),
        .optional => |a| typeEqual(a.child.*, rhs.optional.child.*),
        .error_union => |a| a.anyerror == rhs.error_union.anyerror and typeEqual(a.payload.*, rhs.error_union.payload.*),
        .callback => |a| blk: {
            const b = rhs.callback;
            if (a.c_callconv != b.c_callconv or a.has_userdata != b.has_userdata or a.params.len != b.params.len or !typeEqual(a.@"return".*, b.@"return".*)) break :blk false;
            for (a.params, b.params) |x, y| if (!typeEqual(x, y)) break :blk false;
            break :blk true;
        },
    };
}

fn optionalStringEqual(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if ((lhs == null) != (rhs == null)) return false;
    return lhs == null or std.mem.eql(u8, lhs.?, rhs.?);
}

fn optionalHintEqual(lhs: ?semantic.SemanticHint, rhs: ?semantic.SemanticHint) bool {
    return lhs == rhs;
}

fn findType(types: []const semantic.TypeDecl, name: []const u8) ?semantic.TypeDecl {
    for (types) |declaration| if (std.mem.eql(u8, declaration.name, name)) return declaration;
    return null;
}

test "parameter type changes are breaking and functions are added" {
    const old: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{.{
        .name = "value",
        .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_value",
    }} };
    const current: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{
        .{ .name = "value", .params = &.{.{ .name = "p0", .type = .{ .int = .{ .bits = 64, .signed = true } } }}, .@"return" = .{ .void = {} }, .symbol = "zg_value" },
        .{ .name = "extra", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_extra" },
    } };
    var report = try diff(std.testing.allocator, old, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), report.changes.items.len);
    try std.testing.expect(report.hasBreaking());
    try std.testing.expectEqual(ChangeKind.added, report.changes.items[1].kind);
}

test "appending an error is ABI compatible" {
    var old_payload: semantic.TypeNode = .{ .void = {} };
    var new_payload: semantic.TypeNode = .{ .void = {} };
    const old: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{.{
        .name = "run",
        .params = &.{},
        .@"return" = .{ .error_union = .{ .error_set = &.{"First"}, .payload = &old_payload } },
        .symbol = "zg_run",
    }} };
    const current: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{.{
        .name = "run",
        .params = &.{},
        .@"return" = .{ .error_union = .{ .error_set = &.{ "First", "Second" }, .payload = &new_payload } },
        .symbol = "zg_run",
    }} };
    var report = try diff(std.testing.allocator, old, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(!report.hasBreaking());
    try std.testing.expectEqual(ChangeKind.compatible, report.changes.items[0].kind);
}
