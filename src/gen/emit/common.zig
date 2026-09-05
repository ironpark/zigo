//! Helpers every output file shares: type spellings for Zig, C and Go,
//! generated names, and the program-wide predicates emitters gate on.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");
const callbacks = @import("callbacks.zig");
const docs = @import("docs.zig");
const emit = @import("emit.zig");
const header = @import("header.zig");
const public = @import("public.zig");
const public_runtime = @import("public_runtime.zig");
const public_writers = @import("public_writers.zig");
const raw = @import("raw.zig");
const shim = @import("shim.zig");
const lower = @import("lower");

/// Public Go package name: the override when set, otherwise the snake_case
/// binding name. The C header and the native library keep the binding name.
pub fn publicPackageAlloc(allocator: std.mem.Allocator, program: abi.Program, options: emit.Options) ![]u8 {
    if (options.go_package.len != 0) return allocator.dupe(u8, options.go_package);
    return naming.snakeAlloc(allocator, program.package);
}

pub fn publicPackagePathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: emit.Options) ![]u8 {
    if (options.go_package_path.len != 0) return allocator.dupe(u8, options.go_package_path);
    return publicPackageAlloc(allocator, program, options);
}

/// Go parameter names for one function, computed once per emitted function.
pub fn goParamNamesForAlloc(allocator: std.mem.Allocator, params: []const semantic.Parameter) ![][]u8 {
    const zig_names = try allocator.alloc([]const u8, params.len);
    defer allocator.free(zig_names);
    for (params, 0..) |parameter, index| zig_names[index] = parameter.name;
    return naming.goParamNamesAlloc(allocator, zig_names);
}

/// The Zig spelling of a registered type inside the shim, which imports the
/// user's root module as `target`. A type declared inside a container is only
/// reachable through that container, so the reflected `zig_path` decides the
/// spelling. A path under `root.` maps straight onto `target.`; a path from a
/// dependency module (`terminal.Terminal.Options`) is reached through the
/// nearest registered ancestor whose path is a prefix of it (`Terminal`, so
/// `target.Terminal.Options`), which holds whatever the module is called. A
/// path with a generic instantiation, or one with no registered ancestor,
/// keeps the bare registered name as before: that name is what the root
/// module is expected to export.
pub fn targetTypeSpellingAlloc(allocator: std.mem.Allocator, program: abi.Program, name: []const u8) ![]u8 {
    const path = registeredZigPath(program, name) orelse
        return std.fmt.allocPrint(allocator, "target.{s}", .{name});
    if (std.mem.startsWith(u8, path, "root."))
        return std.fmt.allocPrint(allocator, "target.{s}", .{path["root.".len..]});
    if (registeredAncestor(program, name, path)) |ancestor| {
        const parent_spelling = try targetTypeSpellingAlloc(allocator, program, ancestor.name);
        defer allocator.free(parent_spelling);
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ parent_spelling, path[ancestor.path_len..] });
    }
    // A dependency-module type with no registered ancestor is whatever the
    // root module re-exports. When the registered name is the Zig name there
    // is one spelling; otherwise the root may export either, so the shim
    // resolves the first one it finds at comptime.
    if (targetTypeCandidates(path, name)) |candidates| {
        var spelling: std.ArrayList(u8) = .empty;
        errdefer spelling.deinit(allocator);
        try spelling.appendSlice(allocator, "zigoTargetType(&.{ ");
        for (candidates.slice(), 0..) |candidate, index| {
            if (index != 0) try spelling.appendSlice(allocator, ", ");
            try spelling.print(allocator, "\"{s}\"", .{candidate});
        }
        try spelling.appendSlice(allocator, " })");
        return spelling.toOwnedSlice(allocator);
    }
    return std.fmt.allocPrint(allocator, "target.{s}", .{name});
}

const RegisteredAncestor = struct { name: []const u8, path_len: usize };

/// The registered type whose Zig path is the longest proper prefix of `path`,
/// which is the type the spelling nests under.
fn registeredAncestor(program: abi.Program, name: []const u8, path: []const u8) ?RegisteredAncestor {
    var ancestor: ?RegisteredAncestor = null;
    for (program.types) |declaration| {
        if (std.mem.eql(u8, declaration.name, name)) continue;
        const other = registeredZigPath(program, declaration.name) orelse continue;
        if (other.len >= path.len or !std.mem.startsWith(u8, path, other) or path[other.len] != '.') continue;
        if (ancestor == null or other.len > ancestor.?.path_len)
            ancestor = .{ .name = declaration.name, .path_len = other.len };
    }
    return ancestor;
}

const TargetTypeCandidates = struct {
    items: [3][]const u8,
    len: usize,

    fn slice(self: *const TargetTypeCandidates) []const []const u8 {
        return self.items[0..self.len];
    }
};

/// The names a dependency-module type may be reached by from the root
/// module, most specific first: the path below the module (`Nested.Impl`),
/// the type's own name (`Impl`), and the registered name (`Probe`). Null when
/// the registered name already is the Zig name, which the plain `target.`
/// spelling covers.
fn targetTypeCandidates(path: []const u8, name: []const u8) ?TargetTypeCandidates {
    const module_end = std.mem.indexOfScalar(u8, path, '.') orelse return null;
    const below_module = path[module_end + 1 ..];
    const last = if (std.mem.lastIndexOfScalar(u8, path, '.')) |dot| path[dot + 1 ..] else path;
    if (std.mem.eql(u8, last, name)) return null;
    var result: TargetTypeCandidates = .{ .items = undefined, .len = 0 };
    for ([_][]const u8{ below_module, last, name }) |candidate| {
        var duplicate = false;
        for (result.slice()) |existing| duplicate = duplicate or std.mem.eql(u8, existing, candidate);
        if (duplicate) continue;
        result.items[result.len] = candidate;
        result.len += 1;
    }
    return result;
}

/// True when some registered type is spelled through `zigoTargetType`, so
/// the shim has to define it.
pub fn programNeedsTargetTypeResolver(program: abi.Program) bool {
    for (program.types) |declaration| {
        const path = registeredZigPath(program, declaration.name) orelse continue;
        if (std.mem.startsWith(u8, path, "root.")) continue;
        // A nested type is spelled through its ancestor, which is checked on
        // its own turn through this loop.
        if (registeredAncestor(program, declaration.name, path) != null) continue;
        if (targetTypeCandidates(path, declaration.name) != null) return true;
    }
    return false;
}

