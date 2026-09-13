//! The `.implements` wrappers: the method a Go standard interface requires,
//! added next to a bound handle method and calling it.
//!
//! A built-in plugin, on the same terms as `iterator.zig`: the declaration
//! key, the `semantic.json` spelling and `ZIGO058` stay where they were, and
//! the typed field is read directly rather than through `ext`.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const plugin_api = @import("plugin");
const semantic = @import("semantic");
const site = plugin_api.site;

pub const plugin: plugin_api.Plugin = .{
    .name = "IMPLEMENTS",
    .validate = validateDocument,
    .method_hook = methodHook,
    .file_hook = runtimeHook,
};

fn methodHook(context: plugin_api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    const kinds = function.origin.goImplements();
    if (kinds.len == 0) return;
    const method = context.method.?;
    // One wrapper per named interface, in the order the declaration named
    // them; every one of them calls the same public method.
    // The name the generated body was written under: a declaration another
    // plugin claimed still has one, and it is what the adapter has to call.
    for (kinds) |kind| try renderImplementsWrapper(writer, function, kind, method.receiver_name.?, method.checked_name, method.needs_check);
}

fn validateDocument(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    const document = context.document;
    for (document.functions) |function| {
        if (try implementsIssue(allocator, function)) |issue| try context.diagnose(issue);
    }
}

