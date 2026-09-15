//! Range-over-func wrappers for `.iterator` methods: a `next()` that returns
//! `?T` becomes an `iter.Seq`/`iter.Seq2` the caller ranges over.
//!
//! A built-in plugin on the same terms as an added one: its options travel
//! under its `ext` key, written by `use(zigo.features.iterator, .{ ... })`
//! with the wrapper name already resolved, and every hook reads them through
//! `optionsOf`. The core reads them too -- name collision rules and
//! `abi-diff` -- through `plugin.builtins.iterator.read`, which is the same
//! public reader a third-party plugin would call.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const plugin_api = @import("plugin");
const semantic = @import("semantic");
const site = plugin_api.site;

/// What `use(zigo.features.iterator, .{ .name = ... })` attaches: the
/// wrapper's name. The reflector has already resolved an empty name to
/// `All` (or `AllChecked` over a `*Checked` method) by the time it is here.
pub const Options = plugin_api.builtins.iterator.Options;

/// The contract's descriptor -- name, options and subjects, the half the
/// authoring module attaches with -- plus this file's hooks.
pub const plugin: plugin_api.Plugin = blk: {
    var declared = plugin_api.builtins.iterator.plugin;
    declared.after = &.{ "MUST", "IMPLEMENTS" };
    declared.validate = validateDocument;
    declared.go = .{ .visit = visit };
    break :blk declared;
};

/// The wrapper is written after the method it drives, in the file that owns
/// the method: a visit of the function node is exactly where the direct call
/// was.
fn visit(context: plugin_api.GoContext, node: plugin_api.Node, b: *plugin_api.Builder) !void {
    if (node != .function) return;
    const options = try context.optionsOf(plugin, .function, node) orelse return;
    try renderIteratorWrapper(context, b, node.function, options);
}

/// The shape rule for `.iterator`, run over the whole document. The name
/// clash between the wrapper and another method of the same type is not here:
/// it belongs with every other public-name collision, in `names.zig`.
fn validateDocument(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    const document = context.document;
    for (document.functions) |function| {
        const options = try context.optionsOf(plugin, .function, function.ext) orelse continue;
        if (try iteratorIssue(allocator, function, options)) |issue| try context.diagnose(issue);
    }
}

/// The wrapper after its method. It calls the public method, so every
/// handle check, range check and error mapping the method does is shared;
/// the wrapper only decides when the loop ends. A method whose Go signature
/// carries an `error` yields `iter.Seq2[T, error]`: the error is yielded
/// once, with the zero value, and the sequence stops. Otherwise it yields
/// `iter.Seq[T]`.
pub fn renderIteratorWrapper(context: plugin_api.GoContext, b: *plugin_api.Builder, function: abi.AbiFn, iterator: Options) !void {
    const allocator = context.allocator;
    const method = context.method.?;
    const receiver_name = method.receiver_name.?;
    const go_name = method.checked_name;
    const receiver = function.origin.receiver.?;
    const with_error = method.needs_check or function.origin.@"return" == .error_union;
    var payload: std.Io.Writer.Allocating = .init(allocator);
    try context.writeValueType(&payload.writer, function);
    const payload_type = payload.written();
    const cancellable = function.origin.cancel != null;

    var doc: std.Io.Writer.Allocating = .init(allocator);
    defer doc.deinit();
    try doc.writer.print("{0s} returns a sequence that calls {1s} until it reports no value.", .{ iterator.name, go_name });
    if (with_error) try doc.writer.print("\nA failed call yields its error once, with the zero {s}, and the sequence ends.", .{payload_type});
    if (cancellable) try doc.writer.writeAll("\nctx is passed to every call, so cancelling it ends the sequence with ctx.Err().");

    const value_type = b.valueType(function);
    const yield_params: []const plugin_api.gobuild.Param = if (with_error)
        &.{ .{ .type = value_type }, .{ .type = b.ident("error") } }
    else
        &.{.{ .type = value_type }};
    const sequence = try b.indexExpr(
        try b.selName("iter", if (with_error) "Seq2" else "Seq"),
        if (with_error) &.{ value_type, b.ident("error") } else &.{value_type},
    );

    // The call is the public method's own, so every handle check, range check
    // and error mapping it does is shared; the loop only decides when to stop.
    const call = try b.callForwarding(try b.selName(receiver_name, go_name), function);
    var loop: std.ArrayList(plugin_api.gobuild.Stmt) = .empty;
    defer loop.deinit(allocator);
    try loop.append(allocator, try b.define(if (with_error) &.{ "value", "ok", "err" } else &.{ "value", "ok" }, call));
    if (with_error) try loop.append(allocator, try b.ifStmt(.{
        .cond = try b.bin("!=", b.ident("err"), .nil),
        .body = &.{
            b.declare("zero", value_type, null),
            b.exprStmt(try b.callName("yield", &.{ b.ident("zero"), b.ident("err") })),
            try b.ret(&.{}),
        },
    }));
    const yielded = try b.callName("yield", if (with_error) &.{ b.ident("value"), .nil } else &.{b.ident("value")});
    try loop.append(allocator, try b.ifStmt(.{
        .cond = try b.bin("||", try b.not(b.ident("ok")), try b.not(yielded)),
        .body = &.{try b.ret(&.{})},
    }));

    try b.emit(&.{try b.func(.{
        .doc = .{ .text = doc.written() },
        .receiver = .{ .name = receiver_name, .type = receiver, .pointer = true },
        .name = iterator.name,
        .signature = .{ .explicit = .{
            .params = if (cancellable) &.{.{ .names = &.{"ctx"}, .type = try b.selName("context", "Context") }} else &.{},
            .results = &.{sequence},
        } },
        .body = &.{try b.ret(&.{try b.funcLiteral(
            &.{.{ .names = &.{"yield"}, .type = try b.funcType(yield_params, &.{b.ident("bool")}) }},
            &.{},
            &.{try b.forever(loop.items)},
        )})},
    })}, .{ .blank_before = true });
}

/// An iterator wrapper drives `next()` for the caller, so the method has to
/// be one Go can call with nothing but the receiver (and its `ctx`), and it
/// has to say when it is finished: `?T` or `!?T`.
pub fn iteratorIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn, iterator: Options) !?diagnostic.Diagnostic {
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
