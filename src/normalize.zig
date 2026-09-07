//! Resolve an authoring tree once into the reflector's private flat declarations.
const std = @import("std");
const a = @import("author.zig");
const ir = @import("declare.zig");

const State = struct {
    root: type,
    source_types: []const a.Type = &.{},
    types: []const ir.Type = &.{},
    functions: []const ir.Function = &.{},
    function_refs: []const a.FunctionRef = &.{},
    packages: []const ir.Package = &.{},
    interfaces: []const ir.Interface = &.{},
};

pub fn binding(comptime source: a.Binding) ir.Binding {
    return comptime blk: {
        @setEvalBranchQuota(2_000_000);
        var state: State = .{ .root = source.root };
        collectTypes(source.declarations, &state);
        flatten(source.declarations, &state, null, null, source.defaults);
        var exclusions: []const []const u8 = &.{};
        const discover: ?ir.Discover = switch (source.discovery) {
            .explicit => null,
            .public, .recursive => |selection| b: {
                for (selection.exclude) |ref| {
                    checkRoot(ref.root, source.root, ref.path);
                    const path = functionPath(ref, state);
                    for (exclusions) |previous| if (std.mem.eql(u8, previous, path)) @compileError("zigo duplicate discovery exclusion: " ++ ref.path);
                    exclusions = exclusions ++ [_][]const u8{path};
                }
                break :b if (source.discovery == .public) .public else .recursive;
            },
        };
        const release = if (source.string_release) |ref| functionPath(ref, state) else null;
        if (source.string_release) |ref| requireFunction(ref, state);
        for (state.functions) |f| if (f.returns.release) |path| {
            var found = false;
            for (state.functions) |candidate| if (std.mem.eql(u8, candidate.path, path)) {
                found = true;
            };
            if (!found) @compileError("zigo release function is not exported: " ++ path);
        };
        break :blk .{
            .root = source.root,
            .allocator = source.allocator,
            .io = source.io,
            .codepoints = source.defaults.codepoints orelse .explicit,
            .strings = source.defaults.strings orelse .explicit,
            .discover = discover,
            .exclude = exclusions,
            .string_release = release,
            .types = state.types,
            .functions = state.functions,
            .packages = state.packages,
            .interfaces = state.interfaces,
        };
    };
}
fn checkRoot(comptime actual: type, comptime expected: type, comptime path: []const u8) void {
    if (actual != expected) @compileError("zigo reference belongs to a different root: " ++ path);
}
fn checkExtensions(comptime extensions: []const ir.Extension) void {
    for (extensions, 0..) |entry, i| {
        for (extensions[0..i]) |previous| if (std.mem.eql(u8, previous.plugin, entry.plugin)) @compileError("zigo duplicate plugin attachment: " ++ entry.plugin);
    }
}
fn typeName(comptime ref: a.TypeRef, comptime state: State) []const u8 {
    checkRoot(ref.root, state.root, ref.path);
    for (state.source_types, state.types) |t, n| if (std.mem.eql(u8, t.ref.path, ref.path) and t.ref.type == ref.type) return n.goName();
    @compileError("zigo type reference is not registered: " ++ ref.path);
}
fn functionPath(comptime ref: a.FunctionRef, comptime state: State) []const u8 {
    checkRoot(ref.root, state.root, ref.path);
    // Match the longest registered owner, so nested types cannot be captured
    // by an outer registration. Go package placement never enters this path.
    var best: ?usize = null;
    for (state.source_types, 0..) |t, i| {
        if (!std.mem.startsWith(u8, ref.path, t.ref.path ++ ".")) continue;
        if (best == null or t.ref.path.len > state.source_types[best.?].ref.path.len) best = i;
    }
    if (best) |i| return state.types[i].goName() ++ ref.path[state.source_types[i].ref.path.len..];
    return ref.path;
}
fn requireFunction(comptime ref: a.FunctionRef, comptime state: State) void {
    const path = functionPath(ref, state);
    for (state.functions) |f| if (std.mem.eql(u8, f.path, path)) return;
    @compileError("zigo function reference is not exported: " ++ ref.path);
}
fn collectTypes(comptime entries: []const a.Entry, state: *State) void {
    for (entries) |entry| switch (entry) {
        .type => |t| {
            checkRoot(t.ref.root, state.root, t.ref.path);
            checkExtensions(t.extensions);
            for (state.source_types) |previous| {
                if (std.mem.eql(u8, previous.ref.path, t.ref.path)) @compileError("zigo duplicate type declaration: " ++ t.ref.path);
                if (previous.ref.type == t.ref.type) @compileError("zigo ambiguous registration of the same Zig type: " ++ t.ref.path);
            }
            const name = t.options.name orelse lastSegment(t.ref.path);
            for (state.types) |previous| if (std.mem.eql(u8, previous.goName(), name)) @compileError("zigo duplicate Go type name: " ++ name);
            const result: ir.Type = switch (t.representation) {
                .handle => |o| .{ .handle = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .fields = o.fields, .ext = t.extensions } },
                .value => |o| .{ .value = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .fields = o.fields, .go = o.go, .ext = t.extensions } },
                .materialized => |o| .{ .materialized = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .fields = o.fields } },
                .enumeration => |o| b: {
                    var covers: []const []const u8 = &.{};
                    for (o.covers) |ref| {
                        checkRoot(ref.root, state.root, ref.path);
                        covers = covers ++ [_][]const u8{ref.path};
                    }
                    break :b .{ .enumeration = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .go = o.go, .exhaustive = o.exhaustive, .covers = covers, .ext = t.extensions } };
                },
                .tagged_union => |o| .{ .tagged_union = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .access = o.access, .omit = o.omit, .ext = t.extensions } },
                .callback => |o| .{ .callback = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .params = o.params, .returns = .{ .semantic = o.returns.semantic }, .userdata = o.userdata, .retention = o.retention, .thread = o.thread, .reentrancy = o.reentrancy, .on_callback_failure = o.on_callback_failure } },
            };
            state.source_types = state.source_types ++ [_]a.Type{t};
            state.types = state.types ++ [_]ir.Type{result};
            collectTypes(t.options.members, state);
        },
        .package => |p| collectTypes(p.declarations, state),
        else => {},
    };
}
fn flatten(comptime entries: []const a.Entry, state: *State, comptime package_index: ?usize, comptime parent: ?a.TypeRef, comptime defaults: a.Defaults) void {
    for (entries) |entry| switch (entry) {
        .package => |p| {
            if (parent != null) @compileError("zigo a package cannot be nested inside a type");
            const path = if (package_index) |i| state.packages[i].path ++ "/" ++ p.path else p.path;
            if (path.len == 0 or path[0] == '/' or std.mem.indexOf(u8, path, "..") != null) @compileError("zigo invalid package path: " ++ path);
            for (state.packages) |previous| if (std.mem.eql(u8, previous.path, path)) @compileError("zigo duplicate package: " ++ path);
            const index = state.packages.len;
            state.packages = state.packages ++ [_]ir.Package{.{ .path = path, .name = p.name, .doc = p.doc }};
            flatten(p.declarations, state, index, null, .{ .codepoints = p.defaults.codepoints orelse defaults.codepoints, .strings = p.defaults.strings orelse defaults.strings });
        },
        .type => |t| {
            if (parent != null) @compileError("zigo type members must be functions, not nested type registrations");
            if (package_index) |i| {
                var packages = state.packages[0..state.packages.len].*;
                packages[i].types = packages[i].types ++ [_][]const u8{typeName(t.ref, state.*)};
                state.packages = &packages;
            }
            flatten(t.options.members, state, package_index, t.ref, defaults);
        },
        .function => |f| {
            checkRoot(f.ref.root, state.root, f.ref.path);
            checkExtensions(f.extensions);
            const path = functionPath(f.ref, state.*);
            for (state.functions) |previous| if (std.mem.eql(u8, previous.path, path)) @compileError("zigo duplicate function declaration: " ++ f.ref.path);
            const normalized = normalizeFunction(f, state.*, parent, defaults);
            state.functions = state.functions ++ [_]ir.Function{normalized};
            state.function_refs = state.function_refs ++ [_]a.FunctionRef{f.ref};
            if (package_index) |i| {
                var packages = state.packages[0..state.packages.len].*;
                packages[i].functions = packages[i].functions ++ [_][]const u8{path};
                state.packages = &packages;
            }
        },
        .interface => |i| {
            if (parent != null) @compileError("zigo an interface cannot be nested inside a type");
            var types: []const type = &.{};
            for (i.types) |ref| {
                _ = typeName(ref, state.*);
                types = types ++ [_]type{ref.type};
            }
            state.interfaces = state.interfaces ++ [_]ir.Interface{.{ .name = i.name, .methods = i.methods, .types = types, .closer = i.closer, .doc = i.doc }};
        },
    };
}
fn normalizeFunction(comptime f: a.Function, comptime state: State, comptime parent: ?a.TypeRef, comptime defaults: a.Defaults) ir.Function {
    var result: ir.Function = .{ .path = functionPath(f.ref, state), .name = f.options.name, .doc = f.options.doc, .ext = f.extensions, .codepoints = defaults.codepoints, .strings = defaults.strings };
    const info = f.ref.signature();
    if (info.is_generic or info.is_var_args) @compileError("zigo function requires a concrete non-variadic wrapper: " ++ f.ref.path);
    var receiver: ?a.TypeRef = null;
    switch (f.options.role) {
        .auto => {
            if (parent) |p| {
                if (firstVisible(info)) |index| {
                    if (isReceiver(info.params[index].type.?, p.type)) receiver = p;
                }
            }
        },
        .method => |r| receiver = r,
        .constructor => |r| {
            _ = typeName(r.type, state);
            result.constructs = r.type.type;
            receiver = r.receiver;
            if (r.parent == .receiver and receiver == null) @compileError("zigo a child constructor needs a receiver: " ++ f.ref.path);
            result.child_of_receiver = r.parent == .receiver;
        },
        .destructor => |r| {
            _ = typeName(r, state);
            result.destroys = r.type;
            receiver = r;
        },
    }
    if (receiver) |r| {
        _ = typeName(r, state);
        result.receiver = r.type;
    }
    const first = firstVisible(info);
    var receiver_index: ?usize = null;
    if (receiver) |r| {
        if (first == null or !isReceiver(info.params[first.?].type.?, r.type)) @compileError("zigo receiver does not match the first non-injected Zig argument: " ++ f.ref.path);
        receiver_index = first;
    } else if (first) |index| {
        // Match the reflector's automatic handle and owner-enum receiver inference.
        const T = info.params[index].type.?;
        for (state.types) |t| {
            if (t.isHandle() and isReceiver(T, t.zigType())) receiver_index = index;
            if (t == .enumeration and T == t.zigType() and std.mem.startsWith(u8, result.path, t.goName() ++ ".")) receiver_index = index;
        }
    }
    result.returns.semantic = f.options.returns.semantic;
    result.returns.go = f.options.returns.go;
    switch (f.options.returns.lifetime) {
        .inferred => {},
        .owned => |owned| {
            result.returns.ownership = .caller;
            if (owned.release) |ref| result.returns.release = functionPath(ref, state);
        },
        .borrowed => {
            if (receiver_index == null) @compileError("zigo a borrowed result needs a receiver: " ++ f.ref.path);
            result.returns.ownership = .borrowed;
        },
        .library => result.returns.ownership = .library,
    }
    var covers: []const []const u8 = &.{};
    for (f.options.covers) |ref| covers = covers ++ [_][]const u8{functionPath(ref, state)};
    result.covers = covers;
    for (f.options.params, 0..) |p, i| {
        if (p.index >= info.params.len) @compileError("zigo parameter index is outside the Zig signature: " ++ f.ref.path);
        if (p.index == receiver_index or injected(info.params[p.index].type.?)) @compileError("zigo cannot annotate a receiver or injected parameter: " ++ f.ref.path);
        for (f.options.params[0..i]) |previous| if (previous.index == p.index) @compileError("zigo duplicate parameter index: " ++ f.ref.path);
    }
    if (f.options.params.len != 0) {
        var params: []const ir.Param = &.{};
        for (info.params, 0..) |parameter, index| {
            if (index == receiver_index or injected(parameter.type.?)) continue;
            var out: ir.Param = .{};
            for (f.options.params) |p| if (p.index == index) {
                out.name = p.go_name;
                out.semantic = p.semantic;
                out.go = p.go;
                switch (p.contract) {
                    .value => {},
                    .buffer => |b| switch (b) {
                        .input => {},
                        .output => |o| {
                            out.direction = .out;
                            out.written = o.written;
                        },
                        .inout => |o| {
                            out.direction = .inout;
                            out.written = o.written;
                        },
                    },
                    .stream => |o| out.buffer = o.buffer,
                    .flatten => |fields| out.flatten = fields,
                    .callback => |c| {
                        out.retention = c.retention;
                        out.reentrancy = c.reentrancy;
                        out.thread = c.thread;
                        out.go_error = c.go_error;
                        out.on_callback_failure = c.on_failure;
                        if (c.userdata) |at| {
                            if (at >= info.params.len or at == receiver_index or injected(info.params[at].type.?)) @compileError("zigo invalid callback userdata index: " ++ f.ref.path);
                            out.userdata = .{ .param = paramName(f, at, info, receiver_index) };
                        }
                    },
                    .cancel => |c| {
                        if (result.cancel != null) @compileError("zigo duplicate cancellation flag: " ++ f.ref.path);
                        out.name = paramName(f, index, info, receiver_index);
                        result.cancel = .{ .param = out.name.?, .canceled = c.canceled };
                    },
                }
            };
            // Explicit userdata references require an explicit stable name even
            // if source-name enrichment would rename an otherwise unnamed slot.
            for (f.options.params) |p| if (p.contract == .callback) {
                if (p.contract.callback.userdata == index) out.name = paramName(f, index, info, receiver_index);
            };
            params = params ++ [_]ir.Param{out};
        }
        result.params = params;
    }
    return result;
}
fn paramName(comptime f: a.Function, comptime at: usize, comptime info: std.builtin.Type.Fn, comptime receiver: ?usize) []const u8 {
    for (f.options.params) |p| if (p.index == at) {
        if (p.go_name) |name| return name;
    };
    var index: usize = 0;
    for (info.params, 0..) |_, i| {
        if (i == at) break;
        if (i != receiver) index += 1;
    }
    return std.fmt.comptimePrint("p{d}", .{index});
}
fn firstVisible(comptime info: std.builtin.Type.Fn) ?usize {
    for (info.params, 0..) |p, i| {
        if (!injected(p.type.?)) return i;
    }
    return null;
}
fn injected(comptime T: type) bool {
    return T == std.mem.Allocator or T == std.Io;
}
fn isReceiver(comptime T: type, comptime Owner: type) bool {
    return T == Owner or (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one and @typeInfo(T).pointer.child == Owner);
}
fn lastSegment(comptime path: []const u8) []const u8 {
    return path[(std.mem.lastIndexOfScalar(u8, path, '.') orelse unreachable) + 1 ..];
}

