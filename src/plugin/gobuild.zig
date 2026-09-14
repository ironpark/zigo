//! A small Go AST for plugins: declarations, statements and expressions a
//! hook composes instead of printing Go source. Nodes are values; the slices
//! a `Builder` method is given are copied into the run arena, so a tree built
//! inside a loop stays valid until it is rendered.
//!
//! Rendering is deterministic and indents with tabs, the way the generated
//! tree is already written, so `gofmt` leaves the result alone. The generator
//! answers for anything a plugin cannot spell on its own -- type names, public
//! signatures, parameter names -- through the writers behind `plugin.Context`,
//! which `Expr.typeName`, `Expr.valueType` and `Signature.function` reach.
const std = @import("std");
const abi = @import("abi");
const naming = @import("naming");
const semantic = @import("semantic");
const plugin = @import("../plugin.zig");

/// A doc comment above a declaration, a struct field or an interface method.
pub const Doc = union(enum) {
    none,
    /// Comment text without markers. Every line becomes `// line`; an empty
    /// line becomes `//`.
    text: []const u8,
    /// Lines that already carry their `//` markers, written as they are.
    rendered: []const u8,
};

/// A Go expression. `raw` is the escape hatch for the rare spelling the other
/// nodes do not cover; everything else renders from structure.
pub const Expr = union(enum) {
    raw: []const u8,
    ident: []const u8,
    /// Rendered as an interpreted Go string literal, quotes and escapes included.
    string: []const u8,
    int: i128,
    boolean: bool,
    nil,
    /// A generated type as this package spells it, qualified when it lives in
    /// another generated package.
    type_name: []const u8,
    /// The Go spelling of a semantic type node.
    go_type: semantic.TypeNode,
    /// The Go type of the value a public function hands back.
    value_type: abi.AbiFn,
    selector: struct { target: *const Expr, field: []const u8 },
    /// `x[i]`, and the type argument list of a generic type.
    index: struct { target: *const Expr, indices: []const Expr },
    call: struct { callee: *const Expr, args: Args, ellipsis: bool = false },
    unary: struct { op: []const u8, operand: *const Expr },
    binary: struct { op: []const u8, left: *const Expr, right: *const Expr },
    paren: *const Expr,
    /// `*T` in type position.
    pointer: *const Expr,
    /// `[]T` in type position.
    slice: *const Expr,
    /// `...T` in a parameter list.
    variadic: *const Expr,
    func_type: struct { params: []const Param, results: []const Expr },
    func_literal: struct { params: []const Param, results: []const Expr, body: []const Stmt },
    composite: struct { type: ?*const Expr, elements: []const Element, multiline: bool = false },

    /// A call's arguments: written out, or the public call arguments of a
    /// generated function, which only the generator can name.
    pub const Args = union(enum) { list: []const Expr, function: abi.AbiFn };
    pub const Element = struct { key: ?[]const u8 = null, value: Expr };
};

/// One group of a parameter list: the names that share a type, then the type.
/// An empty name list writes the type alone, which is what an interface
/// method and a func type do.
pub const Param = struct { names: []const []const u8 = &.{}, type: Expr };

/// A parameter list and result, either written out or taken from the public
/// signature the generator gives a function.
pub const Signature = union(enum) {
    explicit: struct { params: []const Param = &.{}, results: []const Expr = &.{} },
    function: struct { function: abi.AbiFn, options: plugin.SignatureOptions = .{} },
};

pub const Stmt = union(enum) {
    raw: []const u8,
    comment: Doc,
    /// An empty line, which separates the parts of a long body.
    blank,
    expr: Expr,
    ret: []const Expr,
    assign: struct { lhs: []const Expr, op: []const u8, rhs: []const Expr },
    /// `var name T`, `var name T = value`, `var name = value`.
    declare: struct { name: []const u8, type: ?Expr, value: ?Expr },
    inc_dec: struct { target: *const Expr, op: []const u8 },
    if_stmt: If,
    switch_stmt: Switch,
    for_range: ForRange,
    for_loop: ForLoop,
    block: []const Stmt,
    defer_stmt: Expr,
    continue_stmt,
    break_stmt,

    pub const If = struct {
        init: ?*const Stmt = null,
        cond: Expr,
        body: []const Stmt,
        /// Another `if_stmt` for `else if`, or a `block` for a plain `else`.
        @"else": ?*const Stmt = null,
    };
    pub const Case = struct { values: []const Expr, body: []const Stmt };
    pub const Switch = struct { tag: ?Expr = null, cases: []const Case, default: ?[]const Stmt = null };
    pub const ForRange = struct { key: ?[]const u8 = null, value: ?[]const u8 = null, define: bool = true, over: Expr, body: []const Stmt };
    pub const ForLoop = struct { init: ?*const Stmt = null, cond: ?Expr = null, post: ?*const Stmt = null, body: []const Stmt };
};

pub const Field = struct { doc: Doc = .none, name: []const u8, type: Expr, tag: ?[]const u8 = null };
pub const InterfaceMethod = struct { doc: Doc = .none, name: []const u8, signature: Signature };

pub const TypeSpec = union(enum) {
    /// A definition or alias of another type: `type Seconds int64`.
    expr: Expr,
    @"struct": struct {
        fields: []const Field,
        /// Pad the names to one column, the way gofmt lays a block out.
        align_fields: bool = false,
    },
    interface: struct { methods: []const InterfaceMethod = &.{}, embeds: []const Expr = &.{} },
};

pub const Decl = union(enum) {
    /// A comment with no declaration under it.
    comment: Doc,
    raw: []const u8,
    func: Func,
    variable: Variable,
    constant: Variable,
    type_decl: TypeDecl,

    pub const Func = struct {
        doc: Doc = .none,
        receiver: ?plugin.Receiver = null,
        name: []const u8,
        signature: Signature = .{ .explicit = .{} },
        body: []const Stmt = &.{},
        /// Write the body between braces on the header line, the way a
        /// one-statement forwarding method is written.
        single_line: bool = false,
    };
    pub const Variable = struct { doc: Doc = .none, names: []const []const u8, type: ?Expr = null, value: ?Expr = null };
    pub const TypeDecl = struct { doc: Doc = .none, name: []const u8, alias: bool = false, spec: TypeSpec };
};

/// How a group of declarations is spaced.
pub const Layout = struct {
    blank_before: bool = false,
    blank_after: bool = false,
    blank_between: bool = true,
};

