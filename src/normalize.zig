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
    sessions: []const ir.Session = &.{},
};

pub fn binding(comptime source: a.Binding) ir.Binding {
    return comptime blk: {
        @setEvalBranchQuota(2_000_000);
        var state: State = .{ .root = source.root };
        collectTypes(source.declarations, &state);
        resolveTypeReferences(&state);
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
            .sessions = state.sessions,
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
            if (t.representation == .handle) for (t.representation.handle.fields) |field| checkExtensions(field.ext);
            for (state.source_types) |previous| {
                if (std.mem.eql(u8, previous.ref.path, t.ref.path)) @compileError("zigo duplicate type declaration: " ++ t.ref.path);
                if (previous.ref.type == t.ref.type) @compileError("zigo ambiguous registration of the same Zig type: " ++ t.ref.path);
            }
            const name = t.options.name orelse lastSegment(t.ref.path);
            for (state.types) |previous| if (std.mem.eql(u8, previous.goName(), name)) @compileError("zigo duplicate Go type name: " ++ name);
            const result: ir.Type = switch (t.representation) {
                .handle => |o| .{ .handle = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .fields = o.fields, .ext = externalExtensions(t.extensions) } },
                .value => |o| .{ .value = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .fields = o.fields, .go = o.go, .ext = externalExtensions(t.extensions) } },
                .materialized => |o| .{ .materialized = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .fields = o.fields, .ext = externalExtensions(t.extensions) } },
                .enumeration => |o| .{ .enumeration = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .go = o.go, .exhaustive = o.exhaustive, .fields = o.fields, .text = hasText(t.extensions), .ext = externalExtensions(t.extensions) } },
                .tagged_union => |o| .{ .tagged_union = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .access = o.access, .omit = o.omit, .ext = externalExtensions(t.extensions) } },
                .callback => |o| .{ .callback = .{ .type = t.ref.type, .name = name, .doc = t.options.doc, .params = callbackParams(t.ref.type, o, t.ref.path), .returns = .{ .semantic = o.returns.semantic }, .userdata = o.userdata, .retention = o.retention, .thread = o.thread, .reentrancy = o.reentrancy, .on_callback_failure = o.on_failure, .ext = externalExtensions(t.extensions) } },
            };
            state.source_types = state.source_types ++ [_]a.Type{t};
            state.types = state.types ++ [_]ir.Type{result};
            collectTypes(t.options.members, state);
        },
        .package => |p| collectTypes(p.declarations, state),
        else => {},
    };
}
fn resolveTypeReferences(state: *State) void {
    // All owners must be registered before resolving covers, including a
    // reference to a type that appears later in the declaration tree.
    var types = state.types[0..state.types.len].*;
    for (state.source_types, 0..) |source, i| {
        if (source.representation != .enumeration) continue;
        var covers: []const []const u8 = &.{};
        for (source.representation.enumeration.covers) |ref|
            covers = covers ++ [_][]const u8{functionPath(ref, state.*)};
        types[i].enumeration.covers = covers;
    }
    const frozen = types;
    state.types = &frozen;
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
                const frozen = packages;
                state.packages = &frozen;
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
                const frozen = packages;
                state.packages = &frozen;
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
        .session => |s| {
            if (parent != null) @compileError("zigo a session cannot be nested inside a type");
            _ = typeName(s.primary, state.*);
            var children: []const ir.SessionChild = &.{};
            for (s.children) |child| {
                _ = typeName(child.type, state.*);
                children = children ++ [_]ir.SessionChild{.{ .type = child.type.type, .name = child.name, .plural = child.plural }};
            }
            state.sessions = state.sessions ++ [_]ir.Session{.{ .name = s.name, .primary = s.primary.type, .children = children, .doc = s.doc }};
        },
    };
}
fn normalizeFunction(comptime f: a.Function, comptime state: State, comptime parent: ?a.TypeRef, comptime defaults: a.Defaults) ir.Function {
    var result: ir.Function = .{ .path = functionPath(f.ref, state), .name = f.options.name, .doc = f.options.doc, .symbol = f.options.symbol, .ext = externalExtensions(f.extensions), .codepoints = defaults.codepoints, .strings = defaults.strings };
    for (f.extensions) |ext| switch (ext.builtin) {
        .iterator => |value| result.iterator = value,
        .implements => |value| result.implements = value,
        else => {},
    };
    const info = f.ref.signature();
    if (info.is_generic or info.is_var_args) @compileError("zigo function requires a concrete non-variadic wrapper: " ++ f.ref.path);
    var receiver: ?a.TypeRef = null;
    switch (f.options.role) {
        .free => result.force_free = true,
        .auto => {
            if (parent) |p| {
                if (firstVisible(info)) |index| {
                    for (state.types) |registered| {
                        if (registered.zigType() != p.type) continue;
                        if (automaticReceiver(info.params[index].type.?, registered) or (registered == .enumeration and info.params[index].type.? == p.type)) receiver = p;
                    }
                }
            }
        },
        .method => |r| receiver = r,
        .constructor => |r| {
            _ = typeName(r.type, state);
            result.constructs = r.type.type;
            receiver = switch (r.receiver) {
                .none => null,
                .member => parent orelse @compileError("zigo member receiver requires an enclosing type: " ++ f.ref.path),
                .type => |ref| ref,
            };
            result.force_free = r.receiver == .none;
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
        if (parent) |p| {
            if (p.type != r.type or !std.mem.eql(u8, p.path, r.path))
                @compileError("zigo receiver differs from the enclosing member type: " ++ f.ref.path);
        }
        _ = typeName(r, state);
        result.receiver = r.type;
    }
    const first = firstVisible(info);
    var receiver_index: ?usize = null;
    if (receiver) |r| {
        if (first == null or !isReceiver(info.params[first.?].type.?, r.type)) @compileError("zigo receiver does not match the first non-injected Zig argument: " ++ f.ref.path);
        receiver_index = first;
    } else if (if (result.force_free) null else first) |index| {
        // Match the reflector's automatic handle and owner-enum receiver inference.
        const T = info.params[index].type.?;
        for (state.types) |t| {
            if (automaticReceiver(T, t)) {
                if (parent) |p| {
                    if (p.type != t.zigType()) @compileError("zigo receiver differs from the enclosing member type: " ++ f.ref.path);
                }
                receiver_index = index;
            }
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
        validateContract(p, info.params[p.index].type.?, f.ref.path);
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
                    .options => |opt| {
                        out.flatten = opt.fields;
                        out.options = opt.options;
                    },
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
fn validateContract(comptime p: a.Param, comptime T: type, comptime path: []const u8) void {
    const info = @typeInfo(T);
    const valid = switch (p.contract) {
        .value => true,
        .buffer => info == .pointer and info.pointer.size == .slice,
        .stream => T == *std.Io.Writer or T == *std.Io.Reader,
        .callback => info == .pointer and @typeInfo(info.pointer.child) == .@"fn",
        .cancel => T == *const std.atomic.Value(u32),
        .flatten => |fields| info == .@"struct" and fields.len != 0,
        .options => |opt| info == .@"struct" and opt.fields.len != 0,
    };
    if (!valid) @compileError("zigo " ++ @tagName(p.contract) ++ " contract does not match Zig argument " ++ std.fmt.comptimePrint("{d}", .{p.index}) ++ ": " ++ path);
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
    const result = comptime binding(.{ .root = Lib, .declarations = &.{a.package(.{ .path = "io", .declarations = &.{api.handle("Document", .{}).with(.{ .members = &.{ doc.func("create", .{}), doc.func("read", .{ .params = &.{.{ .index = 3, .go_name = "dst", .contract = .{ .buffer = .{ .output = .{ .written = .result } } } }} }), doc.func("deinit", .{}) } })} })} });
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
        api.in("Store").func("size", .{}),
        api.func("take", .{ .returns = .{ .lifetime = .{ .owned = .{ .release = api.ref("free") } }, .semantic = .utf8_string } }),
        api.func("free", .{}),
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
        a.package(.{ .path = "text", .defaults = .{ .strings = .explicit }, .declarations = &.{api.func("text", .{})} }),
    } });
    try std.testing.expectEqual(ir.Strings.explicit, result.functions[0].strings.?);
    try std.testing.expectEqual(ir.Codepoints.infer_u21, result.functions[0].codepoints.?);
}

fn externalExtensions(comptime entries: []const ir.Extension) []const ir.Extension {
    var result: []const ir.Extension = &.{};
    for (entries) |e| if (e.builtin == .none) {
        result = result ++ [_]ir.Extension{e};
    };
    return result;
}
fn hasText(comptime entries: []const ir.Extension) bool {
    for (entries) |e| if (e.builtin == .text) return true;
    return false;
}

fn automaticReceiver(comptime T: type, comptime entry: ir.Type) bool {
    if (!entry.isHandle()) return false;
    return switch (@typeInfo(T)) {
        .pointer => |p| p.size == .one and p.child == entry.zigType(),
        .@"struct" => T == entry.zigType(),
        else => false,
    };
}

test "contract helpers and explicit constructor context normalize once" {
    const p = @import("param.zig");
    const r = @import("result.zig");
    const Lib = struct {
        pub const Parent = opaque {};
        pub const Child = opaque {};
        pub fn create(_: *Parent, _: []u8) *Child {
            unreachable;
        }
        pub fn release(_: []u8) void {}
        pub fn take() []u8 {
            unreachable;
        }
    };
    const api = a.scope(Lib);
    const member = comptime binding(.{ .root = Lib, .declarations = &.{
        api.handle("Parent", .{}).members(&.{api.func("create", .{
            .role = .{ .constructor = .{ .type = api.typeRef("Child"), .receiver = .member, .parent = .receiver } },
            .params = &.{p.output(1, .all).named("dst")},
        })}),
        api.handle("Child", .{}),
    } });
    try std.testing.expectEqual(Lib.Parent, member.functions[0].receiver.?);
    try std.testing.expect(member.functions[0].child_of_receiver);
    try std.testing.expectEqual(@as(usize, 1), member.functions[0].params.len);
    try std.testing.expectEqualStrings("dst", member.functions[0].params[0].name.?);
    const static = comptime binding(.{ .root = Lib, .declarations = &.{
        api.handle("Parent", .{}).members(&.{api.func("create", .{
            .role = .{ .constructor = .{ .type = api.typeRef("Child") } },
            .params = &.{.{ .index = 0, .go_name = "parent" }},
        })}),
        api.handle("Child", .{}),
        api.func("take", .{ .returns = r.releasedBy(api.ref("release")) }),
        api.func("release", .{}),
    } });
    try std.testing.expect(static.functions[0].force_free);
    try std.testing.expect(static.functions[0].receiver == null);
    try std.testing.expectEqual(@as(usize, 2), static.functions[0].params.len);
    try std.testing.expectEqualStrings("root.release", static.functions[1].returns.release.?);
    try std.testing.expectEqual(a.Lifetime.inferred, (a.Returns{}).lifetime);
    try std.testing.expect(r.owned().lifetime.owned.release == null);
    try std.testing.expect(r.borrowed().lifetime == .borrowed);
    try std.testing.expect(p.input(0).contract.buffer == .input);
    try std.testing.expect(p.inout(1, .result).contract.buffer == .inout);
    try std.testing.expectEqual(@as(?u32, 1024), p.stream(2, 1024).contract.stream.buffer);
    try std.testing.expectEqual(@as(?usize, 3), p.callback(2, .{ .userdata = 3 }).contract.callback.userdata);
    try std.testing.expectEqualStrings("Canceled", p.cancel(4, "Canceled").contract.cancel.canceled.?);
    try std.testing.expectEqualStrings("x", p.flatten(5, &.{"x"}).contract.flatten[0]);
    try std.testing.expectEqualStrings("x", p.options(5, &.{"x"}, .{}).contract.options.fields[0]);
    try std.testing.expectEqualStrings("Terminal", p.options(5, &.{"x"}, .{ .prefix = "Terminal" }).contract.options.options.prefix.?);
}

fn callbackParams(comptime T: type, comptime options: a.CallbackOptions, comptime path: []const u8) []const ir.CallbackParam {
    const pointer = @typeInfo(T);
    if (pointer != .pointer or @typeInfo(pointer.pointer.child) != .@"fn")
        @compileError("zigo callback requires a function pointer: " ++ path);
    const info = @typeInfo(pointer.pointer.child).@"fn";
    const count = info.params.len;
    if (info.is_generic or info.is_var_args)
        @compileError("zigo callback requires a concrete non-variadic signature: " ++ path);
    const userdata: ?usize = if (options.userdata) |spec| switch (spec) {
        .first => 0,
        .last => if (count == 0) 0 else count - 1,
        .index => |index| index,
    } else if (count != 0 and info.params[count - 1].type == usize) count - 1 else null;
    if (userdata) |index| {
        if (index >= count) @compileError("zigo callback userdata index is outside the Zig signature: " ++ path);
        if (info.params[index].type != usize) @compileError("zigo callback userdata must be usize: " ++ path);
    }
    const layout = ir.callback_layout.describe(info, userdata);
    var params: [layout.go_count - @intFromBool(userdata != null)]ir.CallbackParam = @splat(.{});
    for (options.params, 0..) |param, i| {
        if (param.index >= count) @compileError("zigo callback parameter index is outside the Zig signature: " ++ path);
        for (options.params[0..i]) |previous| {
            if (previous.index == param.index) @compileError("zigo duplicate callback parameter index: " ++ path);
        }
        switch (layout.kinds[param.index]) {
            .userdata => @compileError("zigo cannot annotate callback userdata: " ++ path),
            .pair_length => @compileError("zigo annotate the callback byte pointer, not its length: " ++ path),
            .value, .pair_pointer => params[layout.go_index[param.index]] = .{ .semantic = param.semantic },
        }
    }
    const frozen = params;
    return if (options.params.len == 0) &.{} else &frozen;
}

test "callback hints use sparse native indices for every userdata position" {
    const Lib = struct {
        pub const First = *const fn (usize, u32, [*]const u8, usize) callconv(.c) void;
        pub const Middle = *const fn (u32, usize, [*]const u8, usize) callconv(.c) void;
        pub const Last = *const fn (u32, [*]const u8, usize, usize) callconv(.c) void;
    };
    const api = a.scope(Lib);
    const result = comptime binding(.{ .root = Lib, .declarations = &.{
        api.callback("First", .{ .userdata = .first, .params = &.{
            .{ .index = 2, .semantic = .opaque_bytes }, .{ .index = 1, .semantic = .codepoint },
        }, .on_failure = .{ .result = 0 } }),
        api.callback("Middle", .{ .userdata = .{ .index = 1 }, .params = &.{.{ .index = 2, .semantic = .utf8_string }} }),
        api.callback("Last", .{ .params = &.{.{ .index = 1, .semantic = .opaque_bytes }} }),
    } });
    try std.testing.expectEqual(@as(usize, 2), result.types[0].callback.params.len);
    try std.testing.expectEqual(ir.SemanticHint.codepoint, result.types[0].callback.params[0].semantic.?);
    try std.testing.expectEqual(ir.SemanticHint.opaque_bytes, result.types[0].callback.params[1].semantic.?);
    try std.testing.expect(result.types[1].callback.params[0].semantic == null);
    try std.testing.expectEqual(ir.SemanticHint.utf8_string, result.types[1].callback.params[1].semantic.?);
    try std.testing.expectEqual(ir.SemanticHint.opaque_bytes, result.types[2].callback.params[1].semantic.?);
    try std.testing.expectEqual(@as(i64, 0), result.types[0].callback.on_callback_failure.?.result);
}
