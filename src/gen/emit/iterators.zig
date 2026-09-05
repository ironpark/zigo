//! Range-over-func wrappers for `.iterator` methods: a `next()` that returns
//! `?T` becomes an `iter.Seq`/`iter.Seq2` the caller ranges over.
const std = @import("std");
const abi = @import("abi");
const must = @import("must.zig");
const public_writers = @import("public_writers.zig");

/// The wrapper after its method. It calls the public method, so every
/// handle check, range check and error mapping the method does is shared;
/// the wrapper only decides when the loop ends. A method whose Go signature
/// carries an `error` yields `iter.Seq2[T, error]`: the error is yielded
/// once, with the zero value, and the sequence stops. Otherwise it yields
/// `iter.Seq[T]`.
pub fn renderIteratorWrapper(
    scope: public_writers.PublicScope,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    go_names: [][]u8,
    receiver_name: []const u8,
    go_name: []const u8,
    needs_check: bool,
) !void {
    const iterator = function.origin.iterator.?;
    const receiver = function.origin.receiver.?;
    const with_error = needs_check or function.origin.@"return" == .error_union;
    var payload: std.Io.Writer.Allocating = .init(allocator);
    defer payload.deinit();
    try must.writeMustResultType(scope, &payload.writer, function.origin.*, null);
    const payload_type = payload.written();
    const cancellable = function.origin.cancel != null;

    try writer.print("\n// {0s} returns a sequence that calls {1s} until it reports no value.\n", .{ iterator.name, go_name });
    if (with_error) try writer.print("// A failed call yields its error once, with the zero {s}, and the sequence ends.\n", .{payload_type});
    if (cancellable) try writer.writeAll("// ctx is passed to every call, so cancelling it ends the sequence with ctx.Err().\n");
    try writer.print("func ({s} *{s}) {s}(", .{ receiver_name, receiver, iterator.name });
    if (cancellable) try writer.writeAll("ctx context.Context");
    try writer.writeAll(") ");
    if (with_error)
        try writer.print("iter.Seq2[{s}, error] {{\n\treturn func(yield func({s}, error) bool) {{\n", .{ payload_type, payload_type })
    else
        try writer.print("iter.Seq[{s}] {{\n\treturn func(yield func({s}) bool) {{\n", .{ payload_type, payload_type });
    try writer.writeAll("\t\tfor {\n\t\t\tvalue, ok");
    if (with_error) try writer.writeAll(", err");
    try writer.print(" := {s}.{s}(", .{ receiver_name, go_name });
    try must.writeMustCallArguments(allocator, writer, function, go_names);
    try writer.writeAll(")\n");
    if (with_error) try writer.print(
        "\t\t\tif err != nil {{\n\t\t\t\tvar zero {s}\n\t\t\t\tyield(zero, err)\n\t\t\t\treturn\n\t\t\t}}\n",
        .{payload_type},
    );
    if (with_error)
        try writer.writeAll("\t\t\tif !ok || !yield(value, nil) {\n\t\t\t\treturn\n\t\t\t}\n")
    else
        try writer.writeAll("\t\t\tif !ok || !yield(value) {\n\t\t\t\treturn\n\t\t\t}\n");
    try writer.writeAll("\t\t}\n\t}\n}\n");
}
