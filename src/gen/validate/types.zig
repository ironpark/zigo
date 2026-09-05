//! Registered type declarations and the C ABI rules every type answers to.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const functions = @import("functions.zig");
const materialized = @import("materialized.zig");
const ownership = @import("ownership.zig");
const site = @import("site.zig");
const validate = @import("validate.zig");

/// Every registered type, judged on its own declaration.
pub fn typeIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.types) |declaration| {
        if (declaration.kind == .materialized) {
            if (try materialized.materializedProblemAlloc(allocator, document, declaration)) |problem| return .{
                .severity = .@"error",
                .code = "ZIGO048",
                .message = try std.fmt.allocPrint(allocator, "materialized field `{s}` is unsupported", .{problem.path}),
                .site = .{ .path = "semantic.json", .declaration = declaration.name },
                .hint = problem.reason,
            };
        }
        if (declaration.omitted_variants) |omitted| {
            for (omitted, 0..) |name, index| {
                var found = false;
                for (declaration.fields) |field| if (std.mem.eql(u8, field.name, name)) {
                    found = true;
                    break;
                };
                for (omitted[0..index]) |earlier| if (std.mem.eql(u8, earlier, name)) {
                    found = false;
                    break;
                };
                if (!found) return .{
                    .severity = .@"error",
                    .code = "ZIGO039",
                    .message = "invalid omitted tagged-union variant",
                    .site = .{ .path = "semantic.json", .declaration = declaration.name },
                    .hint = try std.fmt.allocPrint(allocator, "name `{s}` exactly once in `.omit_variants` and ensure it is a variant of the registered union", .{name}),
                };
            }
        }
        for (declaration.fields) |field| {
            const node = field.type orelse continue;
            if (!functions.containsIoStream(node)) continue;
            return .{
                .severity = .@"error",
                .code = "ZIGO023",
                .message = try std.fmt.allocPrint(allocator, "`*std.Io.Writer` and `*std.Io.Reader` are only supported as whole parameters, not in field `{s}`", .{field.name}),
                .site = .{ .path = "semantic.json", .declaration = declaration.name },
                .hint = "the shim adapter lives on the call stack, so a stream cannot be stored; take the stream as a parameter of the function that uses it",
            };
        }
        if (declaration.kind == .@"enum" and declaration.open == true and declaration.exhaustive) return .{
            .severity = .@"error",
            .code = "ZIGO029",
            .message = "open-enum opt-in applied to an exhaustive enum",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "remove `.exhaustive = false`, or make the Zig enum non-exhaustive",
        };
        if (declaration.text == true and declaration.kind != .@"enum") return .{
            .severity = .@"error",
            .code = "ZIGO051",
            .message = "text encoding opt-in applied to a type that is not an enum",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "`.text = true` belongs on `.repr = .enumeration` entries only",
        };
        if (declaration.kind == .@"enum" and !declaration.exhaustive and declaration.open != true) return .{
            .severity = .@"error",
            .code = "ZIGO002",
            .message = "cannot expose a non-exhaustive enum",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "make the enum exhaustive, or register it with `.exhaustive = false`",
        };
        if (declaration.kind == .tagged_union and
            !document.isValueOnlyTaggedUnion(declaration.name) and
            !taggedUnionAccessorsSupported(document, declaration)) return .{
            .severity = .@"error",
            .code = "ZIGO006",
            .message = "tagged union contains a payload that cannot use generated accessors",
            .site = .{ .path = "semantic.json", .declaration = declaration.name },
            .hint = "use void, scalar, enum, opaque-pointer, or numeric-slice payloads",
        };
        if (declaration.kind == .value_struct and declaration.layout == .@"extern") {
            // A width zigo would promote elsewhere gets its own message here:
            // the field is mirrored into C byte for byte, with no shim in
            // between to convert it.
            for (declaration.fields) |field| {
                const node = field.type orelse continue;
                if (node != .int or integerSupported(node.int) or !promotableInteger(node.int)) continue;
                const spelling = try zigSpellingAlloc(allocator, node);
                return .{
                    .severity = .@"error",
                    .code = "ZIGO018",
                    .message = try std.fmt.allocPrint(allocator, "cannot promote integer width `{s}` in field `{s}`", .{ spelling, field.name }),
                    .site = .{ .path = "semantic.json", .declaration = declaration.name },
                    .hint = "an `extern struct` is mirrored into C field by field; use an 8, 16, 32, or 64-bit integer here",
                };
            }
            if (externStructProblem(document, declaration, 0)) |problem_site| return .{
                .severity = .@"error",
                .code = "ZIGO012",
                .message = "extern struct cannot cross the C ABI",
                .site = .{ .path = "semantic.json", .declaration = problem_site },
                .hint = "give every field a bool, integer, float, registered enum, or nested `extern struct` type; an empty struct has no C representation",
            };
        }
        if (declaration.kind == .value_struct and declaration.layout == .@"packed") {
            if (packedStructProblem(document, declaration, 0)) |field| return .{
                .severity = .@"error",
                .code = "ZIGO044",
                .message = try std.fmt.allocPrint(allocator, "packed struct field `{s}` cannot cross as a value", .{field}),
                .site = .{ .path = "semantic.json", .declaration = declaration.name },
                .hint = "use only bool, integer, registered enum, or registered integer-backed packed struct fields",
            };
        }
        if (declaration.kind == .tagged_union and declaration.accessStrategy() == .snapshot) {
            if (snapshotIneligibleVariant(document, declaration)) |variant| return .{
                .severity = .@"error",
                .code = "ZIGO011",
                .message = "tagged union variant cannot be mirrored into a value snapshot",
                .site = .{ .path = "semantic.json", .declaration = variant },
                .hint = "use `.access = .projection`, or give every variant a void, bool, integer, float, or enum payload and a name other than `tag`",
            };
        }
    }
    return null;
}

pub fn integrityIssue(_: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    if (findIntegrityProblem(document)) |declaration| return .{
        .severity = .@"error",
        .code = "ZIGO010",
        .message = "semantic document contains an unresolved or incompatible declaration reference",
        .site = .{ .path = "semantic.json", .declaration = declaration },
        .hint = "regenerate semantic.json from matching bindings and source declarations",
    };
    return null;
}