/// `text` as an interpreted Go string literal. Quotes, backslashes and the
/// common control characters take their short escapes; any other control byte
/// is written as `\xNN`. Bytes above ASCII pass through, so UTF-8 text reads
/// as it was written.
pub fn writeStringLiteral(writer: *std.Io.Writer, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |byte| switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\t' => try writer.writeAll("\\t"),
        '\r' => try writer.writeAll("\\r"),
        0...8, 11, 12, 14...31, 127 => try writer.print("\\x{x:0>2}", .{byte}),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

/// Builds and renders Go nodes. Every constructor copies the slices it is
/// given into the context's arena, so a node outlives the array literal it
/// was built from.
pub const Builder = struct {
    allocator: std.mem.Allocator,
    context: plugin.Context,
    /// Where `emit` writes: the buffer the generator flushes at the insertion
    /// point of the node being visited. It is null on the builder a plugin
    /// makes for one of its own files, which renders into the writer that file
    /// was handed.
    out: ?*std.Io.Writer = null,

    // -- rendering -----------------------------------------------------

    /// Writes `decls` into this visit's output. The generator flushes it at
    /// the insertion point of the node the visit was called for.
    pub fn emit(self: Builder, decls: []const Decl, layout: Layout) !void {
        return self.render(try self.output(), decls, layout);
    }

    /// This visit's output itself, for the rare hook that writes text no node
    /// spells. `emit` is how a plugin writes Go.
    pub fn output(self: Builder) !*std.Io.Writer {
        return self.out orelse error.NoBuilderOutput;
    }

    /// Writes `decls` in order, spaced by `layout`.
    pub fn render(self: Builder, writer: *std.Io.Writer, decls: []const Decl, layout: Layout) !void {
        if (decls.len == 0) return;
        if (layout.blank_before) try writer.writeByte('\n');
        for (decls, 0..) |decl, index| {
            if (index != 0 and layout.blank_between) try writer.writeByte('\n');
            try self.renderDecl(writer, decl);
        }
        if (layout.blank_after) try writer.writeByte('\n');
    }

    /// One declaration, with its doc comment and a trailing newline.
    pub fn renderDecl(self: Builder, writer: *std.Io.Writer, decl: Decl) anyerror!void {
        switch (decl) {
            .comment => |doc| try self.writeDoc(writer, doc, 0),
            .raw => |text| try writer.writeAll(text),
            .func => |value| try self.renderFunc(writer, value),
            .variable => |value| try self.renderVariable(writer, value, "var"),
            .constant => |value| try self.renderVariable(writer, value, "const"),
            .type_decl => |value| try self.renderTypeDecl(writer, value),
        }
    }

    /// The number of results the public signature of `function` writes, which
    /// decides which forwarding helper a wrapper calls.
    pub fn resultCount(self: Builder, function: abi.AbiFn, options: plugin.ResultOptions) !usize {
        var buffer: std.Io.Writer.Allocating = .init(self.allocator);
        defer buffer.deinit();
        return self.context.writeResultType(&buffer.writer, function, options);
    }

    fn writeDoc(self: Builder, writer: *std.Io.Writer, doc: Doc, depth: usize) anyerror!void {
        _ = self;
        switch (doc) {
            .none => {},
            .text => |text| {
                var lines = std.mem.splitScalar(u8, text, '\n');
                while (lines.next()) |line| {
                    try indent(writer, depth);
                    try plugin.writeCommentLine(writer, line);
                }
            },
            .rendered => |text| {
                var lines = std.mem.splitScalar(u8, text, '\n');
                while (lines.next()) |line| {
                    try indent(writer, depth);
                    try writer.writeAll(line);
                    try writer.writeByte('\n');
                }
            },
        }
    }

    fn renderFunc(self: Builder, writer: *std.Io.Writer, value: Decl.Func) anyerror!void {
        try self.writeDoc(writer, value.doc, 0);
        try writer.writeAll("func ");
        if (value.receiver) |receiver| {
            try writer.print("({s} {s}{s}) ", .{ receiver.name, if (receiver.pointer) "*" else "", receiver.type });
        }
        try writer.writeAll(value.name);
        try self.renderSignature(writer, value.signature);
        if (value.single_line) {
            try writer.writeAll(" { ");
            for (value.body, 0..) |statement, index| {
                if (index != 0) try writer.writeAll("; ");
                try self.renderStmtInline(writer, statement);
            }
            try writer.writeAll(" }\n");
            return;
        }
        try writer.writeAll(" {\n");
        try self.renderBody(writer, value.body, 1);
        try writer.writeAll("}\n");
    }

    fn renderVariable(self: Builder, writer: *std.Io.Writer, value: Decl.Variable, keyword: []const u8) anyerror!void {
        try self.writeDoc(writer, value.doc, 0);
        try writer.writeAll(keyword);
        for (value.names, 0..) |name, index| {
            try writer.writeAll(if (index == 0) " " else ", ");
            try writer.writeAll(name);
        }
        if (value.type) |node| {
            try writer.writeByte(' ');
            try self.renderExpr(writer, node, 0);
        }
        if (value.value) |node| {
            try writer.writeAll(" = ");
            try self.renderExpr(writer, node, 0);
        }
        try writer.writeByte('\n');
    }

    fn renderTypeDecl(self: Builder, writer: *std.Io.Writer, value: Decl.TypeDecl) anyerror!void {
        try self.writeDoc(writer, value.doc, 0);
        try writer.print("type {s} {s}", .{ value.name, if (value.alias) "= " else "" });
        switch (value.spec) {
            .expr => |node| {
                try self.renderExpr(writer, node, 0);
                try writer.writeByte('\n');
            },
            .@"struct" => |spec| {
                try writer.writeAll("struct {\n");
                var width: usize = 0;
                if (spec.align_fields) for (spec.fields) |field| {
                    width = @max(width, field.name.len);
                };
                for (spec.fields) |field| {
                    try self.writeDoc(writer, field.doc, 1);
                    try writer.writeByte('\t');
                    try writer.writeAll(field.name);
                    try writer.splatByteAll(' ', @max(width, field.name.len) - field.name.len + 1);
                    try self.renderExpr(writer, field.type, 1);
                    if (field.tag) |tag| try writer.print(" `{s}`", .{tag});
                    try writer.writeByte('\n');
                }
                try writer.writeAll("}\n");
            },
            .interface => |spec| {
                try writer.writeAll("interface {\n");
                for (spec.methods) |method| {
                    try self.writeDoc(writer, method.doc, 1);
                    try writer.print("\t{s}", .{method.name});
                    try self.renderSignature(writer, method.signature);
                    try writer.writeByte('\n');
                }
                for (spec.embeds) |embed| {
                    try writer.writeByte('\t');
                    try self.renderExpr(writer, embed, 1);
                    try writer.writeByte('\n');
                }
                try writer.writeAll("}\n");
            },
        }
    }

    fn renderSignature(self: Builder, writer: *std.Io.Writer, signature: Signature) anyerror!void {
        switch (signature) {
            .function => |spec| try self.context.writeSignatureWith(writer, spec.function, spec.options),
            .explicit => |spec| {
                try self.renderParams(writer, spec.params);
                try self.renderResults(writer, spec.results);
            },
        }
    }

    fn renderParams(self: Builder, writer: *std.Io.Writer, params: []const Param) anyerror!void {
        try writer.writeByte('(');
        for (params, 0..) |param, index| {
            if (index != 0) try writer.writeAll(", ");
            for (param.names, 0..) |name, name_index| {
                if (name_index != 0) try writer.writeAll(", ");
                try writer.writeAll(name);
            }
            if (param.names.len != 0) try writer.writeByte(' ');
            try self.renderExpr(writer, param.type, 0);
        }
        try writer.writeByte(')');
    }

    fn renderResults(self: Builder, writer: *std.Io.Writer, results: []const Expr) anyerror!void {
        if (results.len == 0) return;
        try writer.writeByte(' ');
        if (results.len == 1) return self.renderExpr(writer, results[0], 0);
        try writer.writeByte('(');
        for (results, 0..) |result, index| {
            if (index != 0) try writer.writeAll(", ");
            try self.renderExpr(writer, result, 0);
        }
        try writer.writeByte(')');
    }

    fn renderBody(self: Builder, writer: *std.Io.Writer, body: []const Stmt, depth: usize) anyerror!void {
        for (body) |statement| try self.renderStmt(writer, statement, depth);
    }

    fn renderStmt(self: Builder, writer: *std.Io.Writer, statement: Stmt, depth: usize) anyerror!void {
        switch (statement) {
            .blank => return writer.writeByte('\n'),
            .comment => |doc| return self.writeDoc(writer, doc, depth),
            .block => |body| {
                try indent(writer, depth);
                try writer.writeAll("{\n");
                try self.renderBody(writer, body, depth + 1);
                try indent(writer, depth);
                return writer.writeAll("}\n");
            },
            .if_stmt => {
                try indent(writer, depth);
                try self.renderIf(writer, statement.if_stmt, depth);
                return writer.writeByte('\n');
            },
            .switch_stmt => |spec| {
                try indent(writer, depth);
                try writer.writeAll("switch");
                if (spec.tag) |tag| {
                    try writer.writeByte(' ');
                    try self.renderExpr(writer, tag, depth);
                }
                try writer.writeAll(" {\n");
                for (spec.cases) |case| {
                    try indent(writer, depth);
                    try writer.writeAll("case ");
                    for (case.values, 0..) |value, index| {
                        if (index != 0) try writer.writeAll(", ");
                        try self.renderExpr(writer, value, depth);
                    }
                    try writer.writeAll(":\n");
                    try self.renderBody(writer, case.body, depth + 1);
                }
                if (spec.default) |body| {
                    try indent(writer, depth);
                    try writer.writeAll("default:\n");
                    try self.renderBody(writer, body, depth + 1);
                }
                try indent(writer, depth);
                return writer.writeAll("}\n");
            },
            .for_range => |spec| {
                try indent(writer, depth);
                try writer.writeAll("for ");
                if (spec.key != null or spec.value != null) {
                    try writer.writeAll(spec.key orelse "_");
                    if (spec.value) |value| try writer.print(", {s}", .{value});
                    try writer.writeAll(if (spec.define) " := " else " = ");
                }
                try writer.writeAll("range ");
                try self.renderExpr(writer, spec.over, depth);
                try writer.writeAll(" {\n");
                try self.renderBody(writer, spec.body, depth + 1);
                try indent(writer, depth);
                return writer.writeAll("}\n");
            },
            .for_loop => |spec| {
                try indent(writer, depth);
                try writer.writeAll("for");
                if (spec.init != null or spec.post != null) {
                    try writer.writeByte(' ');
                    if (spec.init) |init| try self.renderStmtInline(writer, init.*);
                    try writer.writeAll("; ");
                    if (spec.cond) |cond| try self.renderExpr(writer, cond, depth);
                    try writer.writeAll("; ");
                    if (spec.post) |post| try self.renderStmtInline(writer, post.*);
                } else if (spec.cond) |cond| {
                    try writer.writeByte(' ');
                    try self.renderExpr(writer, cond, depth);
                }
                try writer.writeAll(" {\n");
                try self.renderBody(writer, spec.body, depth + 1);
                try indent(writer, depth);
                return writer.writeAll("}\n");
            },
            else => {
                try indent(writer, depth);
                try self.renderStmtInlineAt(writer, statement, depth);
                return writer.writeByte('\n');
            },
        }
    }

    fn renderIf(self: Builder, writer: *std.Io.Writer, spec: Stmt.If, depth: usize) anyerror!void {
        try writer.writeAll("if ");
        if (spec.init) |init| {
            try self.renderStmtInline(writer, init.*);
            try writer.writeAll("; ");
        }
        try self.renderExpr(writer, spec.cond, depth);
        try writer.writeAll(" {\n");
        try self.renderBody(writer, spec.body, depth + 1);
        try indent(writer, depth);
        try writer.writeByte('}');
        const otherwise = spec.@"else" orelse return;
        try writer.writeAll(" else ");
        switch (otherwise.*) {
            .if_stmt => |nested| try self.renderIf(writer, nested, depth),
            .block => |body| {
                try writer.writeAll("{\n");
                try self.renderBody(writer, body, depth + 1);
                try indent(writer, depth);
                try writer.writeByte('}');
            },
            else => return error.InvalidGoElse,
        }
    }

    fn renderStmtInline(self: Builder, writer: *std.Io.Writer, statement: Stmt) anyerror!void {
        return self.renderStmtInlineAt(writer, statement, 0);
    }

    /// A statement with neither indentation nor a trailing newline: an `if`
    /// initializer, a `for` clause, or a one-line body.
    fn renderStmtInlineAt(self: Builder, writer: *std.Io.Writer, statement: Stmt, depth: usize) anyerror!void {
        switch (statement) {
            .raw => |text| try writer.writeAll(text),
            .expr => |node| try self.renderExpr(writer, node, depth),
            .ret => |values| {
                try writer.writeAll("return");
                for (values, 0..) |value, index| {
                    try writer.writeAll(if (index == 0) " " else ", ");
                    try self.renderExpr(writer, value, depth);
                }
            },
            .assign => |spec| {
                for (spec.lhs, 0..) |node, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try self.renderExpr(writer, node, depth);
                }
                try writer.print(" {s} ", .{spec.op});
                for (spec.rhs, 0..) |node, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try self.renderExpr(writer, node, depth);
                }
            },
            .declare => |spec| {
                try writer.print("var {s}", .{spec.name});
                if (spec.type) |node| {
                    try writer.writeByte(' ');
                    try self.renderExpr(writer, node, depth);
                }
                if (spec.value) |node| {
                    try writer.writeAll(" = ");
                    try self.renderExpr(writer, node, depth);
                }
            },
            .inc_dec => |spec| {
                try self.renderExpr(writer, spec.target.*, depth);
                try writer.writeAll(spec.op);
            },
            .defer_stmt => |node| {
                try writer.writeAll("defer ");
                try self.renderExpr(writer, node, depth);
            },
            .continue_stmt => try writer.writeAll("continue"),
            .break_stmt => try writer.writeAll("break"),
            else => return error.InvalidGoInlineStatement,
        }
    }

    fn renderExpr(self: Builder, writer: *std.Io.Writer, node: Expr, depth: usize) anyerror!void {
        switch (node) {
            .raw, .ident => |text| try writer.writeAll(text),
            .string => |text| try writeStringLiteral(writer, text),
            .int => |value| try writer.print("{d}", .{value}),
            .boolean => |value| try writer.writeAll(if (value) "true" else "false"),
            .nil => try writer.writeAll("nil"),
            .type_name => |name| try self.context.writeTypeName(writer, name),
            .go_type => |type_node| try self.context.writeGoType(writer, type_node),
            .value_type => |function| try self.context.writeValueType(writer, function),
            .selector => |spec| {
                try self.renderExpr(writer, spec.target.*, depth);
                try writer.print(".{s}", .{spec.field});
            },
            .index => |spec| {
                try self.renderExpr(writer, spec.target.*, depth);
                try writer.writeByte('[');
                for (spec.indices, 0..) |argument, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try self.renderExpr(writer, argument, depth);
                }
                try writer.writeByte(']');
            },
            .call => |spec| {
                try self.renderExpr(writer, spec.callee.*, depth);
                try writer.writeByte('(');
                switch (spec.args) {
                    .function => |function| try self.context.writeCallArguments(writer, function),
                    .list => |args| for (args, 0..) |argument, index| {
                        if (index != 0) try writer.writeAll(", ");
                        try self.renderExpr(writer, argument, depth);
                    },
                }
                if (spec.ellipsis) try writer.writeAll("...");
                try writer.writeByte(')');
            },
            .unary => |spec| {
                try writer.writeAll(spec.op);
                try self.renderExpr(writer, spec.operand.*, depth);
            },
            .binary => |spec| {
                try self.renderExpr(writer, spec.left.*, depth);
                try writer.print(" {s} ", .{spec.op});
                try self.renderExpr(writer, spec.right.*, depth);
            },
            .paren => |inner| {
                try writer.writeByte('(');
                try self.renderExpr(writer, inner.*, depth);
                try writer.writeByte(')');
            },
            .pointer => |inner| {
                try writer.writeByte('*');
                try self.renderExpr(writer, inner.*, depth);
            },
            .slice => |inner| {
                try writer.writeAll("[]");
                try self.renderExpr(writer, inner.*, depth);
            },
            .variadic => |inner| {
                try writer.writeAll("...");
                try self.renderExpr(writer, inner.*, depth);
            },
            .func_type => |spec| {
                try writer.writeAll("func");
                try self.renderParams(writer, spec.params);
                try self.renderResults(writer, spec.results);
            },
            .func_literal => |spec| {
                try writer.writeAll("func");
                try self.renderParams(writer, spec.params);
                try self.renderResults(writer, spec.results);
                try writer.writeAll(" {\n");
                try self.renderBody(writer, spec.body, depth + 1);
                try indent(writer, depth);
                try writer.writeByte('}');
            },
            .composite => |spec| {
                if (spec.type) |type_node| try self.renderExpr(writer, type_node.*, depth);
                try writer.writeByte('{');
                if (spec.multiline) {
                    try writer.writeByte('\n');
                    for (spec.elements) |element| {
                        try indent(writer, depth + 1);
                        if (element.key) |key| try writer.print("{s}: ", .{key});
                        try self.renderExpr(writer, element.value, depth + 1);
                        try writer.writeAll(",\n");
                    }
                    try indent(writer, depth);
                } else for (spec.elements, 0..) |element, index| {
                    if (index != 0) try writer.writeAll(", ");
                    if (element.key) |key| try writer.print("{s}: ", .{key});
                    try self.renderExpr(writer, element.value, depth);
                }
                try writer.writeByte('}');
            },
        }
    }

    // -- expressions ---------------------------------------------------

    pub fn ident(_: Builder, name: []const u8) Expr {
        return .{ .ident = name };
    }
    pub fn raw(_: Builder, text: []const u8) Expr {
        return .{ .raw = text };
    }
    pub fn string(_: Builder, text: []const u8) Expr {
        return .{ .string = text };
    }
    pub fn int(_: Builder, value: i128) Expr {
        return .{ .int = value };
    }
    pub fn boolean(_: Builder, value: bool) Expr {
        return .{ .boolean = value };
    }
    pub fn typeName(_: Builder, name: []const u8) Expr {
        return .{ .type_name = name };
    }
    pub fn goType(_: Builder, node: semantic.TypeNode) Expr {
        return .{ .go_type = node };
    }
    pub fn valueType(_: Builder, function: abi.AbiFn) Expr {
        return .{ .value_type = function };
    }

    pub fn sel(self: Builder, target: Expr, field: []const u8) !Expr {
        return .{ .selector = .{ .target = try self.box(target), .field = field } };
    }
    /// `qualifier.field`, the spelling a package-qualified name has.
    pub fn selName(self: Builder, qualifier: []const u8, field: []const u8) !Expr {
        return self.sel(self.ident(qualifier), field);
    }
    pub fn indexExpr(self: Builder, target: Expr, indices: []const Expr) !Expr {
        return .{ .index = .{ .target = try self.box(target), .indices = try self.dupExprs(indices) } };
    }
    pub fn call(self: Builder, callee: Expr, args: []const Expr) !Expr {
        return .{ .call = .{ .callee = try self.box(callee), .args = .{ .list = try self.dupExprs(args) } } };
    }
    pub fn callName(self: Builder, name: []const u8, args: []const Expr) !Expr {
        return self.call(self.ident(name), args);
    }
    pub fn callSel(self: Builder, target: Expr, method: []const u8, args: []const Expr) !Expr {
        return self.call(try self.sel(target, method), args);
    }
    /// A call spread over its last argument: `errors.Join(failures...)`.
    pub fn callSpread(self: Builder, callee: Expr, args: []const Expr) !Expr {
        return .{ .call = .{ .callee = try self.box(callee), .args = .{ .list = try self.dupExprs(args) }, .ellipsis = true } };
    }
    /// A call whose arguments are the public call arguments of `function`,
    /// which only the generator can name.
    pub fn callForwarding(self: Builder, callee: Expr, function: abi.AbiFn) !Expr {
        return .{ .call = .{ .callee = try self.box(callee), .args = .{ .function = function } } };
    }
    pub fn unary(self: Builder, op: []const u8, operand: Expr) !Expr {
        return .{ .unary = .{ .op = op, .operand = try self.box(operand) } };
    }
    pub fn addr(self: Builder, operand: Expr) !Expr {
        return self.unary("&", operand);
    }
    pub fn deref(self: Builder, operand: Expr) !Expr {
        return self.unary("*", operand);
    }
    pub fn not(self: Builder, operand: Expr) !Expr {
        return self.unary("!", operand);
    }
    pub fn bin(self: Builder, op: []const u8, left: Expr, right: Expr) !Expr {
        return .{ .binary = .{ .op = op, .left = try self.box(left), .right = try self.box(right) } };
    }
    pub fn paren(self: Builder, inner: Expr) !Expr {
        return .{ .paren = try self.box(inner) };
    }
    pub fn ptr(self: Builder, inner: Expr) !Expr {
        return .{ .pointer = try self.box(inner) };
    }
    pub fn sliceOf(self: Builder, inner: Expr) !Expr {
        return .{ .slice = try self.box(inner) };
    }
    pub fn variadic(self: Builder, inner: Expr) !Expr {
        return .{ .variadic = try self.box(inner) };
    }
    /// `(T)(value)`: the conversion form a pointer type needs parentheses for.
    pub fn convert(self: Builder, target: Expr, value: Expr) !Expr {
        return self.call(try self.paren(target), &.{value});
    }
    pub fn funcType(self: Builder, params: []const Param, results: []const Expr) !Expr {
        return .{ .func_type = .{ .params = try self.dupParams(params), .results = try self.dupExprs(results) } };
    }
    pub fn funcLiteral(self: Builder, params: []const Param, results: []const Expr, body: []const Stmt) !Expr {
        return .{ .func_literal = .{ .params = try self.dupParams(params), .results = try self.dupExprs(results), .body = try self.dupStmts(body) } };
    }
    pub fn composite(self: Builder, type_node: ?Expr, elements: []const Expr.Element) !Expr {
        return .{ .composite = .{ .type = if (type_node) |node| try self.box(node) else null, .elements = try self.dupElements(elements) } };
    }
    pub fn compositeLines(self: Builder, type_node: ?Expr, elements: []const Expr.Element) !Expr {
        return .{ .composite = .{ .type = if (type_node) |node| try self.box(node) else null, .elements = try self.dupElements(elements), .multiline = true } };
    }

    // -- statements ----------------------------------------------------

    pub fn exprStmt(_: Builder, node: Expr) Stmt {
        return .{ .expr = node };
    }
    pub fn rawStmt(_: Builder, text: []const u8) Stmt {
        return .{ .raw = text };
    }
    pub fn commentStmt(_: Builder, text: []const u8) Stmt {
        return .{ .comment = .{ .text = text } };
    }
    pub fn blankLine(_: Builder) Stmt {
        return .blank;
    }
    pub fn ret(self: Builder, values: []const Expr) !Stmt {
        return .{ .ret = try self.dupExprs(values) };
    }
    pub fn assign(self: Builder, lhs: []const Expr, op: []const u8, rhs: []const Expr) !Stmt {
        return .{ .assign = .{ .lhs = try self.dupExprs(lhs), .op = op, .rhs = try self.dupExprs(rhs) } };
    }
    /// `names... := value`.
    pub fn define(self: Builder, names: []const []const u8, value: Expr) !Stmt {
        const lhs = try self.allocator.alloc(Expr, names.len);
        for (lhs, names) |*node, name| node.* = self.ident(name);
        return .{ .assign = .{ .lhs = lhs, .op = ":=", .rhs = try self.dupExprs(&.{value}) } };
    }
    pub fn declare(_: Builder, name: []const u8, type_node: ?Expr, value: ?Expr) Stmt {
        return .{ .declare = .{ .name = name, .type = type_node, .value = value } };
    }
    pub fn incDec(self: Builder, target: Expr, op: []const u8) !Stmt {
        return .{ .inc_dec = .{ .target = try self.box(target), .op = op } };
    }
    pub fn deferStmt(_: Builder, node: Expr) Stmt {
        return .{ .defer_stmt = node };
    }
    pub fn block(self: Builder, body: []const Stmt) !Stmt {
        return .{ .block = try self.dupStmts(body) };
    }

    /// `if [init; ]cond { body }`, with an optional `else` branch. Pass
    /// another `if` statement as `otherwise` for `else if`.
    pub fn ifStmt(self: Builder, spec: struct {
        init: ?Stmt = null,
        cond: Expr,
        body: []const Stmt,
        else_body: ?[]const Stmt = null,
        otherwise: ?Stmt = null,
    }) !Stmt {
        const branch: ?Stmt = if (spec.otherwise) |value| value else if (spec.else_body) |body| try self.block(body) else null;
        return .{ .if_stmt = .{
            .init = if (spec.init) |value| try self.boxStmt(value) else null,
            .cond = spec.cond,
            .body = try self.dupStmts(spec.body),
            .@"else" = if (branch) |value| try self.boxStmt(value) else null,
        } };
    }

    pub fn switchStmt(self: Builder, spec: struct { tag: ?Expr = null, cases: []const Stmt.Case, default: ?[]const Stmt = null }) !Stmt {
        const cases = try self.allocator.alloc(Stmt.Case, spec.cases.len);
        for (cases, spec.cases) |*entry, source| {
            entry.* = .{ .values = try self.dupExprs(source.values), .body = try self.dupStmts(source.body) };
        }
        return .{ .switch_stmt = .{
            .tag = spec.tag,
            .cases = cases,
            .default = if (spec.default) |body| try self.dupStmts(body) else null,
        } };
    }

    pub fn forRange(self: Builder, spec: struct { key: ?[]const u8 = null, value: ?[]const u8 = null, define: bool = true, over: Expr, body: []const Stmt }) !Stmt {
        return .{ .for_range = .{ .key = spec.key, .value = spec.value, .define = spec.define, .over = spec.over, .body = try self.dupStmts(spec.body) } };
    }

    pub fn forLoop(self: Builder, spec: struct { init: ?Stmt = null, cond: ?Expr = null, post: ?Stmt = null, body: []const Stmt }) !Stmt {
        return .{ .for_loop = .{
            .init = if (spec.init) |value| try self.boxStmt(value) else null,
            .cond = spec.cond,
            .post = if (spec.post) |value| try self.boxStmt(value) else null,
            .body = try self.dupStmts(spec.body),
        } };
    }

    /// `for { body }`.
    pub fn forever(self: Builder, body: []const Stmt) !Stmt {
        return self.forLoop(.{ .body = body });
    }

    // -- declarations --------------------------------------------------

    pub fn func(self: Builder, spec: Decl.Func) !Decl {
        var value = spec;
        value.body = try self.dupStmts(spec.body);
        if (spec.signature == .explicit) value.signature = .{ .explicit = .{
            .params = try self.dupParams(spec.signature.explicit.params),
            .results = try self.dupExprs(spec.signature.explicit.results),
        } };
        return .{ .func = value };
    }

    pub fn variable(self: Builder, spec: Decl.Variable) !Decl {
        var value = spec;
        value.names = try self.dupNames(spec.names);
        return .{ .variable = value };
    }

    pub fn constant(self: Builder, spec: Decl.Variable) !Decl {
        var value = spec;
        value.names = try self.dupNames(spec.names);
        return .{ .constant = value };
    }

    pub fn structDecl(self: Builder, spec: struct { doc: Doc = .none, name: []const u8, fields: []const Field, align_fields: bool = false }) !Decl {
        const fields = try self.allocator.dupe(Field, spec.fields);
        return .{ .type_decl = .{ .doc = spec.doc, .name = spec.name, .spec = .{ .@"struct" = .{ .fields = fields, .align_fields = spec.align_fields } } } };
    }

    pub fn interfaceDecl(self: Builder, spec: struct { doc: Doc = .none, name: []const u8, methods: []const InterfaceMethod = &.{}, embeds: []const Expr = &.{} }) !Decl {
        return .{ .type_decl = .{ .doc = spec.doc, .name = spec.name, .spec = .{ .interface = .{
            .methods = try self.allocator.dupe(InterfaceMethod, spec.methods),
            .embeds = try self.dupExprs(spec.embeds),
        } } } };
    }

    pub fn typeDecl(_: Builder, spec: Decl.TypeDecl) Decl {
        return .{ .type_decl = spec };
    }

    /// `var _ I = (*T)(nil)` or `var _ I = *new(T)`: the compile-time
    /// assertion that a generated type implements an interface.
    pub fn assertImplements(self: Builder, spec: struct { doc: Doc = .none, interface: Expr, type_name: []const u8, form: enum { pointer, value } = .pointer }) !Decl {
        const value = switch (spec.form) {
            .pointer => try self.convert(try self.ptr(self.ident(spec.type_name)), .nil),
            .value => try self.deref(try self.callName("new", &.{self.ident(spec.type_name)})),
        };
        return self.variable(.{ .doc = spec.doc, .names = &.{"_"}, .type = spec.interface, .value = value });
    }

    // -- arena helpers -------------------------------------------------

    pub fn dupExprs(self: Builder, list: []const Expr) ![]const Expr {
        return self.allocator.dupe(Expr, list);
    }
    pub fn dupStmts(self: Builder, list: []const Stmt) ![]const Stmt {
        return self.allocator.dupe(Stmt, list);
    }
    pub fn dupParams(self: Builder, list: []const Param) ![]const Param {
        const copy = try self.allocator.dupe(Param, list);
        for (copy) |*param| param.names = try self.dupNames(param.names);
        return copy;
    }
    pub fn dupElements(self: Builder, list: []const Expr.Element) ![]const Expr.Element {
        return self.allocator.dupe(Expr.Element, list);
    }
    pub fn dupNames(self: Builder, list: []const []const u8) ![][]const u8 {
        return self.allocator.dupe([]const u8, list);
    }

    fn box(self: Builder, value: Expr) !*const Expr {
        const node = try self.allocator.create(Expr);
        node.* = value;
        return node;
    }
    fn boxStmt(self: Builder, value: Stmt) !*const Stmt {
        const node = try self.allocator.create(Stmt);
        node.* = value;
        return node;
    }
};