test "tree normalization owns packages and sparse original argument indices" {
    const Lib = struct {
        pub const Document = opaque {
            pub fn create(_: std.mem.Allocator) *@This() {
                unreachable;
            }
            pub fn read(_: *@This(), _: std.mem.Allocator, _: u32, _: []u8) void {}
            pub fn deinit(_: *@This()) void {}
        };
    };
    const api = a.scope(Lib);
    const doc = api.in("Document");
    const result = comptime binding(.{ .root = Lib, .declarations = &.{a.package(.{ .path = "io", .declarations = &.{api.handle("Document", .{}).with(.{ .members = &.{ doc.function("create", .{}), doc.function("read", .{ .params = &.{.{ .index = 3, .go_name = "dst", .contract = .{ .buffer = .{ .output = .{ .written = .result } } } }} }), doc.function("deinit", .{}) } })} })} });
    try std.testing.expectEqualStrings("Document.read", result.functions[1].path);
    try std.testing.expectEqual(@as(usize, 2), result.functions[1].params.len);
    try std.testing.expectEqualStrings("dst", result.functions[1].params[1].name.?);
    try std.testing.expectEqual(ir.Direction.out, result.functions[1].params[1].direction);
    try std.testing.expectEqualStrings("Document", result.packages[0].types[0]);
    try std.testing.expectEqualStrings("Document.read", result.packages[0].functions[1]);
}