pub fn writeTargetTypeResolver(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        "/// A registered type from a dependency module, reached through whichever\n" ++
            "/// of its names the root module exports.\n" ++
            "fn zigoTargetType(comptime candidates: []const []const u8) type {\n" ++
            "    comptime {\n" ++
            "        var message: []const u8 = \"zigo: the root module exports none of the names this type can be reached by:\";\n" ++
            "        for (candidates) |candidate| {\n" ++
            "            if (zigoResolveTargetDecl(candidate)) |T| return T;\n" ++
            "            message = message ++ \" \" ++ candidate;\n" ++
            "        }\n" ++
            "        @compileError(message);\n" ++
            "    }\n" ++
            "}\n" ++
            "fn zigoResolveTargetDecl(comptime path: []const u8) ?type {\n" ++
            "    comptime {\n" ++
            "        var current: type = target;\n" ++
            "        var segments = std.mem.splitScalar(u8, path, '.');\n" ++
            "        while (segments.next()) |segment| {\n" ++
            "            if (!@hasDecl(current, segment)) return null;\n" ++
            "            const next = @field(current, segment);\n" ++
            "            if (@TypeOf(next) != type) return null;\n" ++
            "            current = next;\n" ++
            "        }\n" ++
            "        return current;\n" ++
            "    }\n" ++
            "}\n\n",
    );
}

/// The reflected Zig path of a registered type when it can be spelled as a
/// path: a generic instantiation or a disambiguated registration (`#`) cannot.
fn registeredZigPath(program: abi.Program, name: []const u8) ?[]const u8 {
    for (program.types) |declaration| {
        if (!std.mem.eql(u8, declaration.name, name)) continue;
        const path = declaration.zig_path orelse return null;
        return if (std.mem.indexOfAny(u8, path, "(#") == null) path else null;
    }
    return null;
}

pub fn writeTargetType(writer: *std.Io.Writer, program: abi.Program, name: []const u8) !void {
    var buffer: [512]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const spelling = targetTypeSpellingAlloc(fba.allocator(), program, name) catch {
        try writer.print("target.{s}", .{name});
        return;
    };
    try writer.writeAll(spelling);
}

pub fn flattenedGoNameAlloc(allocator: std.mem.Allocator, abi_name: []const u8) ![]u8 {
    const names = try naming.goParamNamesAlloc(allocator, &.{abi_name});
    defer allocator.free(names);
    return names[0];
}

pub fn flattenedField(parameter: semantic.Parameter, abi_parameter: abi.AbiParam) semantic.FlattenedField {
    return parameter.flatten.?[abi_parameter.field_index.?];
}

/// Suffix of the raw Go mirror of an `extern struct`. Named once so the
/// declaration and every reference to it cannot drift apart.
pub const raw_struct_suffix = "Data";

pub fn structRawTypeNameAlloc(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ name, raw_struct_suffix });
}

/// The Go spelling of a snapshot member. Padding keeps the layout without
/// becoming part of the API, so it is written to the blank identifier.
pub fn snapshotGoFieldAlloc(allocator: std.mem.Allocator, field: abi.AbiSnapshot.Field) ![]u8 {
    if (field.kind == .padding) return allocator.dupe(u8, "_");
    return naming.pascalAlloc(allocator, field.name);
}

pub fn snapshotRawTypeNameAlloc(allocator: std.mem.Allocator, snapshot: abi.AbiSnapshot) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}SnapshotData", .{snapshot.owner.name});
}

pub fn snapshotRawFunctionNameAlloc(allocator: std.mem.Allocator, snapshot: abi.AbiSnapshot) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}ReadSnapshot", .{snapshot.owner.name});
}

pub fn rawGoTypeName(program: abi.Program, node: semantic.TypeNode) []const u8 {
    const scalar = semanticScalar(program, node);
    return switch (scalar) {
        .usize => "uint",
        .isize => "int",
        .bool_u8 => "uint8",
        .signed_int => |bits| switch (bits) {
            8 => "int8",
            16 => "int16",
            32 => "int32",
            64 => "int64",
            else => unreachable,
        },
        .unsigned_int => |bits| switch (bits) {
            8 => "uint8",
            16 => "uint16",
            32 => "uint32",
            64 => "uint64",
            else => unreachable,
        },
        .float => |bits| switch (bits) {
            32 => "float32",
            64 => "float64",
            else => unreachable,
        },
        else => unreachable,
    };
}

pub fn goZero(node: semantic.TypeNode) []const u8 {
    return switch (node) {
        .bool => "false",
        .slice, .opaque_ptr => "nil",
        .materialized => |value| if (value.pointer) "nil" else "0",
        else => "0",
    };
}

/// The zero value an error path returns. A struct needs its own composite
/// literal, so callers that can see one use this instead of `goZero`.
pub fn writeGoZeroValue(scope: public_writers.PublicScope, writer: *std.Io.Writer, node: semantic.TypeNode) !void {
    if (node == .value_struct or (node == .materialized and !node.materialized.pointer)) {
        try scope.writeTypeName(writer, if (node == .value_struct) node.value_struct.ref else node.materialized.ref);
        return writer.writeAll("{}");
    }
    try writer.writeAll(goZero(node));
}

pub fn rawGoZero(node: semantic.TypeNode) []const u8 {
    return switch (node) {
        .slice, .opaque_ptr => "nil",
        else => "0",
    };
}

pub fn semanticScalar(program: abi.Program, node: semantic.TypeNode) abi.AbiScalar {
    return switch (node) {
        .void => .void,
        .bool => .bool_u8,
        // The promoted width, matching what lowering put in the ABI, so a
        // narrow integer spells the same C, Zig, and Go type everywhere.
        .int => |value| if (value.is_usize)
            (if (value.signed) .isize else .usize)
        else if (value.signed)
            .{ .signed_int = abi.promotedIntBits(value.bits) }
        else
            .{ .unsigned_int = abi.promotedIntBits(value.bits) },
        .float => |value| .{ .float = value.bits },
        .@"enum" => |value| semanticScalar(program, enumDecl(program, value.ref).tag_type.?),
        .value_struct => if (isPackedValue(program, node))
            semanticScalar(program, enumDecl(program, node.value_struct.ref).backing_type.?)
        else
            unreachable,
        .opaque_ptr => |value| .{ .@"opaque" = handleRecord(program, value.ref) },
        else => unreachable,
    };
}

/// The lowered handle for a semantic type name. Lowering records one for every
/// `opaque` and tagged union, so a missing entry is a malformed program.
pub fn handleRecord(program: abi.Program, name: []const u8) abi.AbiOpaque {
    for (program.handles) |handle| if (std.mem.eql(u8, handle.name, name)) return handle;
    unreachable;
}

