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
const site = @import("../validate/site.zig");

pub const plugin: plugin_api.Plugin = .{
    .name = "IMPLEMENTS",
    .validate = validateDocument,
    .method_hook = methodHook,
};

fn methodHook(context: plugin_api.Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    if (function.origin.implements == null) return;
    const method = context.method.?;
    try renderImplementsWrapper(writer, function, method.receiver_name.?, method.go_name, method.needs_check);
}

fn validateDocument(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.functions) |function| {
        if (try implementsIssue(allocator, function)) |issue| return issue;
    }
    return null;
}

/// The wrapper after its method. It calls the public method, so every handle
/// check, poison and error mapping the method does is shared; the wrapper
/// only adapts the shape. A `void` result means the whole input was handled;
/// an integer result is the count the interface reports.
pub fn renderImplementsWrapper(
    writer: *std.Io.Writer,
    function: abi.AbiFn,
    receiver_name: []const u8,
    go_name: []const u8,
    needs_check: bool,
) !void {
    const implements = function.origin.implements.?;
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

    try writer.print("\n// {s} calls {s}, satisfying {s}.\n", .{ method, go_name, interface });
    switch (implements) {
        .writer => {
            if (counts)
                try writer.writeAll("// The count is what the method reports; a count short of len(p) without an error is io.ErrShortWrite.\n")
            else
                try writer.writeAll("// The method takes the whole of p, so the count is len(p) whenever it succeeds.\n");
            try writer.print("func ({s} *{s}) Write(p []byte) (int, error) {{\n", .{ receiver_name, receiver });
            if (counts) {
                try writeCall(writer, receiver_name, go_name, "p", with_error, true);
                try writer.writeAll("\tif int(n) < len(p) {\n\t\treturn int(n), io.ErrShortWrite\n\t}\n\treturn int(n), nil\n}\n");
            } else {
                try writeCall(writer, receiver_name, go_name, "p", with_error, false);
                try writer.writeAll("\treturn len(p), nil\n}\n");
            }
        },
        .reader => {
            try writer.writeAll("// A call that fills nothing while p has room reports io.EOF.\n");
            try writer.print("func ({s} *{s}) Read(p []byte) (int, error) {{\n", .{ receiver_name, receiver });
            try writeCall(writer, receiver_name, go_name, "p", with_error, true);
            try writer.writeAll("\tif n == 0 && len(p) > 0 {\n\t\treturn 0, io.EOF\n\t}\n\treturn int(n), nil\n}\n");
        },
        .writer_to => {
            if (counts)
                try writer.writeAll("// The count is what the method reports.\n")
            else
                try writer.writeAll("// The count is what w received during the call.\n");
            try writer.print("func ({s} *{s}) WriteTo(w io.Writer) (int64, error) {{\n", .{ receiver_name, receiver });
            if (counts) {
                try writeCall(writer, receiver_name, go_name, "w", with_error, true);
                try writer.writeAll("\treturn int64(n), nil\n}\n");
            } else {
                try writer.writeAll("\tcounting := &zigoCountingWriter{w: w}\n");
                try writeCallCounting(writer, receiver_name, go_name, "counting", with_error);
            }
        },
        .reader_from => {
            if (counts)
                try writer.writeAll("// The count is what the method reports.\n")
            else
                try writer.writeAll("// The count is what r handed over during the call.\n");
            try writer.print("func ({s} *{s}) ReadFrom(r io.Reader) (int64, error) {{\n", .{ receiver_name, receiver });
            if (counts) {
                try writeCall(writer, receiver_name, go_name, "r", with_error, true);
                try writer.writeAll("\treturn int64(n), nil\n}\n");
            } else {
                try writer.writeAll("\tcounting := &zigoCountingReader{r: r}\n");
                try writeCallCounting(writer, receiver_name, go_name, "counting", with_error);
            }
        },
    }
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
        if (function.origin.implements == kind and function.origin.@"return".errorPayload() == .void) return true;
    }
    return false;
}
/// An `.implements` wrapper calls the public method with the interface's
/// arguments and adapts its result, so the method has to be a handle method
/// whose Go shape is one step from the interface: the single parameter the
/// interface passes, and a `void` or integer result.
pub fn implementsIssue(allocator: std.mem.Allocator, function: semantic.SemanticFn) !?diagnostic.Diagnostic {
    const implements = function.implements orelse return null;
    const interface = implements.interfaceName();
    if (function.receiver == null) return .{
        .severity = .@"error",
        .code = "ZIGO058",
        .message = try std.fmt.allocPrint(allocator, "`.implements = .{s}` on `{s}`, which has no receiver", .{ @tagName(implements), function.name }),
        .site = site.functionSite(function),
        .hint = try std.fmt.allocPrint(allocator, "`{s}` is satisfied by a method; move `.implements` to a method of a registered opaque type", .{interface}),
    };
    const receiver = function.receiver.?;
    if (function.iterator != null or function.cancel != null) return .{
        .severity = .@"error",
        .code = "ZIGO058",
        .message = try std.fmt.allocPrint(allocator, "`.implements = .{s}` on `{s}.{s}`, which also has `{s}`", .{ @tagName(implements), receiver, function.name, if (function.iterator != null) "`.iterator`" else "`.cancel`" }),
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
        .reader => "one `.out` `[]u8` parameter with `.written = .result`",
        .writer_to => "one `*std.Io.Writer` parameter",
        .reader_from => "one `*std.Io.Reader` parameter",
    };
    const shape_ok = data_count == 1 and switch (implements) {
        .writer => data.?.direction == .in and data.?.type == .slice and semantic.isByte(data.?.type.slice.element.*) and !semantic.isTextHint(data.?.semantic),
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