fn indent(writer: *std.Io.Writer, depth: usize) !void {
    try writer.splatByteAll('\t', depth);
}

// -- tests -------------------------------------------------------------

/// Writers that answer with fixed spellings, so the tests below check what the
/// builder does with a generator answer rather than what the generator says.
const test_writers: plugin.Writers = .{
    .writeTypeName = struct {
        fn f(_: plugin.Context, writer: *std.Io.Writer, name: []const u8) anyerror!void {
            return writer.print("other.{s}", .{name});
        }
    }.f,
    .writeGoType = struct {
        fn f(_: plugin.Context, writer: *std.Io.Writer, _: semantic.TypeNode) anyerror!void {
            return writer.writeAll("uint8");
        }
    }.f,
    .writeValueType = struct {
        fn f(_: plugin.Context, writer: *std.Io.Writer, _: abi.AbiFn) anyerror!void {
            return writer.writeAll("Payload");
        }
    }.f,
    .writeSignature = struct {
        fn f(_: plugin.Context, writer: *std.Io.Writer, _: abi.AbiFn, options: plugin.SignatureOptions) anyerror!void {
            return writer.writeAll(if (options.omit_error) "(count int) Payload" else "(count int) (Payload, error)");
        }
    }.f,
    .writeCallArguments = struct {
        fn f(_: plugin.Context, writer: *std.Io.Writer, _: abi.AbiFn) anyerror!void {
            return writer.writeAll("count");
        }
    }.f,
    .writeParameters = struct {
        fn f(_: plugin.Context, writer: *std.Io.Writer, _: abi.AbiFn) anyerror!void {
            return writer.writeAll("(count int)");
        }
    }.f,
    .writeResultType = struct {
        fn f(_: plugin.Context, writer: *std.Io.Writer, _: abi.AbiFn, options: plugin.ResultOptions) anyerror!usize {
            try writer.writeAll(if (options.omit_error) " Payload" else " (Payload, error)");
            return if (options.omit_error) 1 else 2;
        }
    }.f,
    .receiverNameAlloc = struct {
        fn f(_: plugin.Context, allocator: std.mem.Allocator, _: []const u8) anyerror![]u8 {
            return allocator.dupe(u8, "value");
        }
    }.f,
    .writeDoc = struct {
        fn f(writer: *std.Io.Writer, public_name: []const u8, _: []const u8, doc: []const u8) anyerror!void {
            return writer.print("// {s} {s}\n", .{ public_name, doc });
        }
    }.f,
    .functionInfo = struct {
        fn f(_: plugin.Context, _: abi.AbiFn) anyerror!plugin.FunctionInfo {
            return .{ .public_name = "Take", .is_public = true, .has_error = true };
        }
    }.f,
    .identifierAlloc = plugin.format.identifierAlloc,
};