/// The lowered enum for a semantic type name, on the same terms as
/// `handleRecord`.
pub fn enumRecord(program: abi.Program, name: []const u8) abi.AbiEnum {
    for (program.enums) |record| if (std.mem.eql(u8, record.name, name)) return record;
    unreachable;
}

pub fn enumDecl(program: abi.Program, name: []const u8) semantic.TypeDecl {
    return semantic.typeDecl(program.types, name) orelse unreachable;
}

pub fn isPackedValue(program: abi.Program, node: semantic.TypeNode) bool {
    return semantic.isPackedValue(program.types, node);
}

pub fn packedValuePubliclyUsed(program: abi.Program, name: []const u8) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (packedValueReachable(program, parameter.type, name, 0)) return true;
            if (parameter.flatten) |fields| for (fields) |field| {
                if (packedValueReachable(program, field.type, name, 0)) return true;
            };
        }
        if (packedValueReachable(program, function.origin.@"return", name, 0)) return true;
    }
    return false;
}

fn packedValueReachable(program: abi.Program, node: semantic.TypeNode, name: []const u8, depth: usize) bool {
    if (depth >= 16) return false;
    return switch (node) {
        .value_struct => |value| blk: {
            if (std.mem.eql(u8, value.ref, name)) break :blk true;
            const declaration = enumDecl(program, value.ref);
            if (declaration.kind == .tagged_union) break :blk false;
            for (declaration.fields) |field| if (field.type) |child| {
                if (packedValueReachable(program, child, name, depth + 1)) break :blk true;
            };
            break :blk false;
        },
        .slice => |value| packedValueReachable(program, value.element.*, name, depth + 1),
        .optional => |value| packedValueReachable(program, value.child.*, name, depth + 1),
        .error_union => |value| packedValueReachable(program, value.payload.*, name, depth + 1),
        .callback => |value| blk: {
            for (value.params) |parameter| if (packedValueReachable(program, parameter, name, depth + 1)) break :blk true;
            break :blk packedValueReachable(program, value.@"return".*, name, depth + 1);
        },
        else => false,
    };
}

pub fn writePackedZigToBackingPrefix(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode) !void {
    const backing = enumDecl(program, node.value_struct.ref).backing_type.?.int;
    try writer.print("@intCast(@as({c}{d}, @bitCast(", .{
        if (backing.signed) @as(u8, 'i') else @as(u8, 'u'),
        backing.bits,
    });
}

pub fn writePackedZigFromBacking(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode, expression: []const u8) !void {
    const backing = enumDecl(program, node.value_struct.ref).backing_type.?.int;
    try writer.print("@bitCast(@as({c}{d}, @truncate({s})))", .{
        if (backing.signed) @as(u8, 'i') else @as(u8, 'u'),
        backing.bits,
        expression,
    });
}

pub fn isTaggedUnionValue(program: abi.Program, node: semantic.TypeNode) bool {
    return node == .value_struct and enumDecl(program, node.value_struct.ref).kind == .tagged_union;
}

pub fn writePublicTaggedUnionRawArguments(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    declaration: semantic.TypeDecl,
    value_name: []const u8,
) !void {
    try writer.writeAll(rawGoTypeName(program, declaration.tag_type.?));
    try writer.print("({s}.tag)", .{value_name});
    for (program.liveFields(declaration.name)) |field| {
        const payload = field.type.?;
        if (payload == .void) continue;
        const member = try naming.camelAlloc(allocator, field.name);
        defer allocator.free(member);
        const expression = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ value_name, member });
        defer allocator.free(expression);
        try writePublicTaggedUnionPayloadRawArguments(allocator, writer, program, payload, expression);
    }
}

fn writePublicTaggedUnionPayloadRawArguments(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    node: semantic.TypeNode,
    expression: []const u8,
) !void {
    if (node == .value_struct) {
        const declaration = enumDecl(program, node.value_struct.ref);
        if (declaration.layout == .@"packed") {
            try writer.print(", zigo{s}ToBacking({s})", .{ declaration.name, expression });
            return;
        }
        for (declaration.fields) |field| {
            const member = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(member);
            const child = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ expression, member });
            defer allocator.free(child);
            try writePublicTaggedUnionPayloadRawArguments(allocator, writer, program, field.type.?, child);
        }
        return;
    }
    try writer.writeAll(", ");
    switch (node) {
        .bool => try writer.print("boolToUint8({s})", .{expression}),
        .@"enum" => {
            try writer.writeAll(rawGoTypeName(program, node));
            try writer.print("({s})", .{expression});
        },
        else => try writer.writeAll(expression),
    }
}

/// The `semantic.Semantic` rule applied to lowered functions: a tagged union
/// that only ever crosses by value gets a snapshot struct, not a handle.
pub fn isValueOnlyTaggedUnion(program: abi.Program, name: []const u8) bool {
    if (enumDecl(program, name).kind != .tagged_union) return false;
    var by_value = false;
    for (program.constructors) |constructor| if (std.mem.eql(u8, constructor.type, name)) return false;
    for (program.functions) |function| {
        if (semantic.functionUsesAsHandle(function.origin.*, name)) return false;
        by_value = by_value or semantic.functionPassesByValue(function.origin.*, name);
    }
    return by_value;
}

pub fn writeZigType(writer: *std.Io.Writer, program: abi.Program, value: abi.AbiScalar) !void {
    switch (value) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("u8"),
        .usize => try writer.writeAll("usize"),
        .isize => try writer.writeAll("isize"),
        .signed_int => |bits| try writer.print("i{d}", .{bits}),
        .unsigned_int => |bits| try writer.print("u{d}", .{bits}),
        .float => |bits| try writer.print("f{d}", .{bits}),
        .@"opaque" => |handle| try writeTargetType(writer, program, handle.name),
        .snapshot => |name| try writer.writeAll(name),
        .value_struct => |record| try writeTargetType(writer, program, record.name),
        .pointer => |pointer| {
            // A `[*c]` pointer is already nullable and has no `?` spelling:
            // `?[*c]T` is rejected outright in a `callconv(.c)` signature.
            // Only `*T` and `[*:0]T` need the marker written out.
            if (pointer.is_optional and (!pointer.is_many or pointer.is_c_string)) try writer.writeByte('?');
            try writer.writeAll(if (pointer.is_c_string) "[*:0]" else if (pointer.is_many) "[*c]" else "*");
            if (pointer.is_const) try writer.writeAll("const ");
            try writeZigType(writer, program, pointer.child.*);
        },
        .callback => |callback| {
            try writer.writeAll("*const fn (");
            for (callback.params, 0..) |parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writeZigType(writer, program, parameter);
            }
            try writer.writeAll(") callconv(.c) ");
            try writeZigType(writer, program, callback.ret.*);
        },
    }
}

