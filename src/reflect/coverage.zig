const std = @import("std");
const semantic = @import("semantic");
const walk = @import("walk.zig");

pub const Status = enum { bound, wrapped, excluded, unbound };

pub const Declaration = struct {
    path: []const u8,
    status: Status,
    reason: ?[]const u8 = null,
    via: ?[]const u8 = null,
};

pub const Report = struct {
    package: []const u8,
    bound: usize,
    unbound: usize,
    excluded: usize,
    declarations: []const Declaration,
    unregistered_types: []const []const u8,

    pub fn render(self: Report, writer: *std.Io.Writer) !void {
        const total = self.bound + self.unbound;
        const percent = if (total == 0) 0 else self.bound * 100 / total;
        try writer.print("{s}: {d}/{d} public declarations bound ({d}%)\n", .{ self.package, self.bound, total, percent });
        for (self.declarations) |declaration| switch (declaration.status) {
            .bound, .wrapped => {},
            .excluded => try writer.print("  excluded: {s}\n", .{declaration.path}),
            .unbound => try writer.print("  unbound: {s}  (reason: {s})\n", .{ declaration.path, declaration.reason orelse "unsupported signature" }),
        };
        var wrote_wrapped = false;
        for (self.declarations) |declaration| {
            if (declaration.status != .wrapped) continue;
            if (!wrote_wrapped) {
                try writer.writeAll("  wrapped:\n");
                wrote_wrapped = true;
            }
            try writer.print("    {s} <- {s}\n", .{ declaration.path, declaration.via.? });
        }
        if (self.unregistered_types.len != 0) {
            try writer.writeAll("  unregistered types:\n");
            for (self.unregistered_types) |name| try writer.print("    {s}\n", .{name});
        }
    }

    pub fn json(self: Report, allocator: std.mem.Allocator) ![]u8 {
        return std.json.Stringify.valueAlloc(allocator, self, .{ .whitespace = .indent_2, .emit_null_optional_fields = false });
    }
};

pub fn classify(
    allocator: std.mem.Allocator,
    comptime binding: anytype,
    package: []const u8,
    document: semantic.Semantic,
    source_functions: []const semantic.SemanticFn,
) !Report {
    @setEvalBranchQuota(100_000);
    var declarations: std.ArrayList(Declaration) = .empty;
    var seen_functions: std.ArrayList([]const u8) = .empty;
    defer seen_functions.deinit(allocator);
    var public_types: std.ArrayList([]const u8) = .empty;
    defer public_types.deinit(allocator);
    var referenced_types: std.ArrayList([]const u8) = .empty;
    defer referenced_types.deinit(allocator);

    if (@hasField(@TypeOf(binding), "types")) inline for (binding.types) |entry| {
        if (comptime entry.repr != .callback) try collectContainer(
            allocator,
            &declarations,
            &seen_functions,
            &public_types,
            &referenced_types,
            binding,
            document,
            source_functions,
            entry.type,
            comptime walk.typeEntryName(entry),
            comptime walk.typeEntryName(entry),
            comptime walk.discoveryEnabled(binding) and entry.repr != .enumeration,
        );
    };
    try collectContainer(allocator, &declarations, &seen_functions, &public_types, &referenced_types, binding, document, source_functions, binding.root, null, "root", comptime walk.discoveryEnabled(binding));

    // Field accessors are generated functions even though there is no Zig
    // declaration to enumerate. Count each getter and setter exactly once.
    for (document.functions) |function| if (function.field_access != null) try declarations.append(allocator, .{
        .path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ function.receiver.?, function.name }),
        .status = .bound,
    });

    // A wrapper supplements the upstream declaration; it does not replace a
    // direct binding or an explicit exclusion, and therefore only changes an
    // otherwise-unbound declaration's classification.
    for (document.functions) |function| {
        for (function.covers orelse &.{}) |covered_path| {
            const wanted = coverageDisplayPath(covered_path);
            for (declarations.items) |*declaration| {
                if (declaration.status != .unbound or !std.mem.eql(u8, declaration.path, wanted)) continue;
                declaration.status = .wrapped;
                declaration.reason = null;
                declaration.via = try functionDisplayPath(allocator, function);
                break;
            }
        }
    }

    var unregistered: std.ArrayList([]const u8) = .empty;
    for (referenced_types.items) |full_name| {
        if (!contains(public_types.items, full_name) or typeKnownToDocument(document, full_name) or isTranslateCTypeName(full_name)) continue;
        const name = coverageTypeName(binding, full_name);
        if (!contains(unregistered.items, name)) try unregistered.append(allocator, name);
    }
    std.mem.sort([]const u8, unregistered.items, {}, lessThan);
    std.mem.sort(Declaration, declarations.items, {}, declarationLessThan);

    var bound: usize = 0;
    var unbound: usize = 0;
    var excluded: usize = 0;
    for (declarations.items) |item| switch (item.status) {
        .bound, .wrapped => bound += 1,
        .unbound => unbound += 1,
        .excluded => excluded += 1,
    };
    return .{
        .package = package,
        .bound = bound,
        .unbound = unbound,
        .excluded = excluded,
        .declarations = try declarations.toOwnedSlice(allocator),
        .unregistered_types = try unregistered.toOwnedSlice(allocator),
    };
}

