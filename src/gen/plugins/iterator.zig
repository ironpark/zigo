//! Range-over-func wrappers for `.iterator` methods: a `next()` that returns
//! `?T` becomes an `iter.Seq`/`iter.Seq2` the caller ranges over.
//!
//! A built-in plugin. It keeps its declaration key (`.iterator`) and its
//! `semantic.json` spelling, and reads the typed field directly instead of
//! going through `ext`: an in-tree plugin may, and every document and golden
//! that predates the plugin frame stays exactly as it was. An out-of-tree
//! plugin transports its options with `extend`.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const must = @import("must.zig");
const plugin_api = @import("plugin");
const public_writers = @import("../emit/public_writers.zig");
const semantic = @import("semantic");
const site = @import("../validate/site.zig");

pub const plugin: plugin_api.Plugin = .{
    .name = "ITERATOR",
    .validate = validateDocument,
    .method_hook = methodHook,
};

/// The wrapper is written after the method it drives, in the file that owns
/// the method: a plugin's method hook is exactly where the direct call was.
fn methodHook(context: plugin_api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    if (function.origin.iterator == null) return;
    const method = context.method.?;
    try renderIteratorWrapper(
        .{ .program = context.program, .options = context.options },
        context.allocator,
        writer,
        function,
        method.param_names,
        method.receiver_name.?,
        method.go_name,
        method.needs_check,
    );
}

/// The shape rule for `.iterator`, run over the whole document. The name
/// clash between the wrapper and another method of the same type is not here:
/// it belongs with every other public-name collision, in `names.zig`.
fn validateDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.functions) |function| {
        if (try iteratorIssue(allocator, function)) |issue| return issue;
    }
    return null;
}

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
/// An iterator wrapper drives `next()` for the caller, so the method has to
/// be one Go can call with nothing but the receiver (and its `ctx`), and it
/// has to say when it is finished: `?T` or `!?T`.
pub fn iteratorIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn) !?diagnostic.Diagnostic {
    const iterator = function.iterator orelse return null;
    if (function.receiver == null) return .{
        .severity = .@"error",
        .code = "ZIGO050",
        .message = try std.fmt.allocPrint(allocator, "`.iterator` on `{s}`, which has no receiver", .{function.name}),
        .site = site.functionSite(function),
        .hint = "an iterator wrapper is a method of the handle it advances; move `.iterator` to a method of a registered opaque type",
    };
    if (function.@"return".errorPayload() != .optional) return .{
        .severity = .@"error",
        .code = "ZIGO050",
        .message = try std.fmt.allocPrint(allocator, "`.iterator` on `{s}.{s}`, which does not return `?T` or `!?T`", .{ function.receiver.?, function.name }),
        .site = site.functionSite(function),
        .hint = "the absent value is what ends the sequence; return an optional",
    };
    for (function.params) |parameter| {
        if (parameter.injected != null or parameter.type == .cancel_flag) continue;
        return .{
            .severity = .@"error",
            .code = "ZIGO050",
            .message = try std.fmt.allocPrint(allocator, "`.iterator` on `{s}.{s}`, which takes parameter `{s}`", .{ function.receiver.?, function.name, parameter.name }),
            .site = site.functionSite(function),
            .hint = try std.fmt.allocPrint(allocator, "`{s}()` is called with only the receiver; move the argument into the handle's constructor", .{iterator.name}),
        };
    }
    if (iterator.name.len == 0 or !std.ascii.isUpper(iterator.name[0])) return .{
        .severity = .@"error",
        .code = "ZIGO050",
        .message = try std.fmt.allocPrint(allocator, "`.iterator` name `{s}` on `{s}.{s}` is not an exported Go identifier", .{ iterator.name, function.receiver.?, function.name }),
        .site = site.functionSite(function),
        .hint = "start the wrapper name with an uppercase letter, or omit `.name` for `All`",
    };
    return null;
}