fn testBuilder(allocator: std.mem.Allocator) Builder {
    const context: plugin.Context = .{
        .allocator = allocator,
        .program = .{ .package = "test", .prefix = "zg", .functions = &.{} },
        .options = .{},
        .writers = &test_writers,
    };
    return context.builder();
}

/// The stub writers above never read the function they are handed, so the
/// tests do not have to lower one to reach the nodes that carry it.
fn testFunction() abi.AbiFn {
    return undefined;
}

test "every expression kind renders" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const b = testBuilder(arena.allocator());
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const cases: []const struct { expected: []const u8, node: Expr } = &.{
        .{ .expected = "raw[0]", .node = b.raw("raw[0]") },
        .{ .expected = "name", .node = b.ident("name") },
        .{ .expected = "\"tab\\t\\\"q\\\"\"", .node = b.string("tab\t\"q\"") },
        .{ .expected = "-12", .node = b.int(-12) },
        .{ .expected = "true", .node = b.boolean(true) },
        .{ .expected = "nil", .node = .nil },
        .{ .expected = "other.Color", .node = b.typeName("Color") },
        .{ .expected = "uint8", .node = b.goType(.{ .int = .{ .bits = 8, .signed = false } }) },
        .{ .expected = "Payload", .node = b.valueType(testFunction()) },
        .{ .expected = "json.Marshal", .node = try b.selName("json", "Marshal") },
        .{ .expected = "items[index]", .node = try b.indexExpr(b.ident("items"), &.{b.ident("index")}) },
        .{ .expected = "iter.Seq2[Payload, error]", .node = try b.indexExpr(try b.selName("iter", "Seq2"), &.{ b.valueType(testFunction()), b.ident("error") }) },
        .{ .expected = "len(p)", .node = try b.callName("len", &.{b.ident("p")}) },
        .{ .expected = "s.Close()", .node = try b.callSel(b.ident("s"), "Close", &.{}) },
        .{ .expected = "errors.Join(failures...)", .node = try b.callSpread(try b.selName("errors", "Join"), &.{b.ident("failures")}) },
        .{ .expected = "s.take(count)", .node = try b.callForwarding(try b.selName("s", "take"), testFunction()) },
        .{ .expected = "&value", .node = try b.addr(b.ident("value")) },
        .{ .expected = "*value", .node = try b.deref(b.ident("value")) },
        .{ .expected = "!ok", .node = try b.not(b.ident("ok")) },
        .{ .expected = "a && b", .node = try b.bin("&&", b.ident("a"), b.ident("b")) },
        .{ .expected = "(a)", .node = try b.paren(b.ident("a")) },
        .{ .expected = "*Color", .node = try b.ptr(b.ident("Color")) },
        .{ .expected = "[]byte", .node = try b.sliceOf(b.ident("byte")) },
        .{ .expected = "...*Child", .node = try b.variadic(try b.ptr(b.ident("Child"))) },
        .{ .expected = "(*Color)(nil)", .node = try b.convert(try b.ptr(b.ident("Color")), .nil) },
        .{ .expected = "func(a int, b string) bool", .node = try b.funcType(&.{ .{ .names = &.{"a"}, .type = b.ident("int") }, .{ .names = &.{"b"}, .type = b.ident("string") } }, &.{b.ident("bool")}) },
        .{ .expected = "Color{Red: 1}", .node = try b.composite(b.ident("Color"), &.{.{ .key = "Red", .value = b.int(1) }}) },
        .{ .expected = "[]Mode{\n\tModeIdle,\n}", .node = try b.compositeLines(try b.sliceOf(b.ident("Mode")), &.{.{ .value = b.ident("ModeIdle") }}) },
    };
    for (cases) |case| {
        output.clearRetainingCapacity();
        try b.renderExpr(&output.writer, case.node, 0);
        try std.testing.expectEqualStrings(case.expected, output.written());
    }

    output.clearRetainingCapacity();
    try b.renderExpr(&output.writer, try b.funcLiteral(
        &.{.{ .names = &.{"yield"}, .type = try b.funcType(&.{.{ .type = b.ident("int") }}, &.{b.ident("bool")}) }},
        &.{},
        &.{try b.ret(&.{})},
    ), 0);
    try std.testing.expectEqualStrings("func(yield func(int) bool) {\n\treturn\n}", output.written());
}

