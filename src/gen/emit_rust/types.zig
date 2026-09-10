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

/// How a semantic type this backend cannot render reads in a diagnostic, or
/// null when it can render it.
///
/// A whitelist, deliberately. The ABI-level checks below cannot see everything:
/// with the cgo callback convention a callback parameter is not an ABI
/// parameter at all -- only its `userdata` token crosses -- so every callback
/// case reached `type_spelling.semanticScalar` and hit its `unreachable`.
/// Naming the kinds this backend *does* render means a shape it has never seen
/// is refused rather than crashing.
pub fn unsupportedNode(node: semantic.TypeNode) ?[]const u8 {
    return switch (node) {
        .int, .float, .bool, .void, .slice, .opaque_ptr => null,
        // Refused with their own messages elsewhere, so they are not named
        // here: naming them twice would let the two descriptions drift.
        .@"enum", .optional, .error_union, .value_struct, .materialized => null,
        .callback => "a callback parameter",
        .io_stream => "a std.Io stream parameter",
        .cancel_flag => "a cancellable call",
        .atomic_ptr => "a shared atomic parameter",
    };
}

/// The registered opaque type `name` names, or null when it is not one this
/// backend owns through `Drop`.
///
/// A tagged union is also lowered into `program.handles` -- C only ever holds
/// a pointer to one -- but it is not a handle in the sense this backend means,
/// so it is excluded here and refused with the tagged-union message instead.
pub fn handleFor(program: abi.Program, name: []const u8) ?abi.AbiOpaque {
    for (program.handles) |handle| {
        if (!std.mem.eql(u8, handle.name, name)) continue;
        const declaration = semantic.typeDecl(program.types, name) orelse return null;
        return if (declaration.kind == .@"opaque") handle else null;
    }
    return null;
}

/// The handle `name` names, when this backend can actually own one.
///
/// Owning means `Drop`, and `Drop` means a destructor to call, so a registered
/// opaque with no constructor-and-destructor pair is not a handle this backend
/// can emit -- `plugin_disabled` registers exactly that, a `Counter` nothing is
/// bound to, and rendering it crashed on the missing destructor.
///
/// Skipping such a type is not a silent omission: no function can mention it
/// without being refused, because the parameter and receiver rules both ask
/// for the constructor. It is `placementOf` that must keep using the plain
/// `handleFor`, so that a method on an unowned type is refused as a method
/// rather than misreported as a namespaced free function.
pub fn ownedHandleFor(program: abi.Program, name: []const u8) ?abi.AbiOpaque {
    const handle = handleFor(program, name) orelse return null;
    const constructor = handle.lifecycle.constructor orelse return null;
    for (program.functions) |function| {
        const origin = function.origin.*;
        if (!std.mem.eql(u8, origin.receiver orelse "", name)) continue;
        if (std.mem.eql(u8, constructor.deinit, origin.name)) return handle;
    }
    return null;
}

/// How this backend holds a handle.
pub const HandleKind = enum {
    /// A constructor made it and `Drop` releases it.
    owned,
    /// A pointer into an object another handle owns. No `Drop`, and a lifetime
    /// parameter tying it to the borrow it came from.
    ///
    /// This is where Rust says something Go cannot. Go's binding hands back a
    /// wrapper with a doc comment -- "remains valid only while its parent
    /// handle remains open" -- and a run-time parent refcount to catch the
    /// mistake after it is made. Rust makes outliving the owner a compile
    /// error, and the phase's compile-fail check is what proves it.
    borrowed,
};

pub const RenderableHandle = struct { record: abi.AbiOpaque, kind: HandleKind };

/// The handle `name` names and how this backend holds one, or null when it
/// cannot hold one at all.
pub fn renderableHandle(program: abi.Program, name: []const u8) ?RenderableHandle {
    const record = handleFor(program, name) orelse return null;
    if (ownedHandleFor(program, name) != null) return .{ .record = record, .kind = .owned };
    // Only a type something actually borrows out is a view. A registered
    // opaque nothing is bound to -- `plugin_disabled` has one -- is neither,
    // and skipping it is safe because no function can mention it without
    // being refused.
    for (program.functions) |function| {
        if (function.ownership != .borrowed_view) continue;
        if (std.mem.eql(u8, function.ownership.borrowed_view.type_name, name))
            return .{ .record = record, .kind = .borrowed };
    }
    return null;
}