/// The wrapper after its method. It calls the public method, so every handle
/// check, poison and error mapping the method does is shared; the wrapper
/// only adapts the shape. A `void` result means the whole input was handled;
/// an integer result is the count the interface reports.
pub fn renderImplementsWrapper(
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    implements: semantic.Implements,
    receiver_name: []const u8,
    go_name: []const u8,
    needs_check: bool,
) !void {
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

    try writer.print("\n// {s} calls {s}, satisfying {s}.\n", .{ method, go_name, interface });
    switch (implements) {
        .writer => {
            if (counts)
                try writer.print("// The count is what the method reports; a count short of len({s}) without an error is io.ErrShortWrite.\n", .{name})
            else
                try writer.print("// The method takes the whole of {0s}, so the count is len({0s}) whenever it succeeds.\n", .{name});
            try writer.print("func ({s} *{s}) Write({s} []byte) (int, error) {{\n", .{ receiver_name, receiver, name });
            if (counts) {
                try writeCall(writer, receiver_name, go_name, name, with_error, true);
                try writer.print("\tif int(n) < len({s}) {{\n\t\treturn int(n), io.ErrShortWrite\n\t}}\n\treturn int(n), nil\n}}\n", .{name});
            } else {
                try writeCall(writer, receiver_name, go_name, name, with_error, false);
                try writer.print("\treturn len({s}), nil\n}}\n", .{name});
            }
        },
        .string_writer => {
            // Neither shape copies, which is the whole reason this kind
            // exists rather than a Write wrapper. A method whose own Go
            // parameter is a `string` is handed the argument as it stands; a
            // method that takes bytes is lent the string's own bytes for the
            // length of the call, the same loan `.writer` makes with `p`.
            const passes_string = stringWriterPassesString(function.origin.*);
            const argument: []const u8 = if (passes_string) name else "zigoBytes";
            if (counts)
                try writer.print("// The count is what the method reports; a count short of len({s}) without an error is io.ErrShortWrite.\n", .{name})
            else
                try writer.print("// The method takes the whole of {0s}, so the count is len({0s}) whenever it succeeds.\n", .{name});
            if (!passes_string)
                try writer.print("// The method takes bytes, so {s} lends its own, without a copy; native reads them during the call only.\n", .{name});
            try writer.print("func ({s} *{s}) WriteString({s} string) (int, error) {{\n", .{ receiver_name, receiver, name });
            if (!passes_string)
                try writer.print("\tzigoBytes := unsafe.Slice(unsafe.StringData({0s}), len({0s}))\n", .{name});
            if (counts) {
                try writeCall(writer, receiver_name, go_name, argument, with_error, true);
                try writer.print("\tif int(n) < len({s}) {{\n\t\treturn int(n), io.ErrShortWrite\n\t}}\n\treturn int(n), nil\n}}\n", .{name});
            } else {
                try writeCall(writer, receiver_name, go_name, argument, with_error, false);
                try writer.print("\treturn len({s}), nil\n}}\n", .{name});
            }
        },
        .reader => {
            try writer.print("// A call that fills nothing while {s} has room reports io.EOF.\n", .{name});
            try writer.print("func ({s} *{s}) Read({s} []byte) (int, error) {{\n", .{ receiver_name, receiver, name });
            try writeCall(writer, receiver_name, go_name, name, with_error, true);
            try writer.print("\tif n == 0 && len({s}) > 0 {{\n\t\treturn 0, io.EOF\n\t}}\n\treturn int(n), nil\n}}\n", .{name});
        },
        .writer_to => {
            if (counts)
                try writer.writeAll("// The count is what the method reports.\n")
            else
                try writer.print("// The count is what {s} received during the call.\n", .{name});
            try writer.print("func ({s} *{s}) WriteTo({s} io.Writer) (int64, error) {{\n", .{ receiver_name, receiver, name });
            if (counts) {
                try writeCall(writer, receiver_name, go_name, name, with_error, true);
                try writer.writeAll("\treturn int64(n), nil\n}\n");
            } else {
                try writer.print("\tcounting := &zigoCountingWriter{{w: {s}}}\n", .{name});
                try writeCallCounting(writer, receiver_name, go_name, "counting", with_error);
            }
        },
        .reader_from => {
            if (counts)
                try writer.writeAll("// The count is what the method reports.\n")
            else
                try writer.print("// The count is what {s} handed over during the call.\n", .{name});
            try writer.print("func ({s} *{s}) ReadFrom({s} io.Reader) (int64, error) {{\n", .{ receiver_name, receiver, name });
            if (counts) {
                try writeCall(writer, receiver_name, go_name, name, with_error, true);
                try writer.writeAll("\treturn int64(n), nil\n}\n");
            } else {
                try writer.print("\tcounting := &zigoCountingReader{{r: {s}}}\n", .{name});
                try writeCallCounting(writer, receiver_name, go_name, "counting", with_error);
            }
        },
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

/// `n, err := m(arg)` with the error returned first, in the shapes the
/// method can have: with or without a count, with or without an error.
fn writeCall(writer: *std.Io.Writer, receiver_name: []const u8, go_name: []const u8, argument: []const u8, with_error: bool, counts: bool) !void {
    if (counts and with_error) {
        try writer.print("\tn, err := {s}.{s}({s})\n\tif err != nil {{\n\t\treturn 0, err\n\t}}\n", .{ receiver_name, go_name, argument });
    } else if (counts) {
        try writer.print("\tn := {s}.{s}({s})\n", .{ receiver_name, go_name, argument });
    } else if (with_error) {
        try writer.print("\tif err := {s}.{s}({s}); err != nil {{\n\t\treturn 0, err\n\t}}\n", .{ receiver_name, go_name, argument });
    } else {
        try writer.print("\t{s}.{s}({s})\n", .{ receiver_name, go_name, argument });
    }
}

/// The call through a counting stream: the count is reported even when the
/// call failed, since the bytes had already moved.
fn writeCallCounting(writer: *std.Io.Writer, receiver_name: []const u8, go_name: []const u8, argument: []const u8, with_error: bool) !void {
    if (with_error) {
        try writer.print("\terr := {s}.{s}({s})\n\treturn {s}.n, err\n}}\n", .{ receiver_name, go_name, argument, argument });
    } else {
        try writer.print("\t{s}.{s}({s})\n\treturn {s}.n, nil\n}}\n", .{ receiver_name, go_name, argument, argument });
    }
}

/// The counting stream types the `void`-result `WriteTo`/`ReadFrom`
/// wrappers route their stream through. Only emitted when one needs them.
pub fn renderCountingStreams(writer: *std.Io.Writer, program: abi.Program) !void {
    if (programNeedsCountingStream(program, .writer_to)) try writer.writeAll(
        "// zigoCountingWriter counts the bytes a WriteTo wrapper sends on to w.\n" ++
            "type zigoCountingWriter struct {\n\tw io.Writer\n\tn int64\n}\n\n" ++
            "// Write passes p on to w and adds what w took to the count.\n" ++
            "func (c *zigoCountingWriter) Write(p []byte) (int, error) {\n" ++
            "\tn, err := c.w.Write(p)\n\tc.n += int64(n)\n\treturn n, err\n}\n\n",
    );
    if (programNeedsCountingStream(program, .reader_from)) try writer.writeAll(
        "// zigoCountingReader counts the bytes a ReadFrom wrapper takes from r.\n" ++
            "type zigoCountingReader struct {\n\tr io.Reader\n\tn int64\n}\n\n" ++
            "// Read fills p from r and adds what r handed over to the count.\n" ++
            "func (c *zigoCountingReader) Read(p []byte) (int, error) {\n" ++
            "\tn, err := c.r.Read(p)\n\tc.n += int64(n)\n\treturn n, err\n}\n\n",
    );
}

fn programNeedsCountingStream(program: abi.Program, kind: semantic.Implements) bool {
    for (program.functions) |function| {
        if (function.origin.@"return".errorPayload() != .void) continue;
        for (function.origin.goImplements()) |declared| if (declared == kind) return true;
    }
    return false;
}
/// An `.implements` wrapper calls the public method with the interface's
/// arguments and adapts its result, so the method has to be a handle method
/// whose Go shape is one step from the interface: the single parameter the
/// interface passes, and a `void` or integer result.
pub fn implementsIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn) !?diagnostic.Diagnostic {
    const kinds = function.goImplements();
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
    if (function.goIterator() != null or function.cancel != null) return .{
        .severity = .@"error",
        .code = "ZIGO058",
        .message = try std.fmt.allocPrint(allocator, "`.implements = .{s}` on `{s}.{s}`, which also has `{s}`", .{ @tagName(implements), receiver, function.name, if (function.goIterator() != null) "`.iterator`" else "`.cancel`" }),
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

fn runtimeHook(context: plugin_api.Context, writer: *std.Io.Writer, file: plugin_api.FileInfo, phase: plugin_api.FilePhase) !void {
    if (file.kind == .runtime and phase == .end) try renderCountingStreams(writer, context.program);
}