pub fn writeCType(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("uint8_t"),
        .usize => try writer.writeAll("size_t"),
        .isize => try writer.writeAll("ptrdiff_t"),
        .signed_int => |bits| try writer.print("int{d}_t", .{bits}),
        .unsigned_int => |bits| try writer.print("uint{d}_t", .{bits}),
        .float => |bits| try writer.writeAll(if (bits == 32) "float" else "double"),
        // The handle's own typedef, so a C consumer cannot hand one type's
        // handle to another's function. The projections already spell it.
        .@"opaque" => |handle| try writer.writeAll(handle.c_name),
        .snapshot => |name| try writer.writeAll(name),
        .value_struct => |record| try writer.writeAll(record.c_name),
        .pointer => |pointer| {
            if (pointer.is_c_string) return writer.writeAll("const char *");
            if (pointer.is_const) try writer.writeAll("const ");
            try writeCType(writer, pointer.child.*);
            try writer.writeAll(" *");
        },
        .callback => unreachable,
    }
}

pub fn writeCParam(writer: *std.Io.Writer, value: abi.AbiScalar, name: []const u8) !void {
    if (value != .callback) {
        try writeCType(writer, value);
        try writer.print(" {s}", .{name});
        return;
    }
    const callback = value.callback;
    try writeCType(writer, callback.ret.*);
    try writer.print(" (*{s})(", .{name});
    if (callback.params.len == 0) try writer.writeAll("void");
    for (callback.params, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        try writeCType(writer, parameter);
    }
    try writer.writeByte(')');
}

/// A handle argument crosses cgo as the header's typedef pointer, converted
/// from the unsafe.Pointer the raw signature carries; anything else passes
/// as it is.
pub fn writeCgoHandleArgument(writer: *std.Io.Writer, scalar: abi.AbiScalar, name: []const u8) !void {
    if (scalar == .pointer and scalar.pointer.child.* == .@"opaque") {
        try writer.print("(*C.{s})({s})", .{ scalar.pointer.child.@"opaque".c_name, name });
        return;
    }
    try writer.writeAll(name);
}

/// The typedef behind a constructor's `out_result`, so the raw layer can
/// declare the local the C side writes through.
pub fn payloadOutHandleCName(function: abi.AbiFn) []const u8 {
    for (function.params) |parameter| {
        if (parameter.role != .payload_out) continue;
        return parameter.scalar.pointer.child.pointer.child.@"opaque".c_name;
    }
    unreachable;
}

pub fn writeCgoType(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("uint8_t"),
        .usize => try writer.writeAll("size_t"),
        .isize => try writer.writeAll("ptrdiff_t"),
        .signed_int => |bits| try writer.print("int{d}_t", .{bits}),
        .unsigned_int => |bits| try writer.print("uint{d}_t", .{bits}),
        .float => |bits| try writer.writeAll(if (bits == 32) "float" else "double"),
        .@"opaque" => try writer.writeAll("void"),
        .snapshot => |name| try writer.writeAll(name),
        .value_struct => |record| try writer.writeAll(record.c_name),
        .pointer => unreachable,
        .callback => unreachable,
    }
}

pub fn writeGoScalar(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .bool_u8 => try writer.writeAll("uint8"),
        .usize => try writer.writeAll("uint"),
        .isize => try writer.writeAll("int"),
        .signed_int => |bits| try writeIntegerName(writer, true, bits, false),
        .unsigned_int => |bits| try writeIntegerName(writer, false, bits, false),
        .float => |bits| try writer.print("float{d}", .{bits}),
        .@"opaque", .pointer => try writer.writeAll("unsafe.Pointer"),
        .callback => try writer.writeAll("uintptr"),
        else => unreachable,
    }
}

pub fn writeIntegerName(writer: *std.Io.Writer, signed: bool, bits: u16, c_name: bool) !void {
    _ = c_name;
    try writer.print("{s}{d}", .{ if (signed) "int" else "uint", bits });
}

pub fn writeAtomicGoName(writer: *std.Io.Writer, node: semantic.TypeNode) !void {
    const integer = node.int;
    try writer.print("{s}{d}", .{ if (integer.signed) "Int" else "Uint", integer.bits });
}

fn programHasSlices(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| if (semantic.sliceThroughOptional(parameter.type) == .slice) return true;
        if (semantic.sliceThroughOptional(function.origin.@"return") == .slice) return true;
    }
    return false;
}

pub fn programHasCString(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params, 0..) |_, index| if (function.paramString(index).role == .c_string) return true;
        if ((function.ret_string == .c_string)) return true;
    }
    return false;
}

pub fn programHasOpaqueTypes(program: abi.Program) bool {
    for (program.types) |declaration| {
        if (declaration.isHandle() and !isValueOnlyTaggedUnion(program, declaration.name)) return true;
    }
    return false;
}

pub fn programHasStreams(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| if (parameter.type == .io_stream) return true;
    }
    return false;
}

test "open enum docs permit values outside named constants" {
    const document: semantic.Semantic = .{
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocument(arena.allocator(), document, "terminal", "zg", &.{});
    const enums = try emit.renderForTest(public.renderPublicEnumsFile, program);
    defer std.testing.allocator.free(enums);
    try std.testing.expect(std.mem.indexOf(u8, enums, "// EraseDisplay represents the corresponding Zig open enum; values outside the named constants are valid.") != null);
    try std.testing.expect(std.mem.indexOf(u8, enums, "return \"EraseDisplay(\" + strconv.Itoa(int(value)) + \")\"") != null);
}

pub fn programHasStreamDirection(program: abi.Program, direction: semantic.StreamDirection) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (parameter.type == .io_stream and parameter.type.io_stream.direction == direction) return true;
        }
    }
    return false;
}

/// The fixed `//export` symbol a cgo stream trampoline is bound by. One pair
/// per binding rather than one per parameter: the signature is decided by the
/// direction, so every writer in the binding shares a trampoline.
pub fn streamTrampolineNameAlloc(allocator: std.mem.Allocator, program: abi.Program, direction: semantic.StreamDirection) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}_zigo_stream_{s}", .{
        program.prefix,
        if (direction == .writer) "write" else "read",
    });
}

