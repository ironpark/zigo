const std = @import("std");
const naming = @import("naming");
const abi = @import("abi");
const semantic = @import("semantic");
const lower = @import("lower");
const stream_return = @import("stream_return");

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

    // The C shape of a function is whatever lowering makes of it, so both
    // documents are lowered and their lowered forms compared. Nothing here
    // restates which parts of a Zig type reach C.
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const base_program = try lowerFor(scratch.allocator(), base, base_backend);
    const current_program = try lowerFor(scratch.allocator(), current, current_backend);
    const base_spans = try loweredSpans(scratch.allocator(), base);
    const current_spans = try loweredSpans(scratch.allocator(), current);

    if (base_backend != current_backend)
        try add(allocator, &report, .breaking, "document.backend", "binding backend and callback ABI convention changed");

    if (base.ir_version != current.ir_version)
        try add(allocator, &report, .breaking, "document.ir_version", "semantic IR version changed");
    if (!std.mem.eql(u8, base.package, current.package))
        try add(allocator, &report, .breaking, "document.package", "generated package identity changed");
    if (!std.mem.eql(u8, base.prefix, current.prefix))
        try add(allocator, &report, .breaking, "document.prefix", "generated C symbol prefix changed");

    for (base.functions, 0..) |old, old_index| {
        const new_index = findFunctionIndex(current.functions, old) orelse {
            const identity = try functionIdentity(allocator, old);
            defer allocator.free(identity);
            try add(allocator, &report, .breaking, identity, "function removed");
            continue;
        };
        const new = current.functions[new_index];
        const identity = try functionIdentity(allocator, old);
        defer allocator.free(identity);
        if (!std.mem.eql(u8, old.symbol, new.symbol)) {
            if (try isSymbolMetadataCorrection(allocator, current.prefix, old, new))
                try add(allocator, &report, .compatible, identity, "exported C symbol metadata corrected")
            else
                try add(allocator, &report, .breaking, identity, "exported C symbol changed");
        }
        // The written hint decides whether the C signature carries a
        // `{name}_written` out parameter, so it explains a lowered difference
        // rather than adding one; naming it is more use than the generic
        // message, and reporting both would say the same thing twice.
        const written_hint_kept = writtenEqual(old.params, new.params);
        if (!written_hint_kept)
            try add(allocator, &report, .breaking, identity, "parameter written hint changed (C signature)")
        else if (!signaturesEqual(
            base_program.functions[base_spans[old_index]..base_spans[old_index + 1]],
            current_program.functions[current_spans[new_index]..current_spans[new_index + 1]],
        ))
            try add(allocator, &report, .breaking, identity, "signature changed");
        if (!semantic.optionalStringEqual(old.release, new.release))
            try add(allocator, &report, .breaking, identity, "release function changed");
        // The C symbol does not move, but the Go surface does: the function
        // becomes (or stops being) a type's constructor, so every call site
        // that named it changes.
        if (!semantic.optionalStringEqual(old.goOwner(), new.goOwner()))
            try add(allocator, &report, .breaking, identity, "Go owner changed");
        const old_go_name = try effectivePublicFunctionNameAlloc(allocator, base, old);
        defer allocator.free(old_go_name);
        const new_go_name = try effectivePublicFunctionNameAlloc(allocator, current, new);
        defer allocator.free(new_go_name);
        if (!std.mem.eql(u8, old_go_name, new_go_name))
            try add(allocator, &report, .breaking, identity, "Go signature changed");
        if (old.ownership != new.ownership or old.returnsBorrowedHandle() != new.returnsBorrowedHandle() or
            !optionalHintEqual(old.return_semantic, new.return_semantic))
            try add(allocator, &report, .breaking, identity, "return ownership or semantics changed");
        if (!retentionEqual(old.params, new.params))
            try add(allocator, &report, .breaking, identity, "parameter retention changed");
        // The C signature does not move, but the Go callback type does: it
        // gains or loses a second result, and every caller's function literal
        // stops compiling. Breaking on the surface consumers actually write.
        if (!goErrorEqual(old.params, new.params))
            try add(allocator, &report, .breaking, identity, "callback Go error surface changed");
        if (!callbackFailureEqual(old.params, new.params))
            try add(allocator, &report, .compatible, identity, "callback failure result changed");
        // The C signature keeps its flag parameter either way, but the Go one
        // gains or loses its leading `ctx`, so every call site moves.
        if (!semantic.optionalStringEqual(old.cancel, new.cancel))
            try add(allocator, &report, .breaking, identity, "cancellation surface changed");
        if (!std.mem.eql(u8, old.cancelError(), new.cancelError()))
            try add(allocator, &report, .breaking, identity, "cancellation error mapping changed");
        if (!semantic.optionalStringEqual(old.package, new.package))
            try add(allocator, &report, .breaking, identity, "Go package assignment changed");
        // The native signature is unchanged, but generated Go gains or loses
        // the parent/child Close ordering contract.
        if (old.childOfReceiver() != new.childOfReceiver())
            try add(allocator, &report, .compatible, identity, "dependent handle lifetime Go surface changed");
        if (!streamBufferEqual(old.params, new.params))
            try add(allocator, &report, .compatible, identity, "stream staging buffer resized");
        try compareErrors(allocator, &report, identity, old.@"return", new.@"return");
    }
    for (current.functions) |new| if (findFunctionIndex(base.functions, new) == null) {
        const identity = try functionIdentity(allocator, new);
        defer allocator.free(identity);
        try add(allocator, &report, .added, identity, "function added");
    };

    for (base.types) |old| {
        const new = findType(current.types, old.name) orelse {
            try add(allocator, &report, .breaking, old.name, "type removed");
            continue;
        };
        if (!semantic.optionalStringEqual(old.package, new.package))
            try add(allocator, &report, .breaking, old.name, "Go package assignment changed");
        if (!std.meta.eql(old.on_callback_failure, new.on_callback_failure))
            try add(allocator, &report, .compatible, old.name, "callback failure result changed");
        switch (classifyTypeChange(old, new)) {
            .equal => {},
            .appended => if (old.kind == .tagged_union and base.taggedUnionUsedByValue(old.name))
                try add(
                    allocator,
                    &report,
                    .breaking,
                    old.name,
                    "tagged-union variant appended; a value-parameter C signature grew",
                )
            else
                try add(
                    allocator,
                    &report,
                    .compatible,
                    old.name,
                    if (old.kind == .tagged_union)
                        "tagged-union variant appended"
                    else if (old.kind == .value_struct)
                        "packed-struct field appended within backing width"
                    else
                        "enum value appended",
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

test "wrapper coverage metadata is ignored" {
    const plain: semantic.SemanticFn = .{
        .name = "wrapper",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "zg_wrapper",
    };
    var covered = plain;
    covered.covers = &.{"Service.upstream"};
    const base: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{plain} };
    const current: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{covered} };
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), report.changes.items.len);
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

