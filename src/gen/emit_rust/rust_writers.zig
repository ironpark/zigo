//! The crate's answers to `plugin.RustWriters`: the four spellings a Rust
//! hook cannot derive on its own.
//!
//! The counterpart of `emit/public_writers.zig`, and deliberately a quarter
//! its size. Go's plugin surface has to answer for package qualification,
//! adapter conversions and the `(T, error)` result shape; a Rust hook asks
//! for a type name, the signature of the item it is being written beside, the
//! receiver clause that item takes, and a name in one of Rust's three casings.
const std = @import("std");
const abi = @import("abi");
const plugin = @import("plugin");
const rust = @import("targets").rust;
const buffers = @import("buffers.zig");
const public = @import("public.zig");
const raw = @import("raw.zig");
const types = @import("types.zig");

pub const writers: plugin.RustWriters = .{
    .writeTypeName = writeTypeName,
    .writeSignature = writeSignature,
    .receiverFormAlloc = receiverFormAlloc,
    .identifierAlloc = plugin.rustbuild.identifierAlloc,
    .functionInfo = functionInfo,
};

/// A registered type as the crate spells it, qualified from the crate root.
///
/// `crate::Name` rather than the bare name, because a plugin item can land in
/// `lib.rs`, in `handle.rs`, in `zigo_plugins.rs` or in a module of the
/// plugin's own, and only the crate-rooted path reads the same in all four.
/// It is also what the generated enum conversions already use.
fn writeTypeName(context: plugin.RustContext, writer: *std.Io.Writer, name: []const u8) anyerror!void {
    const converted = try rust.typeNameAlloc(context.allocator, name);
    defer context.allocator.free(converted);
    return writer.print("crate::{s}", .{converted});
}

/// The public signature of a bound function, parentheses included, exactly as
/// the generated item spells it -- receiver, parameters and `-> Result<..>`
/// alike -- so a wrapper beside it cannot disagree about a single type.
fn writeSignature(
    context: plugin.RustContext,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    options: plugin.RustSignatureOptions,
) anyerror!void {
    const shape = try raw.Shape.of(context.allocator, context.program, function);
    defer shape.deinit(context.allocator);
    try writer.writeByte('(');
    const leading = if (options.receiver) if (shape.receiver) |record| record.publicSelf() else null else null;
    if (options.parameter_names) {
        try public.writeParameters(writer, shape, leading);
    } else {
        try writeTypesOnly(writer, shape, leading);
    }
    try writer.writeByte(')');
    try public.writePublicResultType(writer, shape);
}

/// The same list with the names left off, which is the shape a function
/// pointer or a trait method declaration takes.
fn writeTypesOnly(writer: *std.Io.Writer, shape: raw.Shape, leading: ?[]const u8) !void {
    var written = false;
    if (leading) |value| {
        try writer.writeAll(value);
        written = true;
    }
    for (shape.inputs) |input| {
        if (input.injected) continue;
        if (written) try writer.writeAll(", ");
        written = true;
        try input.writePublicType(writer);
    }
}

fn receiverFormAlloc(context: plugin.RustContext, allocator: std.mem.Allocator, function: abi.AbiFn) anyerror!?[]u8 {
    const shape = try raw.Shape.of(context.allocator, context.program, function);
    defer shape.deinit(context.allocator);
    const record = shape.receiver orelse return null;
    const form: []u8 = try allocator.dupe(u8, record.publicSelf());
    return form;
}

fn functionInfo(context: plugin.RustContext, function: abi.AbiFn) anyerror!plugin.RustFunctionInfo {
    const shape = try raw.Shape.of(context.allocator, context.program, function);
    defer shape.deinit(context.allocator);
    // A destructor is consumed by `Drop` and a buffer's release function by
    // `OwnedSlice`, so neither has a public item a hook can be written beside.
    const placement = types.placementOf(context.program, function);
    const published = placement != .destructor and !buffers.isRelease(context.program, function);
    return .{
        .public_name = try context.allocator.dupe(u8, shape.public_name),
        .is_public = published,
        .has_error = shape.declares_errors,
    };
}
