const std = @import("std");
const naming = @import("naming");
const semantic = @import("semantic");

pub const Backend = enum { cgo, purego };

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
    return diffWithBackends(allocator, base, .cgo, current, .cgo);
}

pub fn diffWithBackends(allocator: std.mem.Allocator, base: semantic.Semantic, base_backend: Backend, current: semantic.Semantic, current_backend: Backend) !Report {
    var report: Report = .{};
    errdefer report.deinit(allocator);

    if (base_backend != current_backend)
        try add(allocator, &report, .breaking, "document.backend", "binding backend and callback ABI convention changed");

    if (base.ir_version != current.ir_version)
        try add(allocator, &report, .breaking, "document.ir_version", "semantic IR version changed");
    if (!std.mem.eql(u8, base.package, current.package))
        try add(allocator, &report, .breaking, "document.package", "generated package identity changed");
    if (!std.mem.eql(u8, base.prefix, current.prefix))
        try add(allocator, &report, .breaking, "document.prefix", "generated C symbol prefix changed");

    for (base.functions) |old| {
        const new = findFunction(current.functions, old) orelse {
            const identity = try functionIdentity(allocator, old);
            defer allocator.free(identity);
            try add(allocator, &report, .breaking, identity, "function removed");
            continue;
        };
        const identity = try functionIdentity(allocator, old);
        defer allocator.free(identity);
        if (!std.mem.eql(u8, old.symbol, new.symbol)) {
            if (try isSymbolMetadataCorrection(allocator, current.prefix, old, new))
                try add(allocator, &report, .compatible, identity, "exported C symbol metadata corrected")
            else
                try add(allocator, &report, .breaking, identity, "exported C symbol changed");
        }
        if (!signatureEqual(old, new)) try add(allocator, &report, .breaking, identity, "signature changed");
        if (!optionalNameEqual(old.release, new.release))
            try add(allocator, &report, .breaking, identity, "release function changed");
        if (old.ownership != new.ownership or !optionalHintEqual(old.return_semantic, new.return_semantic))
            try add(allocator, &report, .breaking, identity, "return ownership or semantics changed");
        if (!retentionEqual(old.params, new.params))
            try add(allocator, &report, .breaking, identity, "parameter retention changed");
        if (!writtenEqual(old.params, new.params))
            try add(allocator, &report, .breaking, identity, "parameter written hint changed (C signature)");
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
        switch (classifyTypeChange(old, new)) {
            .equal => {},
            .appended => try add(
                allocator,
                &report,
                .compatible,
                old.name,
                if (old.kind == .tagged_union) "tagged-union variant appended" else "enum value appended",
            ),
            .snapshot_appended => try add(
                allocator,
                &report,
                .breaking,
                old.name,
                "tagged-union variant appended to a value snapshot; the snapshot struct grew",
            ),
            .access_changed => try add(allocator, &report, .breaking, old.name, "type access strategy changed"),
            .breaking => try add(allocator, &report, .breaking, old.name, "type definition changed"),
        }
    }
    for (current.types) |new| if (findType(base.types, new.name) == null)
        try add(allocator, &report, .added, new.name, "type added");

    for (base.constructors) |old| {
        const new = findConstructor(current.constructors, old.type) orelse {
            try add(allocator, &report, .breaking, old.type, "constructor mapping removed");
            continue;
        };
        if (!std.mem.eql(u8, old.init, new.init) or !std.mem.eql(u8, old.deinit, new.deinit))
            try add(allocator, &report, .breaking, old.type, "constructor or destructor mapping changed");
    }
    for (current.constructors) |new| if (findConstructor(base.constructors, new.type) == null)
        try add(allocator, &report, .added, new.type, "constructor mapping added");

    return report;
}

test "backend switching is an explicit breaking ABI change" {
    const document: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0" };
    var report = try diffWithBackends(std.testing.allocator, document, .cgo, document, .purego);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
    try std.testing.expectEqualStrings("document.backend", report.changes.items[0].subject);
    try std.testing.expectEqualStrings("binding backend and callback ABI convention changed", report.changes.items[0].detail);
}