// Types the C ABI cannot name are reported last so that the sharper
// diagnostics above keep naming the declarations they always did.
pub fn abiTypeIssue(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.functions) |function| {
        for (function.params) |parameter| {
            if (parameter.type == .atomic_ptr) continue;
            if (abi.narrowSliceElement(parameter.type.errorPayload()) != null) {
                if (document.allocator == null) return .{
                    .severity = .@"error",
                    .code = "ZIGO045",
                    .message = try std.fmt.allocPrint(
                        allocator,
                        "narrow integer slice parameter `{s}` needs temporary storage",
                        .{parameter.name},
                    ),
                    .site = site.functionSiteFor(function, try site.functionDeclarationAlloc(allocator, function)),
                    .hint = "set `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator`, or a declaration path in the binding",
                };
            }
            if (try typeOffense(allocator, parameter.type, true)) |offense| {
                const root = try std.fmt.allocPrint(allocator, "parameter `{s}`", .{parameter.name});
                const location = try locationAlloc(allocator, offense.context, root);
                return try offenseDiagnostic(allocator, function, offense, location);
            }
        }
        if (abi.narrowSliceElement(function.@"return".errorPayload())) |element| {
            if (function.ownership != .caller or function.release == null) {
                const spelling = try zigSpellingAlloc(allocator, element);
                return .{
                    .severity = .@"error",
                    .code = "ZIGO018",
                    .message = try std.fmt.allocPrint(allocator, "cannot promote integer width `{s}` in a borrowed slice return", .{spelling}),
                    .site = site.functionSiteFor(function, try site.functionDeclarationAlloc(allocator, function)),
                    .hint = "mark the slice return `.returns = .caller` and name its `.release`; borrowed narrow slices have no stable widened storage",
                };
            }
        }
        if (try typeOffense(allocator, function.@"return", true)) |offense| {
            const location = try locationAlloc(allocator, offense.context, "the return value");
            return try offenseDiagnostic(allocator, function, offense, location);
        }
    }
    return null;
}

/// The type the C ABI cannot name, plus how it was reached from the parameter
/// or return value that carries it. `context` is built on the way back out, so
/// a document that validates never allocates.
const Offense = struct {
    node: semantic.TypeNode,
    context: ?[]const u8 = null,
    reason: Reason = .unsupported,

    /// `narrow_position` is a width zigo does promote, found where it cannot:
    /// the two need different hints because only one of them is about the type.
    const Reason = enum { unsupported, narrow_position };
};

/// `promotable` is true only where the shim stands between Zig and C and can
/// convert a single value. Nested positions are mirrored byte for byte, so a
/// width C cannot name is still a rejection there.
fn typeOffense(allocator: std.mem.Allocator, node: semantic.TypeNode, promotable: bool) error{OutOfMemory}!?Offense {
    switch (node) {
        .void, .bool, .@"enum", .materialized, .opaque_ptr, .value_struct, .io_stream, .cancel_flag => return null,
        .atomic_ptr => return Offense{ .node = node },
        .int => |value| {
            if (integerSupported(value)) return null;
            if (promotable and promotableInteger(value)) return null;
            return Offense{ .node = node, .reason = if (promotableInteger(value)) .narrow_position else .unsupported };
        },
        .float => |value| return if (floatSupported(value)) null else Offense{ .node = node },
        // `?T` only has an ABI shape as a whole parameter, return value, or
        // error payload -- `promotable` doubles as "is this that position"
        // for every caller here, so a slice element or callback signature
        // reaches this the same way a bare unsupported type would. The
        // allowed children are the ones `walk.zig` can reflect: bool, an
        // integer (narrow ones promoted exactly as a bare parameter would
        // be), float, enum, or an extern struct (checked for `extern`-ness by
        // `unsupportedValueStruct`, not here).
        .optional => |value| {
            if (!promotable) return Offense{ .node = node };
            return switch (value.child.*) {
                .bool, .@"enum", .value_struct => null,
                .int => |integer| if (integerSupported(integer) or promotableInteger(integer))
                    null
                else
                    Offense{ .node = value.child.*, .reason = .unsupported },
                .float => |float| if (floatSupported(float)) null else Offense{ .node = value.child.* },
                // `?[]T` spends the slice's own pointer on absence, so the
                // element rules are exactly the slice ones. A slice of slices
                // is the exception: its lowering builds a second array of
                // pointers, and there is no NULL left to mean absent.
                .slice => |slice| if (slice.element.* == .slice)
                    Offense{ .node = node }
                else
                    wrapOffense(allocator, try typeOffense(allocator, slice.element.*, false), "the slice element"),
                else => Offense{ .node = node },
            };
        },
        // A direct slice of narrow integers has a promoted C element type and
        // is converted element by element by the shim. Sentinel slices retain
        // their existing rule.
        .slice => |value| return wrapOffense(
            allocator,
            try typeOffense(allocator, value.element.*, value.sentinel == null and value.element.* == .int),
            "the slice element",
        ),
        .error_union => |value| return wrapOffense(allocator, try typeOffense(allocator, value.payload.*, promotable), "the error payload"),
        .callback => |value| {
            for (value.params, 0..) |parameter, index| {
                if (try typeOffense(allocator, parameter, false)) |found| {
                    const label = try std.fmt.allocPrint(allocator, "callback parameter {d}", .{index});
                    return wrapOffense(allocator, found, label);
                }
            }
            return wrapOffense(allocator, try typeOffense(allocator, value.@"return".*, false), "the callback return value");
        },
    }
}

fn wrapOffense(allocator: std.mem.Allocator, found: ?Offense, label: []const u8) error{OutOfMemory}!?Offense {
    const offense = found orelse return null;
    const context = offense.context orelse return Offense{ .node = offense.node, .context = label, .reason = offense.reason };
    return Offense{
        .node = offense.node,
        .context = try std.fmt.allocPrint(allocator, "{s} of {s}", .{ context, label }),
        .reason = offense.reason,
    };
}

fn locationAlloc(allocator: std.mem.Allocator, context: ?[]const u8, root: []const u8) ![]const u8 {
    const inner = context orelse return root;
    return std.fmt.allocPrint(allocator, "{s} of {s}", .{ inner, root });
}

