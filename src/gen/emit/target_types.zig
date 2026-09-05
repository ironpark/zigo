//! Resolve reflected Zig paths without depending on output emitters.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");

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
    const declaration = semantic.typeDecl(program.types, name) orelse return null;
    const path = declaration.zig_path orelse return null;
    return if (std.mem.indexOfAny(u8, path, "(#") == null) path else null;
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