test "the one-time symbol metadata correction is compatible, a rename is not" {
    const params: []const semantic.Parameter = &.{};
    const base_fn: semantic.SemanticFn = .{
        .name = "deinit",
        .receiver = "Counter",
        .params = params,
        .@"return" = .{ .void = {} },
        .symbol = "zg_deinit",
    };
    var corrected = base_fn;
    corrected.symbol = "zg_counter_deinit";
    const base: semantic.Semantic = .{
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .functions = &.{base_fn},
    };
    const current: semantic.Semantic = .{
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .functions = &.{corrected},
    };
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(!report.hasBreaking());
    try std.testing.expectEqualStrings("exported C symbol metadata corrected", report.changes.items[0].detail);

    var renamed = base_fn;
    renamed.symbol = "zg_counter_dispose";
    const moved: semantic.Semantic = .{
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .functions = &.{renamed},
    };
    var rename_report = try diff(std.testing.allocator, base, moved);
    defer rename_report.deinit(std.testing.allocator);
    try std.testing.expect(rename_report.hasBreaking());
    try std.testing.expectEqualStrings("exported C symbol changed", rename_report.changes.items[0].detail);
}

fn add(allocator: std.mem.Allocator, report: *Report, kind: ChangeKind, subject: []const u8, detail: []const u8) !void {
    const owned_subject = try allocator.dupe(u8, subject);
    errdefer allocator.free(owned_subject);
    const owned_detail = try allocator.dupe(u8, detail);
    errdefer allocator.free(owned_detail);
    try report.changes.append(allocator, .{
        .kind = kind,
        .subject = owned_subject,
        .detail = owned_detail,
    });
}

/// Documents written before the symbol rule was unified recorded
/// `{prefix}_{name}`, dropping the owning type. Recomputing both spellings
/// tells that one-time metadata correction apart from a genuine rename: the
/// exported C symbol never moved, only the field that reported it.
fn isSymbolMetadataCorrection(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    old: semantic.SemanticFn,
    new: semantic.SemanticFn,
) !bool {
    const legacy = try naming.legacyFunctionSymbolAlloc(allocator, prefix, old.name);
    defer allocator.free(legacy);
    if (!std.mem.eql(u8, old.symbol, legacy)) return false;
    const corrected = try naming.functionSymbolAlloc(
        allocator,
        prefix,
        new.receiver orelse new.namespace,
        new.name,
    );
    defer allocator.free(corrected);
    return std.mem.eql(u8, new.symbol, corrected);
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
        // An injected parameter is absent from the C signature, so turning
        // one into an ordinary parameter (or the reverse) moves the ABI even
        // though the Zig type did not.
        if (a.injected != b.injected) return false;
        if (a.direction != b.direction or a.semantic != b.semantic or !typeEqual(a.type, b.type)) return false;
    }
    return true;
}

fn retentionEqual(lhs: []const semantic.Parameter, rhs: []const semantic.Parameter) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |a, b| if (a.retention != b.retention) return false;
    return true;
}

/// Only an `.all` output slice carries a `{name}_written` out parameter, so
/// changing the hint adds or removes a C parameter and breaks every caller
/// linked against the old signature.
fn writtenEqual(lhs: []const semantic.Parameter, rhs: []const semantic.Parameter) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |a, b| if (a.writtenHint() != b.writtenHint()) return false;
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

const TypeChange = enum { equal, appended, snapshot_appended, access_changed, breaking };

/// Appending a variant is source-compatible for a projection union, whose
/// symbols are per variant. A value snapshot union carries its variants in one
/// struct, so the same append changes that struct's size and layout.
fn classifyTypeChange(lhs: semantic.TypeDecl, rhs: semantic.TypeDecl) TypeChange {
    if (lhs.kind != rhs.kind or lhs.layout != rhs.layout or lhs.exhaustive != rhs.exhaustive) return .breaking;
    if (lhs.accessStrategy() != rhs.accessStrategy()) return .access_changed;
    if ((lhs.tag_type == null) != (rhs.tag_type == null)) return .breaking;
    if (lhs.tag_type) |tag| if (!typeEqual(tag, rhs.tag_type.?)) return .breaking;
    if (rhs.fields.len < lhs.fields.len) return .breaking;
    for (lhs.fields, rhs.fields[0..lhs.fields.len]) |a, b| if (!typeFieldEqual(a, b)) return .breaking;
    if (rhs.fields.len == lhs.fields.len) return .equal;
    if (lhs.kind == .@"enum") return .appended;
    if (lhs.kind != .tagged_union) return .breaking;
    return if (lhs.accessStrategy() == .snapshot) .snapshot_appended else .appended;
}