/// The shim's local names for one stream parameter: its staging buffer, the
/// adapter built on it, and the `*std.Io.Reader` the target call receives when
/// a reader may also arrive as a plain byte slice.
pub fn streamBufferNameAlloc(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}_stream_buffer", .{name});
}

pub fn streamAdapterNameAlloc(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}_stream", .{name});
}

/// The allocator a staging buffer too large for the shim's stack comes from.
/// The binding's own allocator when it named one, so a program that routes
/// every allocation through an arena keeps doing so.
pub fn streamHeapAllocator(program: abi.Program) []const u8 {
    return program.allocator orelse "std.heap.c_allocator";
}

/// Whether the binding needs the Go callback machinery at all: the callback
/// state, the token registry, the panic rethrow, and the imports behind them.
/// A stream parameter answers yes for the same reasons a user callback does --
/// it is a Go value the native side calls back into, and it can panic there.
pub fn programHasCallbacks(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (parameter.type == .callback or parameter.type == .io_stream) return true;
        }
    }
    return false;
}

pub fn functionHasStream(function: semantic.SemanticFn) bool {
    return lower.functionHasStream(function);
}

/// True when some generated function takes a `context.Context` to be stopped
/// through.
pub fn programHasCancellation(program: abi.Program) bool {
    for (program.functions) |function| if (function.origin.cancel != null) return true;
    return false;
}

/// True when a cancellable native call directly owns a Go callback. Only such
/// bindings need to carry the call-scoped cancel pointer on callback state.
pub fn programHasCallbackCancellation(program: abi.Program) bool {
    for (program.functions) |function| {
        if (function.origin.cancel == null) continue;
        for (function.origin.params) |parameter| if (parameter.type == .callback) return true;
    }
    return false;
}

pub fn programHasCallbackFailureResult(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (parameter.type == .callback and callbacks.callbackFailureResult(program, parameter) != null) return true;
        }
    }
    return false;
}

pub fn programHasAtomicPointers(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| if (parameter.type == .atomic_ptr) return true;
    }
    return false;
}

/// The stream operation a function was synthesized for, if it was.
pub fn streamAccessorOp(function: semantic.SemanticFn) ?semantic.StreamAccessor.Op {
    const accessor = function.stream_accessor orelse return null;
    return accessor.op;
}

/// True when the public package generates a `Read` that has to name `io.EOF`.
pub fn programHasStreamRead(program: abi.Program) bool {
    for (program.functions) |function| {
        if (streamAccessorOp(function.origin.*) == .read) return true;
    }
    return false;
}

fn isErrorCallback(parameter: semantic.Parameter) bool {
    return lower.isErrorCallback(parameter);
}

pub fn programHasCallbackErrors(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| if (isErrorCallback(parameter)) return true;
    }
    return false;
}

pub fn callbackSignatureHasGoError(program: abi.Program, wanted: semantic.Callback) bool {
    return lower.callbackSignatureHasGoError(program.origins, wanted);
}

pub fn callbackHasGoError(program: abi.Program, parameter: semantic.Parameter) bool {
    return lower.callbackHasGoError(program.origins, parameter);
}

pub fn typeOwnsErrorCallbacks(program: abi.Program, type_name: []const u8) bool {
    return lower.typeOwnsErrorCallbacks(program.origins, program.constructors, type_name);
}

/// True for a `*std.Io.Reader` parameter, the only direction with a
/// byte-slice fast path: a Go reader that can hand its remaining bytes over
/// in one piece crosses as a slice and costs no trampoline call at all.
pub fn isReaderStream(parameter: semantic.Parameter) bool {
    return parameter.type == .io_stream and parameter.type.io_stream.direction == .reader;
}

pub fn programHasReaderStream(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| if (isReaderStream(parameter)) return true;
    }
    return false;
}

/// The Go handle constructor for one direction, and the half of its name that
/// the public wrapper and the helper both have to agree on.
pub fn streamHandleName(direction: semantic.StreamDirection) []const u8 {
    return if (direction == .writer) "Writer" else "Reader";
}

pub fn programHasTaggedUnionTypes(program: abi.Program) bool {
    return program.projections.len != 0 or program.snapshots.len != 0;
}

/// Every constructed handle carries the `runtime.AddCleanup` safety net, so
/// owning a constructor is the whole test. Handle types the binding never
/// constructs have nothing to release and stay plain.
fn isAutoCleanupType(program: abi.Program, type_name: []const u8) bool {
    return constructorForType(program, type_name) != null;
}

/// Whether a handle type retains callback handles for its own lifetime. This
/// is a per-type question: a program can mix types that take callbacks with
/// types that do not, and only the former need the bookkeeping.
pub fn typeOwnsCallbacks(program: abi.Program, type_name: []const u8) bool {
    for (program.functions) |function| {
        const owner = retainedCallbackOwner(program, function) orelse continue;
        if (!std.mem.eql(u8, owner, type_name)) continue;
        if (hasRetainedCallback(function.origin.*)) return true;
    }
    return false;
}

pub fn retainedCallbackOwner(program: abi.Program, function: abi.AbiFn) ?[]const u8 {
    return lower.retainedCallbackOwner(program.constructors, function.origin.*);
}

pub fn retainedCallbacksBelongToReceiver(program: abi.Program, function: semantic.SemanticFn) bool {
    if (!hasRetainedCallback(function) or function.receiver == null) return false;
    return constructorForInit(program, function) == null and ownedOpaqueReturn(program, function) == null;
}

pub fn publicNeedsRuntime(program: abi.Program) bool {
    for (program.functions) |function| {
        if (constructorForInit(program, function.origin.*) == null and constructorForDeinit(program, function.origin.*) != null) continue;
        if (raw.isReleaseTarget(program, function.origin.*)) continue;
        if (function.origin.@"return" == .error_union) return true;
        if (function.origin.receiver) |receiver| {
            if (isAutoCleanupType(program, receiver)) return true;
        }
        for (function.origin.params) |parameter| switch (parameter.type) {
            .atomic_ptr => return true,
            .opaque_ptr => |pointer| if (isAutoCleanupType(program, pointer.ref)) return true,
            else => {},
        };
    }
    return false;
}

pub fn hasRetainedCallback(function: semantic.SemanticFn) bool {
    return lower.hasRetainedCallback(function);
}