fn findFunctionIndex(functions: []const semantic.SemanticFn, wanted: semantic.SemanticFn) ?usize {
    for (functions, 0..) |function, index| {
        if (semantic.optionalStringEqual(function.receiver, wanted.receiver) and
            semantic.optionalStringEqual(function.namespace, wanted.namespace) and
            declarationIdentityEqual(function, wanted)) return index;
    }
    return null;
}

fn declarationIdentityEqual(lhs: semantic.SemanticFn, rhs: semantic.SemanticFn) bool {
    if (lhs.zig_path) |path| return pathNamesFunction(path, rhs);
    if (rhs.zig_path) |path| return pathNamesFunction(path, lhs);
    return std.mem.eql(u8, lhs.name, rhs.name);
}

fn pathNamesFunction(path: []const u8, function: semantic.SemanticFn) bool {
    if (function.zig_path) |other| return std.mem.eql(u8, path, other);
    if (std.mem.eql(u8, path, function.name)) return true;
    const owner = function.receiver orelse function.namespace orelse return false;
    return path.len == owner.len + function.name.len + 1 and
        std.mem.startsWith(u8, path, owner) and path[owner.len] == '.' and
        std.mem.endsWith(u8, path, function.name);
}

fn effectivePublicFunctionNameAlloc(allocator: std.mem.Allocator, document: semantic.Semantic, function: semantic.SemanticFn) ![]u8 {
    for (document.constructors) |constructor| {
        if (!std.mem.eql(u8, constructor.init, function.name) or
            !std.mem.eql(u8, constructor.type, function.goOwner() orelse "")) continue;
        if (constructor.name) |name| return naming.pascalAlloc(allocator, name);
        return std.fmt.allocPrint(allocator, "New{s}", .{constructor.type});
    }
    return naming.pascalAlloc(allocator, function.name);
}

/// The lowered form of a document, in the arena the comparison lives in.
/// Both sides are documents the generator wrote and validation accepted, so
/// lowering can assume the same well-formedness it assumes during generation.
/// Lowering assumes a validated document: an unresolved type reference is an
/// `unreachable` inside `lower`, not an error. Every caller -- the `abi-diff`
/// command included -- runs `validate.findIssue` over the document first.
fn lowerFor(allocator: std.mem.Allocator, document: semantic.Semantic, backend: Backend) !abi.Program {
    // `semantic.json` keeps the stream-returning Zig method; lowering only
    // ever sees the operations it expands into, so the comparison does too.
    const expanded = try stream_return.expand(allocator, document);
    return lower.semanticDocumentForBackend(allocator, expanded, document.package, document.prefix, try errorCodesFor(allocator, expanded), switch (backend) {
        .cgo => .cgo,
        .purego => .purego,
    });
}

/// Where each semantic function's lowered operations start, plus the total,
/// so function `n` owns `starts[n]..starts[n + 1]`.
fn loweredSpans(allocator: std.mem.Allocator, document: semantic.Semantic) ![]const usize {
    const starts = try allocator.alloc(usize, document.functions.len + 1);
    var total: usize = 0;
    for (document.functions, 0..) |function, index| {
        starts[index] = total;
        total += stream_return.operationCount(function);
    }
    starts[document.functions.len] = total;
    return starts;
}

/// The error codes lowering numbers a document with. The identity of an error
/// is compared on the semantic error sets; these only have to exist, and to
/// be numbered by the same rule generation uses, so the lowered shapes of two
/// documents stay comparable.
fn errorCodesFor(allocator: std.mem.Allocator, document: semantic.Semantic) ![]const abi.ErrorCode {
    var codes: std.ArrayList(abi.ErrorCode) = .empty;
    for (document.functions) |function| {
        if (function.@"return" != .error_union) continue;
        for (function.@"return".error_union.error_set) |name| {
            var exists = false;
            for (codes.items) |entry| if (std.mem.eql(u8, entry.name, name)) {
                exists = true;
                break;
            };
            if (!exists) try codes.append(allocator, .{ .code = @intCast(codes.items.len + 1), .name = name });
        }
    }
    return codes.toOwnedSlice(allocator);
}

fn functionIdentity(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]u8 {
    const owner = function.receiver orelse function.namespace;
    return if (owner) |value|
        std.fmt.allocPrint(allocator, "{s}.{s}", .{ value, function.name })
    else
        allocator.dupe(u8, function.name);
}

/// The parameters a comparison sees. An injected argument has no C parameter
/// and no Go argument behind it, so it is not part of any signature: gaining
/// or losing one moves nothing, while turning an ordinary parameter into an
/// injected one (or the reverse) shows up here as a parameter appearing or
/// disappearing, which is exactly what it is.
const ExposedParams = struct {
    params: []const semantic.Parameter,
    index: usize = 0,

    fn next(self: *ExposedParams) ?semantic.Parameter {
        while (self.index < self.params.len) {
            const parameter = self.params[self.index];
            self.index += 1;
            if (parameter.injected == null) return parameter;
        }
        return null;
    }
};

fn exposedParams(params: []const semantic.Parameter) ExposedParams {
    return .{ .params = params };
}

/// Walks two exposed parameter lists in step, stopping at the first pair
/// `matches` rejects and at any difference in length.
fn exposedParamsMatch(
    lhs: []const semantic.Parameter,
    rhs: []const semantic.Parameter,
    matches: fn (semantic.Parameter, semantic.Parameter) bool,
) bool {
    var old = exposedParams(lhs);
    var new = exposedParams(rhs);
    while (true) {
        const a = old.next();
        const b = new.next();
        if (a == null or b == null) return a == null and b == null;
        if (!matches(a.?, b.?)) return false;
    }
}