fn offenseDiagnostic(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    offense: Offense,
    location: []const u8,
) !diagnostic.Diagnostic {
    const node = offense.node;
    const spelling = try zigSpellingAlloc(allocator, node);
    const declaration = try site.functionDeclarationAlloc(allocator, function);
    return switch (node) {
        .int => if (offense.reason == .narrow_position) .{
            .severity = .@"error",
            .code = "ZIGO018",
            .message = try std.fmt.allocPrint(allocator, "cannot promote integer width `{s}` in {s}", .{ spelling, location }),
            .site = site.functionSiteFor(function, declaration),
            .hint = "zigo widens narrow integers only as whole values or direct non-sentinel slice elements; value-struct fields, union payloads, callbacks, and nested slices must use 8, 16, 32, or 64 bits",
        } else .{
            .severity = .@"error",
            .code = "ZIGO018",
            .message = try std.fmt.allocPrint(allocator, "unsupported integer width `{s}` in {s}", .{ spelling, location }),
            .site = site.functionSiteFor(function, declaration),
            .hint = "use an integer of 64 bits or fewer",
        },
        .float => .{
            .severity = .@"error",
            .code = "ZIGO018",
            .message = try std.fmt.allocPrint(allocator, "unsupported float width `{s}` in {s}", .{ spelling, location }),
            .site = site.functionSiteFor(function, declaration),
            .hint = "use `f32` or `f64`",
        },
        // `?T` has a C shape only as a whole parameter, return value, or
        // error payload; anywhere else there is nowhere to put presence, so
        // the generic hint would send the reader looking for the wrong fix.
        .optional => .{
            .severity = .@"error",
            .code = "ZIGO019",
            .message = try std.fmt.allocPrint(allocator, "unsupported optional in {s}", .{location}),
            .site = site.functionSiteFor(function, declaration),
            .hint = "zigo carries an optional only as a whole parameter, return value, or error payload, and only over a bool, integer, float, enum, extern struct, or pointer to a declared opaque type",
        },
        else => .{
            .severity = .@"error",
            .code = "ZIGO019",
            .message = try std.fmt.allocPrint(allocator, "unsupported type `{s}` in {s}", .{ spelling, location }),
            .site = site.functionSiteFor(function, declaration),
            .hint = "use a bool, integer, float, enum, opaque pointer, extern struct, slice, or callback type",
        },
    };
}

/// How a Zig author spells the offending type, so the message names what they
/// wrote rather than the IR tag that stands in for it.
fn zigSpellingAlloc(allocator: std.mem.Allocator, node: semantic.TypeNode) ![]const u8 {
    return switch (node) {
        .int => |value| if (value.is_usize)
            try allocator.dupe(u8, if (value.signed) "isize" else "usize")
        else
            try std.fmt.allocPrint(allocator, "{s}{d}", .{ if (value.signed) "i" else "u", value.bits }),
        .float => |value| try std.fmt.allocPrint(allocator, "f{d}", .{value.bits}),
        else => try allocator.dupe(u8, @tagName(node)),
    };
}

fn findIntegrityProblem(document: semantic.Semantic) ?[]const u8 {
    for (document.types, 0..) |declaration, index| {
        for (document.types[0..index]) |previous| {
            if (std.mem.eql(u8, declaration.name, previous.name)) return declaration.name;
        }
        if (declaration.kind == .@"enum") {
            const tag = declaration.tag_type orelse return declaration.name;
            if (tag != .int or tag.int.bits == 0 or tag.int.bits > 64) return declaration.name;
        } else if (declaration.tag_type) |tag| {
            // A tagged union names its tag enum through `tag_type`, and
            // lowering resolves that reference the same way it resolves a
            // field's: an unresolved one has to be reported here, not met as
            // an `unreachable` inside `lower`.
            if (!referencesValid(document, tag)) return declaration.name;
        }
        for (declaration.fields) |field| {
            if (field.type) |node| if (!referencesValid(document, node)) return declaration.name;
        }
    }
    for (document.functions) |function| {
        if (function.receiver) |receiver| {
            if (!hasHandleType(document, receiver)) return function.name;
        }
        for (function.params) |parameter| {
            if (!referencesValid(document, parameter.type)) return function.name;
            // A flattened parameter's selected fields are lowered on their
            // own, so their references have to resolve on their own too.
            if (parameter.flatten) |fields| {
                for (fields) |field| if (!referencesValid(document, field.type)) return function.name;
            }
        }
        if (!referencesValid(document, function.@"return")) return function.name;
    }
    for (document.constructors, 0..) |constructor, index| {
        if (!hasHandleType(document, constructor.type)) return constructor.type;
        for (document.constructors[0..index]) |previous| {
            if (std.mem.eql(u8, constructor.type, previous.type)) return constructor.type;
        }
        if (!ownership.hasConstructorInit(document, constructor)) return constructor.init;
        if (!ownership.hasConstructorDeinit(document, constructor)) return constructor.deinit;
    }
    return null;
}

fn referencesValid(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .@"enum" => |value| hasTypeKind(document, value.ref, .@"enum"),
        .opaque_ptr => |value| hasHandleType(document, value.ref),
        .value_struct => |value| hasTypeKind(document, value.ref, .value_struct) or hasTypeKind(document, value.ref, .tagged_union),
        .slice => |value| referencesValid(document, value.element.*),
        .optional => |value| referencesValid(document, value.child.*),
        .error_union => |value| referencesValid(document, value.payload.*),
        .callback => |value| blk: {
            if (value.ref) |ref| if (!hasTypeKind(document, ref, .callback)) break :blk false;
            for (value.params) |parameter| if (!referencesValid(document, parameter)) break :blk false;
            break :blk referencesValid(document, value.@"return".*);
        },
        else => true,
    };
}

pub fn containsTaggedUnionValue(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .value_struct => |value| hasTypeKind(document, value.ref, .tagged_union),
        .slice => |value| containsTaggedUnionValue(document, value.element.*),
        .optional => |value| containsTaggedUnionValue(document, value.child.*),
        .error_union => |value| containsTaggedUnionValue(document, value.payload.*),
        .callback => |value| blk: {
            for (value.params) |parameter| if (containsTaggedUnionValue(document, parameter)) break :blk true;
            break :blk containsTaggedUnionValue(document, value.@"return".*);
        },
        else => false,
    };
}

pub fn taggedUnionValueDeclaration(document: semantic.Semantic, node: semantic.TypeNode) ?semantic.TypeDecl {
    if (node != .value_struct) return null;
    for (document.types) |declaration| {
        if (declaration.kind == .tagged_union and std.mem.eql(u8, declaration.name, node.value_struct.ref))
            return declaration;
    }
    return null;
}

