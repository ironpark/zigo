//! The `.implements` wrappers: the method a Go standard interface requires,
//! added next to a bound handle method and calling it.
//!
//! A built-in plugin on the same terms as an added one: the kinds travel
//! under its `ext` key, written by `use(zigo.features.implements, .{ ... })`,
//! and every hook reads them through `optionsOf`. The core reads them too --
//! name collision rules and the Must mirror -- through
//! `plugin.builtins.implements.read`, which is the same public reader a
//! third-party plugin would call.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const plugin_api = @import("plugin");
const semantic = @import("semantic");
const site = plugin_api.site;
const Expr = plugin_api.gobuild.Expr;
const Stmt = plugin_api.gobuild.Stmt;

/// What `use(zigo.features.implements, .{ ... })` attaches.
pub const Options = plugin_api.builtins.implements.Options;

/// The contract's descriptor -- name, options and subjects, the half the
/// authoring module attaches with -- plus this file's hooks.
pub const plugin: plugin_api.Plugin = blk: {
    var declared = plugin_api.builtins.implements.plugin;
    declared.validate = validateDocument;
    declared.claims = hidesOriginal;
    declared.visit = visit;
    break :blk declared;
};

/// The wrappers are the public spelling: the zigo-shaped method is written
/// under its unexported checked name unless the declaration asked to keep it.
fn hidesOriginal(context: plugin_api.Context, node: plugin_api.Node) !bool {
    if (node != .function) return false;
    const options = try context.optionsOf(plugin, .function, node) orelse return false;
    return options.hidesOriginal();
}

/// The three places this plugin writes: the interface wrappers after the
/// method they adapt, the assertions after the handle that carries them, and
/// the counting streams at the end of the runtime file.
fn visit(context: plugin_api.Context, node: plugin_api.Node, b: *plugin_api.Builder) !void {
    switch (node) {
        .function => |function| try renderWrappers(context, b, function),
        .type => |declaration| try renderAssertions(context, b, declaration),
        .file_end => |file| if (file.kind == .runtime) try renderCountingStreams(context, b),
        else => {},
    }
}

/// One assertion per interface a handle satisfies through `.implements`, so
/// a wrapper that stops matching the interface fails this package's build
/// rather than a consumer's.
fn renderAssertions(context: plugin_api.Context, b: *plugin_api.Builder, declaration: semantic.TypeDecl) !void {
    if (declaration.kind != .@"opaque") return;
    var assertions: std.ArrayList(plugin_api.gobuild.Decl) = .empty;
    defer assertions.deinit(context.allocator);
    for (context.program.functions) |function| {
        const receiver = function.origin.receiver orelse continue;
        if (!std.mem.eql(u8, receiver, declaration.name)) continue;
        const options = try context.optionsOf(plugin, .function, function.origin.ext) orelse continue;
        for (options.kinds) |kind| try assertions.append(context.allocator, try b.assertImplements(.{
            .interface = b.raw(kind.interfaceName()),
            .type_name = declaration.name,
        }));
    }
    try b.emit(assertions.items, .{ .blank_before = true, .blank_between = false });
}

fn renderWrappers(context: plugin_api.Context, b: *plugin_api.Builder, function: abi.AbiFn) !void {
    const options = try context.optionsOf(plugin, .function, function.origin.ext) orelse return;
    const method = context.method.?;
    // One wrapper per named interface, in the order the declaration named
    // them; every one of them calls the same bound method, under the name
    // its body was written with: the exported one when the declaration kept
    // it, the unexported checked name otherwise.
    for (options.kinds) |kind| try renderImplementsWrapper(context, b, function, kind, options.hidesOriginal(), method.receiver_name.?, method.checked_name, method.needs_check);
}

fn validateDocument(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    const document = context.document;
    for (document.functions) |function| {
        const options = try context.optionsOf(plugin, .function, function.ext) orelse continue;
        if (try implementsIssue(allocator, function, options)) |issue| try context.diagnose(issue);
    }
}

