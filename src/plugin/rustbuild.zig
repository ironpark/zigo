//! A small Rust AST for plugins: items, statements and expressions a hook
//! composes instead of printing Rust source. Nodes are values; the slices a
//! `Builder` method is given are copied into the run arena, so a tree built
//! inside a loop stays valid until it is rendered.
//!
//! The Go builder's sibling, written against the same shape so a plugin that
//! fills both render slots meets one idea twice rather than two ideas once.
//! What differs is what Rust has and Go does not -- attributes, a trait
//! `impl`, `match` guards, `?`, lifetimes -- and what Go has and Rust does
//! not, which is most of its statement forms.
//!
//! Rendering is deterministic and indents with four spaces, the way `rustfmt`
//! lays a file out, so the formatter leaves the result alone. Generics,
//! lifetimes and `where` clauses are raw strings: spelling them structurally
//! would be a second type system, and the shapes a binding plugin writes are
//! short enough that the escape hatch is the honest surface. The generator
//! answers for anything a plugin cannot spell on its own -- the crate's name
//! for a type, the signature of a bound method -- through `RustWriters`,
//! which `Expr.type_name` and `Signature.function` reach.
const std = @import("std");
const abi = @import("abi");
const naming = @import("naming");
const semantic = @import("semantic");
const plugin = @import("../plugin.zig");

/// A doc comment above an item, a field or a variant.
pub const Doc = union(enum) {
    none,
    /// Comment text without markers. Every line becomes `/// line`; an empty
    /// line becomes `///`.
    text: []const u8,
    /// An ordinary comment: every line becomes `// line`. A doc comment is
    /// not legal inside a function body, so this is what a statement-level
    /// comment uses.
    line: []const u8,
    /// Module documentation: every line becomes `//! line`.
    module: []const u8,
    /// Lines that already carry their markers, written as they are.
    rendered: []const u8,
};

/// How an item is published. `crate` is `pub(crate)`.
pub const Visibility = enum { private, public, crate };

/// The receiver an associated function takes. `none` makes it an associated
/// function rather than a method.
pub const Receiver = enum { none, value, reference, mutable_reference };

/// One parameter: `name: Type`.
pub const Param = struct { name: []const u8, type: Expr };

/// A parameter list and result, either written out or taken from the public
/// signature the generator gives a bound function.
pub const Signature = union(enum) {
    explicit: struct {
        receiver: Receiver = .none,
        params: []const Param = &.{},
        /// Absent is `()`, which Rust writes by leaving the arrow off.
        result: ?Expr = null,
    },
    function: struct { function: abi.AbiFn, options: plugin.RustSignatureOptions = .{} },
};

/// A Rust expression. `raw` is the escape hatch for the rare spelling the
/// other nodes do not cover; everything else renders from structure.
pub const Expr = union(enum) {
    raw: []const u8,
    /// A path, which is also how a plain identifier and a type are spelled:
    /// `value`, `u8`, `core::fmt::Result`, `Self::Idle`.
    path: []const u8,
    /// A generated type as the crate spells it.
    type_name: []const u8,
    /// Rendered as a Rust string literal, quotes and escapes included.
    string: []const u8,
    int: i128,
    /// Written as it is given, so a plugin decides the spelling of `1.0`.
    float: []const u8,
    boolean: bool,
    /// The unit value and the unit type, which Rust spells the same.
    unit,
    /// `target.name`, and `target.0` for a tuple element.
    field: struct { target: *const Expr, name: []const u8 },
    index: struct { target: *const Expr, index: *const Expr },
    call: struct { callee: *const Expr, args: []const Expr },
    method_call: struct {
        receiver: *const Expr,
        method: []const u8,
        /// The turbofish, without the leading `::`: `<u8>`.
        turbofish: ?[]const u8 = null,
        args: []const Expr,
    },
    /// `&value` and `&mut value`, and `&'a T` and `&'a mut T` in type
    /// position.
    reference: struct { lifetime: ?[]const u8 = null, mutable: bool = false, operand: *const Expr },
    deref: *const Expr,
    unary: struct { op: []const u8, operand: *const Expr },
    binary: struct { op: []const u8, left: *const Expr, right: *const Expr },
    paren: *const Expr,
    /// `value?`.
    try_expr: *const Expr,
    /// `value as T`.
    cast: struct { value: *const Expr, type: *const Expr },
    /// `start..end`, `start..=end`, and either half omitted.
    range: struct { start: ?*const Expr = null, end: ?*const Expr = null, inclusive: bool = false },
    closure: struct { move: bool = false, params: []const ClosureParam, body: *const Expr },
    /// `format!("{}", value)`, `vec![1, 2]`, `println!("hi")`. The delimiter
    /// is the macro's own convention, not a formatting choice.
    macro_call: struct { name: []const u8, delimiter: MacroDelimiter = .paren, args: []const Expr },
    /// `Point { x: 1, y: 2 }`, with an optional `..rest`.
    struct_literal: struct { path: *const Expr, fields: []const FieldValue, rest: ?*const Expr = null, multiline: bool = false },
    tuple: []const Expr,
    array: struct { elements: []const Expr, multiline: bool = false },
    /// `Vec<u8>`, `Result<T, Error>`, `Option<&'a str>`.
    generic: struct { base: *const Expr, args: []const Expr },
    /// `[T]` in type position.
    slice: *const Expr,
    /// A block used for its value: `{ stmts }`.
    block: []const Stmt,
    /// Boxed, because `Match` and `If` both hold expressions of their own
    /// and a by-value field here would make the three types mutually
    /// recursive.
    match_expr: *const Match,
    if_expr: *const If,

    pub const ClosureParam = struct { name: []const u8, type: ?Expr = null };
    pub const FieldValue = struct { name: []const u8, value: Expr };
    pub const MacroDelimiter = enum { paren, bracket, brace };
};

pub const Stmt = union(enum) {
    raw: []const u8,
    comment: Doc,
    /// An empty line, which separates the parts of a long body.
    blank,
    /// `let [mut] name[: T] [= value];`
    let: struct { mutable: bool = false, name: []const u8, type: ?Expr = null, value: ?Expr = null },
    /// An expression written for its effect: `value;`.
    expr: Expr,
    /// The block's value: an expression with no semicolon, which only the
    /// last statement of a body may be.
    tail: Expr,
    ret: ?Expr,
    /// `lhs op rhs;`, where `op` is `=`, `+=` and so on.
    assign: struct { lhs: Expr, op: []const u8, rhs: Expr },
    if_stmt: If,
    match_stmt: Match,
    for_loop: struct { pattern: []const u8, over: Expr, body: []const Stmt },
    while_loop: struct { cond: Expr, body: []const Stmt },
    loop_stmt: []const Stmt,
    block: []const Stmt,
    break_stmt,
    continue_stmt,
};

pub const If = struct {
    /// The condition, or a `let` pattern written raw: `let Some(value) = x`.
    cond: Expr,
    body: []const Stmt,
    /// Another `if` for `else if`, or a block for a plain `else`.
    @"else": ?*const Else = null,

    pub const Else = union(enum) { if_branch: If, block: []const Stmt };
};

pub const Match = struct {
    value: Expr,
    arms: []const Arm,

    pub const Arm = struct {
        /// The pattern, written raw: patterns are their own grammar and a
        /// binding plugin writes short ones.
        pattern: []const u8,
        /// `if guard` after the pattern.
        guard: ?Expr = null,
        body: Body,

        pub const Body = union(enum) { expr: Expr, block: []const Stmt };
    };
};

pub const Field = struct { doc: Doc = .none, attributes: []const []const u8 = &.{}, visibility: Visibility = .private, name: []const u8, type: Expr };

pub const Variant = struct {
    doc: Doc = .none,
    attributes: []const []const u8 = &.{},
    name: []const u8,
    payload: Payload = .unit,
    /// The explicit discriminant of a `repr`-carrying enum.
    value: ?Expr = null,

    pub const Payload = union(enum) { unit, tuple: []const Expr, named: []const Field };
};

pub const StructBody = union(enum) {
    unit,
    tuple: []const TupleField,
    named: []const Field,

    pub const TupleField = struct { visibility: Visibility = .private, type: Expr };
};

