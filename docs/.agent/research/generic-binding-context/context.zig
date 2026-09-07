//! Research prototype, not a public zigo API.
const std = @import("std");
const zigo = @import("zigo");

/// Production Entry.context() could use the existing private Scope directly.
/// This bridge reuses public scope resolution without changing production code.
fn sourceScope(comptime reference: zigo.TypeRef) type {
    comptime {
        var pieces = std.mem.splitScalar(u8, reference.path, '.');
        if (!std.mem.eql(u8, pieces.next().?, "root"))
            @compileError("research context requires a root-relative reference");
        var Source = zigo.scope(reference.root);
        while (pieces.next()) |piece| Source = Source.in(piece);
        return Source;
    }
}

pub fn context(comptime entry: zigo.Entry) type {
    if (entry != .type) @compileError("research context requires a type entry");
    if (entry.type.representation == .callback)
        @compileError("research callback entries have no member context");
    return struct {
        const Self = @This();
        pub const Target = entry.type.ref.type;
        pub const source = sourceScope(entry.type.ref);
        pub const function = source.function;
        pub const functions = source.functions;
        pub const ref = source.ref;

        pub fn typeRef() zigo.TypeRef {
            return entry.typeRef();
        }
        pub fn define(comptime members: []const zigo.Entry) zigo.Entry {
            return entry.members(members);
        }
        pub fn select(comptime selector: zigo.Selector) zigo.Entry {
            return Self.define(Self.functions(selector));
        }
        /// A compared alternative: supply the generated context to a factory.
        pub fn build(comptime factory: anytype) zigo.Entry {
            return Self.define(factory(Self));
        }
        /// Probe-only: demonstrates the lexical Self identity.
        pub fn contextType() type {
            return Self;
        }
    };
}
