const std = @import("std");
const zigo = @import("zigo");
const ctx = @import("context");

fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();
        pub fn create() *Self {
            unreachable;
        }
        pub fn push(_: *Self, _: T) void {}
        pub fn len(_: *const Self) usize {
            return 0;
        }
        pub fn deinit(_: *Self) void {}
    };
}
const Lib = struct {
    pub const FloatBuffer = Buffer(f32);
    pub const IntBuffer = Buffer(i32);
    pub const Document = opaque {
        pub fn read(_: *@This(), _: std.mem.Allocator, _: []u8) usize {
            return 0;
        }
        pub fn newStream(_: *@This()) *Stream {
            unreachable;
        }
    };
    pub const Stream = opaque {};
    pub const Point = extern struct { x: i32 };
    pub const Probe = struct { text: []const u8 };
    pub const Mode = enum {
        a,
        b,
        pub fn number(_: @This()) u32 {
            return 0;
        }
    };
    pub const Value = union(enum) { number: u32 };
    pub const nested = struct {
        pub const Alias = Buffer(u16);
    };
    pub fn newStream(_: *Document) *Stream {
        unreachable;
    }
    pub fn freeStream(_: *Stream) void {}
    pub fn streamLen(_: *const Stream) u32 {
        return 0;
    }
    pub fn release(_: []u8) void {}
    pub fn take() []u8 {
        unreachable;
    }
};
const api = zigo.scope(Lib);

test "generic context Self, target and alias identity stay distinct" {
    const Float = ctx.context(api.handle("FloatBuffer", .{}));
    const Int = ctx.context(api.handle("IntBuffer", .{}));
    const Alias = ctx.context(api.in("nested").handle("Alias", .{}));
    try std.testing.expect(Float.contextType() == Float);
    try std.testing.expect(Float != Int);
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Float));
    try std.testing.expect(Float != Float.Target);
    try std.testing.expect(Float.Target == Lib.FloatBuffer);
    try std.testing.expectEqualStrings("root.nested.Alias", Alias.typeRef().path);
    try std.testing.expectEqualStrings("root.nested.Alias.push", Alias.ref("push").path);
    const names: zigo.Selector = .{ .names = &.{ "create", "push", "len", "deinit" } };
    const actual = comptime zigo.define(.{ .root = Lib, .declarations = &.{ Float.select(names), Int.select(names) } });
    const expected = comptime zigo.define(.{ .root = Lib, .declarations = &.{
        api.handle("FloatBuffer", .{}).members(api.in("FloatBuffer").functions(names)),
        api.handle("IntBuffer", .{}).members(api.in("IntBuffer").functions(names)),
    } });
    comptime try std.testing.expectEqualDeep(expected, actual);
}

test "root functions, contextual child constructors and packages preserve normal form" {
    const Doc = ctx.context(api.handle("Document", .{}).named("TextDocument"));
    const Stream = ctx.context(api.handle("Stream", .{}));
    const actual = comptime zigo.define(.{ .root = Lib, .declarations = &.{
        zigo.package(.{ .path = "io", .declarations = &.{
            Doc.define(&.{
                Doc.function("read", .{ .params = &.{zigo.param.output(2, .result)} }),
                Doc.function("newStream", .{ .role = .{ .constructor = .{
                    .type = Stream.typeRef(),
                    .receiver = .member,
                    .parent = .receiver,
                } } }),
            }),
            Stream.define(&.{
                api.function("freeStream", .{ .role = .{ .destructor = Stream.typeRef() } }),
                api.function("streamLen", .{}).named("len"),
            }),
        } }),
    } });
    try std.testing.expectEqualStrings("TextDocument.read", actual.functions[0].path);
    try std.testing.expect(actual.functions[0].receiver.? == Lib.Document);
    try std.testing.expectEqual(@as(usize, 1), actual.functions[0].params.len);
    try std.testing.expect(actual.functions[1].constructs.? == Lib.Stream);
    try std.testing.expect(actual.functions[1].child_of_receiver);
    try std.testing.expect(actual.functions[2].destroys.? == Lib.Stream);
    try std.testing.expect(actual.functions[3].receiver.? == Lib.Stream);
    try std.testing.expectEqualStrings("io", actual.packages[0].path);
    try std.testing.expectEqualStrings("root.Document", Doc.typeRef().path);
}