test "every statement kind renders at its depth" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const b = testBuilder(arena.allocator());
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try b.renderBody(&output.writer, &.{
        b.rawStmt("raw := 1"),
        b.commentStmt("a comment"),
        .blank,
        b.exprStmt(try b.callName("work", &.{})),
        try b.ret(&.{ b.int(0), .nil }),
        try b.assign(&.{b.ident("total")}, "+=", &.{b.int(1)}),
        try b.define(&.{ "n", "err" }, try b.callName("read", &.{})),
        b.declare("zero", b.ident("Payload"), null),
        b.declare("count", null, b.int(2)),
        try b.incDec(b.ident("index"), "--"),
        b.deferStmt(try b.callSel(b.ident("mu"), "Unlock", &.{})),
        try b.ifStmt(.{
            .init = try b.define(&.{"err"}, try b.callName("read", &.{})),
            .cond = try b.bin("!=", b.ident("err"), .nil),
            .body = &.{try b.ret(&.{b.ident("err")})},
            .otherwise = try b.ifStmt(.{
                .cond = b.ident("ok"),
                .body = &.{.continue_stmt},
                .else_body = &.{.break_stmt},
            }),
        }),
        try b.switchStmt(.{
            .tag = b.ident("text"),
            .cases = &.{.{ .values = &.{ b.string("a"), b.string("b") }, .body = &.{try b.ret(&.{b.int(1)})} }},
            .default = &.{try b.ret(&.{b.int(0)})},
        }),
        try b.forRange(.{ .key = "_", .value = "handle", .over = b.ident("handles"), .body = &.{.continue_stmt} }),
        try b.forLoop(.{
            .init = try b.define(&.{"index"}, b.int(0)),
            .cond = try b.bin("<", b.ident("index"), b.int(3)),
            .post = try b.incDec(b.ident("index"), "++"),
            .body = &.{.break_stmt},
        }),
        try b.forever(&.{.break_stmt}),
        try b.block(&.{b.exprStmt(b.ident("scoped"))}),
    }, 1);
    try std.testing.expectEqualStrings(
        "\traw := 1\n" ++
            "\t// a comment\n" ++
            "\n" ++
            "\twork()\n" ++
            "\treturn 0, nil\n" ++
            "\ttotal += 1\n" ++
            "\tn, err := read()\n" ++
            "\tvar zero Payload\n" ++
            "\tvar count = 2\n" ++
            "\tindex--\n" ++
            "\tdefer mu.Unlock()\n" ++
            "\tif err := read(); err != nil {\n" ++
            "\t\treturn err\n" ++
            "\t} else if ok {\n" ++
            "\t\tcontinue\n" ++
            "\t} else {\n" ++
            "\t\tbreak\n" ++
            "\t}\n" ++
            "\tswitch text {\n" ++
            "\tcase \"a\", \"b\":\n" ++
            "\t\treturn 1\n" ++
            "\tdefault:\n" ++
            "\t\treturn 0\n" ++
            "\t}\n" ++
            "\tfor _, handle := range handles {\n" ++
            "\t\tcontinue\n" ++
            "\t}\n" ++
            "\tfor index := 0; index < 3; index++ {\n" ++
            "\t\tbreak\n" ++
            "\t}\n" ++
            "\tfor {\n" ++
            "\t\tbreak\n" ++
            "\t}\n" ++
            "\t{\n" ++
            "\t\tscoped\n" ++
            "\t}\n",
        output.written(),
    );
}