/// The wrapper after its method. It calls the public method, so every handle
/// check, poison and error mapping the method does is shared; the wrapper
/// only adapts the shape. A `void` result means the whole input was handled;
/// an integer result is the count the interface reports.
pub fn renderImplementsWrapper(
    context: plugin_api.Context,
    b: *plugin_api.Builder,
    function: abi.AbiFn,
    implements: semantic.Implements,
    hides_original: bool,
    receiver_name: []const u8,
    go_name: []const u8,
    needs_check: bool,
) !void {
    const allocator = context.allocator;
    const receiver = function.origin.receiver.?;
    const result = function.origin.@"return".errorPayload();
    const counts = result == .int;
    var has_stream = false;
    for (function.origin.params) |parameter| {
        if (parameter.type == .io_stream) has_stream = true;
    }
    const with_error = needs_check or function.origin.@"return" == .error_union or has_stream;
    const method = implements.methodName();
    const interface = implements.interfaceName();

    // The interface fixes the parameter's type, not its name, so the wrapper
    // renames it out of the way when the receiver already took the letter.
    const name = switch (implements) {
        .writer, .reader => wrapperParamName(receiver_name, "p", "buf"),
        .string_writer => wrapperParamName(receiver_name, "s", "str"),
        .writer_to => wrapperParamName(receiver_name, "w", "dst"),
        .reader_from => wrapperParamName(receiver_name, "r", "src"),
    };

    var doc: std.Io.Writer.Allocating = .init(allocator);
    defer doc.deinit();
    if (hides_original)
        try doc.writer.print("{s} calls the Zig method {s}.{s}, satisfying {s}.", .{ method, receiver, function.origin.name, interface })
    else
        try doc.writer.print("{s} calls {s}, satisfying {s}.", .{ method, go_name, interface });
    switch (implements) {
        .writer, .string_writer => if (counts)
            try doc.writer.print("\nThe count is what the method reports; a count short of len({s}) without an error is io.ErrShortWrite.", .{name})
        else
            try doc.writer.print("\nThe method takes the whole of {0s}, so the count is len({0s}) whenever it succeeds.", .{name}),
        .reader => try doc.writer.print("\nA call that fills nothing while {s} has room reports io.EOF.", .{name}),
        .writer_to => if (counts)
            try doc.writer.writeAll("\nThe count is what the method reports.")
        else
            try doc.writer.print("\nThe count is what {s} received during the call.", .{name}),
        .reader_from => if (counts)
            try doc.writer.writeAll("\nThe count is what the method reports.")
        else
            try doc.writer.print("\nThe count is what {s} handed over during the call.", .{name}),
    }

    // Neither `.string_writer` shape copies, which is the whole reason that
    // kind exists rather than a Write wrapper. A method whose own Go parameter
    // is a `string` is handed the argument as it stands; a method that takes
    // bytes is lent the string's own bytes for the length of the call, the
    // same loan `.writer` makes with `p`.
    const passes_string = implements != .string_writer or stringWriterPassesString(function.origin.*);
    if (implements == .string_writer and !passes_string)
        try doc.writer.print("\nThe method takes bytes, so {s} lends its own, without a copy; native reads them during the call only.", .{name});

    const parameter_type: Expr = switch (implements) {
        .writer, .reader => try b.sliceOf(b.ident("byte")),
        .string_writer => b.ident("string"),
        .writer_to => try b.selName("io", "Writer"),
        .reader_from => try b.selName("io", "Reader"),
    };
    const results: []const Expr = switch (implements) {
        .writer, .string_writer, .reader => &.{ b.ident("int"), b.ident("error") },
        .writer_to, .reader_from => &.{ b.ident("int64"), b.ident("error") },
    };

    var body: std.ArrayList(Stmt) = .empty;
    defer body.deinit(allocator);
    const argument: []const u8 = if (implements == .string_writer and !passes_string) "zigoBytes" else name;
    if (implements == .string_writer and !passes_string) try body.append(allocator, try b.define(
        &.{"zigoBytes"},
        try b.call(try b.selName("unsafe", "Slice"), &.{
            try b.call(try b.selName("unsafe", "StringData"), &.{b.ident(name)}),
            try b.callName("len", &.{b.ident(name)}),
        }),
    ));

    switch (implements) {
        .writer, .string_writer => {
            try appendCall(b, &body, receiver_name, go_name, b.ident(argument), with_error, counts);
            if (counts) {
                try body.append(allocator, try b.ifStmt(.{
                    .cond = try b.bin("<", try b.callName("int", &.{b.ident("n")}), try b.callName("len", &.{b.ident(name)})),
                    .body = &.{try b.ret(&.{ try b.callName("int", &.{b.ident("n")}), try b.selName("io", "ErrShortWrite") })},
                }));
                try body.append(allocator, try b.ret(&.{ try b.callName("int", &.{b.ident("n")}), .nil }));
            } else {
                try body.append(allocator, try b.ret(&.{ try b.callName("len", &.{b.ident(name)}), .nil }));
            }
        },
        .reader => {
            try appendCall(b, &body, receiver_name, go_name, b.ident(name), with_error, true);
            try body.append(allocator, try b.ifStmt(.{
                .cond = try b.bin(
                    "&&",
                    try b.bin("==", b.ident("n"), b.int(0)),
                    try b.bin(">", try b.callName("len", &.{b.ident(name)}), b.int(0)),
                ),
                .body = &.{try b.ret(&.{ b.int(0), try b.selName("io", "EOF") })},
            }));
            try body.append(allocator, try b.ret(&.{ try b.callName("int", &.{b.ident("n")}), .nil }));
        },
        .writer_to, .reader_from => {
            if (counts) {
                try appendCall(b, &body, receiver_name, go_name, b.ident(name), with_error, true);
                try body.append(allocator, try b.ret(&.{ try b.callName("int64", &.{b.ident("n")}), .nil }));
            } else {
                // A nil stream goes to the method as it is, so the method's own
                // nil check reports it; wrapped in a counting adapter it would
                // look present.
                const nil_call = try b.call(try b.selName(receiver_name, go_name), &.{.nil});
                try body.append(allocator, try b.ifStmt(.{
                    .cond = try b.bin("==", b.ident(name), .nil),
                    .body = if (with_error)
                        try b.dupStmts(&.{try b.ret(&.{ b.int(0), nil_call })})
                    else
                        try b.dupStmts(&.{ b.exprStmt(nil_call), try b.ret(&.{ b.int(0), .nil }) }),
                }));
                const adapter = if (implements == .writer_to) "zigoCountingWriter" else "zigoCountingReader";
                const field = if (implements == .writer_to) "w" else "r";
                try body.append(allocator, try b.define(&.{"counting"}, try b.addr(try b.composite(b.ident(adapter), &.{.{ .key = field, .value = b.ident(name) }}))));
                // The count is reported even when the call failed, since the
                // bytes had already moved.
                const counting_call = try b.call(try b.selName(receiver_name, go_name), &.{b.ident("counting")});
                if (with_error) {
                    try body.append(allocator, try b.define(&.{"err"}, counting_call));
                    try body.append(allocator, try b.ret(&.{ try b.selName("counting", "n"), b.ident("err") }));
                } else {
                    try body.append(allocator, b.exprStmt(counting_call));
                    try body.append(allocator, try b.ret(&.{ try b.selName("counting", "n"), .nil }));
                }
            }
        },
    }

    try b.emit(&.{try b.func(.{
        .doc = .{ .text = doc.written() },
        .receiver = .{ .name = receiver_name, .type = receiver, .pointer = true },
        .name = method,
        .signature = .{ .explicit = .{
            .params = &.{.{ .names = &.{name}, .type = parameter_type }},
            .results = results,
        } },
        .body = body.items,
    })}, .{ .blank_before = true });
}