/// The package-level callback counters diagnose ownership that can outlive a
/// call: retained callbacks and stream adapters. A transient callback cannot
/// leak beyond its wrapper, so emitting the accessors for it is dead code.
/// The callback diagnostics (`activeCallbackHandleCount` and friends) are an
/// API the package offers to its own tests, not a helper generated code
/// calls, so they are decided here rather than read off the rendered text.
pub fn programUsesCallbackDiagnostics(program: abi.Program) bool {
    if (programHasStreams(program)) return true;
    for (program.functions) |function| if (hasRetainedCallback(function.origin.*)) return true;
    return false;
}

/// Index of the callback parameter whose userdata this parameter carries.
pub fn callbackTrampolineNameAlloc(allocator: std.mem.Allocator, function: abi.AbiFn, parameter_index: usize) ![]u8 {
    const parameter_name = try naming.snakeAlloc(allocator, function.origin.params[parameter_index].name);
    defer allocator.free(parameter_name);
    return std.fmt.allocPrint(allocator, "{s}_go_callback_{s}", .{ function.symbol, parameter_name });
}

/// The static shim function the native side actually receives when a callback
/// carries floats, and the global holding the Go dispatcher it forwards to.
pub fn callbackThunkNameAlloc(allocator: std.mem.Allocator, function: abi.AbiFn, parameter_index: usize) ![]u8 {
    const parameter_name = try naming.snakeAlloc(allocator, function.origin.params[parameter_index].name);
    defer allocator.free(parameter_name);
    return std.fmt.allocPrint(allocator, "{s}_bits_thunk_{s}", .{ function.symbol, parameter_name });
}

pub fn callbackBindingNameAlloc(allocator: std.mem.Allocator, function: abi.AbiFn, parameter_index: usize) ![]u8 {
    const parameter_name = try naming.snakeAlloc(allocator, function.origin.params[parameter_index].name);
    defer allocator.free(parameter_name);
    return std.fmt.allocPrint(allocator, "{s}_bits_target_{s}", .{ function.symbol, parameter_name });
}

pub fn callbackPackedThunkNameAlloc(allocator: std.mem.Allocator, function: abi.AbiFn, parameter_index: usize) ![]u8 {
    const parameter_name = try naming.snakeAlloc(allocator, function.origin.params[parameter_index].name);
    defer allocator.free(parameter_name);
    return std.fmt.allocPrint(allocator, "{s}_{s}_packed_thunk", .{ function.symbol, parameter_name });
}

pub fn callbackHasPackedParam(program: abi.Program, callback: semantic.Callback) bool {
    for (callback.params) |parameter| if (isPackedValue(program, parameter)) return true;
    return false;
}

/// True when the callback's own parameters include a float, which the purego
/// callback ABI carries as an integer bit pattern instead.
pub fn callbackHasFloatParam(callback: semantic.Callback) bool {
    for (callback.params) |parameter| if (parameter == .float) return true;
    return false;
}

/// The lowered wire signature for a callback parameter: the same shape the
/// header and the exported shim function spell, with floats already replaced
/// by integers.
pub fn callbackWireScalar(function: abi.AbiFn, source_index: usize) ?abi.AbiScalar {
    for (function.params) |parameter| {
        if (parameter.source_index == source_index and parameter.scalar == .callback) return parameter.scalar;
    }
    return null;
}

/// Every purego callback parameter that carries a float needs the shim to sit
/// between the native caller and Go: the native side calls with real floats and
/// Go must receive their bits.
pub fn needsCallbackBitThunk(program: abi.Program, function: abi.AbiFn, parameter_index: usize) bool {
    if (program.backend != .purego) return false;
    const parameter = function.origin.params[parameter_index];
    if (parameter.type != .callback) return false;
    return callbackHasFloatParam(parameter.type.callback) or callbackHasPackedParam(program, parameter.type.callback);
}

fn publicTypeNameExists(program: abi.Program, name: []const u8) bool {
    for (program.types) |declaration| if (std.mem.eql(u8, declaration.name, name)) return true;
    return false;
}

pub fn programNeedsUnsafe(program: abi.Program) bool {
    // A stream trampoline builds a Go slice over the native buffer it was
    // handed, which is the whole of what it does.
    if (programHasSlices(program) or programHasOpaqueTypes(program) or programHasStreams(program)) return true;
    // The layout guards a castable struct carries are spelled with `unsafe`.
    for (program.structs) |record| if (record.castable) return true;
    for (program.functions) |function| {
        if (function.origin.receiver != null) return true;
        for (function.origin.params) |parameter| if (parameter.type == .opaque_ptr) return true;
        if (function.origin.@"return" == .opaque_ptr) return true;
        if (function.origin.@"return" == .error_union and function.origin.@"return".error_union.payload.* == .opaque_ptr) return true;
    }
    return false;
}

pub fn rawGoNameAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]u8 {
    const function_name = try naming.pascalAlloc(allocator, function.name);
    defer allocator.free(function_name);
    const owner = function.receiver orelse function.namespace orelse return allocator.dupe(u8, function_name);
    const owner_name = try naming.ownerPascalAlloc(allocator, owner);
    defer allocator.free(owner_name);
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ owner_name, function_name });
}

/// An owner is a dotted path once a binding names a nested namespace. Each
/// segment becomes one Pascal word, so `unicode.codepointWidth` reaches the
/// raw layer as `UnicodeCodepointWidth`. A registered type name is already one
/// Pascal word, which is why single-segment owners come out unchanged.
pub fn receiverVariableAlloc(allocator: std.mem.Allocator, receiver: []const u8, go_names: []const []const u8) ![]u8 {
    const snake = try naming.snakeAlloc(allocator, receiver);
    defer allocator.free(snake);
    for (1..snake.len + 1) |length| {
        const candidate = snake[0..length];
        var collides = false;
        for (go_names) |name| {
            if (std.mem.eql(u8, candidate, name)) {
                collides = true;
                break;
            }
        }
        if (!collides) return allocator.dupe(u8, candidate);
    }
    return allocator.dupe(u8, "recv");
}

test "receiver names extend past parameters and retain the short default" {
    const short = try receiverVariableAlloc(std.testing.allocator, "Terminal", &.{});
    defer std.testing.allocator.free(short);
    try std.testing.expectEqualStrings("t", short);

    const extended = try receiverVariableAlloc(std.testing.allocator, "Terminal", &.{"t"});
    defer std.testing.allocator.free(extended);
    try std.testing.expectEqualStrings("te", extended);

    const fallback = try receiverVariableAlloc(std.testing.allocator, "Terminal", &.{ "terminal", "termina", "termin", "termi", "term", "ter", "te", "t" });
    defer std.testing.allocator.free(fallback);
    try std.testing.expectEqualStrings("recv", fallback);
}