fn typeFieldEqual(lhs: semantic.TypeField, rhs: semantic.TypeField) bool {
    if (!std.mem.eql(u8, lhs.name, rhs.name) or lhs.value != rhs.value or (lhs.type == null) != (rhs.type == null)) return false;
    return lhs.type == null or typeEqual(lhs.type.?, rhs.type.?);
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
        // sentinel/sentinel_many는 shim이 Zig element 타입을 되살릴 때만 쓰는 주석이고
        // 하강된 C ABI 모양을 바꾸지 않으므로 시그니처 비교에서 제외한다.
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

fn optionalNameEqual(lhs: ?[]const u8, rhs: ?[]const u8) bool {
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

fn findConstructor(constructors: []const semantic.Constructor, type_name: []const u8) ?semantic.Constructor {
    for (constructors) |constructor| if (std.mem.eql(u8, constructor.type, type_name)) return constructor;
    return null;
}

test "string slice element sentinels are not a signature change" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var plain: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    var sentinel: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte, .sentinel = 0 } };
    const old: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{.{
        .name = "paths",
        .params = &.{.{ .name = "p0", .semantic = .utf8_string, .type = .{ .slice = .{ .@"const" = true, .element = &plain } } }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_paths",
    }} };
    const current: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{.{
        .name = "paths",
        .params = &.{.{ .name = "p0", .semantic = .utf8_string, .type = .{ .slice = .{ .@"const" = true, .element = &sentinel } } }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_paths",
    }} };
    var report = try diff(std.testing.allocator, old, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), report.changes.items.len);
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

test "a nested namespace reports its dotted identity and keeps a narrow width breaking" {
    const old: semantic.Semantic = .{ .package = "text", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{.{
        .name = "breaks",
        .namespace = "unicode.grapheme",
        .params = &.{.{ .name = "cp", .type = .{ .int = .{ .bits = 21, .signed = false } } }},
        .@"return" = .{ .bool = {} },
        .symbol = "zg_unicode_grapheme_breaks",
    }} };
    const current: semantic.Semantic = .{ .package = "text", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{.{
        .name = "breaks",
        .namespace = "unicode.grapheme",
        .params = &.{.{ .name = "cp", .type = .{ .int = .{ .bits = 32, .signed = false } } }},
        .@"return" = .{ .bool = {} },
        .symbol = "zg_unicode_grapheme_breaks",
    }} };
    var report = try diff(std.testing.allocator, old, current);
    defer report.deinit(std.testing.allocator);
    // The C signature is `uint32_t` either way, but the declared width is what
    // the value means, so widening it is still a contract change.
    try std.testing.expect(report.hasBreaking());
    try std.testing.expectEqualStrings("unicode.grapheme.breaks", report.changes.items[0].subject);
}

test "tagged union variant payload changes are breaking" {
    const old: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "number", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 0 }},
            .kind = .tagged_union,
            .name = "Value",
            .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
        }},
        .zig_version = "0.16.0",
    };
    const current: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "number", .type = .{ .int = .{ .bits = 64, .signed = true } }, .value = 0 }},
            .kind = .tagged_union,
            .name = "Value",
            .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
        }},
        .zig_version = "0.16.0",
    };
    var report = try diff(std.testing.allocator, old, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
    try std.testing.expectEqualStrings("Value", report.changes.items[0].subject);
    try std.testing.expectEqualStrings("type definition changed", report.changes.items[0].detail);
}

test "appending tagged union variants and tag values is ABI compatible" {
    const old: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "none", .type = .{ .void = {} }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{.{ .name = "none", .value = 0 }},
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    const current: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "number", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
                },
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{ .{ .name = "none", .value = 0 }, .{ .name = "number", .value = 1 } },
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    var report = try diff(std.testing.allocator, old, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(!report.hasBreaking());
    try std.testing.expectEqual(@as(usize, 2), report.changes.items.len);
    try std.testing.expectEqual(ChangeKind.compatible, report.changes.items[0].kind);
    try std.testing.expectEqualStrings("tagged-union variant appended", report.changes.items[0].detail);
    try std.testing.expectEqual(ChangeKind.compatible, report.changes.items[1].kind);
    try std.testing.expectEqualStrings("enum value appended", report.changes.items[1].detail);
}