test "every declaration kind renders, with the layout the caller asked for" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const b = testBuilder(arena.allocator());
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try b.render(&output.writer, &.{
        .{ .comment = .{ .text = "a standalone comment\n\nafter a blank line" } },
        .{ .raw = "//go:generate something\n" },
        try b.constant(.{ .doc = .{ .text = "Name is the plugin's own." }, .names = &.{"Name"}, .value = b.string("TEST") }),
        try b.variable(.{ .names = &.{ "a", "b" }, .type = b.ident("int") }),
        b.typeDecl(.{ .name = "Seconds", .spec = .{ .expr = b.ident("int64") } }),
        b.typeDecl(.{ .name = "Alias", .alias = true, .spec = .{ .expr = try b.selName("time", "Duration") } }),
        try b.structDecl(.{
            .doc = .{ .text = "Wire is the shape on the wire." },
            .name = "Wire",
            .fields = &.{
                .{ .doc = .{ .text = "Red is the red channel." }, .name = "Red", .type = b.ident("uint8"), .tag = "json:\"red\"" },
                .{ .name = "Codepoint", .type = b.ident("rune") },
            },
        }),
        try b.structDecl(.{ .name = "Session", .align_fields = true, .fields = &.{
            .{ .name = "mu", .type = try b.selName("sync", "Mutex") },
            .{ .name = "closeOnce", .type = try b.selName("sync", "Once") },
        } }),
        try b.interfaceDecl(.{
            .name = "Batch",
            .methods = &.{
                .{ .doc = .{ .rendered = "// Len reports the count." }, .name = "Len", .signature = .{ .function = .{ .function = testFunction() } } },
                .{ .doc = .{ .text = "MustLen panics instead." }, .name = "MustLen", .signature = .{ .function = .{ .function = testFunction(), .options = .{ .omit_error = true } } } },
            },
            .embeds = &.{try b.selName("io", "Closer")},
        }),
        try b.func(.{
            .doc = .{ .text = "Take takes one." },
            .receiver = .{ .name = "s", .type = "Session", .pointer = true },
            .name = "Take",
            .signature = .{ .function = .{ .function = testFunction() } },
            .body = &.{try b.ret(&.{ b.ident("zero"), .nil })},
        }),
        try b.func(.{
            .name = "Reset",
            .body = &.{try b.ret(&.{})},
            .single_line = true,
        }),
        try b.assertImplements(.{ .interface = try b.selName("io", "Closer"), .type_name = "Session" }),
        try b.assertImplements(.{ .interface = try b.selName("fmt", "Stringer"), .type_name = "Mode", .form = .value }),
    }, .{ .blank_before = true, .blank_after = true });
    try std.testing.expectEqualStrings(
        "\n" ++
            "// a standalone comment\n" ++
            "//\n" ++
            "// after a blank line\n" ++
            "\n" ++
            "//go:generate something\n" ++
            "\n" ++
            "// Name is the plugin's own.\n" ++
            "const Name = \"TEST\"\n" ++
            "\n" ++
            "var a, b int\n" ++
            "\n" ++
            "type Seconds int64\n" ++
            "\n" ++
            "type Alias = time.Duration\n" ++
            "\n" ++
            "// Wire is the shape on the wire.\n" ++
            "type Wire struct {\n" ++
            "\t// Red is the red channel.\n" ++
            "\tRed uint8 `json:\"red\"`\n" ++
            "\tCodepoint rune\n" ++
            "}\n" ++
            "\n" ++
            "type Session struct {\n" ++
            "\tmu        sync.Mutex\n" ++
            "\tcloseOnce sync.Once\n" ++
            "}\n" ++
            "\n" ++
            "type Batch interface {\n" ++
            "\t// Len reports the count.\n" ++
            "\tLen(count int) (Payload, error)\n" ++
            "\t// MustLen panics instead.\n" ++
            "\tMustLen(count int) Payload\n" ++
            "\tio.Closer\n" ++
            "}\n" ++
            "\n" ++
            "// Take takes one.\n" ++
            "func (s *Session) Take(count int) (Payload, error) {\n" ++
            "\treturn zero, nil\n" ++
            "}\n" ++
            "\n" ++
            "func Reset() { return }\n" ++
            "\n" ++
            "var _ io.Closer = (*Session)(nil)\n" ++
            "\n" ++
            "var _ fmt.Stringer = *new(Mode)\n" ++
            "\n",
        output.written(),
    );
}

