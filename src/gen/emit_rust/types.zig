//! How the C ABI's scalars and parameter roles are spelled in Rust, and which
//! shapes this backend supports at all.
//!
//! The minimal backend covers scalars, `[]const T` slice parameters and
//! error-union returns. Everything else -- callbacks, streams, handles,
//! tagged unions, materialized trees, cancellation -- is out of scope, and
//! `unsupported` says so by name rather than by producing a signature that
//! compiles and lies.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const diagnostic = @import("diagnostic");

/// The shapes this backend refuses, each mapped to the feature that would
/// have to be designed to accept it. Reported as a diagnostic naming the
/// function, so a user pointing `--target rust` at a binding it cannot render
/// learns which declaration to remove rather than reading broken Rust.
pub const Unsupported = struct {
    what: []const u8,
    hint: []const u8,
};

/// The parameter roles the raw and public layers know how to render. Anything
/// outside this set makes the whole function unsupported.
fn supportedRole(role: abi.AbiParam.Role) bool {
    return switch (role) {
        .value, .slice_pointer, .slice_length, .string_data, .string_data_length => true,
        .payload_out, .return_slice_pointer, .return_slice_length => true,
        else => false,
    };
}

/// Whether the minimal Rust backend can render `function`, and what stands in
/// the way when it cannot. The order of the checks is the order a reader would
/// ask the questions in, so the first refusal is the most specific one.
pub fn unsupported(program: abi.Program, function: abi.AbiFn) ?Unsupported {
    const origin = function.origin.*;
    if (origin.cancel != null) return .{
        .what = "a cancellable call",
        .hint = "cancellation has no Rust counterpart yet; drop `.cancel` or generate this binding for Go",
    };
    if (origin.receiver != null) return .{
        .what = "a method on a handle or value receiver",
        .hint = "the minimal Rust backend binds free functions only",
    };
    if (function.ret_struct != null or function.payload_struct != null) return .{
        .what = "an extern struct result",
        .hint = "the minimal Rust backend supports scalar and slice results only",
    };
    if (function.materialized_return != null or function.materialized_out != null) return .{
        .what = "a materialized result tree",
        .hint = "Rust would carry this as a borrowed slice or a Drop wrapper; not designed yet",
    };
    if (function.ret_optional or origin.@"return" == .optional) return .{
        .what = "an optional result",
        .hint = "the minimal Rust backend supports scalar, slice and error-union results only",
    };
    if (function.ownership == .handle or function.ownership == .borrowed_view) return .{
        .what = "a handle result",
        .hint = "an opaque handle would map to a Drop wrapper; not designed yet",
    };
    if (function.ownership == .buffer) return .{
        .what = "a caller-owned buffer result",
        .hint = "a released slice result is not in the minimal Rust backend",
    };
    if (function.ret_string == .string_slice) return .{
        .what = "a slice-of-strings result",
        .hint = "the minimal Rust backend supports one scalar or one byte slice",
    };
    for (function.params) |parameter| if (!supportedRole(parameter.role)) return .{
        .what = @tagName(parameter.role),
        .hint = "the minimal Rust backend supports scalar and slice parameters only",
    };
    for (function.params) |parameter| switch (parameter.scalar) {
        .callback, .@"opaque", .snapshot, .value_struct => return .{
            .what = "a callback, handle or struct parameter",
            .hint = "the minimal Rust backend supports scalar and slice parameters only",
        },
        .pointer => |pointer| if (pointer.is_c_string or pointer.is_optional) return .{
            .what = "a C-string or nullable pointer parameter",
            .hint = "the minimal Rust backend supports plain `[]const T` slices",
        },
        else => {},
    };
    for (origin.params) |parameter| {
        if (parameter.type == .optional) return .{
            .what = "an optional parameter",
            .hint = "the minimal Rust backend supports non-optional scalars and slices",
        };
        if (parameter.type == .slice and parameter.type.slice.sentinel != null) return .{
            .what = "a sentinel-terminated slice parameter",
            .hint = "the minimal Rust backend supports plain `[]const T` slices",
        };
        if (parameter.direction == .out) return .{
            .what = "an out parameter",
            .hint = "the minimal Rust backend returns results rather than writing them",
        };
    }
    if (program.projections.len != 0 or program.snapshots.len != 0) return .{
        .what = "a tagged union in the binding",
        .hint = "Rust would map a tagged union to an enum; not designed yet",
    };
    return null;
}