test "removing renaming or retagging an existing variant is breaking" {
    const base: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{
                .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                .{ .name = "number", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
            },
            .kind = .tagged_union,
            .name = "Value",
            .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
        }},
        .zig_version = "0.16.0",
    };
    const changed_fields = [_][]const semantic.TypeField{
        &.{.{ .name = "none", .type = .{ .void = {} }, .value = 0 }},
        &.{
            .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
            .{ .name = "integer", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
        },
        &.{
            .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
            .{ .name = "number", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 7 },
        },
    };
    for (changed_fields) |fields| {
        const current: semantic.Semantic = .{
            .package = "variant",
            .prefix = "zg",
            .types = &.{.{
                .fields = fields,
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            }},
            .zig_version = "0.16.0",
        };
        var report = try diff(std.testing.allocator, base, current);
        defer report.deinit(std.testing.allocator);
        try std.testing.expect(report.hasBreaking());
        try std.testing.expectEqualStrings("type definition changed", report.changes.items[0].detail);
    }
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

test "changing the release function of a fallible slice return is breaking" {
    var float_node: semantic.TypeNode = .{ .float = .{ .bits = 32 } };
    var slice_payload: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &float_node } };
    const extract: semantic.SemanticFn = .{
        .name = "extractSamplesChecked",
        .ownership = .caller,
        .params = &.{},
        .release = "freeSamples",
        .@"return" = .{ .error_union = .{ .error_set = &.{"Empty"}, .payload = &slice_payload } },
        .symbol = "zg_extract_samples_checked",
    };
    var renamed = extract;
    renamed.release = "releaseSamples";
    const base: semantic.Semantic = .{
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .functions = &.{extract},
    };
    const current: semantic.Semantic = .{
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .functions = &.{renamed},
    };
    // The buffer is freed by whichever symbol the generated Go calls, so
    // pointing the return at a different one is an ABI break even though the
    // C signature is untouched.
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), report.changes.items.len);
    try std.testing.expectEqual(ChangeKind.breaking, report.changes.items[0].kind);
    try std.testing.expectEqualStrings("release function changed", report.changes.items[0].detail);
}

test "document identity and exported symbol changes are breaking" {
    const base: semantic.Semantic = .{
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .functions = &.{.{
            .name = "run",
            .params = &.{},
            .@"return" = .{ .void = {} },
            .symbol = "zg_run",
        }},
    };
    const current: semantic.Semantic = .{
        .ir_version = 2,
        .package = "renamed",
        .prefix = "acme",
        .zig_version = "0.16.0",
        .functions = &.{.{
            .name = "run",
            .params = &.{},
            .@"return" = .{ .void = {} },
            .symbol = "acme_run",
        }},
    };
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), report.changes.items.len);
    try std.testing.expect(report.hasBreaking());
    for (report.changes.items) |change| try std.testing.expectEqual(ChangeKind.breaking, change.kind);
}

test "constructor mapping changes break while additions are compatible" {
    const base: semantic.Semantic = .{
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .constructors = &.{.{ .type = "Context", .init = "create", .deinit = "deinit" }},
    };
    const current: semantic.Semantic = .{
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .constructors = &.{
            .{ .type = "Context", .init = "open", .deinit = "close" },
            .{ .type = "Session", .init = "create", .deinit = "deinit" },
        },
    };
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), report.changes.items.len);
    try std.testing.expectEqual(ChangeKind.breaking, report.changes.items[0].kind);
    try std.testing.expectEqual(ChangeKind.added, report.changes.items[1].kind);
}

test "changing the written hint of an output slice breaks the C signature" {
    var element: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const count: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    const slice: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &element } };
    const old: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{.{
        .name = "fill",
        .params = &.{.{ .direction = .out, .name = "dst", .type = slice }},
        .@"return" = count,
        .symbol = "zg_fill",
    }} };
    const current: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{.{
        .name = "fill",
        .params = &.{.{ .direction = .out, .name = "dst", .type = slice, .written = .@"return" }},
        .@"return" = count,
        .symbol = "zg_fill",
    }} };
    // `.all` takes a `dst_written` out parameter and `.return` does not, so
    // either direction drops or adds a C parameter.
    var forward = try diff(std.testing.allocator, old, current);
    defer forward.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), forward.changes.items.len);
    try std.testing.expectEqual(ChangeKind.breaking, forward.changes.items[0].kind);
    try std.testing.expectEqualStrings("parameter written hint changed (C signature)", forward.changes.items[0].detail);
    try std.testing.expect(forward.hasBreaking());

    var backward = try diff(std.testing.allocator, current, old);
    defer backward.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), backward.changes.items.len);
    try std.testing.expectEqual(ChangeKind.breaking, backward.changes.items[0].kind);
}