/// Where one function's public surface goes.
///
/// One definition, because three emitters read it: `lib.rs` writes the free
/// functions, `handle.rs` writes the constructors and the methods, and the
/// destructor is written by neither -- it belongs to `Drop`. If they disagreed
/// about one function, it would be emitted twice or not at all.
pub const Placement = union(enum) {
    free_function,
    /// An associated function on the named handle type.
    constructor: []const u8,
    /// A method on the named handle type.
    method: []const u8,
    /// Consumed by the handle's `Drop`, so it has no public surface of its
    /// own. This is the whole of Rust's advantage here: Go has to publish
    /// `Close()` and then guard every method against having been called after
    /// it.
    destructor: []const u8,
    /// Consumed by `OwnedSlice`'s `Drop`, for the same reason: publishing it
    /// beside a buffer that already frees itself would be a double free
    /// waiting to be written.
    release,
};

pub fn placementOf(program: abi.Program, function: abi.AbiFn) Placement {
    const origin = function.origin.*;
    if (origin.receiver) |receiver| {
        const handle = handleFor(program, receiver) orelse return .free_function;
        if (handle.lifecycle.constructor) |constructor| {
            if (std.mem.eql(u8, constructor.deinit, origin.name)) return .{ .destructor = receiver };
        }
        return .{ .method = receiver };
    }
    if (semantic.constructorForInit(program.constructors, origin)) |constructor| {
        if (handleFor(program, constructor.type) != null) return .{ .constructor = constructor.type };
    }
    if (@import("buffers.zig").isRelease(program, function)) return .release;
    return .free_function;
}

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
        // The handle a method is called on. It is not in `origin.params`, so
        // it never reaches the parameter walk below and is judged by the
        // receiver rules instead.
        .receiver => true,
        else => false,
    };
}

/// Whether the minimal Rust backend can render `function`, and what stands in
/// the way when it cannot. The order of the checks is the order a reader would
/// ask the questions in, so the first refusal is the most specific one.
/// How an unsupported parameter role reads in a diagnostic.
///
/// `@tagName` was reaching the user, so a binding with a flattened struct
/// parameter was told "it has flattened_field" -- an internal enum name for a
/// concept the message never explained. A diagnostic names the feature the
/// user wrote, not the field the generator stores it in.
fn roleDescription(role: abi.AbiParam.Role) []const u8 {
    return switch (role) {
        .flattened_field => "a struct parameter whose fields are passed individually",
        .struct_in, .struct_out => "an extern struct parameter",
        .optional_in => "an optional parameter",
        .payload_has_out => "an optional error-union payload",
        .slice_written => "a slice the callee writes into",
        .string_lengths, .string_count => "a slice-of-strings parameter",
        .union_tag, .union_payload => "a tagged union passed by value",
        .cancel_flag => "a cancellable call",
        .atomic_ptr => "a shared atomic parameter",
        .stream_callback, .stream_data, .stream_data_length, .stream_userdata => "a std.Io stream parameter",
        // Every remaining role is one this backend renders, so reaching here
        // means `supportedRole` and this table disagree.
        else => "an unsupported parameter",
    };
}

/// Whether `node` reaches a registered enum, at any depth this backend can
/// otherwise render.
///
/// `type_spelling.semanticScalar` happily maps an enum to its tag integer,
/// which is how a `EraseDisplay` parameter was arriving in Rust as a bare
/// `u8`: correct at the ABI, and useless to a caller who has no way to learn
/// that `0` means `below`. Go emits a named type with constants. Until Rust
/// does too, a boundary enum is refused rather than silently flattened.
fn reachesEnum(node: semantic.TypeNode) bool {
    return switch (node) {
        .@"enum" => true,
        .slice => |slice| reachesEnum(slice.element.*),
        .optional => |optional| reachesEnum(optional.child.*),
        .error_union => |union_type| reachesEnum(union_type.payload.*),
        else => false,
    };
}