pub const Item = union(enum) {
    /// A comment with no item under it.
    comment: Doc,
    raw: []const u8,
    use: Use,
    module: Module,
    func: Func,
    impl_block: Impl,
    struct_item: Struct,
    enum_item: Enum,
    const_item: Const,
    static_item: Static,

    pub const Use = struct { doc: Doc = .none, visibility: Visibility = .private, path: []const u8, alias: ?[]const u8 = null };
    /// `mod name;` when `items` is null, `mod name { .. }` when it is not.
    pub const Module = struct { doc: Doc = .none, visibility: Visibility = .private, attributes: []const []const u8 = &.{}, name: []const u8, items: ?[]const Item = null };
    pub const Func = struct {
        doc: Doc = .none,
        attributes: []const []const u8 = &.{},
        visibility: Visibility = .private,
        unsafe_fn: bool = false,
        name: []const u8,
        /// `<'a, T: Debug>`, written raw.
        generics: []const u8 = "",
        signature: Signature = .{ .explicit = .{} },
        /// `where T: Clone`, written raw and without the keyword.
        where_clause: ?[]const u8 = null,
        body: []const Stmt = &.{},
    };
    pub const Impl = struct {
        doc: Doc = .none,
        attributes: []const []const u8 = &.{},
        /// `<'a, T>`, written raw.
        generics: []const u8 = "",
        /// The trait being implemented, or null for an inherent `impl`.
        trait: ?Expr = null,
        type: Expr,
        where_clause: ?[]const u8 = null,
        items: []const Item = &.{},
    };
    pub const Struct = struct {
        doc: Doc = .none,
        attributes: []const []const u8 = &.{},
        visibility: Visibility = .private,
        name: []const u8,
        generics: []const u8 = "",
        where_clause: ?[]const u8 = null,
        body: StructBody = .unit,
    };
    pub const Enum = struct {
        doc: Doc = .none,
        attributes: []const []const u8 = &.{},
        visibility: Visibility = .private,
        name: []const u8,
        generics: []const u8 = "",
        variants: []const Variant = &.{},
    };
    pub const Const = struct { doc: Doc = .none, attributes: []const []const u8 = &.{}, visibility: Visibility = .private, name: []const u8, type: Expr, value: Expr };
    pub const Static = struct { doc: Doc = .none, attributes: []const []const u8 = &.{}, visibility: Visibility = .private, mutable: bool = false, name: []const u8, type: Expr, value: Expr };
};

/// How a group of items is spaced. `rustfmt` keeps one blank line between
/// items and removes any more, so `blank_between` is on by default.
pub const Layout = struct {
    blank_before: bool = false,
    blank_after: bool = false,
    blank_between: bool = true,
};