test "unchanged semantic contract has an empty report" {
    const document: semantic.Semantic = .{
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
        .constructors = &.{.{ .type = "Context", .init = "create", .deinit = "deinit" }},
        .functions = &.{.{
            .name = "run",
            .params = &.{},
            .@"return" = .{ .void = {} },
            .symbol = "zg_run",
        }},
    };
    var report = try diff(std.testing.allocator, document, document);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), report.changes.items.len);
    try std.testing.expect(!report.hasBreaking());
}

test "diff cleans up every partial allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expectExpandedBreakingReport, .{});
}

fn expectExpandedBreakingReport(allocator: std.mem.Allocator) !void {
    const base: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0" };
    const current: semantic.Semantic = .{
        .ir_version = 2,
        .package = "renamed",
        .prefix = "acme",
        .zig_version = "0.16.0",
        .functions = &.{.{
            .name = "extra",
            .params = &.{},
            .@"return" = .{ .void = {} },
            .symbol = "zg_extra",
        }},
    };
    var report = try diff(allocator, base, current);
    defer report.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 4), report.changes.items.len);
}

test "switching a tagged union between access strategies is breaking" {
    const variants = [_]semantic.TypeField{.{ .name = "ticks", .type = .{ .int = .{ .bits = 32, .signed = false } }, .value = 0 }};
    const tags = [_]semantic.TypeField{.{ .name = "ticks", .value = 0 }};
    const projection: semantic.TypeDecl = .{
        .fields = &variants,
        .kind = .tagged_union,
        .name = "Signal",
        .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
    };
    var snapshot = projection;
    snapshot.access = .snapshot;
    const tag_decl: semantic.TypeDecl = .{
        .fields = &tags,
        .kind = .@"enum",
        .name = "SignalTag",
        .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
    };
    const base: semantic.Semantic = .{
        .package = "contract",
        .prefix = "zg",
        .types = &.{ projection, tag_decl },
        .zig_version = "0.16.0",
    };
    var current = base;
    current.types = &.{ snapshot, tag_decl };

    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
    try std.testing.expectEqualStrings("Signal", report.changes.items[0].subject);
    try std.testing.expectEqualStrings("type access strategy changed", report.changes.items[0].detail);
}

test "every extern struct field change is breaking" {
    const width: semantic.TypeField = .{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } };
    const height: semantic.TypeField = .{ .name = "height", .type = .{ .int = .{ .bits = 32, .signed = true } } };
    const depth: semantic.TypeField = .{ .name = "depth", .type = .{ .int = .{ .bits = 32, .signed = true } } };
    const wide: semantic.TypeField = .{ .name = "width", .type = .{ .int = .{ .bits = 64, .signed = true } } };

    const base: semantic.Semantic = .{
        .package = "contract",
        .prefix = "zg",
        .types = &.{.{ .fields = &.{ width, height }, .kind = .value_struct, .layout = .@"extern", .name = "Config" }},
        .zig_version = "0.16.0",
    };
    // An enum or a projection union tolerates an append; a struct cannot,
    // because the append moves its size.
    const cases = [_][]const semantic.TypeField{
        &.{ width, height, depth },
        &.{width},
        &.{ height, width },
        &.{ wide, height },
    };
    for (cases) |fields| {
        var current = base;
        const types = [_]semantic.TypeDecl{.{ .fields = fields, .kind = .value_struct, .layout = .@"extern", .name = "Config" }};
        current.types = &types;
        var report = try diff(std.testing.allocator, base, current);
        defer report.deinit(std.testing.allocator);
        try std.testing.expect(report.hasBreaking());
        try std.testing.expectEqualStrings("Config", report.changes.items[0].subject);
        try std.testing.expectEqualStrings("type definition changed", report.changes.items[0].detail);
    }
}

test "giving an infallible function a handle changes its C ABI" {
    var payload: semantic.TypeNode = .{ .int = .{ .bits = 64, .signed = true } };
    _ = &payload;
    const plain: semantic.SemanticFn = .{
        .name = "total",
        .params = &.{},
        .@"return" = .{ .int = .{ .bits = 64, .signed = true } },
        .symbol = "zg_total",
    };
    // A receiver is not just one more argument: a function that can be handed
    // a nil handle needs an `error` in Go, and that turns its C signature into
    // a status return with an `out_result`.
    var checked = plain;
    checked.receiver = "Counter";
    const base: semantic.Semantic = .{
        .functions = &.{plain},
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const current: semantic.Semantic = .{
        .functions = &.{checked},
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
}