/// A type-free function catalog for the syntax enrichment pass. Coverage
/// needs source parameter names for declarations that cannot be reflected
/// into the binding document precisely because their signatures are invalid.
pub fn sourceDocument(
    allocator: std.mem.Allocator,
    comptime binding: anytype,
    package: []const u8,
    prefix: []const u8,
) !semantic.Semantic {
    var functions: std.ArrayList(semantic.SemanticFn) = .empty;
    var seen: std.ArrayList([]const u8) = .empty;
    defer seen.deinit(allocator);
    if (@hasField(@TypeOf(binding), "types")) inline for (binding.types) |entry| {
        if (comptime entry.repr != .callback and entry.repr != .enumeration)
            try collectSourceFunctions(allocator, &functions, &seen, entry.type, comptime walk.typeEntryName(entry));
    };
    try collectSourceFunctions(allocator, &functions, &seen, binding.root, null);
    return .{
        .functions = try functions.toOwnedSlice(allocator),
        .package = package,
        .prefix = prefix,
        .zig_version = @import("builtin").zig_version_string,
    };
}

fn collectSourceFunctions(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(semantic.SemanticFn),
    seen: *std.ArrayList([]const u8),
    comptime Container: type,
    comptime owner: ?[]const u8,
) !void {
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@typeInfo(@TypeOf(value)) != .@"fn") continue;
        const identity = @typeName(Container) ++ "." ++ candidate.name;
        if (!contains(seen.items, identity)) {
            try seen.append(allocator, identity);
            const info = @typeInfo(@TypeOf(value)).@"fn";
            const params = try allocator.alloc(semantic.Parameter, info.params.len);
            for (params, 0..) |*parameter, index| parameter.* = .{
                .name = try std.fmt.allocPrint(allocator, "p{d}", .{index}),
                .name_source = .fallback,
                .type = .{ .void = {} },
            };
            try functions.append(allocator, .{
                .name = candidate.name,
                .namespace = owner,
                .params = params,
                .@"return" = .{ .void = {} },
                .symbol = "",
            });
        }
    }
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@TypeOf(value) != type or comptime !walk.isNestedContainer(Container, value)) continue;
        try collectSourceFunctions(
            allocator,
            functions,
            seen,
            value,
            comptime if (owner) |parent| parent ++ "." ++ candidate.name else candidate.name,
        );
    }
}

fn coverageDisplayPath(path: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, path, "root.")) path["root.".len..] else path;
}