/// The first variant that prevents a tagged union from crossing as flattened
/// scalar arguments. The field name is returned so ZIGO006 identifies the
/// actionable payload rather than suggesting the unrelated pointer-handle API.
pub fn taggedUnionValueIneligibleVariant(document: semantic.Semantic, declaration: semantic.TypeDecl) ?[]const u8 {
    if (declaration.fields.len == 0) return declaration.name;
    for (declaration.fields) |field| {
        if (declaration.variantOmitted(field.name)) continue;
        const payload = field.type orelse return field.name;
        if (payload != .void and !taggedUnionValuePayloadSupported(document, payload)) return field.name;
    }
    return null;
}

fn taggedUnionValuePayloadSupported(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .bool => true,
        .int => |value| integerSupported(value),
        .float => |value| floatSupported(value),
        .@"enum" => |value| hasTypeKind(document, value.ref, .@"enum"),
        .value_struct => |value| blk: {
            const declaration = semantic.typeDecl(document.types, value.ref) orelse break :blk false;
            if (declaration.kind != .value_struct) break :blk false;
            break :blk switch (declaration.layout orelse return false) {
                .@"packed" => declaration.backing_type != null and declaration.backing_type.? == .int and
                    promotableInteger(declaration.backing_type.?.int),
                .@"extern" => externStructProblem(document, declaration, 0) == null,
            };
        },
        else => false,
    };
}

fn taggedUnionAccessorsSupported(document: semantic.Semantic, declaration: semantic.TypeDecl) bool {
    const tag = declaration.tag_type orelse return false;
    if (tag != .@"enum" or !hasTypeKind(document, tag.@"enum".ref, .@"enum")) return false;
    if (declaration.fields.len == 0) return false;
    for (declaration.fields) |field| {
        const payload = field.type orelse return false;
        if (!accessorPayloadSupported(document, payload)) return false;
    }
    return true;
}

/// What zigo can move across the C ABI as a single scalar. `bool` crosses as
/// uint8_t exactly as it does everywhere else; public Go restores it. Every
/// payload rule below is this set plus whatever else that position allows.
fn scalarPayloadSupported(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .bool => true,
        .int => |value| integerSupported(value),
        .float => |value| floatSupported(value),
        .@"enum" => |value| hasTypeKind(document, value.ref, .@"enum"),
        .value_struct => semantic.isPackedValue(document.types, node),
        else => false,
    };
}

fn packedStructProblem(document: semantic.Semantic, declaration: semantic.TypeDecl, depth: usize) ?[]const u8 {
    if (depth >= 16 or declaration.backing_type == null or declaration.backing_type.? != .int or
        !promotableInteger(declaration.backing_type.?.int)) return declaration.name;
    for (declaration.fields) |field| {
        const node = field.type orelse return field.name;
        switch (node) {
            .bool, .int => {},
            .@"enum" => |value| if (!hasTypeKind(document, value.ref, .@"enum")) return field.name,
            .value_struct => |value| {
                var found = false;
                for (document.types) |nested| {
                    if (!std.mem.eql(u8, nested.name, value.ref)) continue;
                    found = true;
                    if (nested.kind != .value_struct or nested.layout != .@"packed" or
                        packedStructProblem(document, nested, depth + 1) != null) return field.name;
                    break;
                }
                if (!found) return field.name;
            },
            else => return field.name,
        }
    }
    return null;
}

fn accessorPayloadSupported(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .void => true,
        .opaque_ptr => |value| hasHandleType(document, value.ref),
        .slice => |value| switch (value.element.*) {
            .int => |integer| integerSupported(integer),
            .float => |float| floatSupported(float),
            else => false,
        },
        else => scalarPayloadSupported(document, node),
    };
}

/// The first variant that cannot live in a zigo-owned snapshot struct, or null
/// when the union is eligible. Slices, opaque handles, nested aggregates,
/// optionals, error unions and callbacks all disqualify it: a snapshot must be
/// a flat copy of C-representable scalars.
fn snapshotIneligibleVariant(document: semantic.Semantic, declaration: semantic.TypeDecl) ?[]const u8 {
    for (declaration.fields) |field| {
        const payload = field.type orelse return field.name;
        if (!snapshotPayloadEligible(document, payload)) return field.name;
        // The snapshot struct spells the discriminant `tag`, so no variant may
        // claim that field name.
        if (std.ascii.eqlIgnoreCase(field.name, "tag")) return field.name;
    }
    return null;
}

fn snapshotPayloadEligible(document: semantic.Semantic, node: semantic.TypeNode) bool {
    return switch (node) {
        .void => true,
        else => scalarPayloadSupported(document, node),
    };
}

/// The C mirror of an `extern struct` is a flat record of C-representable
/// members, so a field must be a scalar, a registered enum, or another
/// eligible `extern struct`. Returns the offending field, or the struct itself
/// when it has no fields to mirror.
fn externStructProblem(document: semantic.Semantic, declaration: semantic.TypeDecl, depth: usize) ?[]const u8 {
    // A well-formed document cannot nest structs cyclically, but a hand-written
    // one can; the bound keeps validation total rather than trusting the input.
    if (depth >= 16) return declaration.name;
    if (declaration.fields.len == 0) return declaration.name;
    for (declaration.fields) |field| {
        const node = field.type orelse return field.name;
        if (!externStructFieldEligible(document, node, depth)) return field.name;
    }
    return null;
}

fn externStructFieldEligible(document: semantic.Semantic, node: semantic.TypeNode, depth: usize) bool {
    return switch (node) {
        .value_struct => |value| for (document.types) |nested| {
            if (!std.mem.eql(u8, nested.name, value.ref)) continue;
            break nested.kind == .value_struct and ((nested.layout == .@"extern" and
                externStructProblem(document, nested, depth + 1) == null) or
                (nested.layout == .@"packed" and packedStructProblem(document, nested, depth + 1) == null));
        } else false,
        else => scalarPayloadSupported(document, node),
    };
}

/// The widths C can name directly. Every position that mirrors bytes into C --
/// an `extern struct` field, a slice element, a callback signature -- answers
/// to this one, because those have no shim between the two spellings.
pub fn integerSupported(value: semantic.Int) bool {
    if (value.is_usize) return value.bits != 0 and value.bits <= 64;
    return value.bits == 8 or value.bits == 16 or value.bits == 32 or value.bits == 64;
}

/// A whole parameter, return value, or error payload passes through the shim,
/// which range-checks the value and casts it, so any width Zig can spell up to
/// 64 bits crosses in the next C integer that exists.
fn promotableInteger(value: semantic.Int) bool {
    return !value.is_usize and value.bits >= 1 and value.bits <= 64;
}

pub fn floatSupported(value: semantic.Float) bool {
    return value.bits == 32 or value.bits == 64;
}