test "decorations before context and after define share existing replacement rules" {
    const Plugin = .{
        .name = "RESEARCH",
        .FunctionOptions = struct {},
        .TypeOptions = struct { label: ?[]const u8 = "default" },
        .targets = [_]enum { value }{.value},
    };
    const Point = ctx.context(api.value("Point", .{}).named("Position").use(Plugin, .{ .label = "point" }));
    const old_members = &[_]zigo.Entry{api.function("take", .{})};
    const again = ctx.context(Point.define(old_members));
    const cleared = again.define(&.{}).named(null).replacePlugin(Plugin, .{ .label = null });
    try std.testing.expectEqual(@as(usize, 0), cleared.type.options.members.len);
    try std.testing.expect(cleared.type.options.name == null);
    try std.testing.expectEqual(@as(usize, 1), cleared.type.extensions.len);
    try std.testing.expectEqualStrings("root.Point", cleared.type.ref.path);
    comptime try std.testing.expectEqualDeep(
        api.value("Point", .{}).named(null).use(Plugin, .{ .label = null }),
        cleared,
    );
}

test "context is representation-independent for member-bearing declarations" {
    const Mode = ctx.context(api.enumeration("Mode", .{}).use(zigo.features.text, .{}));
    const Value = ctx.context(api.taggedUnion("Value", .{ .access = .snapshot }));
    const Probe = ctx.context(api.materialized("Probe", .{}));
    const actual = comptime zigo.define(.{ .root = Lib, .declarations = &.{
        Mode.select(.{ .names = &.{"number"} }), Value.define(&.{}), Probe.define(&.{}),
    } });
    try std.testing.expect(actual.types[0].enumeration.text);
    try std.testing.expect(actual.types[1].tagged_union.access == .snapshot);
    try std.testing.expect(actual.types[2] == .materialized);
    try std.testing.expect(actual.functions[0].receiver.? == Lib.Mode);
}

test "factory parameter receives context but lexical This still refers to the factory" {
    const Float = ctx.context(api.handle("FloatBuffer", .{}));
    const Factory = struct {
        const Self = @This();
        pub fn members(comptime BindingContext: type) []const zigo.Entry {
            if (Self == BindingContext) @compileError("unexpected dynamic This");
            return &.{ BindingContext.function("create", .{}), BindingContext.function("deinit", .{}) };
        }
    };
    comptime try std.testing.expectEqualDeep(
        Float.select(.{ .names = &.{ "create", "deinit" } }),
        Float.build(Factory.members),
    );
}

test "context role remains explicit for a static constructor taking another handle" {
    const Doc = ctx.context(api.handle("Document", .{}));
    const Stream = ctx.context(api.handle("Stream", .{}));
    const actual = comptime zigo.define(.{ .root = Lib, .declarations = &.{
        Doc.define(&.{}),
        Stream.define(&.{
            api.function("newStream", .{ .role = .{ .constructor = .{ .type = Stream.typeRef(), .receiver = .none } } }),
            api.function("freeStream", .{ .role = .{ .destructor = Stream.typeRef() } }),
        }),
    } });
    try std.testing.expect(actual.functions[0].force_free);
    try std.testing.expect(actual.functions[0].receiver == null);
}

test "four real example rewrites produce exactly the existing normalized bindings" {
    @setEvalBranchQuota(4000000);
    comptime try std.testing.expectEqualDeep(@import("before_callback").bindings, @import("after_callback").bindings);
    comptime try std.testing.expectEqualDeep(@import("before_queue").bindings, @import("after_queue").bindings);
    comptime try std.testing.expectEqualDeep(@import("before_streams").bindings, @import("after_streams").bindings);
    comptime try std.testing.expectEqualDeep(@import("before_materialized").bindings, @import("after_materialized").bindings);
}