/// `n, err := m(arg)` with the error returned first, in the shapes the
/// method can have: with or without a count, with or without an error.
fn appendCall(
    b: *plugin_api.Builder,
    body: *std.ArrayList(Stmt),
    receiver_name: []const u8,
    go_name: []const u8,
    argument: Expr,
    with_error: bool,
    counts: bool,
) !void {
    const allocator = b.allocator;
    const call = try b.call(try b.selName(receiver_name, go_name), &.{argument});
    if (counts and with_error) {
        try body.append(allocator, try b.define(&.{ "n", "err" }, call));
        try body.append(allocator, try b.ifStmt(.{
            .cond = try b.bin("!=", b.ident("err"), .nil),
            .body = &.{try b.ret(&.{ b.int(0), b.ident("err") })},
        }));
    } else if (counts) {
        try body.append(allocator, try b.define(&.{"n"}, call));
    } else if (with_error) {
        try body.append(allocator, try b.ifStmt(.{
            .init = try b.define(&.{"err"}, call),
            .cond = try b.bin("!=", b.ident("err"), .nil),
            .body = &.{try b.ret(&.{ b.int(0), b.ident("err") })},
        }));
    } else {
        try body.append(allocator, b.exprStmt(call));
    }
}

/// The interface's own spelling for the argument, unless the receiver took
/// that name first: a method on a `Stream` is written `s`, and a `WriteString`
/// taking another `s` would shadow it. The word after it is a reader's name
/// for the same thing, and the generated one is what is left when even that
/// is spoken for.
fn wrapperParamName(receiver_name: []const u8, preferred: []const u8, fallback: []const u8) []const u8 {
    if (!std.mem.eql(u8, receiver_name, preferred)) return preferred;
    return if (std.mem.eql(u8, receiver_name, fallback)) "zigoArg" else fallback;
}