pub fn unsupported(program: abi.Program, function: abi.AbiFn) ?Unsupported {
    const origin = function.origin.*;
    // A document with sub-packages would have every package's functions
    // flattened into one crate root, silently merging namespaces the binding
    // deliberately separated -- and two same-named functions from different
    // packages would collide into one `pub fn`.
    if (program.packages != null) return .{
        .what = "sub-packages in the binding",
        .hint = "the Rust backend emits one crate root; a crate per package is not designed yet",
    };
    const placement = placementOf(program, function);
    // A free function declared inside a Zig container: `unicode.codepointWidth`
    // has nowhere to go in a flat crate root, so its namespace would be
    // dropped and `a.parse` and `b.parse` would collide. A method and a
    // constructor also carry a namespace -- the type they belong to -- and
    // land in an `impl` block, which is exactly the module a free function
    // lacks.
    if (placement == .free_function and origin.namespace != null) return .{
        .what = "a namespaced free function",
        .hint = "the Rust backend has no module for a Zig namespace yet; the name would be flattened",
    };
    if (origin.receiver) |receiver| {
        if ((origin.receiver_kind orelse .handle) != .handle) return .{
            .what = "a method on a value receiver",
            .hint = "a registered enum owning methods needs the Rust enum mapping first",
        };
        const handle = handleFor(program, receiver) orelse return .{
            .what = "a method on a type that is not a plain opaque handle",
            .hint = "a tagged-union receiver needs the Rust enum mapping first",
        };
        if (renderableHandle(program, receiver) == null) return .{
            .what = "a method on a handle with no bound constructor and destructor pair",
            .hint = "Rust owns a handle through Drop, so it needs both halves bound -- unless the handle is only ever borrowed out of another one",
        };
        if (handle.lifecycle.dependent_parent != null or handle.lifecycle.has_dependent_children) return .{
            .what = "a handle in a parent-child lifetime relation",
            .hint = "a child that must close before its parent needs a lifetime parameter on the child; not designed yet",
        };
        if (handle.retained_callback_slots != 0) return .{
            .what = "a handle that stores retained callbacks",
            .hint = "callbacks are not in the Rust backend, so a handle has none to store",
        };
    }
    switch (function.ownership) {
        .handle => |record| {
            if (record.boxed) return .{
                .what = "a boxed constructor pair",
                .hint = "a create/destroy pair over a boxed value has its own ownership shape; not designed yet",
            };
            if (record.child_of_receiver) return .{
                .what = "a handle that must close before the receiver it came from",
                .hint = "that ordering needs a lifetime parameter on the child; not designed yet",
            };
            if (record.retained_slots != 0) return .{
                .what = "a handle that stores retained callbacks",
                .hint = "callbacks are not in the Rust backend, so a handle has none to store",
            };
            if (record.destructor == null) return .{
                .what = "a constructed handle with no destructor",
                .hint = "Rust frees a handle in Drop, so it needs a destructor to call",
            };
            if (placement != .constructor) return .{
                .what = "a handle returned by something other than its constructor",
                .hint = "the Rust backend constructs a handle only through the constructor the binding paired with it",
            };
        },
        .borrowed_view => |record| {
            if (renderableHandle(program, record.type_name) == null) return .{
                .what = "a borrowed view of a type this backend cannot hold",
                .hint = "a view is a lifetime-bound wrapper, so its type must be a plain opaque handle",
            };
            // A view's lifetime is the receiver's borrow, so a free function
            // returning one has nothing to tie it to.
            if (placement != .method) return .{
                .what = "a borrowed view returned by something other than a method",
                .hint = "a view borrows from its receiver, so only a method can return one",
            };
        },
        else => {},
    }
    if (reachesEnum(origin.@"return")) return .{
        .what = "a registered enum result",
        .hint = "a Rust enum with the tag's repr is not designed yet; the value would arrive as a bare integer",
    };
    for (origin.params) |parameter| if (reachesEnum(parameter.type)) return .{
        .what = "a registered enum parameter",
        .hint = "a Rust enum with the tag's repr is not designed yet; the value would arrive as a bare integer",
    };
    if (origin.cancel != null) return .{
        .what = "a cancellable call",
        .hint = "cancellation has no Rust counterpart yet; drop `.cancel` or generate this binding for Go",
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
    if (function.ownership.asBuffer()) |buffer| {
        if (buffer.release_receiver_c_name != null) return .{
            .what = "a caller-owned buffer whose release function is a method",
            .hint = "the owning slice would have to hold the receiver too, and then outlive it; not designed yet",
        };
        if (buffer.materialized != null) return .{
            .what = "a materialized result tree",
            .hint = "Rust would carry this as a borrowed slice or a Drop wrapper; not designed yet",
        };
        if (buffer.narrow) return .{
            .what = "a caller-owned buffer of narrow integers",
            .hint = "the shim rewrites the buffer in place for these; not designed yet",
        };
        // `ret_string` is the function's own record of how the result carries
        // text; a caller-owned C string crosses as one NUL-terminated pointer
        // rather than as the pointer-and-length pair an owning slice needs.
        if (function.ret_string == .c_string) return .{
            .what = "a caller-owned C string",
            .hint = "the Rust backend owns a slice, not a NUL-terminated buffer; not designed yet",
        };
    }
    if (function.ret_string == .string_slice) return .{
        .what = "a slice-of-strings result",
        .hint = "the minimal Rust backend supports one scalar or one byte slice",
    };
    for (function.params) |parameter| if (!supportedRole(parameter.role)) return .{
        .what = roleDescription(parameter.role),
        .hint = "the Rust backend supports scalar, slice and handle parameters only",
    };
    for (function.params) |parameter| switch (parameter.scalar) {
        .callback, .snapshot, .value_struct => return .{
            .what = "a callback or struct parameter",
            .hint = "the Rust backend supports scalar, slice and handle parameters only",
        },
        // A handle parameter is accepted, but only for a type this backend
        // actually owns: without a constructor and destructor pair there is no
        // wrapper to take a reference to.
        .@"opaque" => |record| if (handleFor(program, record.name) == null) {
            return .{
                .what = "a tagged-union parameter",
                .hint = "a tagged union needs the Rust enum mapping first",
            };
        } else if (renderableHandle(program, record.name) == null) return .{
            .what = "a handle parameter whose type has no bound constructor and destructor pair",
            .hint = "Rust owns a handle through Drop, so it needs both halves bound",
        },
        .pointer => |pointer| if (pointer.is_c_string or pointer.is_optional) return .{
            .what = "a C-string or nullable pointer parameter",
            .hint = "the minimal Rust backend supports plain `[]const T` slices",
        },
        else => {},
    };
    // Before anything that spells a type: a kind this backend has no spelling
    // for must not reach the emitter, which would answer with `unreachable`.
    if (unsupportedNode(origin.@"return".errorPayload())) |what| return .{
        .what = what,
        .hint = "the Rust backend supports scalar, slice and handle results only",
    };
    for (origin.params) |parameter| if (unsupportedNode(parameter.type)) |what| return .{
        .what = what,
        .hint = "the Rust backend supports scalar, slice and handle parameters only",
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
            .hint = "the Rust backend returns results rather than writing them",
        };
        if (parameter.type == .opaque_ptr and parameter.type.opaque_ptr.nullable) return .{
            .what = "a nullable handle parameter",
            .hint = "the Rust backend takes a reference, which cannot be null; an Option<&T> form is not designed yet",
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

/// The Rust name of one handle's opaque C type, as the raw module declares it.
///
/// The C typedef is incomplete -- `typedef struct zg_context zg_context;` --
/// so Rust must not pretend to know the layout. A zero-length private field is
/// the stable way to say "an address I never dereference"; `extern type`, which
/// would say it directly, is still unstable.
pub fn opaqueDeclaration(writer: *std.Io.Writer, handle: abi.AbiOpaque) !void {
    try writer.print(
        \\
        \\/// The native `{0s}`. Incomplete on purpose: the Rust side only ever
        \\/// holds its address.
        \\#[repr(C)]
        \\pub struct {1s} {{
        \\    _private: [u8; 0],
        \\}}
        \\
    , .{ handle.name, handle.c_name });
}

/// The Rust spelling of one C ABI scalar, as an `extern "C"` signature needs
/// it. `size_t` is `usize` and `ptrdiff_t` is `isize` because Rust guarantees
/// both match the platform's pointer width, which is what the C typedefs mean.
/// A C `_Bool` never appears: lowering carries every Zig `bool` as `uint8_t`,
/// so the raw layer sees `u8` and only the public layer knows it is a `bool`.
pub fn rawScalar(value: abi.AbiScalar) ?[]const u8 {
    return switch (value) {
        .void => "()",
        // The incomplete struct `opaqueDeclaration` writes. A handle only ever
        // crosses behind a pointer, so this is always the pointee.
        .@"opaque" => |record| record.c_name,
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

/// One C ABI scalar as an `extern "C"` signature spells it, pointers included.
///
/// `rawScalar` answers the flat cases as a single word; a pointer needs two, so
/// it is written rather than returned. Recursive because a slice return crosses
/// as a pointer to a pointer.
pub fn writeRawScalar(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .pointer => |pointer| {
            try writer.print("*{s} ", .{if (pointer.is_const) "const" else "mut"});
            try writeRawScalar(writer, pointer.child.*);
        },
        else => try writer.writeAll(rawScalar(value) orelse return error.UnsupportedType),
    }
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