fn functionDisplayPath(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]const u8 {
    if (function.zig_path) |path| return path;
    if (function.receiver orelse function.namespace) |owner|
        return std.fmt.allocPrint(allocator, "{s}.{s}", .{ owner, function.name });
    return function.name;
}

fn collectContainer(
    allocator: std.mem.Allocator,
    declarations: *std.ArrayList(Declaration),
    seen_functions: *std.ArrayList([]const u8),
    public_types: *std.ArrayList([]const u8),
    referenced_types: *std.ArrayList([]const u8),
    comptime binding: anytype,
    document: semantic.Semantic,
    source_functions: []const semantic.SemanticFn,
    comptime Container: type,
    comptime owner: ?[]const u8,
    comptime path_prefix: []const u8,
    comptime discovered: bool,
) !void {
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@TypeOf(value) == type and comptime walk.isContainer(value)) {
            if (!contains(public_types.items, @typeName(value))) try public_types.append(allocator, @typeName(value));
        }
        if (@typeInfo(@TypeOf(value)) != .@"fn") continue;
        const identity = @typeName(Container) ++ "." ++ candidate.name;
        if (!contains(seen_functions.items, identity)) {
            try seen_functions.append(allocator, identity);
            const path = path_prefix ++ "." ++ candidate.name;
            const status: Status = if (comptime walk.selectorContains(binding, "exclude", path))
                .excluded
            else if (discovered or comptime functionListed(binding, path))
                .bound
            else
                .unbound;
            try collectFunctionTypes(allocator, referenced_types, @TypeOf(value));
            try declarations.append(allocator, .{
                .path = displayPath(owner, candidate.name),
                .status = status,
                .reason = if (status == .unbound) try signatureReason(allocator, binding, document, source_functions, owner, candidate.name, @TypeOf(value)) else null,
            });
        }
    }
    inline for (comptime std.meta.declarations(Container)) |candidate| {
        const value = @field(Container, candidate.name);
        if (@TypeOf(value) != type or comptime !walk.isNestedContainer(Container, value)) continue;
        try collectContainer(
            allocator,
            declarations,
            seen_functions,
            public_types,
            referenced_types,
            binding,
            document,
            source_functions,
            value,
            comptime if (owner) |parent| parent ++ "." ++ candidate.name else candidate.name,
            path_prefix ++ "." ++ candidate.name,
            comptime discovered and walk.discoveryRecursive(binding),
        );
    }
}

fn displayPath(comptime owner: ?[]const u8, comptime name: []const u8) []const u8 {
    return if (owner) |value| value ++ "." ++ name else name;
}

fn collectFunctionTypes(allocator: std.mem.Allocator, types: *std.ArrayList([]const u8), comptime F: type) !void {
    const info = @typeInfo(F).@"fn";
    inline for (info.params) |parameter| if (parameter.type) |T| try collectType(allocator, types, T);
    if (info.return_type) |T| try collectType(allocator, types, T);
}

fn collectType(allocator: std.mem.Allocator, types: *std.ArrayList([]const u8), comptime T: type) !void {
    switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union" => if (!isBuiltinSpecial(T) and !contains(types.items, @typeName(T))) try types.append(allocator, @typeName(T)),
        .pointer => |info| if (@typeInfo(info.child) == .@"fn") try collectFunctionTypes(allocator, types, info.child) else try collectType(allocator, types, info.child),
        .optional => |info| try collectType(allocator, types, info.child),
        .error_union => |info| try collectType(allocator, types, info.payload),
        .@"fn" => try collectFunctionTypes(allocator, types, T),
        else => {},
    }
}