pub fn hasTypeKind(document: semantic.Semantic, name: []const u8, kind: semantic.TypeKind) bool {
    const declaration = semantic.typeDecl(document.types, name) orelse return false;
    return declaration.kind == kind;
}

fn hasHandleType(document: semantic.Semantic, name: []const u8) bool {
    return hasTypeKind(document, name, .@"opaque") or hasTypeKind(document, name, .tagged_union);
}

test "a narrow integer is accepted where the shim can promote it" {
    var payload: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "codepointWidth",
                .namespace = "unicode",
                .params = &.{.{ .name = "cp", .type = .{ .int = .{ .bits = 21, .signed = false } } }},
                .@"return" = .{ .int = .{ .bits = 24, .signed = true } },
                .symbol = "zg_unicode_codepoint_width",
            },
            .{
                .name = "decode",
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &payload } },
                .symbol = "zg_decode",
            },
        },
        .package = "narrow",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(scratch.allocator(), document));
}

test "narrow integer slices require an allocator and borrowed returns stay rejected" {
    var narrow: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    const narrow_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &narrow } };
    const input_params = [_]semantic.Parameter{.{ .name = "text", .type = narrow_slice }};
    const release_params = [_]semantic.Parameter{.{ .name = "value", .type = narrow_slice }};
    const accepted_functions = [_]semantic.SemanticFn{
        .{ .name = "width", .params = &input_params, .@"return" = .{ .void = {} }, .symbol = "zg_width" },
        .{ .name = "take", .ownership = .caller, .params = &.{}, .release = "free", .@"return" = narrow_slice, .symbol = "zg_take" },
        .{ .name = "free", .params = &release_params, .@"return" = .{ .void = {} }, .symbol = "zg_free" },
    };
    const accepted: semantic.Semantic = .{
        .allocator = "std.heap.c_allocator",
        .functions = &accepted_functions,
        .package = "narrow",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(std.testing.allocator, accepted));

    var missing_allocator = accepted;
    missing_allocator.allocator = null;
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const allocator_issue = (try validate.findIssue(scratch.allocator(), missing_allocator)).?;
    try std.testing.expectEqualStrings("ZIGO045", allocator_issue.code);
    try std.testing.expect(std.mem.indexOf(u8, allocator_issue.hint, ".allocator") != null);

    const borrowed_functions = [_]semantic.SemanticFn{.{
        .name = "view",
        .params = &.{},
        .@"return" = narrow_slice,
        .symbol = "zg_view",
    }};
    var borrowed = accepted;
    borrowed.functions = &borrowed_functions;
    const borrowed_issue = (try validate.findIssue(scratch.allocator(), borrowed)).?;
    try std.testing.expectEqualStrings("ZIGO018", borrowed_issue.code);
    try std.testing.expect(std.mem.indexOf(u8, borrowed_issue.hint, "borrowed narrow slices") != null);
}

test "scalar extern struct slices and whole optional structs are valid while an optional slice element stays rejected" {
    var element: semantic.TypeNode = .{ .value_struct = .{ .ref = "Point" } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "consume",
                .params = &.{.{ .name = "values", .type = .{ .slice = .{ .@"const" = true, .element = &element } } }},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &element } },
                .symbol = "zg_consume",
            },
        },
        .package = "good",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{
                .{ .name = "x", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                .{ .name = "y", .type = .{ .float = .{ .bits = 64 } } },
            },
            .kind = .value_struct,
            .layout = .@"extern",
            .name = "Point",
        }},
        .zig_version = "0.16.0",
    };
    try validate.semanticDocument(std.testing.allocator, document);

    // A whole `?Point` parameter is a supported position: it lowers to a
    // single nullable pointer, the same shape a bare `Point` gets.
    const point_types = [_]semantic.TypeDecl{.{
        .fields = &.{.{ .name = "x", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
        .kind = .value_struct,
        .layout = .@"extern",
        .name = "Point",
    }};
    const optional: semantic.TypeNode = .{ .optional = .{ .child = &element } };
    const valid: semantic.Semantic = .{
        .functions = &.{.{
            .name = "optional",
            .params = &.{.{ .name = "value", .type = optional }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_optional",
        }},
        .package = "good",
        .prefix = "zg",
        .types = &point_types,
        .zig_version = "0.16.0",
    };
    try validate.semanticDocument(std.testing.allocator, valid);

    // `[]?Point`: the struct is nested inside an optional slice element,
    // which has no C ABI shape -- `?T` only lowers as a whole parameter,
    // return value, or error payload.
    var optional_element: semantic.TypeNode = optional;
    const optional_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &optional_element } };
    const invalid: semantic.Semantic = .{
        .functions = &.{.{
            .name = "consumeOptional",
            .params = &.{.{ .name = "values", .type = optional_slice }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_consume_optional",
        }},
        .package = "bad",
        .prefix = "zg",
        .types = &point_types,
        .zig_version = "0.16.0",
    };
    const issue = (try validate.findIssue(std.testing.allocator, invalid)).?;
    try std.testing.expectEqualStrings("ZIGO013", issue.code);
    try std.testing.expect(std.mem.containsAtLeast(u8, issue.hint, 1, "direct slice element"));
}

test "utf8 string slices are the pointer-bearing slice exception" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var string_element: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    const strings: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &string_element } };
    const valid: semantic.Semantic = .{
        .functions = &.{.{
            .name = "extract",
            .params = &.{.{ .name = "paths", .semantic = .utf8_string, .type = strings }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_extract",
        }},
        .package = "good",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try validate.semanticDocument(std.testing.allocator, valid);

    string_element.slice.sentinel = 1;
    const issue = (try validate.findIssue(std.testing.allocator, valid)).?;
    try std.testing.expectEqualStrings("ZIGO005", issue.code);
}

test "tagged union handles accept supported accessor payloads and constructors" {
    var handle_payload: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Value" } };
    const document: semantic.Semantic = .{
        .constructors = &.{.{ .deinit = "deinit", .init = "create", .type = "Value" }},
        .functions = &.{
            .{
                .name = "create",
                .namespace = "Value",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &handle_payload } },
                .symbol = "zg_value_create",
            },
            .{ .name = "deinit", .params = &.{}, .receiver = "Value", .@"return" = .{ .void = {} }, .symbol = "zg_value_deinit" },
        },
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "integer", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
                },
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{
                    .{ .name = "none", .value = 0 },
                    .{ .name = "integer", .value = 1 },
                },
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    try validate.semanticDocument(std.testing.allocator, document);
}

