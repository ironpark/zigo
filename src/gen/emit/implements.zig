//! The `.implements` wrappers: the method a Go standard interface requires,
//! added next to a bound handle method and calling it.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");

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