/// Best-effort coverage reason. It mirrors the broad rejection classes in
/// validate.typeOffense and the sharper ZIGO signature diagnostics; anything
/// it cannot prove falls back to "unsupported signature" at render time.
fn signatureReason(
    allocator: std.mem.Allocator,
    comptime binding: anytype,
    document: semantic.Semantic,
    source_functions: []const semantic.SemanticFn,
    comptime owner: ?[]const u8,
    comptime function_name: []const u8,
    comptime F: type,
) ![]const u8 {
    const info = @typeInfo(F).@"fn";
    var output: std.Io.Writer.Allocating = .init(allocator);
    var count: usize = 0;
    inline for (info.params, 0..) |parameter, index| {
        if (parameter.is_generic or parameter.type == null) {
            if (count != 0) try output.writer.writeAll("; ");
            try output.writer.writeAll("param ");
            if (sourceParameterName(source_functions, owner, function_name, index)) |name|
                try output.writer.writeAll(name)
            else
                try output.writer.print("p{d}", .{index});
            try output.writer.writeAll(": comptime parameter");
            count += 1;
            continue;
        }
        const T = parameter.type.?;
        const reason: ?[]const u8 = if (T == std.mem.Allocator)
            if (!@hasField(@TypeOf(binding), "allocator")) "allocator, no metadata" else null
        else if (T == std.Io)
            if (!@hasField(@TypeOf(binding), "io")) "io, no metadata" else null
        else
            try typeReason(allocator, binding, document, T, true);
        if (reason) |detail| {
            if (count != 0) try output.writer.writeAll("; ");
            try output.writer.writeAll("param ");
            if (sourceParameterName(source_functions, owner, function_name, index)) |name|
                try output.writer.writeAll(name)
            else
                try output.writer.print("p{d}", .{index});
            try output.writer.print(": {s}", .{detail});
            count += 1;
        }
    }
    if (info.return_type) |T| {
        const reason: ?[]const u8 = if (@typeInfo(T) == .error_union and @typeInfo(T).error_union.error_set == anyerror)
            "anyerror"
        else
            try typeReason(allocator, binding, document, T, true);
        if (reason) |detail| {
            if (count != 0) try output.writer.writeAll("; ");
            try output.writer.print("return: {s}", .{detail});
            count += 1;
        }
    }
    if (count == 0) {
        output.deinit();
        return "not listed";
    }
    return try output.toOwnedSlice();
}

fn sourceParameterName(
    functions: []const semantic.SemanticFn,
    comptime owner: ?[]const u8,
    comptime function_name: []const u8,
    index: usize,
) ?[]const u8 {
    for (functions) |function| {
        if (!std.mem.eql(u8, function.name, function_name) or !semantic.optionalStringEqual(function.namespace, owner)) continue;
        if (index < function.params.len) return function.params[index].name;
    }
    return null;
}

fn typeReason(
    allocator: std.mem.Allocator,
    comptime binding: anytype,
    document: semantic.Semantic,
    comptime T: type,
    comptime whole: bool,
) !?[]const u8 {
    return switch (@typeInfo(T)) {
        .void, .bool => null,
        .int => |info| if (whole or info.bits == 8 or info.bits == 16 or info.bits == 32 or info.bits == 64) null else "no C representation",
        .float => |info| if (info.bits == 32 or info.bits == 64) null else "no C representation",
        .@"enum" => if (typeKnownToDocument(document, @typeName(T))) null else try unregisteredReason(allocator, T),
        .@"struct" => |info| if (info.layout == .@"extern" or info.layout == .@"packed" or typeKnownToDocument(document, @typeName(T))) null else try plainStructReason(allocator, binding, document, T),
        .@"union" => |info| if (info.tag_type == null) "no C representation" else if (typeKnownToDocument(document, @typeName(T))) null else try unregisteredReason(allocator, T),
        .pointer => |info| switch (info.size) {
            .slice => try typeReason(allocator, binding, document, info.child, false),
            .one => if (@typeInfo(info.child) == .@"fn") try callbackReason(allocator, binding, document, info.child) else if (isBuiltinSpecial(info.child) or typeKnownToDocument(document, @typeName(info.child))) null else try unregisteredReason(allocator, info.child),
            .many => if (info.child == u8 and info.is_const and info.sentinel() != null) null else "no C representation",
            else => "no C representation",
        },
        .optional => |info| switch (@typeInfo(info.child)) {
            .@"struct" => |child_info| if (child_info.layout == .auto and !typeKnownToDocument(document, @typeName(info.child)))
                "optional of plain struct"
            else if (try typeReason(allocator, binding, document, info.child, whole)) |reason|
                try std.fmt.allocPrint(allocator, "optional of {s}", .{reason})
            else
                null,
            else => if (try typeReason(allocator, binding, document, info.child, whole)) |reason|
                try std.fmt.allocPrint(allocator, "optional of {s}", .{reason})
            else
                null,
        },
        .error_union => |info| try typeReason(allocator, binding, document, info.payload, whole),
        .@"fn" => try callbackReason(allocator, binding, document, T),
        else => "unsupported signature",
    };
}