pub fn constructorForInit(program: abi.Program, function: semantic.SemanticFn) ?semantic.Constructor {
    return semantic.constructorForInit(program.constructors, function);
}

pub fn constructorForDeinit(program: abi.Program, function: semantic.SemanticFn) ?semantic.Constructor {
    return lower.constructorForDeinit(program.constructors, function);
}

pub fn constructorForType(program: abi.Program, type_name: []const u8) ?semantic.Constructor {
    return lower.constructorForType(program.constructors, type_name);
}

pub fn dependentParentType(program: abi.Program, type_name: []const u8) ?[]const u8 {
    for (program.functions) |function| {
        if (!function.origin.childOfReceiver()) continue;
        const constructor = constructorForInit(program, function.origin.*) orelse continue;
        if (!std.mem.eql(u8, constructor.type, type_name)) continue;
        return function.origin.receiver;
    }
    return null;
}

pub fn typeHasDependentChildren(program: abi.Program, type_name: []const u8) bool {
    return typeHasDependentChildrenWithin(program, type_name, program.types.len + 1);
}

fn typeHasDependentChildrenWithin(program: abi.Program, type_name: []const u8, remaining: usize) bool {
    if (remaining == 0) return false;
    for (program.functions) |function| {
        if (function.origin.childOfReceiver() and
            std.mem.eql(u8, function.origin.receiver orelse "", type_name)) return true;
    }
    for (program.functions) |function| {
        const origin = function.origin.*;
        if (!docs.returnsBorrowedView(origin) or
            !std.mem.eql(u8, origin.receiver orelse "", type_name)) continue;
        const node = if (origin.@"return" == .error_union) origin.@"return".error_union.payload.* else origin.@"return";
        if (typeHasDependentChildrenWithin(program, node.opaque_ptr.ref, remaining - 1)) return true;
    }
    return false;
}

pub fn programHasDependentHandles(program: abi.Program) bool {
    for (program.functions) |function| {
        if (function.origin.childOfReceiver() or docs.returnsBorrowedView(function.origin.*)) return true;
    }
    return false;
}

pub fn programHasChildConstructors(program: abi.Program) bool {
    for (program.functions) |function| if (function.origin.childOfReceiver()) return true;
    return false;
}

/// The handle type a caller-owned return hands over.
///
/// Ownership metadata is authoritative, not the function name: `.returns =
/// .caller` makes any function a factory, so a `clone` or `openChild` produces
/// the same owned handle a named constructor does. Registration in
/// `program.constructors` stays name-based because that list also names the
/// deinit that `newX` schedules; this is the wider question of which returns
/// need wrapping at all.
/// True when some generated code hands out a `{name}Ref`: a function that
/// returns the handle without ownership, or a tagged-union payload projection
/// whose payload is that handle. Nothing else can construct one, so a type
/// without either gets no Ref type at all.
pub fn typeHasBorrowedRefs(program: abi.Program, type_name: []const u8) bool {
    for (program.functions) |function| {
        const origin = function.origin.*;
        if (!docs.returnsBorrowedHandle(origin) or docs.returnsBorrowedView(origin)) continue;
        const node = if (origin.@"return" == .error_union) origin.@"return".error_union.payload.* else origin.@"return";
        if (std.mem.eql(u8, node.opaque_ptr.ref, type_name)) return true;
    }
    for (program.projections) |projection| {
        if (projection.kind != .payload) continue;
        const field = projection.field orelse continue;
        const payload = field.type orelse continue;
        if (payload == .opaque_ptr and std.mem.eql(u8, payload.opaque_ptr.ref, type_name)) return true;
    }
    return false;
}

pub fn typeCanBeBorrowed(program: abi.Program, type_name: []const u8) bool {
    for (program.functions) |function| {
        const origin = function.origin.*;
        if (!docs.returnsBorrowedView(origin)) continue;
        const node = if (origin.@"return" == .error_union) origin.@"return".error_union.payload.* else origin.@"return";
        if (std.mem.eql(u8, node.opaque_ptr.ref, type_name)) return true;
    }
    return false;
}

pub fn typeReturnsBorrowedViews(program: abi.Program, type_name: []const u8) bool {
    for (program.functions) |function| {
        if (docs.returnsBorrowedView(function.origin.*) and
            std.mem.eql(u8, function.origin.receiver orelse "", type_name)) return true;
    }
    return false;
}

pub fn ownedOpaqueReturn(program: abi.Program, function: semantic.SemanticFn) ?[]const u8 {
    return lower.ownedOpaqueReturn(program.constructors, function);
}

/// Every constructed handle goes through its `new` helper, which is what
/// registers the cleanup and adopts the callback handles the call retained.
/// `function` owns its result as a `handle`.
pub fn writeOwnedHandleResult(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    expression: []const u8,
) !void {
    const handle = function.ownership.handle;
    try writer.print("new{s}({s}", .{ handle.type_name, expression });
    if (handle.child_of_receiver) {
        try writer.writeAll(", zigoChildParent");
    }
    if (handle.retained_slots != 0) {
        const go_names = try goParamNamesForAlloc(allocator, function.origin.params);
        defer naming.freeParamNames(allocator, go_names);
        try writer.writeAll(", []zigoCallbackHandle{");
        for (0..handle.retained_slots) |slot| {
            if (slot != 0) try writer.writeAll(", ");
            var wrote = false;
            for (function.origin.params, 0..) |parameter, parameter_index| {
                if (parameter.type != .callback or parameter.retention != .retained) continue;
                if (function.callbackSlot(parameter_index).? != slot) continue;
                try writer.print("{s}Handle", .{go_names[parameter_index]});
                wrote = true;
                break;
            }
            if (!wrote) try writer.writeByte('0');
        }
        try writer.writeByte('}');
    }
    try writer.writeByte(')');
}

pub fn rawNameForSemanticAlloc(allocator: std.mem.Allocator, program: abi.Program, name: []const u8, receiver: []const u8) !?[]u8 {
    for (program.functions) |function| {
        if (function.origin.receiver) |actual_receiver| {
            if (std.mem.eql(u8, actual_receiver, receiver) and std.mem.eql(u8, function.origin.name, name)) {
                return try rawGoNameAlloc(allocator, function.origin.*);
            }
        }
    }
    return null;
}