/// Whether the bound method's own Go parameter is already a `string`. Without
/// a text hint it is a `[]byte`, and the wrapper lends the string's bytes
/// rather than converting them.
fn stringWriterPassesString(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| {
        if (parameter.injected != null) continue;
        return semantic.isTextHint(parameter.semantic);
    }
    return false;
}

/// The counting stream types the `void`-result `WriteTo`/`ReadFrom`
/// wrappers route their stream through. Only emitted when one needs them.
pub fn renderCountingStreams(context: plugin_api.Context, b: *plugin_api.Builder) !void {
    if (try programNeedsCountingStream(context, .writer_to)) try renderCountingStream(b, .{
        .name = "zigoCountingWriter",
        .doc = "zigoCountingWriter counts the bytes a WriteTo wrapper sends on to w.",
        .field = "w",
        .stream = "Writer",
        .method = "Write",
        .method_doc = "Write passes p on to w and adds what w took to the count.",
    });
    if (try programNeedsCountingStream(context, .reader_from)) try renderCountingStream(b, .{
        .name = "zigoCountingReader",
        .doc = "zigoCountingReader counts the bytes a ReadFrom wrapper takes from r.",
        .field = "r",
        .stream = "Reader",
        .method = "Read",
        .method_doc = "Read fills p from r and adds what r handed over to the count.",
    });
}

const CountingStream = struct {
    name: []const u8,
    doc: []const u8,
    field: []const u8,
    stream: []const u8,
    method: []const u8,
    method_doc: []const u8,
};

fn renderCountingStream(b: *plugin_api.Builder, spec: CountingStream) !void {
    try b.emit(&.{
        try b.structDecl(.{
            .doc = .{ .text = spec.doc },
            .name = spec.name,
            .fields = &.{
                .{ .name = spec.field, .type = try b.selName("io", spec.stream) },
                .{ .name = "n", .type = b.ident("int64") },
            },
        }),
        try b.func(.{
            .doc = .{ .text = spec.method_doc },
            .receiver = .{ .name = "c", .type = spec.name, .pointer = true },
            .name = spec.method,
            .signature = .{ .explicit = .{
                .params = &.{.{ .names = &.{"p"}, .type = try b.sliceOf(b.ident("byte")) }},
                .results = &.{ b.ident("int"), b.ident("error") },
            } },
            .body = &.{
                try b.define(&.{ "n", "err" }, try b.callSel(try b.selName("c", spec.field), spec.method, &.{b.ident("p")})),
                try b.assign(&.{try b.selName("c", "n")}, "+=", &.{try b.callName("int64", &.{b.ident("n")})}),
                try b.ret(&.{ b.ident("n"), b.ident("err") }),
            },
        }),
    }, .{ .blank_after = true });
}

fn programNeedsCountingStream(context: plugin_api.Context, kind: semantic.Implements) !bool {
    for (context.program.functions) |function| {
        if (function.origin.@"return".errorPayload() != .void) continue;
        const options = try context.optionsOf(plugin, .function, function.origin.ext) orelse continue;
        for (options.kinds) |declared| if (declared == kind) return true;
    }
    return false;
}
/// An `.implements` wrapper calls the public method with the interface's
/// arguments and adapts its result, so the method has to be a handle method
/// whose Go shape is one step from the interface: the single parameter the
/// interface passes, and a `void` or integer result.
pub fn implementsIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn, options: Options) !?diagnostic.Diagnostic {
    const kinds = options.kinds;
    for (kinds, 0..) |kind, index| {
        // Two wrappers of the same kind would be one Go method declared twice.
        for (kinds[0..index]) |earlier| if (earlier == kind) return .{
            .severity = .@"error",
            .code = "ZIGO058",
            .message = try std.fmt.allocPrint(allocator, "`.implements` names `.{s}` twice on `{s}`", .{ @tagName(kind), function.name }),
            .site = site.functionSite(function),
            .hint = "name each interface once; one method cannot carry the same wrapper twice",
        };
        if (try kindIssue(allocator, function, kind)) |issue| return issue;
    }
    return null;
}