test "tagged union value parameters accept only scalar and void payloads" {
    const eligible: semantic.Semantic = .{
        .functions = &.{.{
            .name = "consume",
            .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "small", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
                    .{ .name = "active", .type = .{ .bool = {} }, .value = 2 },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } }, .value = 3 },
                },
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{
                    .{ .name = "none", .value = 0 },
                    .{ .name = "small", .value = 1 },
                    .{ .name = "active", .value = 2 },
                    .{ .name = "mode", .value = 3 },
                },
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{
                .fields = &.{.{ .name = "idle", .value = 0 }},
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    try std.testing.expect((try validate.findIssue(std.testing.allocator, eligible)) == null);
}

test "tagged union value parameter names the first ineligible payload" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const cases = [_]struct { name: []const u8, payload: semantic.TypeNode }{
        .{ .name = "bytes", .payload = .{ .slice = .{ .@"const" = true, .element = &byte } } },
        .{ .name = "child", .payload = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Child" } } },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "consume",
                .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "variant",
            .prefix = "zg",
            .types = &.{
                .{
                    .fields = &.{.{ .name = case.name, .type = case.payload, .value = 0 }},
                    .kind = .tagged_union,
                    .name = "Value",
                    .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
                },
                .{ .fields = &.{.{ .name = case.name, .value = 0 }}, .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
                .{ .kind = .@"opaque", .name = "Child" },
                .{ .fields = &.{.{ .name = "count", .type = .{ .int = .{ .bits = 32, .signed = false } } }}, .kind = .value_struct, .layout = .@"extern", .name = "Config" },
            },
            .zig_version = "0.16.0",
        };
        const issue = (try validate.findIssue(arena.allocator(), document)).?;
        try std.testing.expectEqualStrings("ZIGO006", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.hint, case.name) != null);
    }
}

test "tagged union accessor payload rejects slices containing handles" {
    var handle: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Thing" } };
    const document: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "things", .type = .{ .slice = .{ .@"const" = true, .element = &handle } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{ .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            .{ .kind = .@"opaque", .name = "Thing" },
        },
        .zig_version = "0.16.0",
    };
    const issue = (try validate.findIssue(std.testing.allocator, document)).?;
    try std.testing.expectEqualStrings("ZIGO006", issue.code);
    try std.testing.expectEqualStrings("Value", issue.site.declaration);
}

test "tagged union accessor payload rejects unrepresentable scalar widths" {
    var i24_node: semantic.TypeNode = .{ .int = .{ .bits = 24, .signed = true } };
    const cases = [_]semantic.TypeNode{
        .{ .int = .{ .bits = 128, .signed = false } },
        .{ .float = .{ .bits = 16 } },
        .{ .slice = .{ .@"const" = true, .element = &i24_node } },
    };
    for (cases) |payload| {
        const document: semantic.Semantic = .{
            .package = "variant",
            .prefix = "zg",
            .types = &.{
                .{
                    .fields = &.{.{ .name = "value", .type = payload, .value = 0 }},
                    .kind = .tagged_union,
                    .name = "Value",
                    .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
                },
                .{ .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            },
            .zig_version = "0.16.0",
        };
        const issue = (try validate.findIssue(std.testing.allocator, document)).?;
        try std.testing.expectEqualStrings("ZIGO006", issue.code);
        try std.testing.expectEqualStrings("Value", issue.site.declaration);
    }
}

test "referential integrity failures are reported before lowering" {
    var callback_return: semantic.TypeNode = .{ .@"enum" = .{ .ref = "MissingMode" } };
    var optional_child: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "WrongKind" } };
    var constructor_payload: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Context" } };
    const valid_constructor_functions = [_]semantic.SemanticFn{
        .{
            .name = "create",
            .namespace = "Context",
            .ownership = .caller,
            .params = &.{},
            .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &constructor_payload } },
            .symbol = "ignored",
        },
        .{
            .name = "deinit",
            .params = &.{},
            .receiver = "Context",
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        },
    };
    const cases = [_]struct {
        document: semantic.Semantic,
        declaration: []const u8,
    }{
        .{ .document = .{
            .functions = &.{.{
                .name = "normalize",
                .params = &.{},
                .@"return" = .{ .@"enum" = .{ .ref = "MissingMode" } },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .declaration = "normalize" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"enum", .name = "Mode" }},
            .zig_version = "0.16.0",
        }, .declaration = "Mode" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{
                .{ .kind = .@"opaque", .name = "Thing" },
                .{
                    .fields = &.{.{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
                    .kind = .value_struct,
                    .name = "Thing",
                    .layout = .@"extern",
                },
            },
            .zig_version = "0.16.0",
        }, .declaration = "Thing" },
        .{ .document = .{
            .functions = &.{.{
                .name = "visit",
                .params = &.{.{ .name = "callback", .type = .{ .callback = .{
                    .has_userdata = false,
                    .params = &.{},
                    .@"return" = &callback_return,
                } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .declaration = "visit" },
        .{ .document = .{
            .functions = &.{.{
                .name = "use",
                .params = &.{.{ .name = "thing", .type = .{ .optional = .{ .child = &optional_child } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"enum", .name = "WrongKind", .tag_type = .{ .int = .{ .bits = 32, .signed = false } } }},
            .zig_version = "0.16.0",
        }, .declaration = "use" },
        // A tagged union names its tag enum through `tag_type`; lowering
        // resolves it, so an unresolved one is an integrity problem.
        .{ .document = .{
            .functions = &.{.{
                .name = "take",
                .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "none", .type = .{ .void = {} }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "MissingValueTag" } },
            }},
            .zig_version = "0.16.0",
        }, .declaration = "Value" },
        // A flattened parameter's selected fields are lowered on their own.
        .{ .document = .{
            .functions = &.{.{
                .name = "configure",
                .params = &.{.{
                    .name = "options",
                    .type = .{ .value_struct = .{ .ref = "Options" } },
                    .flatten = &.{.{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "MissingMode" } } }},
                }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
                .kind = .value_struct,
                .name = "Options",
                .layout = .@"extern",
            }},
            .zig_version = "0.16.0",
        }, .declaration = "configure" },
        .{ .document = .{
            .constructors = &.{.{ .type = "Context", .init = "missing", .deinit = "deinit" }},
            .functions = &valid_constructor_functions,
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Context" }},
            .zig_version = "0.16.0",
        }, .declaration = "missing" },
        .{ .document = .{
            .constructors = &.{
                .{ .type = "Context", .init = "create", .deinit = "deinit" },
                .{ .type = "Context", .init = "create", .deinit = "deinit" },
            },
            .functions = &valid_constructor_functions,
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Context" }},
            .zig_version = "0.16.0",
        }, .declaration = "Context" },
    };
    for (cases) |case| {
        const issue = (try validate.findIssue(std.testing.allocator, case.document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO010", issue.code);
        try std.testing.expectEqualStrings(case.declaration, issue.site.declaration);
        try std.testing.expectError(error.InvalidSemantic, validate.semanticDocument(std.testing.allocator, case.document));
    }
}

test "well-formed constructor references pass integrity validation" {
    var payload: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Context" } };
    const document: semantic.Semantic = .{
        .constructors = &.{.{ .type = "Context", .init = "create", .deinit = "deinit" }},
        .functions = &.{
            .{
                .name = "create",
                .namespace = "Context",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &payload } },
                .symbol = "ignored",
            },
            .{
                .name = "deinit",
                .params = &.{},
                .receiver = "Context",
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            },
        },
        .package = "good",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Context" }},
        .zig_version = "0.16.0",
    };
    try std.testing.expect((try validate.findIssue(std.testing.allocator, document)) == null);
    try validate.semanticDocument(std.testing.allocator, document);
}

test "value snapshot eligibility accepts void bool scalar and enum payloads" {
    const eligible: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "idle", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "ticks", .type = .{ .int = .{ .bits = 32, .signed = false } }, .value = 1 },
                    .{ .name = "level", .type = .{ .float = .{ .bits = 32 } }, .value = 2 },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } }, .value = 3 },
                    .{ .name = "active", .type = .{ .bool = {} }, .value = 4 },
                },
                .kind = .tagged_union,
                .name = "Signal",
                .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
                .access = .snapshot,
            },
            .{
                .fields = &.{
                    .{ .name = "idle", .value = 0 },
                    .{ .name = "ticks", .value = 1 },
                    .{ .name = "level", .value = 2 },
                    .{ .name = "mode", .value = 3 },
                    .{ .name = "active", .value = 4 },
                },
                .kind = .@"enum",
                .name = "SignalTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{ .fields = &.{.{ .name = "idle", .value = 0 }}, .kind = .@"enum", .name = "Mode", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(std.testing.allocator, eligible));
    try validate.semanticDocument(std.testing.allocator, eligible);
}

test "an opaque handle payload keeps a union out of the value snapshot representation" {
    var child: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Child" } };
    _ = &child;
    const document: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "child", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Child" } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "Signal",
                .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
                .access = .snapshot,
            },
            .{ .fields = &.{.{ .name = "child", .value = 0 }}, .kind = .@"enum", .name = "SignalTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            .{ .kind = .@"opaque", .name = "Child" },
        },
        .zig_version = "0.16.0",
    };
    const issue = (try validate.findIssue(std.testing.allocator, document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO011", issue.code);
    try std.testing.expectEqualStrings("child", issue.site.declaration);

    // The same union stays valid under the default projection representation.
    var projection_types = document.types[0];
    projection_types.access = null;
    var declarations = [_]semantic.TypeDecl{ projection_types, document.types[1], document.types[2] };
    var projection_document = document;
    projection_document.types = &declarations;
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(std.testing.allocator, projection_document));
}