fn plainStructReason(allocator: std.mem.Allocator, comptime binding: anytype, document: semantic.Semantic, comptime T: type) ![]const u8 {
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (try typeReason(allocator, binding, document, field.type, false)) |reason|
            return std.fmt.allocPrint(allocator, "plain struct (field {s}: {s})", .{ field.name, reason });
    }
    return "plain struct";
}

fn unregisteredReason(allocator: std.mem.Allocator, comptime T: type) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s} unregistered", .{walk.shortTypeName(@typeName(T))});
}

fn callbackReason(allocator: std.mem.Allocator, comptime binding: anytype, document: semantic.Semantic, comptime F: type) !?[]const u8 {
    const info = @typeInfo(F).@"fn";
    if (!std.meta.eql(info.calling_convention, std.builtin.CallingConvention.c)) return "non-C callback";
    inline for (info.params) |parameter| {
        const T = parameter.type orelse return "comptime parameters";
        if (try typeReason(allocator, binding, document, T, false)) |reason| return reason;
    }
    if (info.return_type) |T| return try typeReason(allocator, binding, document, T, false);
    return null;
}

fn functionListed(comptime binding: anytype, comptime path: []const u8) bool {
    if (!@hasField(@TypeOf(binding), "functions")) return false;
    inline for (binding.functions) |entry| if (walk.functionEntryContainsPath(entry, path)) return true;
    return false;
}

fn typeKnownToDocument(document: semantic.Semantic, full_name: []const u8) bool {
    for (document.types) |declaration| {
        const path = declaration.zig_path orelse continue;
        if (std.mem.eql(u8, path, full_name)) return true;
        if (path.len > full_name.len and path[full_name.len] == '#' and std.mem.startsWith(u8, path, full_name)) return true;
    }
    return false;
}

fn coverageTypeName(comptime binding: anytype, full_name: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, full_name, '(') == null) return walk.shortTypeName(full_name);
    const root_name = @typeName(binding.root);
    if (full_name.len > root_name.len and full_name[root_name.len] == '.' and std.mem.startsWith(u8, full_name, root_name))
        return full_name[root_name.len + 1 ..];
    return full_name;
}

fn isTranslateCTypeName(full_name: []const u8) bool {
    return std.mem.indexOf(u8, full_name, "C__struct_") != null or
        std.mem.indexOf(u8, full_name, "cimport.") != null;
}

fn isBuiltinSpecial(comptime T: type) bool {
    return T == std.Io.Writer or T == std.Io.Reader or T == std.mem.Allocator or T == std.Io or T == std.atomic.Value(u32);
}

fn contains(values: []const []const u8, wanted: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, wanted)) return true;
    return false;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn declarationLessThan(_: void, a: Declaration, b: Declaration) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