/// Two functions have the same signature when their lowered C shapes match
/// and the Go surface lowering does not carry matches too. The lowered
/// comparison answers everything about the C ABI -- parameter roles, pointer
/// constness and nullability, promoted integer widths, callback wire shapes,
/// struct mirrors -- so nothing about which annotations reach C is restated
/// here.
fn signaturesEqual(lhs: []const abi.AbiFn, rhs: []const abi.AbiFn) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |a, b| if (!signatureEqual(a, b)) return false;
    return true;
}

fn signatureEqual(lhs: abi.AbiFn, rhs: abi.AbiFn) bool {
    if (lhs.params.len != rhs.params.len) return false;
    for (lhs.params, rhs.params) |a, b| {
        if (a.role != b.role or a.field_index != b.field_index or !scalarEqual(a.scalar, b.scalar)) return false;
    }
    if (!scalarEqual(lhs.ret, rhs.ret) or lhs.ret_optional != rhs.ret_optional or
        lhs.value_union_return != rhs.value_union_return) return false;
    if (!structMirrorEqual(lhs.ret_struct, rhs.ret_struct) or
        !structMirrorEqual(lhs.payload_struct, rhs.payload_struct)) return false;
    return goSurfaceEqual(lhs.origin.*, rhs.origin.*);
}

fn scalarEqual(lhs: abi.AbiScalar, rhs: abi.AbiScalar) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .void, .bool_u8, .isize, .usize => true,
        .signed_int => |a| a == rhs.signed_int,
        .unsigned_int => |a| a == rhs.unsigned_int,
        .float => |a| a == rhs.float,
        .@"opaque" => |a| std.mem.eql(u8, a.c_name, rhs.@"opaque".c_name),
        .snapshot => |a| std.mem.eql(u8, a, rhs.snapshot),
        .value_struct => |a| std.mem.eql(u8, a.c_name, rhs.value_struct.c_name),
        .pointer => |a| a.is_const == rhs.pointer.is_const and a.is_many == rhs.pointer.is_many and
            a.is_c_string == rhs.pointer.is_c_string and a.is_optional == rhs.pointer.is_optional and
            scalarEqual(a.child.*, rhs.pointer.child.*),
        .callback => |a| blk: {
            const b = rhs.callback;
            if (a.params.len != b.params.len or !scalarEqual(a.ret.*, b.ret.*)) break :blk false;
            for (a.params, b.params) |x, y| if (!scalarEqual(x, y)) break :blk false;
            break :blk true;
        },
    };
}

fn structMirrorEqual(lhs: ?*const abi.AbiStruct, rhs: ?*const abi.AbiStruct) bool {
    if (lhs == null or rhs == null) return lhs == null and rhs == null;
    return std.mem.eql(u8, lhs.?.c_name, rhs.?.c_name);
}

/// What the Go surface shows that the lowered C shape does not. Two facts
/// survive lowering only as promotions: the declared integer width, which the
/// shim range-checks and Go spells as the declared type, and the shape of the
/// Zig type itself -- `[]T` and `?[]T` share one C signature but not one Go
/// return arity. The binding's own semantic hint is the third: it decides
/// whether Go sees `string` or `[]byte`.
fn goSurfaceEqual(lhs: semantic.SemanticFn, rhs: semantic.SemanticFn) bool {
    if (!optionalHintEqual(lhs.return_semantic, rhs.return_semantic)) return false;
    if (!goTypeEqual(lhs.@"return", rhs.@"return")) return false;
    return exposedParamsMatch(lhs.params, rhs.params, struct {
        fn matches(a: semantic.Parameter, b: semantic.Parameter) bool {
            return a.direction == b.direction and a.semantic == b.semantic and goTypeEqual(a.type, b.type);
        }
    }.matches);
}

fn goTypeEqual(lhs: semantic.TypeNode, rhs: semantic.TypeNode) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .atomic_ptr => |a| a.@"const" == rhs.atomic_ptr.@"const" and goTypeEqual(a.child.*, rhs.atomic_ptr.child.*),
        // `u21` and `u32` both travel as `uint32_t`, so only the declared
        // width tells them apart, and it is the width Go spells.
        .int => |a| a.bits == rhs.int.bits and a.signed == rhs.int.signed and a.is_usize == rhs.int.is_usize,
        .slice => |a| goTypeEqual(a.element.*, rhs.slice.element.*),
        .optional => |a| goTypeEqual(a.child.*, rhs.optional.child.*),
        .error_union => |a| goTypeEqual(a.payload.*, rhs.error_union.payload.*),
        .callback => |a| blk: {
            const b = rhs.callback;
            if (a.params.len != b.params.len or !goTypeEqual(a.@"return".*, b.@"return".*)) break :blk false;
            for (a.params, b.params) |x, y| if (!goTypeEqual(x, y)) break :blk false;
            break :blk true;
        },
        else => true,
    };
}

fn goErrorEqual(lhs: []const semantic.Parameter, rhs: []const semantic.Parameter) bool {
    return exposedParamsMatch(lhs, rhs, struct {
        fn matches(a: semantic.Parameter, b: semantic.Parameter) bool {
            return a.goError() == b.goError();
        }
    }.matches);
}

fn callbackFailureEqual(lhs: []const semantic.Parameter, rhs: []const semantic.Parameter) bool {
    return exposedParamsMatch(lhs, rhs, struct {
        fn matches(a: semantic.Parameter, b: semantic.Parameter) bool {
            return std.meta.eql(a.on_callback_failure, b.on_callback_failure);
        }
    }.matches);
}

fn retentionEqual(lhs: []const semantic.Parameter, rhs: []const semantic.Parameter) bool {
    return exposedParamsMatch(lhs, rhs, struct {
        fn matches(a: semantic.Parameter, b: semantic.Parameter) bool {
            return a.retention == b.retention;
        }
    }.matches);
}

/// Only an `.all` output slice carries a `{name}_written` out parameter, so
/// changing the hint adds or removes a C parameter and breaks every caller
/// linked against the old signature.
fn writtenEqual(lhs: []const semantic.Parameter, rhs: []const semantic.Parameter) bool {
    return exposedParamsMatch(lhs, rhs, struct {
        fn matches(a: semantic.Parameter, b: semantic.Parameter) bool {
            return a.writtenHint() == b.writtenHint();
        }
    }.matches);
}