test "an extern struct of scalars enums and nested structs passes validation" {
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "configure",
                .params = &.{.{ .name = "config", .type = .{ .value_struct = .{ .ref = "Config" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            },
            .{
                .name = "defaultConfig",
                .params = &.{},
                .@"return" = .{ .value_struct = .{ .ref = "Config" } },
                .symbol = "ignored",
            },
        },
        .package = "config",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                    .{ .name = "ratio", .type = .{ .float = .{ .bits = 64 } } },
                    .{ .name = "enabled", .type = .{ .bool = {} } },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } } },
                    .{ .name = "origin", .type = .{ .value_struct = .{ .ref = "Point" } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Config",
            },
            .{
                .fields = &.{
                    .{ .name = "x", .type = .{ .int = .{ .bits = 16, .signed = true } } },
                    .{ .name = "y", .type = .{ .int = .{ .bits = 16, .signed = true } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Point",
            },
            .{ .fields = &.{.{ .name = "idle", .value = 0 }}, .kind = .@"enum", .name = "Mode", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
        },
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(std.testing.allocator, document));
    try validate.semanticDocument(std.testing.allocator, document);
}

test "a supported packed struct passes and unsupported packed and extern fields are diagnosed" {
    const packed_document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "configure",
            .params = &.{.{ .name = "config", .type = .{ .value_struct = .{ .ref = "Flags" } } }},
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{
            .backing_type = .{ .int = .{ .bits = 8, .signed = false } },
            .fields = &.{.{ .name = "enabled", .type = .{ .bool = {} } }},
            .kind = .value_struct,
            .layout = .@"packed",
            .name = "Flags",
        }},
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(std.testing.allocator, packed_document));

    var unsupported_packed = packed_document;
    const unsupported_fields = [_]semantic.TypeField{.{ .name = "ratio", .type = .{ .float = .{ .bits = 32 } } }};
    const unsupported_types = [_]semantic.TypeDecl{.{
        .backing_type = .{ .int = .{ .bits = 32, .signed = false } },
        .fields = &unsupported_fields,
        .kind = .value_struct,
        .layout = .@"packed",
        .name = "Flags",
    }};
    unsupported_packed.types = &unsupported_types;
    const packed_issue = (try validate.findIssue(std.testing.allocator, unsupported_packed)) orelse return error.MissingDiagnostic;
    defer std.testing.allocator.free(packed_issue.message);
    try std.testing.expectEqualStrings("ZIGO044", packed_issue.code);
    try std.testing.expect(std.mem.indexOf(u8, packed_issue.message, "ratio") != null);

    const unknown_enum_fields = [_]semantic.TypeField{.{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "UnregisteredMode" } } }};
    const plain_struct_fields = [_]semantic.TypeField{.{ .name = "child", .type = .{ .value_struct = .{ .ref = "Plain" } } }};
    const pointer_fields = [_]semantic.TypeField{.{ .name = "owner", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Thing" } } }};
    const invalid_fields = [_][]const semantic.TypeField{ &unknown_enum_fields, &plain_struct_fields, &pointer_fields };
    const invalid_names = [_][]const u8{ "mode", "child", "owner" };
    for (invalid_fields, invalid_names) |fields, field_name| {
        const declarations = [_]semantic.TypeDecl{
            .{
                .backing_type = .{ .int = .{ .bits = 64, .signed = false } },
                .fields = fields,
                .kind = .value_struct,
                .layout = .@"packed",
                .name = "Flags",
            },
            .{ .kind = .value_struct, .name = "Plain" },
            .{ .kind = .@"opaque", .name = "Thing" },
        };
        var invalid = packed_document;
        invalid.types = &declarations;
        const issue = (try validate.findIssue(std.testing.allocator, invalid)) orelse return error.MissingDiagnostic;
        defer std.testing.allocator.free(issue.message);
        try std.testing.expectEqualStrings("ZIGO044", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, field_name) != null);
    }

    const pointer_document: semantic.Semantic = .{
        .package = "bad",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "owner", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Thing" } } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Config",
            },
            .{ .kind = .@"opaque", .name = "Thing" },
        },
        .zig_version = "0.16.0",
    };
    const pointer_issue = (try validate.findIssue(std.testing.allocator, pointer_document)) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO012", pointer_issue.code);
    try std.testing.expectEqualStrings("owner", pointer_issue.site.declaration);
}

