//! Materialized ABI call wiring. Layout is owned by lowering; byte encoding
//! and Go decoding live in dedicated emitters.
const std = @import("std");
const abi = @import("abi");
const common = @import("common.zig");
const shim = @import("shim.zig");
const materializedEncoderNameAlloc = @import("materialized_encoder.zig").materializedEncoderNameAlloc;

/// Every materialization step allocates into the same builder, so they all
/// fail the same way. Naming the panic once keeps the eleven emit sites from
/// drifting apart in wording.
pub const materialize_oom = "catch @panic(\"zigo: materialization allocation failed\")";

pub fn writeMaterializedReturn(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    function: abi.AbiFn,
    materialized: abi.AbiFn.MaterializedReturn,
) !void {
    try writer.writeAll("const result = ");
    try shim.writeTargetCall(allocator, writer, program, function);
    if (materialized.fallible) try shim.writeShimErrorCatch(writer, function) else try writer.writeAll(";\n");
    const encoder = try materializedEncoderNameAlloc(allocator, materialized.root);
    defer allocator.free(encoder);
    try writer.print("    const buffer = {s}Buffer({s}, result, {}) " ++ materialize_oom ++ ";\n", .{ encoder, common.heapAllocator(program), materialized.is_slice });
    try writer.writeAll("    out_result_ptr.* = buffer.ptr;\n    out_result_len.* = buffer.len;\n");
    if (materialized.fallible) try writer.writeAll("    return 0;\n");
    try writer.writeAll("}\n");
}

pub fn writeMaterializedOutput(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    function: abi.AbiFn,
    output: abi.AbiFn.MaterializedOut,
) !void {
    const parameter = function.origin.params[output.source_index];
    try writer.writeAll("const result = ");
    try shim.writeTargetCall(allocator, writer, program, function);
    if (output.fallible) try shim.writeShimErrorCatch(writer, function) else try writer.writeAll(";\n");
    try writer.print("    const written = @min(result, {s}_len);\n", .{parameter.name});
    const encoder = try materializedEncoderNameAlloc(allocator, output.root);
    defer allocator.free(encoder);
    // The C panic bridge does not unwind Zig defers. Free staging storage
    // explicitly after the helper has cleaned up its partial buffer.
    try writer.print("    const buffer = {s}Buffer({s}, zigo_{s}_slice[0..written], true) catch {{\n        {s}.free(zigo_{s}_slice);\n        @panic(\"zigo: materialization allocation failed\");\n    }};\n", .{ encoder, common.heapAllocator(program), parameter.name, common.heapAllocator(program), parameter.name });
    try writer.writeAll("    out_result_ptr.* = buffer.ptr;\n    out_result_len.* = buffer.len;\n");
    if (output.fallible) {
        try writer.writeAll("    out_written.* = result;\n    return 0;\n");
    } else {
        try writer.writeAll("    return result;\n");
    }
    try writer.writeAll("}\n");
}