test "classifier distinguishes selected and unsupported functions" {
    const Api = struct {
        pub const Nested = struct {
            pub const Hidden = struct { value: u32 };
            pub fn omitted(value: i32) i32 {
                return value;
            }
            pub fn unsupported(value: *Hidden) void {
                _ = value;
            }
        };
        pub fn selected(value: i32) i32 {
            return value;
        }
    };
    const binding = .{ .root = Api, .functions = .{.{ .path = "root.selected" }} };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const document = try walk.reflect(allocator, binding, "sample", "zg");
    const report = try classify(allocator, binding, "sample", document, &.{});
    try std.testing.expectEqual(@as(usize, 1), report.bound);
    try std.testing.expectEqual(@as(usize, 2), report.unbound);
    try std.testing.expectEqual(@as(usize, 0), report.excluded);
    try std.testing.expectEqualStrings("not listed", report.declarations[0].reason.?);
    try std.testing.expectEqualStrings("param p0: Hidden unregistered", report.declarations[1].reason.?);
    try std.testing.expectEqualStrings("Hidden", report.unregistered_types[0]);
}

test "covers classifies wrapped declarations in text and JSON" {
    const Api = struct {
        pub const Service = struct {
            pub fn upstream() void {}
        };
        pub fn other() void {}
        pub fn wrapper() void {}
    };
    const binding = .{
        .root = Api,
        .types = .{.{ .type = Api.Service, .repr = .@"opaque" }},
        .functions = .{.{
            .path = "root.wrapper",
            .covers = .{ "Service.upstream", "root.other" },
        }},
    };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const document = try walk.reflect(allocator, binding, "sample", "zg");
    const report = try classify(allocator, binding, "sample", document, &.{});

    try std.testing.expectEqual(@as(usize, 3), report.bound);
    try std.testing.expectEqual(@as(usize, 0), report.unbound);
    try std.testing.expectEqualStrings("Service.upstream", document.functions[0].covers.?[0]);
    try std.testing.expectEqual(.wrapped, report.declarations[0].status);
    try std.testing.expectEqualStrings("wrapper", report.declarations[0].via.?);
    try std.testing.expectEqual(.wrapped, report.declarations[1].status);

    var rendered: std.Io.Writer.Allocating = .init(allocator);
    try report.render(&rendered.writer);
    try std.testing.expectEqualStrings(
        "sample: 3/3 public declarations bound (100%)\n" ++
            "  wrapped:\n" ++
            "    Service.upstream <- wrapper\n" ++
            "    other <- wrapper\n",
        rendered.written(),
    );
    const json = try report.json(allocator);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\": \"wrapped\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"via\": \"wrapper\"") != null);
}

test "unregistered type names are readable and document aware" {
    const Api = struct {
        fn Batch(comptime T: type, comptime enabled: bool) type {
            return struct {
                value: T,
                pub const is_enabled = enabled;
            };
        }

        pub const Coordinate = struct { x: i32 };
        pub const Generic = Batch(Coordinate, true);
        pub const C__struct_117396 = struct { value: u32 };
        pub const Options = struct { enabled: bool = false };

        pub fn generic(value: *Generic) void {
            _ = value;
        }
        pub fn translated(value: *C__struct_117396) void {
            _ = value;
        }
        pub fn optionsPtr(value: *Options) void {
            _ = value;
        }
        pub fn configure(options: Options) void {
            _ = options;
        }
    };
    const binding = .{
        .root = Api,
        .functions = .{.{
            .path = "root.configure",
            .params = .{"options"},
            .param_meta = .{ .options = .{ .flatten = .{"enabled"} } },
        }},
    };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const document = try walk.reflect(allocator, binding, "sample", "zg");
    const report = try classify(allocator, binding, "sample", document, &.{});

    try std.testing.expect(typeKnownToDocument(document, @typeName(Api.Options)));
    try std.testing.expectEqual(@as(usize, 1), report.unregistered_types.len);
    try std.testing.expect(std.mem.indexOfScalar(u8, report.unregistered_types[0], '(') != null);
    try std.testing.expect(!std.mem.eql(u8, report.unregistered_types[0], "Coordinate),true)"));
    for (report.unregistered_types) |name| {
        try std.testing.expect(std.mem.indexOf(u8, name, "C__struct_") == null);
        try std.testing.expect(!std.mem.eql(u8, name, "Options"));
    }

    for (report.declarations) |declaration| {
        if (std.mem.eql(u8, declaration.path, "optionsPtr"))
            try std.testing.expectEqualStrings("not listed", declaration.reason.?);
    }
}