/// The staging buffer behind a stream parameter is a shim-internal size, not
/// part of any signature, so resizing it is reported rather than refused.
fn streamBufferEqual(lhs: []const semantic.Parameter, rhs: []const semantic.Parameter) bool {
    return exposedParamsMatch(lhs, rhs, struct {
        fn matches(a: semantic.Parameter, b: semantic.Parameter) bool {
            if (a.type != .io_stream or b.type != .io_stream) return true;
            return a.bufferSize() == b.bufferSize();
        }
    }.matches);
}

fn containsName(names: []const []const u8, wanted: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, wanted)) return true;
    return false;
}

fn compareErrors(allocator: std.mem.Allocator, report: *Report, subject: []const u8, old_node: semantic.TypeNode, new_node: semantic.TypeNode) !void {
    if (old_node != .error_union or new_node != .error_union) return;
    const old = old_node.error_union.error_set;
    const new = new_node.error_union.error_set;
    // Membership rather than position. The wire code for an error name is
    // pinned by `errors.lock.json`, which travels with `semantic.json`, so a
    // set whose members are the same carries the same codes however the two
    // documents happen to have ordered them -- and Zig's reflection order for
    // an error set moves when unrelated sets are declared around it.
    for (old) |name| {
        if (!containsName(new, name)) {
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
    if (lhs.kind != rhs.kind or lhs.layout != rhs.layout or lhs.exhaustive != rhs.exhaustive or lhs.open != rhs.open) return .breaking;
    // A plain (auto-layout) struct never crosses C as a whole: it is either
    // flattened, where the selected fields ride on the function signature and
    // are compared there, or rejected. Its recorded field list is only the
    // selection reflection happened to walk, so it carries no ABI of its own.
    if (lhs.kind == .value_struct and lhs.layout == null) return .equal;
    if (!optionalTypeEqual(lhs.backing_type, rhs.backing_type)) return .breaking;
    if (!optionalStringsEqual(lhs.omitted_variants, rhs.omitted_variants)) return .breaking;
    if (lhs.accessStrategy() != rhs.accessStrategy()) return .access_changed;
    if ((lhs.tag_type == null) != (rhs.tag_type == null)) return .breaking;
    if (lhs.tag_type) |tag| if (!declaredTypeEqual(tag, rhs.tag_type.?)) return .breaking;
    if (rhs.fields.len < lhs.fields.len) return .breaking;
    for (lhs.fields, rhs.fields[0..lhs.fields.len]) |a, b| if (!typeFieldEqual(a, b)) return .breaking;
    if (rhs.fields.len == lhs.fields.len) return .equal;
    if (lhs.kind == .@"enum") return .appended;
    if (lhs.kind == .value_struct and lhs.layout == .@"packed") return .appended;
    if (lhs.kind != .tagged_union) return .breaking;
    return if (lhs.accessStrategy() == .snapshot) .snapshot_appended else .appended;
}

fn optionalTypeEqual(lhs: ?semantic.TypeNode, rhs: ?semantic.TypeNode) bool {
    if (lhs == null or rhs == null) return lhs == null and rhs == null;
    return declaredTypeEqual(lhs.?, rhs.?);
}

fn optionalStringsEqual(lhs: ?[]const []const u8, rhs: ?[]const []const u8) bool {
    if (lhs == null or rhs == null) return lhs == null and rhs == null;
    if (lhs.?.len != rhs.?.len) return false;
    for (lhs.?, rhs.?) |a, b| if (!std.mem.eql(u8, a, b)) return false;
    return true;
}

fn typeFieldEqual(lhs: semantic.TypeField, rhs: semantic.TypeField) bool {
    if (!std.mem.eql(u8, lhs.name, rhs.name) or lhs.atomic != rhs.atomic or lhs.value != rhs.value or (lhs.type == null) != (rhs.type == null)) return false;
    return lhs.type == null or declaredTypeEqual(lhs.type.?, rhs.type.?);
}

/// Structural equality of two declared types, for comparing the members of a
/// type declaration. A declaration is its own contract -- the header, the Go
/// mirror and the shim all spell its members from the declared types -- so
/// this compares them as written. Function signatures are not compared here;
/// they are compared on the lowered program.
fn declaredTypeEqual(lhs: semantic.TypeNode, rhs: semantic.TypeNode) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .void, .bool, .cancel_flag => true,
        .atomic_ptr => |a| a.@"const" == rhs.atomic_ptr.@"const" and declaredTypeEqual(a.child.*, rhs.atomic_ptr.child.*),
        .int => |a| a.bits == rhs.int.bits and a.signed == rhs.int.signed and a.is_usize == rhs.int.is_usize,
        .float => |a| a.bits == rhs.float.bits,
        .@"enum" => |a| std.mem.eql(u8, a.ref, rhs.@"enum".ref),
        .io_stream => |a| a.direction == rhs.io_stream.direction,
        .materialized => |a| a.pointer == rhs.materialized.pointer and a.nullable == rhs.materialized.nullable and std.mem.eql(u8, a.ref, rhs.materialized.ref),
        .value_struct => |a| std.mem.eql(u8, a.ref, rhs.value_struct.ref),
        .opaque_ptr => |a| a.by_value == rhs.opaque_ptr.by_value and a.@"const" == rhs.opaque_ptr.@"const" and a.nullable == rhs.opaque_ptr.nullable and std.mem.eql(u8, a.ref, rhs.opaque_ptr.ref),
        .slice => |a| a.@"const" == rhs.slice.@"const" and declaredTypeEqual(a.element.*, rhs.slice.element.*),
        .optional => |a| declaredTypeEqual(a.child.*, rhs.optional.child.*),
        .error_union => |a| a.anyerror == rhs.error_union.anyerror and declaredTypeEqual(a.payload.*, rhs.error_union.payload.*),
        .callback => |a| blk: {
            const b = rhs.callback;
            if (a.c_callconv != b.c_callconv or a.has_userdata != b.has_userdata or a.params.len != b.params.len or !declaredTypeEqual(a.@"return".*, b.@"return".*)) break :blk false;
            for (a.params, b.params) |x, y| if (!declaredTypeEqual(x, y)) break :blk false;
            break :blk true;
        },
    };
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

test "adding a flattened struct field is breaking" {
    const u32_node: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = false } };
    const u16_node: semantic.TypeNode = .{ .int = .{ .bits = 16, .signed = false } };
    const old_fields = [_]semantic.FlattenedField{.{ .name = "cols", .type = u32_node }};
    const new_fields = [_]semantic.FlattenedField{
        .{ .name = "cols", .type = u32_node },
        .{ .name = "rows", .type = u16_node },
    };
    const old_fn: semantic.SemanticFn = .{
        .name = "init",
        .params = &.{.{ .name = "options", .flatten = &old_fields, .type = .{ .value_struct = .{ .ref = "Options" } } }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_init",
    };
    var new_fn = old_fn;
    new_fn.params = &.{.{ .name = "options", .flatten = &new_fields, .type = .{ .value_struct = .{ .ref = "Options" } } }};
    const base: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{old_fn} };
    const current: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{new_fn} };
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
    try std.testing.expectEqualStrings("signature changed", report.changes.items[0].detail);
}