test "Go renames preserve source references and release ownership" {
    const Lib = struct {
        pub const Store = opaque {
            pub fn size(_: *@This()) u32 {
                return 0;
            }
        };
        pub fn take() []u8 {
            unreachable;
        }
        pub fn free(_: []u8) void {}
    };
    const api = a.scope(Lib);
    const result = comptime binding(.{ .root = Lib, .declarations = &.{
        api.handle("Store", .{}).named("Renamed"),
        api.in("Store").function("size", .{}),
        api.function("take", .{ .returns = .{ .lifetime = .{ .owned = .{ .release = api.ref("free") } }, .semantic = .utf8_string } }),
        api.function("free", .{}),
    } });
    try std.testing.expectEqualStrings("Renamed.size", result.functions[0].path);
    try std.testing.expectEqualStrings("root.free", result.functions[1].returns.release.?);
    try std.testing.expectEqual(ir.Ownership.caller, result.functions[1].returns.ownership.?);
}

test "package defaults override only declared authoring defaults" {
    const Lib = struct {
        pub fn text(_: []const u8) void {}
    };
    const api = a.scope(Lib);
    const result = comptime binding(.{ .root = Lib, .defaults = .{ .strings = .infer_utf8, .codepoints = .infer_u21 }, .declarations = &.{
        a.package(.{ .path = "text", .defaults = .{ .strings = .explicit }, .declarations = &.{api.function("text", .{})} }),
    } });
    try std.testing.expectEqual(ir.Strings.explicit, result.functions[0].strings.?);
    try std.testing.expectEqual(ir.Codepoints.infer_u21, result.functions[0].codepoints.?);
}