test "the result count of a public signature is the one the generator writes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const b = testBuilder(arena.allocator());
    try std.testing.expectEqual(@as(usize, 2), try b.resultCount(testFunction(), .{}));
    try std.testing.expectEqual(@as(usize, 1), try b.resultCount(testFunction(), .{ .omit_error = true }));
}

test "gofmt leaves a rendered file alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const b = testBuilder(allocator);
    var output: std.Io.Writer.Allocating = .init(allocator);
    try output.writer.writeAll("package sample\n\nimport (\n\t\"io\"\n\t\"sync\"\n)\n");
    try b.render(&output.writer, &.{
        try b.structDecl(.{ .name = "Session", .align_fields = true, .fields = &.{
            .{ .name = "mu", .type = try b.selName("sync", "Mutex") },
            .{ .name = "closeOnce", .type = try b.selName("sync", "Once") },
            .{ .name = "closed", .type = b.ident("bool") },
        } }),
        try b.func(.{
            .doc = .{ .text = "Close closes the session once." },
            .receiver = .{ .name = "s", .type = "Session", .pointer = true },
            .name = "Close",
            .signature = .{ .explicit = .{ .results = &.{b.ident("error")} } },
            .body = &.{
                b.exprStmt(try b.callSel(try b.selName("s", "mu"), "Lock", &.{})),
                b.deferStmt(try b.callSel(try b.selName("s", "mu"), "Unlock", &.{})),
                .blank,
                try b.ifStmt(.{
                    .cond = try b.selName("s", "closed"),
                    .body = &.{try b.ret(&.{.nil})},
                    .else_body = &.{try b.assign(&.{try b.selName("s", "closed")}, "=", &.{b.boolean(true)})},
                }),
                try b.forLoop(.{
                    .init = try b.define(&.{"index"}, b.int(0)),
                    .cond = try b.bin("<", b.ident("index"), b.int(3)),
                    .post = try b.incDec(b.ident("index"), "++"),
                    .body = &.{try b.switchStmt(.{
                        .tag = b.ident("index"),
                        .cases = &.{.{ .values = &.{b.int(0)}, .body = &.{.continue_stmt} }},
                        .default = &.{.break_stmt},
                    })},
                }),
                try b.ret(&.{.nil}),
            },
        }),
        try b.assertImplements(.{ .interface = try b.selName("io", "Closer"), .type_name = "Session" }),
    }, .{ .blank_before = true });

    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "sample.go", .data = output.written() });
    const result = std.process.run(allocator, std.testing.io, .{
        .argv = &.{ "gofmt", "-l", "sample.go" },
        .cwd = .{ .dir = directory.dir },
    }) catch |err| switch (err) {
        // CONTRIBUTING asks for a Go toolchain, but a checkout without one
        // should still run the rest of the suite.
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    try std.testing.expectEqualStrings("", result.stderr);
    try std.testing.expectEqualStrings("", result.stdout);
}