test "adding a field accessor is a compatible function append" {
    const accessor: semantic.SemanticFn = .{
        .field_access = .{ .path = "screen.cursor.x" },
        .name = "cursorX",
        .params = &.{},
        .receiver = "Terminal",
        .@"return" = .{ .int = .{ .bits = 16, .signed = false } },
        .symbol = "zg_terminal_cursor_x",
    };
    const base: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0" };
    const current: semantic.Semantic = .{
        .functions = &.{accessor},
        .package = "demo",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(!report.hasBreaking());
    try std.testing.expectEqual(@as(usize, 1), report.changes.items.len);
    try std.testing.expectEqual(ChangeKind.added, report.changes.items[0].kind);
    try std.testing.expectEqualStrings("function added", report.changes.items[0].detail);
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
        .types = &.{
            .{
                .fields = &.{.{ .name = "number", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{.{ .name = "number", .value = 0 }},
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
                .fields = &.{.{ .name = "number", .type = .{ .int = .{ .bits = 64, .signed = true } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{.{ .name = "number", .value = 0 }},
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    var report = try diff(std.testing.allocator, old, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
    try std.testing.expectEqualStrings("Value", report.changes.items[0].subject);
    try std.testing.expectEqualStrings("type definition changed", report.changes.items[0].detail);
}

test "changing an enum between exhaustive and open is breaking" {
    const closed: semantic.Semantic = .{
        .package = "terminal",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "below", .value = 0 }},
            .kind = .@"enum",
            .name = "EraseDisplay",
            .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
        }},
        .zig_version = "0.16.0",
    };
    const open: semantic.Semantic = .{
        .package = "terminal",
        .prefix = "zg",
        .types = &.{.{
            .exhaustive = false,
            .fields = &.{.{ .name = "below", .value = 0 }},
            .kind = .@"enum",
            .name = "EraseDisplay",
            .open = true,
            .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
        }},
        .zig_version = "0.16.0",
    };
    var report = try diff(std.testing.allocator, closed, open);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
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

test "appending a value-parameter tagged union variant is breaking" {
    const base: semantic.Semantic = .{
        .functions = &.{.{
            .name = "consume",
            .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_consume",
        }},
        .package = "variant",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "none", .type = .{ .void = {} }, .value = 0 }},
            .kind = .tagged_union,
            .name = "Value",
            .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
        }},
        .zig_version = "0.16.0",
    };
    var current = base;
    current.types = &.{.{
        .fields = &.{
            .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
            .{ .name = "number", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
        },
        .kind = .tagged_union,
        .name = "Value",
        .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
    }};
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
    // Two entries name the same growth from both ends: the function whose
    // lowered C signature gained the new variant's payload parameter, and the
    // type declaration the variant was appended to.
    var named_the_type = false;
    for (report.changes.items) |change| {
        if (std.mem.eql(u8, change.detail, "tagged-union variant appended; a value-parameter C signature grew"))
            named_the_type = true;
    }
    try std.testing.expect(named_the_type);
    try std.testing.expectEqualStrings("signature changed", report.changes.items[0].detail);
    try std.testing.expectEqualStrings("consume", report.changes.items[0].subject);
}

test "removing renaming or retagging an existing variant is breaking" {
    const base: semantic.Semantic = .{
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
                .fields = &.{ .{ .name = "none", .value = 0 }, .{ .name = "number", .value = 1 }, .{ .name = "integer", .value = 1 } },
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
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
            .types = &.{
                .{
                    .fields = fields,
                    .kind = .tagged_union,
                    .name = "Value",
                    .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
                },
                .{
                    .fields = &.{ .{ .name = "none", .value = 0 }, .{ .name = "number", .value = 1 }, .{ .name = "integer", .value = 1 } },
                    .kind = .@"enum",
                    .name = "ValueTag",
                    .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
                },
            },
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

test "borrowed and caller-owned handle returns are ABI breaking" {
    const borrowed: semantic.SemanticFn = .{
        .borrowed_return = true,
        .name = "view",
        .params = &.{},
        .receiver = "Parent",
        .@"return" = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "View" } },
        .symbol = "zg_parent_view",
    };
    var caller = borrowed;
    caller.borrowed_return = null;
    caller.ownership = .caller;
    const base: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{borrowed} };
    const current: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{caller} };
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
    try std.testing.expectEqualStrings("return ownership or semantics changed", report.changes.items[0].detail);
}

test "an injected argument moves nothing while the Go owner moves the surface" {
    var byte_element: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const free: semantic.SemanticFn = .{
        .name = "freeString",
        .params = &.{.{ .name = "str", .type = .{ .slice = .{ .@"const" = true, .element = &byte_element } } }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_free_string",
    };
    var injected = free;
    injected.params = &.{
        .{ .injected = .allocator, .name = "allocator", .type = .{ .void = {} } },
        free.params[0],
    };
    const base: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{free} };
    const current: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{injected} };
    // The allocator has no C parameter and no Go argument, so taking it as a
    // parameter changes neither signature.
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), report.changes.items.len);

    var owned = free;
    owned.go_owner = "Terminal";
    const grouped: semantic.Semantic = .{ .package = "demo", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{owned} };
    var owner_report = try diff(std.testing.allocator, base, grouped);
    defer owner_report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), owner_report.changes.items.len);
    try std.testing.expectEqual(ChangeKind.breaking, owner_report.changes.items[0].kind);
    try std.testing.expectEqualStrings("Go owner changed", owner_report.changes.items[0].detail);
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