pub fn unsupportedDiagnostic(
    allocator: std.mem.Allocator,
    function: abi.AbiFn,
    reason: Unsupported,
) !diagnostic.Diagnostic {
    return .{
        .severity = .@"error",
        .code = "ZIGO060",
        .message = try std.fmt.allocPrint(
            allocator,
            "the Rust target cannot bind `{s}`: it has {s}",
            .{ function.origin.name, reason.what },
        ),
        // No path: the declaration came from the semantic document, which is
        // what the renderer names when a diagnostic carries no source line.
        .site = .{ .path = "semantic.json", .declaration = function.origin.name },
        .hint = reason.hint,
    };
}

/// The Rust spelling of one C ABI scalar, as an `extern "C"` signature needs
/// it. `size_t` is `usize` and `ptrdiff_t` is `isize` because Rust guarantees
/// both match the platform's pointer width, which is what the C typedefs mean.
/// A C `_Bool` never appears: lowering carries every Zig `bool` as `uint8_t`,
/// so the raw layer sees `u8` and only the public layer knows it is a `bool`.
pub fn rawScalar(value: abi.AbiScalar) ?[]const u8 {
    return switch (value) {
        .void => "()",
        .bool_u8 => "u8",
        .usize => "usize",
        .isize => "isize",
        .signed_int => |bits| switch (bits) {
            8 => "i8",
            16 => "i16",
            32 => "i32",
            64 => "i64",
            else => null,
        },
        .unsigned_int => |bits| switch (bits) {
            8 => "u8",
            16 => "u16",
            32 => "u32",
            64 => "u64",
            else => null,
        },
        .float => |bits| switch (bits) {
            32 => "f32",
            64 => "f64",
            else => null,
        },
        else => null,
    };
}

/// The Rust spelling of a value as the public API presents it. The one place
/// this differs from `rawScalar` is `bool`, which crosses the C ABI as a byte.
pub fn publicScalar(node: semantic.TypeNode, value: abi.AbiScalar) ?[]const u8 {
    if (node == .bool) return "bool";
    return rawScalar(value);
}

/// The element of a slice parameter or result, and whether it is text.
pub const Element = struct {
    /// The Rust spelling of one element as the C ABI carries it.
    raw: []const u8,
    /// The public spelling: `&str` for a UTF-8 byte slice, `&[T]` otherwise.
    text: bool,
};

pub fn sliceElement(node: semantic.TypeNode, role: abi.AbiFn.StringRole) ?Element {
    const element = node.slice.element.*;
    const scalar = elementScalar(element) orelse return null;
    return .{ .raw = rawScalar(scalar) orelse return null, .text = role == .utf8_slice };
}

fn elementScalar(node: semantic.TypeNode) ?abi.AbiScalar {
    return switch (node) {
        .int => |value| if (value.is_usize)
            (if (value.signed) abi.AbiScalar.isize else abi.AbiScalar.usize)
        else if (value.signed)
            .{ .signed_int = abi.promotedIntBits(value.bits) }
        else
            .{ .unsigned_int = abi.promotedIntBits(value.bits) },
        .float => |value| .{ .float = value.bits },
        else => null,
    };
}

test "every scalar the minimal backend accepts has a Rust spelling" {
    const cases = [_]struct { scalar: abi.AbiScalar, rust: []const u8 }{
        .{ .scalar = .void, .rust = "()" },
        .{ .scalar = .bool_u8, .rust = "u8" },
        .{ .scalar = .usize, .rust = "usize" },
        .{ .scalar = .isize, .rust = "isize" },
        .{ .scalar = .{ .signed_int = 32 }, .rust = "i32" },
        .{ .scalar = .{ .unsigned_int = 64 }, .rust = "u64" },
        .{ .scalar = .{ .float = 64 }, .rust = "f64" },
    };
    for (cases) |case| try std.testing.expectEqualStrings(case.rust, rawScalar(case.scalar).?);
    // A shape with no Rust spelling answers null rather than guessing, so the
    // caller reports it instead of emitting a signature that does not compile.
    const void_scalar: abi.AbiScalar = .void;
    try std.testing.expect(rawScalar(.{ .callback = .{ .params = &.{}, .ret = &void_scalar } }) == null);
}

test "bool is the one value the public layer spells differently from the raw layer" {
    try std.testing.expectEqualStrings("bool", publicScalar(.{ .bool = {} }, .bool_u8).?);
    try std.testing.expectEqualStrings("u8", rawScalar(.bool_u8).?);
    // Every other scalar is the same word on both sides.
    try std.testing.expectEqualStrings("i32", publicScalar(
        .{ .int = .{ .bits = 32, .signed = true, .is_usize = false } },
        .{ .signed_int = 32 },
    ).?);
}