test "an optional is rejected everywhere it has no presence to carry" {
    var word: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var optional_word: semantic.TypeNode = .{ .optional = .{ .child = &word } };
    var void_node: semantic.TypeNode = .{ .void = {} };

    // A slice element: the lowered `T*, len` pair has room for the elements
    // and nothing else.
    const slice_of_optional: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &optional_word } };
    // A callback signature: the function pointer's C type is fixed by the
    // callback declaration, so there is no second argument to add.
    const callback_of_optional: semantic.TypeNode = .{ .callback = .{
        .has_userdata = false,
        .params = &.{optional_word},
        .@"return" = &void_node,
    } };
    // An optional of an optional collapses to one presence flag in C, which
    // could not tell the two levels apart.
    const nested_optional: semantic.TypeNode = .{ .optional = .{ .child = &optional_word } };

    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    for ([_]semantic.TypeNode{ slice_of_optional, callback_of_optional, nested_optional }) |node| {
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "take",
                .params = &.{.{ .name = "value", .type = node }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_take",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try validate.findIssue(scratch.allocator(), document)).?;
        try std.testing.expectEqualStrings("ZIGO019", issue.code);
    }

    // An `extern struct` field: the C mirror is a flat record, and a presence
    // flag beside the member would change its layout.
    const struct_document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "take",
            .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Point" } } }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_take",
        }},
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{
            .fields = &.{.{ .name = "x", .type = optional_word }},
            .kind = .value_struct,
            .layout = .@"extern",
            .name = "Point",
        }},
        .zig_version = "0.16.0",
    };
    const struct_issue = (try validate.findIssue(scratch.allocator(), struct_document)).?;
    try std.testing.expect(struct_issue.severity == .@"error");
}

test "an optional is accepted as a whole parameter, return value, and error payload" {
    var word: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var optional_word: semantic.TypeNode = .{ .optional = .{ .child = &word } };
    var flag: semantic.TypeNode = .{ .bool = {} };
    var mode: semantic.TypeNode = .{ .@"enum" = .{ .ref = "Mode" } };
    var point: semantic.TypeNode = .{ .value_struct = .{ .ref = "Point" } };
    // A narrow integer is promoted inside an optional exactly as it is bare,
    // because both travel in the same widened C parameter.
    var narrow: semantic.TypeNode = .{ .int = .{ .bits = 12, .signed = false } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "double",
                .params = &.{.{ .name = "value", .type = optional_word }},
                .@"return" = optional_word,
                .symbol = "zg_double",
            },
            .{
                .name = "checked",
                .params = &.{
                    .{ .name = "flag", .type = .{ .optional = .{ .child = &flag } } },
                    .{ .name = "mode", .type = .{ .optional = .{ .child = &mode } } },
                    .{ .name = "point", .type = .{ .optional = .{ .child = &point } } },
                    .{ .name = "narrow", .type = .{ .optional = .{ .child = &narrow } } },
                },
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &optional_word } },
                .symbol = "zg_checked",
            },
        },
        .package = "good",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{.{ .name = "x", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Point",
            },
            .{
                .fields = &.{.{ .name = "idle", .value = 0 }},
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    try validate.semanticDocument(std.testing.allocator, document);
}

test "an optional slice is accepted while its unsupported combinations are not" {
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var word: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var point: semantic.TypeNode = .{ .value_struct = .{ .ref = "Point" } };
    var bytes: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte } };
    var words: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &word } };
    const points: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &point } };
    const strings: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &bytes } };
    const point_types = [_]semantic.TypeDecl{.{
        .fields = &.{.{ .name = "x", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
        .kind = .value_struct,
        .layout = .@"extern",
        .name = "Point",
    }};

    // `?[]T` in and out: the slice's own pointer is what says "present".
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "total",
            .params = &.{.{ .name = "values", .type = .{ .optional = .{ .child = &words } } }},
            .@"return" = .{ .optional = .{ .child = &bytes } },
            .symbol = "zg_total",
        }},
        .package = "good",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try validate.semanticDocument(std.testing.allocator, document);

    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();

    // An `.out` slice is the caller's own buffer, so it cannot be absent.
    const out_document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "fill",
            .params = &.{.{
                .name = "buffer",
                .direction = .out,
                .type = .{ .optional = .{ .child = &words } },
            }},
            .@"return" = .{ .void = {} },
            .symbol = "zg_fill",
        }},
        .package = "bad",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const out_issue = (try validate.findIssue(scratch.allocator(), out_document)).?;
    try std.testing.expectEqualStrings("ZIGO019", out_issue.code);
    try std.testing.expect(std.mem.containsAtLeast(u8, out_issue.message, 1, "cannot be optional"));

    // A slice of slices builds a second array of pointers, and there is no
    // NULL left over to mean absent. A slice of extern structs is rejected for
    // the same reason the bare nested position is.
    for ([_]semantic.TypeNode{ strings, points }) |child| {
        var node = child;
        const rejected: semantic.Semantic = .{
            .functions = &.{.{
                .name = "take",
                .params = &.{.{ .name = "values", .type = .{ .optional = .{ .child = &node } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_take",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &point_types,
            .zig_version = "0.16.0",
        };
        try std.testing.expect((try validate.findIssue(scratch.allocator(), rejected)) != null);
    }
}