test "dependent lifetime changes are ABI compatible Go-surface changes" {
    const plain: semantic.SemanticFn = .{
        .name = "newChild",
        .params = &.{},
        .receiver = "Parent",
        .@"return" = .{ .void = {} },
        .symbol = "zg_parent_new_child",
    };
    var dependent = plain;
    dependent.child_of_receiver = true;
    const base: semantic.Semantic = .{ .package = "handles", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{plain} };
    const current: semantic.Semantic = .{ .package = "handles", .prefix = "zg", .zig_version = "0.16.0", .functions = &.{dependent} };

    var gained = try diff(std.testing.allocator, base, current);
    defer gained.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), gained.changes.items.len);
    try std.testing.expectEqual(ChangeKind.compatible, gained.changes.items[0].kind);
    try std.testing.expectEqualStrings("dependent handle lifetime Go surface changed", gained.changes.items[0].detail);
    try std.testing.expect(!gained.hasBreaking());

    var lost = try diff(std.testing.allocator, current, base);
    defer lost.deinit(std.testing.allocator);
    try std.testing.expectEqual(ChangeKind.compatible, lost.changes.items[0].kind);
    try std.testing.expect(!lost.hasBreaking());
}

test "callback failure result changes are ABI compatible" {
    var result: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const callback_params = [_]semantic.TypeNode{};
    const callback: semantic.TypeNode = .{ .callback = .{ .has_userdata = false, .params = &callback_params, .@"return" = &result } };
    const plain_params = [_]semantic.Parameter{.{ .name = "callback", .type = callback }};
    const fallback_params = [_]semantic.Parameter{.{ .name = "callback", .on_callback_failure = .{ .result = 0 }, .type = callback }};
    const plain_functions = [_]semantic.SemanticFn{.{ .name = "run", .params = &plain_params, .@"return" = .{ .void = {} }, .symbol = "zg_run" }};
    const fallback_functions = [_]semantic.SemanticFn{.{ .name = "run", .params = &fallback_params, .@"return" = .{ .void = {} }, .symbol = "zg_run" }};
    const plain: semantic.Semantic = .{ .functions = &plain_functions, .package = "cb", .prefix = "zg", .zig_version = "0.16.0" };
    const fallback: semantic.Semantic = .{ .functions = &fallback_functions, .package = "cb", .prefix = "zg", .zig_version = "0.16.0" };
    var report = try diff(std.testing.allocator, plain, fallback);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), report.changes.items.len);
    try std.testing.expectEqual(ChangeKind.compatible, report.changes.items[0].kind);
    try std.testing.expectEqualStrings("callback failure result changed", report.changes.items[0].detail);
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

test "materialized tree field and pointer-shape changes are breaking" {
    const child_value: semantic.TypeField = .{ .name = "child", .type = .{ .materialized = .{ .ref = "Leaf" } } };
    const child_pointer: semantic.TypeField = .{ .name = "child", .type = .{ .materialized = .{ .ref = "Leaf", .pointer = true } } };
    const extra: semantic.TypeField = .{ .name = "count", .type = .{ .int = .{ .bits = 32, .signed = false } } };
    const base_fields = [_]semantic.TypeField{child_value};
    const pointer_fields = [_]semantic.TypeField{child_pointer};
    const appended_fields = [_]semantic.TypeField{ child_value, extra };
    const base_types = [_]semantic.TypeDecl{.{ .fields = &base_fields, .kind = .materialized, .name = "Root" }};
    const base: semantic.Semantic = .{ .package = "contract", .prefix = "zg", .types = &base_types, .zig_version = "0.16.0" };
    const changed_fields = [_][]const semantic.TypeField{ &pointer_fields, &appended_fields };
    for (changed_fields) |fields| {
        const current_types = [_]semantic.TypeDecl{.{ .fields = fields, .kind = .materialized, .name = "Root" }};
        var current = base;
        current.types = &current_types;
        var report = try diff(std.testing.allocator, base, current);
        defer report.deinit(std.testing.allocator);
        try std.testing.expect(report.hasBreaking());
        try std.testing.expectEqualStrings("type definition changed", report.changes.items[0].detail);
    }
}