/// `text` as a Rust string literal. Quotes, backslashes and the common
/// control characters take their short escapes; any other control byte is
/// written as `\u{NN}`, which Rust accepts where `\xNN` is restricted to
/// ASCII. Bytes above ASCII pass through, so UTF-8 text reads as written.
pub fn writeStringLiteral(writer: *std.Io.Writer, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |byte| switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\t' => try writer.writeAll("\\t"),
        '\r' => try writer.writeAll("\\r"),
        0 => try writer.writeAll("\\0"),
        1...8, 11, 12, 14...31, 127 => try writer.print("\\u{{{x}}}", .{byte}),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

/// A Zig name as the crate spells it: `some_name`, `SomeName` or
/// `SOME_NAME`. The `RustWriters` default, and what a plugin's own tests use.
pub fn identifierAlloc(
    _: plugin.RustContext,
    allocator: std.mem.Allocator,
    name: []const u8,
    style: plugin.RustIdentifierStyle,
) anyerror![]u8 {
    return switch (style) {
        .snake => naming.snakeAlloc(allocator, name),
        .pascal => naming.pascalWithInitialismsAlloc(allocator, name, &.{}),
        .screaming => blk: {
            const snake = try naming.snakeAlloc(allocator, name);
            for (snake) |*byte| byte.* = std.ascii.toUpper(byte.*);
            break :blk snake;
        },
    };
}

/// Builds and renders Rust nodes. Every constructor copies the slices it is
/// given into the context's arena, so a node outlives the array literal it
/// was built from.
pub const Builder = struct {
    allocator: std.mem.Allocator,
    context: plugin.RustContext,
    /// Where `emit` writes: the buffer the generator flushes at the insertion
    /// point of the node being visited. It is null on the builder a plugin
    /// makes for one of its own files, which renders into the writer that
    /// file was handed.
    out: ?*std.Io.Writer = null,

    // -- rendering -----------------------------------------------------

    /// Writes `items` into this visit's output. The generator flushes it at
    /// the insertion point of the node the visit was called for.
    pub fn emit(self: Builder, items: []const Item, layout: Layout) !void {
        return self.render(try self.output(), items, layout);
    }

    /// This visit's output itself, for the rare hook that writes text no node
    /// spells. `emit` is how a plugin writes Rust.
    pub fn output(self: Builder) !*std.Io.Writer {
        return self.out orelse error.NoBuilderOutput;
    }

    /// Writes `items` in order, spaced by `layout`.
    pub fn render(self: Builder, writer: *std.Io.Writer, items: []const Item, layout: Layout) !void {
        if (items.len == 0) return;
        if (layout.blank_before) try writer.writeByte('\n');
        for (items, 0..) |item, index| {
            if (index != 0 and layout.blank_between) try writer.writeByte('\n');
            try self.renderItem(writer, item, 0);
        }
        if (layout.blank_after) try writer.writeByte('\n');
    }

    /// One item, with its doc comment, its attributes and a trailing newline.
    pub fn renderItem(self: Builder, writer: *std.Io.Writer, item: Item, depth: usize) anyerror!void {
        switch (item) {
            .comment => |doc| try self.writeDoc(writer, doc, depth),
            .raw => |text| try writer.writeAll(text),
            .use => |value| {
                try self.writeDoc(writer, value.doc, depth);
                try indent(writer, depth);
                try writeVisibility(writer, value.visibility);
                try writer.print("use {s}", .{value.path});
                if (value.alias) |alias| try writer.print(" as {s}", .{alias});
                try writer.writeAll(";\n");
            },
            .module => |value| try self.renderModule(writer, value, depth),
            .func => |value| try self.renderFunc(writer, value, depth),
            .impl_block => |value| try self.renderImpl(writer, value, depth),
            .struct_item => |value| try self.renderStruct(writer, value, depth),
            .enum_item => |value| try self.renderEnum(writer, value, depth),
            .const_item => |value| {
                try self.writeHeader(writer, value.doc, value.attributes, depth);
                try indent(writer, depth);
                try writeVisibility(writer, value.visibility);
                try writer.print("const {s}: ", .{value.name});
                try self.renderExpr(writer, value.type, depth);
                try writer.writeAll(" = ");
                try self.renderExpr(writer, value.value, depth);
                try writer.writeAll(";\n");
            },
            .static_item => |value| {
                try self.writeHeader(writer, value.doc, value.attributes, depth);
                try indent(writer, depth);
                try writeVisibility(writer, value.visibility);
                try writer.print("static {s}{s}: ", .{ if (value.mutable) "mut " else "", value.name });
                try self.renderExpr(writer, value.type, depth);
                try writer.writeAll(" = ");
                try self.renderExpr(writer, value.value, depth);
                try writer.writeAll(";\n");
            },
        }
    }

    fn writeDoc(self: Builder, writer: *std.Io.Writer, doc: Doc, depth: usize) anyerror!void {
        _ = self;
        switch (doc) {
            .none => {},
            .text, .line, .module => |text| {
                const marker = switch (doc) {
                    .module => "//!",
                    .line => "//",
                    else => "///",
                };
                var lines = std.mem.splitScalar(u8, text, '\n');
                while (lines.next()) |line| {
                    try indent(writer, depth);
                    if (line.len == 0) try writer.print("{s}\n", .{marker}) else try writer.print("{s} {s}\n", .{ marker, line });
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

    /// The doc comment and the attributes above an item, in that order, which
    /// is the order `rustfmt` keeps them in.
    fn writeHeader(self: Builder, writer: *std.Io.Writer, doc: Doc, attributes: []const []const u8, depth: usize) anyerror!void {
        try self.writeDoc(writer, doc, depth);
        for (attributes) |attribute| {
            try indent(writer, depth);
            try writer.print("#[{s}]\n", .{attribute});
        }
    }

    fn renderModule(self: Builder, writer: *std.Io.Writer, value: Item.Module, depth: usize) anyerror!void {
        try self.writeHeader(writer, value.doc, value.attributes, depth);
        try indent(writer, depth);
        try writeVisibility(writer, value.visibility);
        try writer.print("mod {s}", .{value.name});
        const items = value.items orelse return writer.writeAll(";\n");
        try writer.writeAll(" {\n");
        for (items, 0..) |item, index| {
            if (index != 0) try writer.writeByte('\n');
            try self.renderItem(writer, item, depth + 1);
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    fn renderFunc(self: Builder, writer: *std.Io.Writer, value: Item.Func, depth: usize) anyerror!void {
        try self.writeHeader(writer, value.doc, value.attributes, depth);
        try indent(writer, depth);
        try writeVisibility(writer, value.visibility);
        if (value.unsafe_fn) try writer.writeAll("unsafe ");
        try writer.print("fn {s}{s}", .{ value.name, value.generics });
        try self.renderSignature(writer, value.signature, depth);
        if (value.where_clause) |clause| {
            // `rustfmt` puts the opening brace on its own line after a
            // `where` clause, which is the one place the two disagree.
            try writer.print("\nwhere\n", .{});
            try indent(writer, depth + 1);
            try writer.print("{s},\n", .{clause});
            try indent(writer, depth);
            try writer.writeAll("{\n");
        } else try writer.writeAll(" {\n");
        try self.renderBody(writer, value.body, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    fn renderImpl(self: Builder, writer: *std.Io.Writer, value: Item.Impl, depth: usize) anyerror!void {
        try self.writeHeader(writer, value.doc, value.attributes, depth);
        try indent(writer, depth);
        try writer.print("impl{s} ", .{value.generics});
        if (value.trait) |trait| {
            try self.renderExpr(writer, trait, depth);
            try writer.writeAll(" for ");
        }
        try self.renderExpr(writer, value.type, depth);
        if (value.where_clause) |clause| {
            try writer.print("\nwhere\n", .{});
            try indent(writer, depth + 1);
            try writer.print("{s},\n", .{clause});
            try indent(writer, depth);
            try writer.writeAll("{\n");
        } else try writer.writeAll(" {\n");
        for (value.items, 0..) |item, index| {
            if (index != 0) try writer.writeByte('\n');
            try self.renderItem(writer, item, depth + 1);
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    fn renderStruct(self: Builder, writer: *std.Io.Writer, value: Item.Struct, depth: usize) anyerror!void {
        try self.writeHeader(writer, value.doc, value.attributes, depth);
        try indent(writer, depth);
        try writeVisibility(writer, value.visibility);
        try writer.print("struct {s}{s}", .{ value.name, value.generics });
        switch (value.body) {
            .unit => {
                if (value.where_clause) |clause| try writer.print("\nwhere\n    {s},", .{clause});
                try writer.writeAll(";\n");
            },
            .tuple => |fields| {
                try writer.writeByte('(');
                for (fields, 0..) |field, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try writeVisibility(writer, field.visibility);
                    try self.renderExpr(writer, field.type, depth);
                }
                try writer.writeAll(");\n");
            },
            .named => |fields| {
                if (value.where_clause) |clause| {
                    try writer.print("\nwhere\n", .{});
                    try indent(writer, depth + 1);
                    try writer.print("{s},\n", .{clause});
                    try indent(writer, depth);
                    try writer.writeAll("{\n");
                } else try writer.writeAll(" {\n");
                for (fields) |field| try self.renderField(writer, field, depth + 1);
                try indent(writer, depth);
                try writer.writeAll("}\n");
            },
        }
    }

    fn renderField(self: Builder, writer: *std.Io.Writer, field: Field, depth: usize) anyerror!void {
        try self.writeHeader(writer, field.doc, field.attributes, depth);
        try indent(writer, depth);
        try writeVisibility(writer, field.visibility);
        try writer.print("{s}: ", .{field.name});
        try self.renderExpr(writer, field.type, depth);
        try writer.writeAll(",\n");
    }

    fn renderEnum(self: Builder, writer: *std.Io.Writer, value: Item.Enum, depth: usize) anyerror!void {
        try self.writeHeader(writer, value.doc, value.attributes, depth);
        try indent(writer, depth);
        try writeVisibility(writer, value.visibility);
        try writer.print("enum {s}{s} {{\n", .{ value.name, value.generics });
        for (value.variants) |variant| {
            try self.writeHeader(writer, variant.doc, variant.attributes, depth + 1);
            try indent(writer, depth + 1);
            try writer.writeAll(variant.name);
            switch (variant.payload) {
                .unit => {},
                .tuple => |types| {
                    try writer.writeByte('(');
                    for (types, 0..) |node, index| {
                        if (index != 0) try writer.writeAll(", ");
                        try self.renderExpr(writer, node, depth + 1);
                    }
                    try writer.writeByte(')');
                },
                .named => |fields| {
                    try writer.writeAll(" {\n");
                    for (fields) |field| try self.renderField(writer, field, depth + 2);
                    try indent(writer, depth + 1);
                    try writer.writeByte('}');
                },
            }
            if (variant.value) |discriminant| {
                try writer.writeAll(" = ");
                try self.renderExpr(writer, discriminant, depth + 1);
            }
            try writer.writeAll(",\n");
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    fn renderSignature(self: Builder, writer: *std.Io.Writer, signature: Signature, depth: usize) anyerror!void {
        switch (signature) {
            .function => |spec| try self.context.writeSignatureWith(writer, spec.function, spec.options),
            .explicit => |spec| {
                try writer.writeByte('(');
                var written = false;
                switch (spec.receiver) {
                    .none => {},
                    .value => {
                        try writer.writeAll("self");
                        written = true;
                    },
                    .reference => {
                        try writer.writeAll("&self");
                        written = true;
                    },
                    .mutable_reference => {
                        try writer.writeAll("&mut self");
                        written = true;
                    },
                }
                for (spec.params) |param| {
                    if (written) try writer.writeAll(", ");
                    written = true;
                    try writer.print("{s}: ", .{param.name});
                    try self.renderExpr(writer, param.type, depth);
                }
                try writer.writeByte(')');
                if (spec.result) |result| {
                    try writer.writeAll(" -> ");
                    try self.renderExpr(writer, result, depth);
                }
            },
        }
    }

    fn renderBody(self: Builder, writer: *std.Io.Writer, body: []const Stmt, depth: usize) anyerror!void {
        for (body) |statement| try self.renderStmt(writer, statement, depth);
    }

    fn renderStmt(self: Builder, writer: *std.Io.Writer, statement: Stmt, depth: usize) anyerror!void {
        switch (statement) {
            .blank => return writer.writeByte('\n'),
            .comment => |doc| return self.writeDoc(writer, doc, depth),
            .raw => |text| {
                try indent(writer, depth);
                try writer.writeAll(text);
                return writer.writeByte('\n');
            },
            .let => |spec| {
                try indent(writer, depth);
                try writer.print("let {s}{s}", .{ if (spec.mutable) "mut " else "", spec.name });
                if (spec.type) |node| {
                    try writer.writeAll(": ");
                    try self.renderExpr(writer, node, depth);
                }
                if (spec.value) |node| {
                    try writer.writeAll(" = ");
                    try self.renderExpr(writer, node, depth);
                }
                return writer.writeAll(";\n");
            },
            .expr => |node| {
                try indent(writer, depth);
                try self.renderExpr(writer, node, depth);
                return writer.writeAll(";\n");
            },
            .tail => |node| {
                try indent(writer, depth);
                try self.renderExpr(writer, node, depth);
                return writer.writeByte('\n');
            },
            .assign => |spec| {
                try indent(writer, depth);
                try self.renderExpr(writer, spec.lhs, depth);
                try writer.print(" {s} ", .{spec.op});
                try self.renderExpr(writer, spec.rhs, depth);
                return writer.writeAll(";\n");
            },
            .ret => |value| {
                try indent(writer, depth);
                try writer.writeAll("return");
                if (value) |node| {
                    try writer.writeByte(' ');
                    try self.renderExpr(writer, node, depth);
                }
                return writer.writeAll(";\n");
            },
            .if_stmt => |spec| {
                try indent(writer, depth);
                try self.renderIf(writer, spec, depth);
                return writer.writeByte('\n');
            },
            .match_stmt => |spec| {
                try indent(writer, depth);
                try self.renderMatch(writer, spec, depth);
                return writer.writeByte('\n');
            },
            .for_loop => |spec| {
                try indent(writer, depth);
                try writer.print("for {s} in ", .{spec.pattern});
                try self.renderExpr(writer, spec.over, depth);
                try writer.writeAll(" {\n");
                try self.renderBody(writer, spec.body, depth + 1);
                try indent(writer, depth);
                return writer.writeAll("}\n");
            },
            .while_loop => |spec| {
                try indent(writer, depth);
                try writer.writeAll("while ");
                try self.renderExpr(writer, spec.cond, depth);
                try writer.writeAll(" {\n");
                try self.renderBody(writer, spec.body, depth + 1);
                try indent(writer, depth);
                return writer.writeAll("}\n");
            },
            .loop_stmt => |body| {
                try indent(writer, depth);
                try writer.writeAll("loop {\n");
                try self.renderBody(writer, body, depth + 1);
                try indent(writer, depth);
                return writer.writeAll("}\n");
            },
            .block => |body| {
                try indent(writer, depth);
                try writer.writeAll("{\n");
                try self.renderBody(writer, body, depth + 1);
                try indent(writer, depth);
                return writer.writeAll("}\n");
            },
            .break_stmt => {
                try indent(writer, depth);
                return writer.writeAll("break;\n");
            },
            .continue_stmt => {
                try indent(writer, depth);
                return writer.writeAll("continue;\n");
            },
        }
    }

    /// An `if` without its indentation or trailing newline, so an `else if`
    /// chain renders on one line of braces.
    fn renderIf(self: Builder, writer: *std.Io.Writer, spec: If, depth: usize) anyerror!void {
        try writer.writeAll("if ");
        try self.renderExpr(writer, spec.cond, depth);
        try writer.writeAll(" {\n");
        try self.renderBody(writer, spec.body, depth + 1);
        try indent(writer, depth);
        try writer.writeByte('}');
        const otherwise = spec.@"else" orelse return;
        try writer.writeAll(" else ");
        switch (otherwise.*) {
            .if_branch => |nested| try self.renderIf(writer, nested, depth),
            .block => |body| {
                try writer.writeAll("{\n");
                try self.renderBody(writer, body, depth + 1);
                try indent(writer, depth);
                try writer.writeByte('}');
            },
        }
    }

    fn renderMatch(self: Builder, writer: *std.Io.Writer, spec: Match, depth: usize) anyerror!void {
        try writer.writeAll("match ");
        try self.renderExpr(writer, spec.value, depth);
        try writer.writeAll(" {\n");
        for (spec.arms) |arm| {
            try indent(writer, depth + 1);
            try writer.writeAll(arm.pattern);
            if (arm.guard) |guard| {
                try writer.writeAll(" if ");
                try self.renderExpr(writer, guard, depth + 1);
            }
            try writer.writeAll(" => ");
            switch (arm.body) {
                .expr => |node| {
                    try self.renderExpr(writer, node, depth + 1);
                    try writer.writeAll(",\n");
                },
                // A block arm takes no trailing comma, which is what
                // `rustfmt` writes and what it removes if one is there.
                .block => |body| {
                    try writer.writeAll("{\n");
                    try self.renderBody(writer, body, depth + 2);
                    try indent(writer, depth + 1);
                    try writer.writeAll("}\n");
                },
            }
        }
        try indent(writer, depth);
        try writer.writeByte('}');
    }

    fn renderExpr(self: Builder, writer: *std.Io.Writer, node: Expr, depth: usize) anyerror!void {
        switch (node) {
            .raw, .path, .float => |text| try writer.writeAll(text),
            .type_name => |name| try self.context.writeTypeName(writer, name),
            .string => |text| try writeStringLiteral(writer, text),
            .int => |value| try writer.print("{d}", .{value}),
            .boolean => |value| try writer.writeAll(if (value) "true" else "false"),
            .unit => try writer.writeAll("()"),
            .field => |spec| {
                try self.renderExpr(writer, spec.target.*, depth);
                try writer.print(".{s}", .{spec.name});
            },
            .index => |spec| {
                try self.renderExpr(writer, spec.target.*, depth);
                try writer.writeByte('[');
                try self.renderExpr(writer, spec.index.*, depth);
                try writer.writeByte(']');
            },
            .call => |spec| {
                try self.renderExpr(writer, spec.callee.*, depth);
                try self.renderArguments(writer, spec.args, depth);
            },
            .method_call => |spec| {
                try self.renderExpr(writer, spec.receiver.*, depth);
                try writer.print(".{s}", .{spec.method});
                if (spec.turbofish) |turbofish| try writer.print("::{s}", .{turbofish});
                try self.renderArguments(writer, spec.args, depth);
            },
            .reference => |spec| {
                try writer.writeByte('&');
                if (spec.lifetime) |lifetime| try writer.print("{s} ", .{lifetime});
                if (spec.mutable) try writer.writeAll("mut ");
                try self.renderExpr(writer, spec.operand.*, depth);
            },
            .deref => |inner| {
                try writer.writeByte('*');
                try self.renderExpr(writer, inner.*, depth);
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
            .try_expr => |inner| {
                try self.renderExpr(writer, inner.*, depth);
                try writer.writeByte('?');
            },
            .cast => |spec| {
                try self.renderExpr(writer, spec.value.*, depth);
                try writer.writeAll(" as ");
                try self.renderExpr(writer, spec.type.*, depth);
            },
            .range => |spec| {
                if (spec.start) |start| try self.renderExpr(writer, start.*, depth);
                try writer.writeAll(if (spec.inclusive) "..=" else "..");
                if (spec.end) |end| try self.renderExpr(writer, end.*, depth);
            },
            .closure => |spec| {
                if (spec.move) try writer.writeAll("move ");
                try writer.writeByte('|');
                for (spec.params, 0..) |param, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try writer.writeAll(param.name);
                    if (param.type) |type_node| {
                        try writer.writeAll(": ");
                        try self.renderExpr(writer, type_node, depth);
                    }
                }
                try writer.writeAll("| ");
                try self.renderExpr(writer, spec.body.*, depth);
            },
            .macro_call => |spec| {
                try writer.print("{s}!", .{spec.name});
                const open: u8 = switch (spec.delimiter) {
                    .paren => '(',
                    .bracket => '[',
                    .brace => '{',
                };
                const close: u8 = switch (spec.delimiter) {
                    .paren => ')',
                    .bracket => ']',
                    .brace => '}',
                };
                try writer.writeByte(open);
                for (spec.args, 0..) |argument, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try self.renderExpr(writer, argument, depth);
                }
                try writer.writeByte(close);
            },
            .struct_literal => |spec| {
                try self.renderExpr(writer, spec.path.*, depth);
                try writer.writeAll(" {");
                if (spec.multiline) {
                    try writer.writeByte('\n');
                    for (spec.fields) |field| {
                        try indent(writer, depth + 1);
                        try writer.print("{s}: ", .{field.name});
                        try self.renderExpr(writer, field.value, depth + 1);
                        try writer.writeAll(",\n");
                    }
                    if (spec.rest) |rest| {
                        try indent(writer, depth + 1);
                        try writer.writeAll("..");
                        try self.renderExpr(writer, rest.*, depth + 1);
                        try writer.writeByte('\n');
                    }
                    try indent(writer, depth);
                    return writer.writeByte('}');
                }
                for (spec.fields, 0..) |field, index| {
                    try writer.writeAll(if (index == 0) " " else ", ");
                    try writer.print("{s}: ", .{field.name});
                    try self.renderExpr(writer, field.value, depth);
                }
                if (spec.rest) |rest| {
                    try writer.writeAll(if (spec.fields.len == 0) " .." else ", ..");
                    try self.renderExpr(writer, rest.*, depth);
                }
                try writer.writeAll(" }");
            },
            .tuple => |elements| {
                try writer.writeByte('(');
                for (elements, 0..) |element, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try self.renderExpr(writer, element, depth);
                }
                // A one-element tuple needs the comma that tells it from a
                // parenthesized expression.
                if (elements.len == 1) try writer.writeByte(',');
                try writer.writeByte(')');
            },
            .array => |spec| {
                try writer.writeByte('[');
                if (spec.multiline) {
                    try writer.writeByte('\n');
                    for (spec.elements) |element| {
                        try indent(writer, depth + 1);
                        try self.renderExpr(writer, element, depth + 1);
                        try writer.writeAll(",\n");
                    }
                    try indent(writer, depth);
                } else for (spec.elements, 0..) |element, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try self.renderExpr(writer, element, depth);
                }
                try writer.writeByte(']');
            },
            .generic => |spec| {
                try self.renderExpr(writer, spec.base.*, depth);
                try writer.writeByte('<');
                for (spec.args, 0..) |argument, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try self.renderExpr(writer, argument, depth);
                }
                try writer.writeByte('>');
            },
            .slice => |inner| {
                try writer.writeByte('[');
                try self.renderExpr(writer, inner.*, depth);
                try writer.writeByte(']');
            },
            .block => |body| {
                try writer.writeAll("{\n");
                try self.renderBody(writer, body, depth + 1);
                try indent(writer, depth);
                try writer.writeByte('}');
            },
            .match_expr => |spec| try self.renderMatch(writer, spec.*, depth),
            .if_expr => |spec| try self.renderIf(writer, spec.*, depth),
        }
    }

    fn renderArguments(self: Builder, writer: *std.Io.Writer, args: []const Expr, depth: usize) anyerror!void {
        try writer.writeByte('(');
        for (args, 0..) |argument, index| {
            if (index != 0) try writer.writeAll(", ");
            try self.renderExpr(writer, argument, depth);
        }
        try writer.writeByte(')');
    }

    // -- expressions ---------------------------------------------------

    pub fn path(_: Builder, text: []const u8) Expr {
        return .{ .path = text };
    }
    pub fn raw(_: Builder, text: []const u8) Expr {
        return .{ .raw = text };
    }
    pub fn typeName(_: Builder, name: []const u8) Expr {
        return .{ .type_name = name };
    }
    pub fn string(_: Builder, text: []const u8) Expr {
        return .{ .string = text };
    }
    pub fn int(_: Builder, value: i128) Expr {
        return .{ .int = value };
    }
    pub fn float(_: Builder, text: []const u8) Expr {
        return .{ .float = text };
    }
    pub fn boolean(_: Builder, value: bool) Expr {
        return .{ .boolean = value };
    }

    pub fn fieldOf(self: Builder, target: Expr, name: []const u8) !Expr {
        return .{ .field = .{ .target = try self.box(target), .name = name } };
    }
    pub fn indexExpr(self: Builder, target: Expr, index: Expr) !Expr {
        return .{ .index = .{ .target = try self.box(target), .index = try self.box(index) } };
    }
    pub fn call(self: Builder, callee: Expr, args: []const Expr) !Expr {
        return .{ .call = .{ .callee = try self.box(callee), .args = try self.dupExprs(args) } };
    }
    pub fn callPath(self: Builder, name: []const u8, args: []const Expr) !Expr {
        return self.call(self.path(name), args);
    }
    pub fn methodCall(self: Builder, receiver: Expr, method: []const u8, args: []const Expr) !Expr {
        return .{ .method_call = .{ .receiver = try self.box(receiver), .method = method, .args = try self.dupExprs(args) } };
    }
    pub fn addr(self: Builder, operand: Expr) !Expr {
        return .{ .reference = .{ .operand = try self.box(operand) } };
    }
    pub fn addrMut(self: Builder, operand: Expr) !Expr {
        return .{ .reference = .{ .mutable = true, .operand = try self.box(operand) } };
    }
    /// `&'a T` and `&'a mut T` in type position.
    pub fn refType(self: Builder, lifetime: ?[]const u8, mutable: bool, child: Expr) !Expr {
        return .{ .reference = .{ .lifetime = lifetime, .mutable = mutable, .operand = try self.box(child) } };
    }
    pub fn deref(self: Builder, operand: Expr) !Expr {
        return .{ .deref = try self.box(operand) };
    }
    pub fn unary(self: Builder, op: []const u8, operand: Expr) !Expr {
        return .{ .unary = .{ .op = op, .operand = try self.box(operand) } };
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
    pub fn tryExpr(self: Builder, inner: Expr) !Expr {
        return .{ .try_expr = try self.box(inner) };
    }
    pub fn cast(self: Builder, value: Expr, type_node: Expr) !Expr {
        return .{ .cast = .{ .value = try self.box(value), .type = try self.box(type_node) } };
    }
    pub fn range(self: Builder, start: ?Expr, end: ?Expr, inclusive: bool) !Expr {
        return .{ .range = .{
            .start = if (start) |node| try self.box(node) else null,
            .end = if (end) |node| try self.box(node) else null,
            .inclusive = inclusive,
        } };
    }
    pub fn closure(self: Builder, params: []const Expr.ClosureParam, body: Expr) !Expr {
        return .{ .closure = .{ .params = try self.allocator.dupe(Expr.ClosureParam, params), .body = try self.box(body) } };
    }
    pub fn macroCall(self: Builder, name: []const u8, delimiter: Expr.MacroDelimiter, args: []const Expr) !Expr {
        return .{ .macro_call = .{ .name = name, .delimiter = delimiter, .args = try self.dupExprs(args) } };
    }
    /// `format!("{}", value)`.
    pub fn format(self: Builder, args: []const Expr) !Expr {
        return self.macroCall("format", .paren, args);
    }
    /// `vec![a, b]`.
    pub fn vec(self: Builder, args: []const Expr) !Expr {
        return self.macroCall("vec", .bracket, args);
    }
    pub fn structLiteral(self: Builder, type_path: Expr, fields: []const Expr.FieldValue) !Expr {
        return .{ .struct_literal = .{ .path = try self.box(type_path), .fields = try self.dupFieldValues(fields) } };
    }
    pub fn structLiteralLines(self: Builder, type_path: Expr, fields: []const Expr.FieldValue) !Expr {
        return .{ .struct_literal = .{ .path = try self.box(type_path), .fields = try self.dupFieldValues(fields), .multiline = true } };
    }
    pub fn tuple(self: Builder, elements: []const Expr) !Expr {
        return .{ .tuple = try self.dupExprs(elements) };
    }
    pub fn array(self: Builder, elements: []const Expr) !Expr {
        return .{ .array = .{ .elements = try self.dupExprs(elements) } };
    }
    pub fn arrayLines(self: Builder, elements: []const Expr) !Expr {
        return .{ .array = .{ .elements = try self.dupExprs(elements), .multiline = true } };
    }
    /// `Vec<u8>`, `Result<T, Error>`.
    pub fn generic(self: Builder, base: Expr, args: []const Expr) !Expr {
        return .{ .generic = .{ .base = try self.box(base), .args = try self.dupExprs(args) } };
    }
    pub fn sliceOf(self: Builder, inner: Expr) !Expr {
        return .{ .slice = try self.box(inner) };
    }
    pub fn blockExpr(self: Builder, body: []const Stmt) !Expr {
        return .{ .block = try self.dupStmts(body) };
    }
    pub fn matchExpr(self: Builder, value: Expr, arms: []const Match.Arm) !Expr {
        const boxed = try self.allocator.create(Match);
        boxed.* = try self.matchOf(value, arms);
        return .{ .match_expr = boxed };
    }

    /// An `if` used for its value, which is what a Rust hook writes where a Go
    /// one would write a ternary-shaped helper.
    pub fn ifExpr(self: Builder, spec: struct {
        cond: Expr,
        body: []const Stmt,
        else_body: ?[]const Stmt = null,
        otherwise: ?If = null,
    }) !Expr {
        const boxed = try self.allocator.create(If);
        boxed.* = try self.ifOf(spec.cond, spec.body, spec.else_body, spec.otherwise);
        return .{ .if_expr = boxed };
    }

    // -- statements ----------------------------------------------------

    pub fn rawStmt(_: Builder, text: []const u8) Stmt {
        return .{ .raw = text };
    }
    pub fn commentStmt(_: Builder, text: []const u8) Stmt {
        return .{ .comment = .{ .line = text } };
    }
    pub fn blankLine(_: Builder) Stmt {
        return .blank;
    }
    pub fn let(_: Builder, name: []const u8, type_node: ?Expr, value: ?Expr) Stmt {
        return .{ .let = .{ .name = name, .type = type_node, .value = value } };
    }
    pub fn letMut(_: Builder, name: []const u8, type_node: ?Expr, value: ?Expr) Stmt {
        return .{ .let = .{ .mutable = true, .name = name, .type = type_node, .value = value } };
    }
    pub fn exprStmt(_: Builder, node: Expr) Stmt {
        return .{ .expr = node };
    }
    /// The block's value: the last statement of a body, with no semicolon.
    pub fn tail(_: Builder, node: Expr) Stmt {
        return .{ .tail = node };
    }
    pub fn ret(_: Builder, value: ?Expr) Stmt {
        return .{ .ret = value };
    }
    pub fn assign(_: Builder, lhs: Expr, op: []const u8, rhs: Expr) Stmt {
        return .{ .assign = .{ .lhs = lhs, .op = op, .rhs = rhs } };
    }
    pub fn blockStmt(self: Builder, body: []const Stmt) !Stmt {
        return .{ .block = try self.dupStmts(body) };
    }
    pub fn forLoop(self: Builder, pattern: []const u8, over: Expr, body: []const Stmt) !Stmt {
        return .{ .for_loop = .{ .pattern = pattern, .over = over, .body = try self.dupStmts(body) } };
    }
    pub fn whileLoop(self: Builder, cond: Expr, body: []const Stmt) !Stmt {
        return .{ .while_loop = .{ .cond = cond, .body = try self.dupStmts(body) } };
    }
    pub fn loopStmt(self: Builder, body: []const Stmt) !Stmt {
        return .{ .loop_stmt = try self.dupStmts(body) };
    }
    pub fn matchStmt(self: Builder, value: Expr, arms: []const Match.Arm) !Stmt {
        return .{ .match_stmt = try self.matchOf(value, arms) };
    }

    /// `if cond { body }`, with an optional `else` branch. Pass another `if`
    /// as `otherwise` for `else if`.
    pub fn ifStmt(self: Builder, spec: struct {
        cond: Expr,
        body: []const Stmt,
        else_body: ?[]const Stmt = null,
        otherwise: ?If = null,
    }) !Stmt {
        return .{ .if_stmt = try self.ifOf(spec.cond, spec.body, spec.else_body, spec.otherwise) };
    }

    /// The same, as the `If` an `else if` chain is built from.
    pub fn ifBranch(self: Builder, spec: struct {
        cond: Expr,
        body: []const Stmt,
        else_body: ?[]const Stmt = null,
        otherwise: ?If = null,
    }) !If {
        return self.ifOf(spec.cond, spec.body, spec.else_body, spec.otherwise);
    }

    fn ifOf(self: Builder, cond: Expr, body: []const Stmt, else_body: ?[]const Stmt, otherwise: ?If) !If {
        const branch: ?If.Else = if (otherwise) |nested|
            .{ .if_branch = nested }
        else if (else_body) |rest|
            .{ .block = try self.dupStmts(rest) }
        else
            null;
        return .{
            .cond = cond,
            .body = try self.dupStmts(body),
            .@"else" = if (branch) |value| blk: {
                const boxed = try self.allocator.create(If.Else);
                boxed.* = value;
                break :blk boxed;
            } else null,
        };
    }

    fn matchOf(self: Builder, value: Expr, arms: []const Match.Arm) !Match {
        const copied = try self.allocator.alloc(Match.Arm, arms.len);
        for (copied, arms) |*entry, source| {
            entry.* = source;
            if (source.body == .block) entry.body = .{ .block = try self.dupStmts(source.body.block) };
        }
        return .{ .value = value, .arms = copied };
    }

    // -- items ---------------------------------------------------------

    pub fn use(_: Builder, spec: Item.Use) Item {
        return .{ .use = spec };
    }
    pub fn module(self: Builder, spec: Item.Module) !Item {
        var value = spec;
        if (spec.items) |items| value.items = try self.dupItems(items);
        return .{ .module = value };
    }
    pub fn func(self: Builder, spec: Item.Func) !Item {
        var value = spec;
        value.body = try self.dupStmts(spec.body);
        if (spec.signature == .explicit) value.signature = .{ .explicit = .{
            .receiver = spec.signature.explicit.receiver,
            .params = try self.allocator.dupe(Param, spec.signature.explicit.params),
            .result = spec.signature.explicit.result,
        } };
        return .{ .func = value };
    }
    pub fn implBlock(self: Builder, spec: Item.Impl) !Item {
        var value = spec;
        value.items = try self.dupItems(spec.items);
        return .{ .impl_block = value };
    }
    pub fn structItem(self: Builder, spec: Item.Struct) !Item {
        var value = spec;
        value.body = switch (spec.body) {
            .unit => .unit,
            .tuple => |fields| .{ .tuple = try self.allocator.dupe(StructBody.TupleField, fields) },
            .named => |fields| .{ .named = try self.allocator.dupe(Field, fields) },
        };
        return .{ .struct_item = value };
    }
    pub fn enumItem(self: Builder, spec: Item.Enum) !Item {
        var value = spec;
        value.variants = try self.allocator.dupe(Variant, spec.variants);
        return .{ .enum_item = value };
    }
    pub fn constItem(_: Builder, spec: Item.Const) Item {
        return .{ .const_item = spec };
    }
    pub fn staticItem(_: Builder, spec: Item.Static) Item {
        return .{ .static_item = spec };
    }

    // -- arena helpers -------------------------------------------------

    pub fn dupExprs(self: Builder, list: []const Expr) ![]const Expr {
        return self.allocator.dupe(Expr, list);
    }
    pub fn dupStmts(self: Builder, list: []const Stmt) ![]const Stmt {
        return self.allocator.dupe(Stmt, list);
    }
    pub fn dupItems(self: Builder, list: []const Item) ![]const Item {
        return self.allocator.dupe(Item, list);
    }
    pub fn dupFieldValues(self: Builder, list: []const Expr.FieldValue) ![]const Expr.FieldValue {
        return self.allocator.dupe(Expr.FieldValue, list);
    }

    fn box(self: Builder, value: Expr) !*const Expr {
        const node = try self.allocator.create(Expr);
        node.* = value;
        return node;
    }
};

fn writeVisibility(writer: *std.Io.Writer, visibility: Visibility) !void {
    switch (visibility) {
        .private => {},
        .public => try writer.writeAll("pub "),
        .crate => try writer.writeAll("pub(crate) "),
    }
}

fn indent(writer: *std.Io.Writer, depth: usize) !void {
    try writer.splatByteAll(' ', depth * 4);
}

// -- tests -------------------------------------------------------------

/// Writers that answer with fixed spellings, so the tests below check what
/// the builder does with a generator answer rather than what the generator
/// says.
const test_writers: plugin.RustWriters = .{
    .writeTypeName = struct {
        fn f(_: plugin.RustContext, writer: *std.Io.Writer, name: []const u8) anyerror!void {
            return writer.print("crate::{s}", .{name});
        }
    }.f,
    .writeSignature = struct {
        fn f(_: plugin.RustContext, writer: *std.Io.Writer, _: abi.AbiFn, options: plugin.RustSignatureOptions) anyerror!void {
            return writer.writeAll(if (options.receiver) "(&self, count: u32) -> Result<u8, Error>" else "(count: u32) -> Result<u8, Error>");
        }
    }.f,
    .receiverFormAlloc = struct {
        fn f(_: plugin.RustContext, allocator: std.mem.Allocator, _: abi.AbiFn) anyerror!?[]u8 {
            const form: []u8 = try allocator.dupe(u8, "&self");
            return form;
        }
    }.f,
    .identifierAlloc = identifierAlloc,
    .functionInfo = struct {
        fn f(_: plugin.RustContext, _: abi.AbiFn) anyerror!plugin.RustFunctionInfo {
            return .{ .public_name = "take", .is_public = true, .has_error = true };
        }
    }.f,
};

fn testBuilder(allocator: std.mem.Allocator) Builder {
    const context: plugin.RustContext = .{
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
        .{ .expected = "core::fmt::Result", .node = b.path("core::fmt::Result") },
        .{ .expected = "crate::Mode", .node = b.typeName("Mode") },
        .{ .expected = "\"tab\\t\\\"q\\\"\"", .node = b.string("tab\t\"q\"") },
        .{ .expected = "-12", .node = b.int(-12) },
        .{ .expected = "1.5", .node = b.float("1.5") },
        .{ .expected = "true", .node = b.boolean(true) },
        .{ .expected = "()", .node = .unit },
        .{ .expected = "self.handle", .node = try b.fieldOf(b.path("self"), "handle") },
        .{ .expected = "items[index]", .node = try b.indexExpr(b.path("items"), b.path("index")) },
        .{ .expected = "u8::from(value)", .node = try b.callPath("u8::from", &.{b.path("value")}) },
        .{ .expected = "value.as_slice()", .node = try b.methodCall(b.path("value"), "as_slice", &.{}) },
        .{ .expected = "&value", .node = try b.addr(b.path("value")) },
        .{ .expected = "&mut value", .node = try b.addrMut(b.path("value")) },
        .{ .expected = "&'owner mut [u8]", .node = try b.refType("'owner", true, try b.sliceOf(b.path("u8"))) },
        .{ .expected = "*pointer", .node = try b.deref(b.path("pointer")) },
        .{ .expected = "!ok", .node = try b.not(b.path("ok")) },
        .{ .expected = "a && b", .node = try b.bin("&&", b.path("a"), b.path("b")) },
        .{ .expected = "(a)", .node = try b.paren(b.path("a")) },
        .{ .expected = "read()?", .node = try b.tryExpr(try b.callPath("read", &.{})) },
        .{ .expected = "value as u8", .node = try b.cast(b.path("value"), b.path("u8")) },
        .{ .expected = "0..=3", .node = try b.range(b.int(0), b.int(3), true) },
        .{ .expected = "|item| item.len()", .node = try b.closure(&.{.{ .name = "item" }}, try b.methodCall(b.path("item"), "len", &.{})) },
        .{ .expected = "format!(\"{}\", value)", .node = try b.format(&.{ b.string("{}"), b.path("value") }) },
        .{ .expected = "vec![1, 2]", .node = try b.vec(&.{ b.int(1), b.int(2) }) },
        .{ .expected = "Point { x: 1 }", .node = try b.structLiteral(b.path("Point"), &.{.{ .name = "x", .value = b.int(1) }}) },
        .{ .expected = "Point {\n    x: 1,\n}", .node = try b.structLiteralLines(b.path("Point"), &.{.{ .name = "x", .value = b.int(1) }}) },
        .{ .expected = "(a, b)", .node = try b.tuple(&.{ b.path("a"), b.path("b") }) },
        .{ .expected = "(a,)", .node = try b.tuple(&.{b.path("a")}) },
        .{ .expected = "[1, 2]", .node = try b.array(&.{ b.int(1), b.int(2) }) },
        .{ .expected = "Result<u8, Error>", .node = try b.generic(b.path("Result"), &.{ b.path("u8"), b.path("Error") }) },
        .{ .expected = "[u8]", .node = try b.sliceOf(b.path("u8")) },
        .{ .expected = "{\n    1\n}", .node = try b.blockExpr(&.{b.tail(b.int(1))}) },
        .{ .expected = "match value {\n    0 => \"zero\",\n    other if other > 0 => \"positive\",\n    _ => \"negative\",\n}", .node = try b.matchExpr(b.path("value"), &.{
            .{ .pattern = "0", .body = .{ .expr = b.string("zero") } },
            .{ .pattern = "other", .guard = try b.bin(">", b.path("other"), b.int(0)), .body = .{ .expr = b.string("positive") } },
            .{ .pattern = "_", .body = .{ .expr = b.string("negative") } },
        }) },
    };
    for (cases) |case| {
        output.clearRetainingCapacity();
        try b.renderExpr(&output.writer, case.node, 0);
        try std.testing.expectEqualStrings(case.expected, output.written());
    }
}

test "every statement kind renders at its depth" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const b = testBuilder(arena.allocator());
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try b.renderBody(&output.writer, &.{
        b.rawStmt("let raw = 1;"),
        b.commentStmt("a comment"),
        .blank,
        b.let("zero", b.path("u8"), b.int(0)),
        b.letMut("total", null, b.int(1)),
        b.exprStmt(try b.callPath("work", &.{})),
        b.assign(b.path("total"), "+=", b.int(2)),
        b.ret(b.path("total")),
        try b.ifStmt(.{
            .cond = try b.bin("==", b.path("total"), b.int(0)),
            .body = &.{b.ret(null)},
            .otherwise = try b.ifBranch(.{
                .cond = b.path("ok"),
                .body = &.{.continue_stmt},
                .else_body = &.{.break_stmt},
            }),
        }),
        try b.matchStmt(b.path("mode"), &.{.{ .pattern = "_", .body = .{ .block = &.{b.exprStmt(try b.callPath("noop", &.{}))} } }}),
        try b.forLoop("item", b.path("items"), &.{.continue_stmt}),
        try b.whileLoop(b.path("running"), &.{.break_stmt}),
        try b.loopStmt(&.{.break_stmt}),
        try b.blockStmt(&.{b.exprStmt(b.path("scoped"))}),
        b.tail(b.path("total")),
    }, 1);
    try std.testing.expectEqualStrings(
        "    let raw = 1;\n" ++
            "    // a comment\n" ++
            "\n" ++
            "    let zero: u8 = 0;\n" ++
            "    let mut total = 1;\n" ++
            "    work();\n" ++
            "    total += 2;\n" ++
            "    return total;\n" ++
            "    if total == 0 {\n" ++
            "        return;\n" ++
            "    } else if ok {\n" ++
            "        continue;\n" ++
            "    } else {\n" ++
            "        break;\n" ++
            "    }\n" ++
            "    match mode {\n" ++
            "        _ => {\n" ++
            "            noop();\n" ++
            "        }\n" ++
            "    }\n" ++
            "    for item in items {\n" ++
            "        continue;\n" ++
            "    }\n" ++
            "    while running {\n" ++
            "        break;\n" ++
            "    }\n" ++
            "    loop {\n" ++
            "        break;\n" ++
            "    }\n" ++
            "    {\n" ++
            "        scoped;\n" ++
            "    }\n" ++
            "    total\n",
        output.written(),
    );
}

test "a comment statement is written with the marker its doc kind asks for" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const b = testBuilder(arena.allocator());
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try b.render(&output.writer, &.{
        .{ .comment = .{ .module = "The crate's own module doc.\n\nA second paragraph." } },
        .{ .comment = .{ .text = "An item doc with no item." } },
        .{ .comment = .{ .line = "an ordinary comment" } },
        .{ .comment = .{ .rendered = "// written as it is" } },
    }, .{ .blank_between = false });
    try std.testing.expectEqualStrings(
        "//! The crate's own module doc.\n//!\n//! A second paragraph.\n" ++
            "/// An item doc with no item.\n" ++
            "// an ordinary comment\n" ++
            "// written as it is\n",
        output.written(),
    );
}

test "every item kind renders, with the layout the caller asked for" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const b = testBuilder(arena.allocator());
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try b.render(&output.writer, &.{
        b.use(.{ .path = "core::fmt::Write" }),
        b.use(.{ .visibility = .crate, .path = "crate::raw", .alias = "native" }),
        try b.module(.{ .visibility = .public, .name = "helpers" }),
        try b.module(.{ .attributes = &.{"cfg(test)"}, .name = "tests", .items = &.{
            try b.func(.{ .attributes = &.{"test"}, .name = "marker_is_stable", .body = &.{b.exprStmt(try b.macroCall("assert", .paren, &.{b.boolean(true)}))} }),
        } }),
        b.constItem(.{ .doc = .{ .text = "The plugin's own name." }, .visibility = .public, .name = "ZIGO_TEST_PLUGIN", .type = b.path("&'static str"), .value = b.string("TEST") }),
        b.staticItem(.{ .visibility = .crate, .mutable = true, .name = "COUNT", .type = b.path("u32"), .value = b.int(0) }),
        try b.structItem(.{
            .doc = .{ .text = "The shape on the wire." },
            .attributes = &.{"derive(Debug, Clone)"},
            .visibility = .public,
            .name = "Wire",
            .body = .{ .named = &.{
                .{ .doc = .{ .text = "The red channel." }, .visibility = .public, .name = "red", .type = b.path("u8") },
                .{ .name = "codepoint", .type = b.path("char") },
            } },
        }),
        try b.structItem(.{ .visibility = .public, .name = "Tag", .body = .{ .tuple = &.{.{ .visibility = .crate, .type = b.path("u8") }} } }),
        try b.structItem(.{ .visibility = .public, .name = "Marker", .generics = "<'a>", .body = .unit }),
        try b.enumItem(.{
            .attributes = &.{"repr(u8)"},
            .visibility = .public,
            .name = "Mode",
            .variants = &.{
                .{ .doc = .{ .text = "The idle mode." }, .name = "Idle", .value = b.int(0) },
                .{ .name = "Named", .payload = .{ .tuple = &.{b.path("String")} } },
                .{ .name = "Point", .payload = .{ .named = &.{.{ .name = "x", .type = b.path("i32") }} } },
            },
        }),
        try b.implBlock(.{ .type = b.path("Wire"), .items = &.{
            try b.func(.{
                .doc = .{ .text = "Takes one." },
                .visibility = .public,
                .name = "take",
                .signature = .{ .function = .{ .function = testFunction() } },
                .body = &.{b.tail(try b.callPath("Ok", &.{b.int(0)}))},
            }),
        } }),
        try b.implBlock(.{
            .generics = "<'a>",
            .trait = try b.generic(b.path("core::convert::From"), &.{b.path("u8")}),
            .type = try b.generic(b.path("Marker"), &.{b.path("'a")}),
            .items = &.{
                try b.func(.{
                    .name = "from",
                    .signature = .{ .explicit = .{ .params = &.{.{ .name = "value", .type = b.path("u8") }}, .result = b.path("Self") } },
                    .body = &.{b.tail(try b.callPath("Self::new", &.{b.path("value")}))},
                }),
            },
        }),
        try b.func(.{
            .visibility = .public,
            .unsafe_fn = true,
            .name = "raw_count",
            .generics = "<T>",
            .signature = .{ .explicit = .{ .receiver = .reference, .params = &.{.{ .name = "items", .type = try b.refType(null, false, try b.sliceOf(b.path("T"))) }}, .result = b.path("usize") } },
            .where_clause = "T: Copy",
            .body = &.{b.tail(try b.methodCall(b.path("items"), "len", &.{}))},
        }),
    }, .{});
    try std.testing.expectEqualStrings(
        \\use core::fmt::Write;
        \\
        \\pub(crate) use crate::raw as native;
        \\
        \\pub mod helpers;
        \\
        \\#[cfg(test)]
        \\mod tests {
        \\    #[test]
        \\    fn marker_is_stable() {
        \\        assert!(true);
        \\    }
        \\}
        \\
        \\/// The plugin's own name.
        \\pub const ZIGO_TEST_PLUGIN: &'static str = "TEST";
        \\
        \\pub(crate) static mut COUNT: u32 = 0;
        \\
        \\/// The shape on the wire.
        \\#[derive(Debug, Clone)]
        \\pub struct Wire {
        \\    /// The red channel.
        \\    pub red: u8,
        \\    codepoint: char,
        \\}
        \\
        \\pub struct Tag(pub(crate) u8);
        \\
        \\pub struct Marker<'a>;
        \\
        \\#[repr(u8)]
        \\pub enum Mode {
        \\    /// The idle mode.
        \\    Idle = 0,
        \\    Named(String),
        \\    Point {
        \\        x: i32,
        \\    },
        \\}
        \\
        \\impl Wire {
        \\    /// Takes one.
        \\    pub fn take(&self, count: u32) -> Result<u8, Error> {
        \\        Ok(0)
        \\    }
        \\}
        \\
        \\impl<'a> core::convert::From<u8> for Marker<'a> {
        \\    fn from(value: u8) -> Self {
        \\        Self::new(value)
        \\    }
        \\}
        \\
        \\pub unsafe fn raw_count<T>(&self, items: &[T]) -> usize
        \\where
        \\    T: Copy,
        \\{
        \\    items.len()
        \\}
        \\
    , output.written());
}

test "a name is spelled in each of Rust's three casings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const context: plugin.RustContext = .{
        .allocator = allocator,
        .program = .{ .package = "test", .prefix = "zg", .functions = &.{} },
        .options = .{},
        .writers = &test_writers,
    };
    try std.testing.expectEqualStrings("low_water", try context.identifierAlloc(allocator, "lowWater", .snake));
    try std.testing.expectEqualStrings("LowWater", try context.identifierAlloc(allocator, "low_water", .pascal));
    try std.testing.expectEqualStrings("LOW_WATER", try context.identifierAlloc(allocator, "lowWater", .screaming));
}

test "a hook without an output buffer is told so rather than writing nowhere" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const b = testBuilder(arena.allocator());
    try std.testing.expectError(error.NoBuilderOutput, b.emit(&.{b.use(.{ .path = "core::fmt" })}, .{}));
}

test "rustfmt leaves a rendered file alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const b = testBuilder(allocator);
    var output: std.Io.Writer.Allocating = .init(allocator);
    try b.render(&output.writer, &.{
        .{ .comment = .{ .module = "A module the builder wrote." } },
        b.use(.{ .path = "core::fmt::Write" }),
        try b.structItem(.{
            .attributes = &.{"derive(Debug, Clone, Copy)"},
            .visibility = .public,
            .name = "Counter",
            .body = .{ .named = &.{
                .{ .visibility = .public, .name = "count", .type = b.path("u32") },
                .{ .name = "closed", .type = b.path("bool") },
            } },
        }),
        try b.implBlock(.{ .type = b.path("Counter"), .items = &.{
            try b.func(.{
                .doc = .{ .text = "The count, or none once the counter is closed." },
                .visibility = .public,
                .name = "value",
                .signature = .{ .explicit = .{ .receiver = .reference, .result = try b.generic(b.path("Option"), &.{b.path("u32")}) } },
                .body = &.{
                    try b.ifStmt(.{
                        .cond = try b.fieldOf(b.path("self"), "closed"),
                        .body = &.{b.ret(b.path("None"))},
                    }),
                    try b.forLoop("_step", try b.range(b.int(0), b.int(3), false), &.{.continue_stmt}),
                    b.tail(try b.callPath("Some", &.{try b.fieldOf(b.path("self"), "count")})),
                },
            }),
            try b.func(.{
                .visibility = .public,
                .name = "label",
                .signature = .{ .explicit = .{ .receiver = .reference, .result = b.path("String") } },
                .body = &.{try b.matchStmt(try b.fieldOf(b.path("self"), "closed"), &.{
                    .{ .pattern = "true", .body = .{ .expr = try b.methodCall(b.string("closed"), "to_string", &.{}) } },
                    .{ .pattern = "false", .body = .{ .block = &.{b.tail(try b.format(&.{ b.string("open({})"), try b.fieldOf(b.path("self"), "count") }))} } },
                })},
            }),
        } }),
    }, .{});

    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "sample.rs", .data = output.written() });
    const result = std.process.run(allocator, std.testing.io, .{
        .argv = &.{ "rustfmt", "--edition", "2021", "--check", "sample.rs" },
        .cwd = .{ .dir = directory.dir },
    }) catch |err| switch (err) {
        // CONTRIBUTING asks for a Rust toolchain, but a checkout without one
        // should still run the rest of the suite.
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    try std.testing.expectEqualStrings("", result.stderr);
    try std.testing.expectEqualStrings("", result.stdout);
}
