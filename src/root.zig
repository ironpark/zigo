//! Declaration DSL imported by a user's `bindings.zig`.
//!
/// Preserve a binding declaration as comptime data for the reflector.
pub fn define(comptime declaration: anytype) @TypeOf(declaration) {
    return declaration;
}

test "define preserves the declaration tuple" {
    const add = struct {
        fn call(a: i32, b: i32) i32 {
            return a + b;
        }
    }.call;
    const declaration = define(.{ .functions = .{.{ .name = "add", .@"fn" = add }} });
    try @import("std").testing.expectEqual(@as(usize, 1), declaration.functions.len);
}