test "document type resolver accepts disambiguated zig paths" {
    const Api = struct {
        pub const Coordinate = struct { x: i32 };
    };
    const binding = .{ .root = Api, .functions = .{} };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var document = try walk.reflect(allocator, binding, "sample", "zg");
    document.types = &.{.{
        .kind = .value_struct,
        .name = "Coordinate",
        .zig_path = @typeName(Api.Coordinate) ++ "#RegisteredCoordinate",
    }};
    try std.testing.expect(typeKnownToDocument(document, @typeName(Api.Coordinate)));
}

test "writer-only unbound function is merely not listed" {
    const Api = struct {
        pub fn wrapper() void {}
        pub fn write(writer: *std.Io.Writer) void {
            _ = writer;
        }
    };
    const binding = .{ .root = Api, .functions = .{.{ .path = "root.wrapper" }} };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const document = try walk.reflect(allocator, binding, "sample", "zg");
    const source_functions = [_]semantic.SemanticFn{.{
        .name = "write",
        .params = &.{.{ .name = "writer", .type = .{ .void = {} } }},
        .@"return" = .{ .void = {} },
        .symbol = "",
    }};
    const report = try classify(allocator, binding, "sample", document, &source_functions);
    for (report.declarations) |declaration| if (std.mem.eql(u8, declaration.path, "write"))
        try std.testing.expectEqualStrings("not listed", declaration.reason.?);
}

test "signature reason lists every offending parameter and return" {
    const Api = struct {
        pub const Pin = enum { top_left };
        pub const Options = struct { tl: Pin };
        pub const Map = struct { enabled: bool };
        pub const Result = struct { pin: Pin };

        pub fn wrapper() void {}
        pub fn blocked(opts: Options, map: ?Map) Result {
            _ = map;
            return .{ .pin = opts.tl };
        }
    };
    const binding = .{ .root = Api, .functions = .{.{ .path = "root.wrapper" }} };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const document = try walk.reflect(allocator, binding, "sample", "zg");
    const source_functions = [_]semantic.SemanticFn{.{
        .name = "blocked",
        .params = &.{
            .{ .name = "opts", .type = .{ .void = {} } },
            .{ .name = "map", .type = .{ .void = {} } },
        },
        .@"return" = .{ .void = {} },
        .symbol = "",
    }};
    const report = try classify(allocator, binding, "sample", document, &source_functions);
    for (report.declarations) |declaration| if (std.mem.eql(u8, declaration.path, "blocked"))
        try std.testing.expectEqualStrings(
            "param opts: plain struct (field tl: Pin unregistered); " ++
                "param map: optional of plain struct; " ++
                "return: plain struct (field pin: Pin unregistered)",
            declaration.reason.?,
        );
}

test "signature reason names the first offending nested field" {
    const Api = struct {
        pub const Pin = enum { top_left };
        pub const Options = struct { tl: Pin, count: usize };

        pub fn wrapper() void {}
        pub fn configure(opts: Options) void {
            _ = opts;
        }
    };
    const binding = .{ .root = Api, .functions = .{.{ .path = "root.wrapper" }} };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const document = try walk.reflect(allocator, binding, "sample", "zg");
    const source_functions = [_]semantic.SemanticFn{.{
        .name = "configure",
        .params = &.{.{ .name = "opts", .type = .{ .void = {} } }},
        .@"return" = .{ .void = {} },
        .symbol = "",
    }};
    const report = try classify(allocator, binding, "sample", document, &source_functions);
    for (report.declarations) |declaration| if (std.mem.eql(u8, declaration.path, "configure"))
        try std.testing.expectEqualStrings(
            "param opts: plain struct (field tl: Pin unregistered)",
            declaration.reason.?,
        );
}