test "packed struct append within its backing width is compatible and other field changes break" {
    const enabled: semantic.TypeField = .{ .name = "enabled", .type = .{ .bool = {} } };
    const level: semantic.TypeField = .{ .name = "level", .type = .{ .int = .{ .bits = 3, .signed = false } } };
    const renamed: semantic.TypeField = .{ .name = "active", .type = .{ .bool = {} } };
    const wide: semantic.TypeField = .{ .name = "level", .type = .{ .int = .{ .bits = 4, .signed = false } } };
    const base_fields = [_]semantic.TypeField{enabled};
    const base_types = [_]semantic.TypeDecl{.{
        .backing_type = .{ .int = .{ .bits = 16, .signed = false } },
        .fields = &base_fields,
        .kind = .value_struct,
        .layout = .@"packed",
        .name = "Flags",
    }};
    const base: semantic.Semantic = .{ .package = "contract", .prefix = "zg", .types = &base_types, .zig_version = "0.16.0" };

    const appended_fields = [_]semantic.TypeField{ enabled, level };
    const appended_types = [_]semantic.TypeDecl{.{
        .backing_type = .{ .int = .{ .bits = 16, .signed = false } },
        .fields = &appended_fields,
        .kind = .value_struct,
        .layout = .@"packed",
        .name = "Flags",
    }};
    var appended = base;
    appended.types = &appended_types;
    var compatible = try diff(std.testing.allocator, base, appended);
    defer compatible.deinit(std.testing.allocator);
    try std.testing.expect(!compatible.hasBreaking());
    try std.testing.expectEqualStrings("packed-struct field appended within backing width", compatible.changes.items[0].detail);

    const removed_fields = [_]semantic.TypeField{};
    const renamed_fields = [_]semantic.TypeField{renamed};
    const widened_fields = [_]semantic.TypeField{wide};
    const breaking_fields = [_][]const semantic.TypeField{ &removed_fields, &renamed_fields, &widened_fields };
    for (breaking_fields) |fields| {
        const current_types = [_]semantic.TypeDecl{.{
            .backing_type = .{ .int = .{ .bits = 16, .signed = false } },
            .fields = fields,
            .kind = .value_struct,
            .layout = .@"packed",
            .name = "Flags",
        }};
        var current = base;
        current.types = &current_types;
        var report = try diff(std.testing.allocator, base, current);
        defer report.deinit(std.testing.allocator);
        try std.testing.expect(report.hasBreaking());
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

test "a resized stream buffer is compatible while the direction is breaking" {
    const writer: semantic.TypeNode = .{ .io_stream = .{ .direction = .writer } };
    const reader: semantic.TypeNode = .{ .io_stream = .{ .direction = .reader } };
    const old: []const semantic.SemanticFn = &.{.{
        .name = "dump",
        .params = &.{.{ .name = "w", .type = writer }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_dump",
    }};
    const resized: []const semantic.SemanticFn = &.{.{
        .name = "dump",
        .params = &.{.{ .buffer = 4096, .name = "w", .type = writer }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_dump",
    }};
    const flipped: []const semantic.SemanticFn = &.{.{
        .name = "dump",
        .params = &.{.{ .name = "w", .type = reader }},
        .@"return" = .{ .void = {} },
        .symbol = "zg_dump",
    }};

    var buffer_report = try diff(
        std.testing.allocator,
        .{ .functions = old, .package = "stream", .prefix = "zg", .zig_version = "0.16.0" },
        .{ .functions = resized, .package = "stream", .prefix = "zg", .zig_version = "0.16.0" },
    );
    defer buffer_report.deinit(std.testing.allocator);
    try std.testing.expect(!buffer_report.hasBreaking());
    try std.testing.expectEqual(@as(usize, 1), buffer_report.changes.items.len);
    try std.testing.expectEqual(ChangeKind.compatible, buffer_report.changes.items[0].kind);
    try std.testing.expectEqualStrings("stream staging buffer resized", buffer_report.changes.items[0].detail);

    var direction_report = try diff(
        std.testing.allocator,
        .{ .functions = old, .package = "stream", .prefix = "zg", .zig_version = "0.16.0" },
        .{ .functions = flipped, .package = "stream", .prefix = "zg", .zig_version = "0.16.0" },
    );
    defer direction_report.deinit(std.testing.allocator);
    try std.testing.expect(direction_report.hasBreaking());
}

test "making a parameter or a return optional is breaking" {
    var word: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const optional_word: semantic.TypeNode = .{ .optional = .{ .child = &word } };
    // `?T` grows the C signature: a parameter gains a nullable pointer in
    // place of the value, and a return trades its value for a presence flag
    // plus an out parameter. Neither is something an existing caller links
    // against unchanged.
    const plain: []const semantic.SemanticFn = &.{.{
        .name = "double",
        .params = &.{.{ .name = "value", .type = word }},
        .@"return" = word,
        .symbol = "zg_double",
    }};
    const optional_param: []const semantic.SemanticFn = &.{.{
        .name = "double",
        .params = &.{.{ .name = "value", .type = optional_word }},
        .@"return" = word,
        .symbol = "zg_double",
    }};
    const optional_return: []const semantic.SemanticFn = &.{.{
        .name = "double",
        .params = &.{.{ .name = "value", .type = word }},
        .@"return" = optional_word,
        .symbol = "zg_double",
    }};

    var parameter_report = try diff(
        std.testing.allocator,
        .{ .functions = plain, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" },
        .{ .functions = optional_param, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" },
    );
    defer parameter_report.deinit(std.testing.allocator);
    try std.testing.expect(parameter_report.hasBreaking());

    var return_report = try diff(
        std.testing.allocator,
        .{ .functions = plain, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" },
        .{ .functions = optional_return, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" },
    );
    defer return_report.deinit(std.testing.allocator);
    try std.testing.expect(return_report.hasBreaking());

    // A slice carries absence in its own pointer rather than in an extra
    // parameter, so `[]T` and `?[]T` share a C signature -- but not a Go one,
    // and the raw layer's return arity differs, so it is still breaking.
    var element: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &element } };
    const optional_slice: semantic.TypeNode = .{ .optional = .{ .child = &slice } };
    const plain_slice: []const semantic.SemanticFn = &.{.{
        .name = "digits",
        .params = &.{},
        .@"return" = slice,
        .symbol = "zg_digits",
    }};
    const optional_slice_fn: []const semantic.SemanticFn = &.{.{
        .name = "digits",
        .params = &.{},
        .@"return" = optional_slice,
        .symbol = "zg_digits",
    }};
    var slice_report = try diff(
        std.testing.allocator,
        .{ .functions = plain_slice, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" },
        .{ .functions = optional_slice_fn, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" },
    );
    defer slice_report.deinit(std.testing.allocator);
    try std.testing.expect(slice_report.hasBreaking());

    // The same optional on both sides is not a change at all.
    var stable_report = try diff(
        std.testing.allocator,
        .{ .functions = optional_param, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" },
        .{ .functions = optional_param, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" },
    );
    defer stable_report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), stable_report.changes.items.len);
}

test "an error set that only changed order is not a break" {
    var payload: semantic.TypeNode = .{ .void = {} };
    const Sets = struct {
        fn document(comptime names: []const []const u8) semantic.Semantic {
            return .{
                .functions = &.{.{
                    .name = "query",
                    .params = &.{},
                    .receiver = "Hub",
                    .@"return" = .{ .error_union = .{ .error_set = names, .payload = undefined } },
                    .symbol = "zg_hub_query",
                }},
                .package = "hub",
                .prefix = "zg",
                .zig_version = "0.16.0",
            };
        }
    };
    var base = Sets.document(&.{ "InvalidRange", "Empty" });
    var reordered = Sets.document(&.{ "Empty", "InvalidRange" });
    var appended = Sets.document(&.{ "Empty", "Canceled", "InvalidRange" });
    var removed = Sets.document(&.{"Empty"});
    for ([_]*semantic.Semantic{ &base, &reordered, &appended, &removed }) |document| {
        var functions = @constCast(document.functions);
        functions[0].@"return".error_union.payload = &payload;
    }

    // Declaring an unrelated error set moves Zig's reflection order for this
    // one, and the codes are pinned by errors.lock.json either way.
    var same = try diff(std.testing.allocator, base, reordered);
    defer same.deinit(std.testing.allocator);
    try std.testing.expect(!same.hasBreaking());
    try std.testing.expectEqual(@as(usize, 0), same.changes.items.len);

    // A member added anywhere is still just an addition.
    var grew = try diff(std.testing.allocator, base, appended);
    defer grew.deinit(std.testing.allocator);
    try std.testing.expect(!grew.hasBreaking());
    try std.testing.expectEqualStrings("error appended", grew.changes.items[0].detail);

    // A member that is gone is still a break: callers matched on it.
    var shrank = try diff(std.testing.allocator, base, removed);
    defer shrank.deinit(std.testing.allocator);
    try std.testing.expect(shrank.hasBreaking());
}

test "adding or removing cancellation is a Go signature break" {
    var payload: semantic.TypeNode = .{ .void = {} };
    const flag: semantic.TypeNode = .{ .cancel_flag = {} };
    const errors = [_][]const u8{"Canceled"};
    const plain: semantic.Semantic = .{
        .functions = &.{.{
            .name = "crunch",
            .params = &.{.{ .name = "cancel", .type = flag }},
            .receiver = "Job",
            .@"return" = .{ .error_union = .{ .error_set = &errors, .payload = &payload } },
            .symbol = "zg_job_crunch",
        }},
        .package = "job",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var cancellable = plain;
    const functions = try std.testing.allocator.alloc(semantic.SemanticFn, 1);
    defer std.testing.allocator.free(functions);
    functions[0] = plain.functions[0];
    functions[0].cancel = "cancel";
    const params = try std.testing.allocator.alloc(semantic.Parameter, 1);
    defer std.testing.allocator.free(params);
    params[0] = .{ .cancel = true, .name = "cancel", .type = flag };
    functions[0].params = params;
    cancellable.functions = functions;

    // The C signature is identical; the Go one gains a leading ctx.
    var report = try diff(std.testing.allocator, plain, cancellable);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
    try std.testing.expectEqualStrings("cancellation surface changed", report.changes.items[0].detail);

    var explicit_default_functions = [_]semantic.SemanticFn{functions[0]};
    explicit_default_functions[0].cancel_error = "Canceled";
    var explicit_default = cancellable;
    explicit_default.functions = &explicit_default_functions;
    var unchanged = try diff(std.testing.allocator, cancellable, explicit_default);
    defer unchanged.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), unchanged.changes.items.len);

    var configured_functions = [_]semantic.SemanticFn{functions[0]};
    configured_functions[0].cancel_error = "Cancelled";
    var configured = cancellable;
    configured.functions = &configured_functions;
    var remapped = try diff(std.testing.allocator, cancellable, configured);
    defer remapped.deinit(std.testing.allocator);
    try std.testing.expect(remapped.hasBreaking());
    try std.testing.expectEqualStrings("cancellation error mapping changed", remapped.changes.items[0].detail);
}

test "changing an explicit constructor name is a Go signature break" {
    const result: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "AudioBuffer" } };
    const base_functions = [_]semantic.SemanticFn{.{
        .go_owner = "AudioBuffer",
        .name = "makeBuffer",
        .ownership = .caller,
        .params = &.{},
        .@"return" = result,
        .symbol = "zg_make_buffer",
    }};
    const current_functions = [_]semantic.SemanticFn{.{
        .go_owner = "AudioBuffer",
        .name = "extractAudio",
        .ownership = .caller,
        .params = &.{},
        .@"return" = result,
        .symbol = "zg_make_buffer",
        .zig_path = "makeBuffer",
    }};
    const base_constructors = [_]semantic.Constructor{.{ .deinit = "freeBuffer", .init = "makeBuffer", .type = "AudioBuffer" }};
    const current_constructors = [_]semantic.Constructor{.{ .deinit = "freeBuffer", .init = "extractAudio", .name = "extractAudio", .type = "AudioBuffer" }};
    const base: semantic.Semantic = .{ .constructors = &base_constructors, .functions = &base_functions, .package = "audio", .prefix = "zg", .zig_version = "0.16.0" };
    const current: semantic.Semantic = .{ .constructors = &current_constructors, .functions = &current_functions, .package = "audio", .prefix = "zg", .zig_version = "0.16.0" };

    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.hasBreaking());
    var found = false;
    for (report.changes.items) |change| {
        if (std.mem.eql(u8, change.detail, "Go signature changed")) found = true;
    }
    try std.testing.expect(found);
}

test "a sentinel the lowered program never sees is not a change" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const plain: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    const sentinel: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte, .sentinel = 0 } };
    // Both documents live in this frame: a helper returning `&.{...}` built
    // from a runtime parameter would hand back a pointer into its own stack.
    const plain_params = [_]semantic.Parameter{.{ .name = "text", .semantic = .utf8_string, .type = plain }};
    const sentinel_params = [_]semantic.Parameter{.{ .name = "text", .semantic = .utf8_string, .type = sentinel }};
    const plain_functions = [_]semantic.SemanticFn{.{ .name = "greet", .params = &plain_params, .@"return" = .{ .void = {} }, .symbol = "zg_greet" }};
    const sentinel_functions = [_]semantic.SemanticFn{.{ .name = "greet", .params = &sentinel_params, .@"return" = .{ .void = {} }, .symbol = "zg_greet" }};
    const base: semantic.Semantic = .{ .functions = &plain_functions, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" };
    const current: semantic.Semantic = .{ .functions = &sentinel_functions, .package = "demo", .prefix = "zg", .zig_version = "0.16.0" };
    // The sentinel is an annotation the shim uses to rebuild the Zig type; it
    // does not reach C, and the comparison now sees only what lowering
    // produced, so there is nothing to report.
    var report = try diff(std.testing.allocator, base, current);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), report.changes.items.len);
}