test "tagged union emitters generate checked pointer-only projections" {
    var i16_node: semantic.TypeNode = .{ .int = .{ .bits = 16, .signed = true } };
    const document: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "integer", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
                    .{ .name = "flag", .type = .{ .bool = {} }, .value = 2 },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } }, .value = 3 },
                    .{ .name = "child", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Child" } }, .value = 4 },
                    .{ .name = "samples", .type = .{ .slice = .{ .@"const" = true, .element = &i16_node } }, .value = 5 },
                },
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{
                    .{ .name = "none", .value = 0 },
                    .{ .name = "integer", .value = 1 },
                    .{ .name = "flag", .value = 2 },
                    .{ .name = "mode", .value = 3 },
                    .{ .name = "child", .value = 4 },
                    .{ .name = "samples", .value = 5 },
                },
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{
                .fields = &.{ .{ .name = "off", .value = 0 }, .{ .name = "on", .value = 1 } },
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{
                .fields = &.{.{ .name = "URLValue", .type = .{ .int = .{ .bits = 64, .signed = false } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "HTTPResult",
                .tag_type = .{ .@"enum" = .{ .ref = "HTTPResultTag" } },
            },
            .{ .fields = &.{.{ .name = "URLValue", .value = 0 }}, .kind = .@"enum", .name = "HTTPResultTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            .{ .kind = .@"opaque", .name = "Child" },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocument(arena.allocator(), document, "variant", "zg", &.{});

    const shim_text = try emit.renderForTest(shim.renderShim, program);
    defer std.testing.allocator.free(shim_text);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "export fn zg_value_project_tag_impl(self: *const target.Value, out_value: *u8) u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "out_value.* = @intFromEnum(std.meta.activeTag(self.*));") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "if (std.meta.activeTag(self.*) != .integer) return 0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "out_value.* = @intFromBool(self.flag);") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "out_value_ptr.* = self.samples.ptr;") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "project_none") == null);
    const integer_projection = std.mem.indexOf(u8, shim_text, "export fn zg_value_project_integer_impl").?;
    const mismatch_check = std.mem.indexOfPos(u8, shim_text, integer_projection, "if (std.meta.activeTag(self.*) != .integer) return 0;").?;
    const output_write = std.mem.indexOfPos(u8, shim_text, integer_projection, "out_value.* = self.integer;").?;
    try std.testing.expect(mismatch_check < output_write);

    const header_text = try emit.renderForTest(header.renderHeader, program);
    defer std.testing.allocator.free(header_text);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "typedef struct zg_value zg_value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "uint8_t zg_value_project_tag(const zg_value *self, uint8_t *out_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "uint8_t zg_value_project_integer(const zg_value *self, int32_t *out_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "uint8_t zg_value_project_samples(const zg_value *self, const int16_t **out_value_ptr, size_t *out_value_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "uint8_t zg_http_result_project_url_value(const zg_http_result *self, uint64_t *out_value);") != null);

    const panic_source = try emit.renderForTest(shim.renderPanicSource, program);
    defer std.testing.allocator.free(panic_source);
    try std.testing.expect(std.mem.indexOf(u8, panic_source, "uint8_t zg_value_project_tag_impl(const zg_value *self, uint8_t *out_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, panic_source, "if (self == NULL || out_value == NULL) return 2;") != null);
    try std.testing.expect(std.mem.indexOf(u8, panic_source, "return 3;") != null);

    const raw_text = try emit.renderForTest(raw.renderRaw, program);
    defer std.testing.allocator.free(raw_text);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func ValueProjectTag(self unsafe.Pointer) (uint8, uint8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func ValueProjectInteger(self unsafe.Pointer) (int32, uint8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func HTTPResultProjectURLValue(self unsafe.Pointer) (uint64, uint8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "if status != 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "result := make([]int16, int(outValueLen))") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "copy(result, unsafe.Slice((*int16)(unsafe.Pointer(outValuePtr)), int(outValueLen)))") != null);

    const public_types = try emit.renderUnionFilesForTest(program);
    defer std.testing.allocator.free(public_types);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "\t\"runtime\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) Tag() (ValueTag, error)") != null);
    // No function or projection hands out a borrowed Value, so it has no Ref
    // surface; Child is a projection payload, so it does.
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *ValueRef) Tag() (ValueTag, error)") == null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "ValueRef") == null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) AsInteger() (int32, bool, error)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) MustAsInteger() (int32, bool)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) MustAsChild() (*ChildRef, bool)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (h *HTTPResult) MustAsURLValue() (uint64, bool)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "append([]int16(nil), result...)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "ptr, err := zigoCheckedPointer") != null);
    const public_runtime_text = try emit.renderForTest(public.renderPublicRuntimeFile, program);
    defer std.testing.allocator.free(public_runtime_text);
    // The Must* wrappers are runtime, not per-union, so they moved with it.
    try std.testing.expect(std.mem.indexOf(u8, public_runtime_text, "panic(err)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "panic(err)") == null);
    // Handles stay alive through the `defer receiver.zigoRelease()` the handle
    // check emits, so no generated method defers a KeepAlive on one.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, public_types, "defer runtime.KeepAlive("));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, public_types, "func zigoValueTag(receiver zigoHandle)"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, public_types, "ValueProjectInteger(ptr)"));

    // The sealed variant hierarchy sits beside the projections: one concrete
    // type per Zig variant, and a builder that reads the tag and then only
    // the projection the active variant needs.
    try std.testing.expect(std.mem.indexOf(u8, public_types, "type ValueVariant interface{ isValueVariant() }") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "type ValueNone struct{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (ValueNone) isValueVariant() {}") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "type ValueChild struct {\n\t// Value is the payload the child variant carries.\n\tValue *ChildRef\n}") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "type HTTPResultURLValue struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "tag, err := zigoValueTag(receiver)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "payload, matched, err := zigoValueAsInteger(receiver)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) Variant() (ValueVariant, error) { return zigoValueVariant(v) }") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) MustVariant() ValueVariant { return zigoMust(zigoValueVariant(v)) }") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, public_types, "func zigoValueVariant(receiver zigoHandle)"));

    const public_errors = try emit.renderForTest(public_runtime.renderPublicErrors, program);
    defer std.testing.allocator.free(public_errors);
    try std.testing.expect(std.mem.indexOf(u8, public_errors, "var ErrInvalidHandle = errors.New") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_errors, "type HandleError struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_errors, "type NativePanicError struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_errors, "type StatusError struct") != null);
}