fn kindIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn, implements: semantic.Implements) !?diagnostic.Diagnostic {
    const interface = implements.interfaceName();
    if (function.receiver == null) return .{
        .severity = .@"error",
        .code = "ZIGO058",
        .message = try std.fmt.allocPrint(allocator, "`.implements = .{s}` on `{s}`, which has no receiver", .{ @tagName(implements), function.name }),
        .site = site.functionSite(function),
        .hint = try std.fmt.allocPrint(allocator, "`{s}` is satisfied by a method; move `.implements` to a method of a registered opaque type", .{interface}),
    };
    const receiver = function.receiver.?;
    const iterates = try plugin_api.builtins.iterator.read(allocator, function.ext) != null;
    if (iterates or function.cancel != null) return .{
        .severity = .@"error",
        .code = "ZIGO058",
        .message = try std.fmt.allocPrint(allocator, "`.implements = .{s}` on `{s}.{s}`, which also has `{s}`", .{ @tagName(implements), receiver, function.name, if (iterates) "`.iterator`" else "`.cancel`" }),
        .site = site.functionSite(function),
        .hint = try std.fmt.allocPrint(allocator, "`{s}` has no place for a `ctx` or a sequence; bind a plain method for the interface", .{interface}),
    };
    const result = function.@"return".errorPayload();
    if (result != .void and result != .int) return .{
        .severity = .@"error",
        .code = "ZIGO058",
        .message = try std.fmt.allocPrint(allocator, "`.implements = .{s}` on `{s}.{s}`, which does not return `void` or an integer", .{ @tagName(implements), receiver, function.name }),
        .site = site.functionSite(function),
        .hint = try std.fmt.allocPrint(allocator, "`{s}` reports a count; return `void` (the whole input counts) or the number of bytes handled", .{implements.signature()}),
    };
    var data: ?semantic.Parameter = null;
    var data_count: usize = 0;
    for (function.params) |parameter| {
        if (parameter.injected != null) continue;
        data_count += 1;
        data = parameter;
    }
    const expected: []const u8 = switch (implements) {
        .writer => "one `[]const u8` parameter",
        .string_writer => "one `[]const u8` parameter",
        .reader => "one `.out` `[]u8` parameter with `.written = .result`",
        .writer_to => "one `*std.Io.Writer` parameter",
        .reader_from => "one `*std.Io.Reader` parameter",
    };
    const shape_ok = data_count == 1 and switch (implements) {
        .writer => data.?.direction == .in and data.?.type == .slice and semantic.isByte(data.?.type.slice.element.*) and !semantic.isTextHint(data.?.semantic),
        // The same parameter `.writer` takes, read the other way around: a
        // string hint makes the wrapper a pass-through, and without one the
        // wrapper lends the string's bytes for the call.
        .string_writer => data.?.direction == .in and data.?.type == .slice and semantic.isByte(data.?.type.slice.element.*),
        .reader => data.?.direction == .out and data.?.type == .slice and semantic.isByte(data.?.type.slice.element.*) and data.?.writtenHint() == .@"return" and result == .int,
        .writer_to => data.?.type == .io_stream and data.?.type.io_stream.direction == .writer,
        .reader_from => data.?.type == .io_stream and data.?.type.io_stream.direction == .reader,
    };
    if (!shape_ok) {
        const text_hinted = implements == .writer and data_count == 1 and data.?.type == .slice and semantic.isTextHint(data.?.semantic);
        return .{
            .severity = .@"error",
            .code = "ZIGO058",
            .message = try std.fmt.allocPrint(allocator, "`.implements = .{s}` on `{s}.{s}`, which does not take {s}", .{ @tagName(implements), receiver, function.name, expected }),
            .site = site.functionSite(function),
            .hint = if (text_hinted)
                "`Write(p []byte)` passes bytes; drop the string hint so the wrapper does not copy on every call"
            else
                try std.fmt.allocPrint(allocator, "`{s}` calls the method with exactly the argument `{s}` takes", .{ interface, implements.signature() }),
        };
    }
    return null;
}
