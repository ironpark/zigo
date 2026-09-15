//! `satisfies`: the compile-time assertion that a generated Go type implements
//! an interface the binding names.
//!
//! Go has no way to declare that a type implements an interface, so the idiom
//! is `var _ io.ReadWriteCloser = (*Document)(nil)`: a compiler error the day
//! a method changes shape, rather than a caller's build breaking later. Writing
//! that line by hand means keeping a file next to generated code, which is
//! what a visit of the type node is for.
//!
//! The assertion is the backstop, not the report. A claim is checked here
//! first: a standard-library interface has to be one this plugin knows, and a
//! claimed method set has to be one the handle's generated methods cover. What
//! reaches `go build` is then only what the generator could not decide.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const plugin_api = @import("plugin");
const semantic = @import("semantic");

/// The plugin's name: the `ext` key its options travel under and the prefix
/// of the diagnostics it reports.
pub const name = "SATIS";

/// Unresolved references are core's `SATIS002`, so this plugin's own rules
/// start at 003.
const unknown_interface_code = name ++ "003";
const missing_method_code = name ++ "004";

/// What a declaration says with `use(satisfies.plugin, .{ ... })`.
///
/// The two lists are separate rather than one list of a union: a union field
/// has no authoring mapping, so `.{ .entry = ... }` could not be written for
/// it, and a bare string in `interfaces` keeps the wire form every existing
/// document already has.
pub const Options = struct {
    /// Which method set the assertion checks; pointer preserves the legacy default.
    form: enum { pointer, value } = .pointer,
    /// Go standard-library interfaces, such as `io.ReadWriteCloser`. The name
    /// has to be one of the ones listed in `standard_interfaces`: the
    /// qualifier is what brings the package into the generated file, and the
    /// method set is what the claim is checked against.
    interfaces: []const []const u8 = &.{},
    /// Interfaces this binding declared with `zigo.interface(...)`, named as
    /// references: `.{ .entry = Counter }` or `.{ .name = "Counter" }`.
    generated: []const plugin_api.ref.Interface = &.{},
};

pub const plugin: plugin_api.Plugin = .{
    .name = name,
    .TypeOptions = Options,
    .subjects = &.{ .handle, .value, .enumeration, .tagged_union },
    .validate = validateDocument,
    .analyze = analyze,
    .go = .{ .visit = visit },
};

/// One method of a claimed interface: the Go name and the signature as
/// `writeSignature` spells it without parameter names, which is the form two
/// method sets can be compared in.
const Method = struct {
    name: []const u8,
    signature: []const u8,
};

const StandardInterface = struct {
    name: []const u8,
    methods: []const Method,
};

const close: Method = .{ .name = "Close", .signature = "() error" };
const read: Method = .{ .name = "Read", .signature = "([]byte) (int, error)" };
const write: Method = .{ .name = "Write", .signature = "([]byte) (int, error)" };

/// The Go standard-library interfaces this plugin can check a claim against.
/// A name outside the list is reported rather than passed through: an
/// unchecked name would only be read by `go build`, in generated code the
/// user did not write. Extending the list is the way to claim one more.
const standard_interfaces = [_]StandardInterface{
    .{ .name = "error", .methods = &.{.{ .name = "Error", .signature = "() string" }} },
    .{ .name = "fmt.Stringer", .methods = &.{.{ .name = "String", .signature = "() string" }} },
    .{ .name = "fmt.GoStringer", .methods = &.{.{ .name = "GoString", .signature = "() string" }} },
    .{ .name = "io.Reader", .methods = &.{read} },
    .{ .name = "io.Writer", .methods = &.{write} },
    .{ .name = "io.Closer", .methods = &.{close} },
    .{ .name = "io.ReadWriter", .methods = &.{ read, write } },
    .{ .name = "io.ReadCloser", .methods = &.{ read, close } },
    .{ .name = "io.WriteCloser", .methods = &.{ write, close } },
    .{ .name = "io.ReadWriteCloser", .methods = &.{ read, write, close } },
    .{ .name = "io.ReaderFrom", .methods = &.{.{ .name = "ReadFrom", .signature = "(io.Reader) (int64, error)" }} },
    .{ .name = "io.WriterTo", .methods = &.{.{ .name = "WriteTo", .signature = "(io.Writer) (int64, error)" }} },
    .{ .name = "io.StringWriter", .methods = &.{.{ .name = "WriteString", .signature = "(string) (int, error)" }} },
    .{ .name = "io.ByteReader", .methods = &.{.{ .name = "ReadByte", .signature = "() (byte, error)" }} },
    .{ .name = "io.ByteWriter", .methods = &.{.{ .name = "WriteByte", .signature = "(byte) error" }} },
    .{ .name = "io.RuneReader", .methods = &.{.{ .name = "ReadRune", .signature = "() (rune, int, error)" }} },
    .{ .name = "io.Seeker", .methods = &.{.{ .name = "Seek", .signature = "(int64, int) (int64, error)" }} },
    .{ .name = "encoding.TextMarshaler", .methods = &.{.{ .name = "MarshalText", .signature = "() ([]byte, error)" }} },
    .{ .name = "encoding.TextUnmarshaler", .methods = &.{.{ .name = "UnmarshalText", .signature = "([]byte) error" }} },
    .{ .name = "encoding.BinaryMarshaler", .methods = &.{.{ .name = "MarshalBinary", .signature = "() ([]byte, error)" }} },
    .{ .name = "encoding.BinaryUnmarshaler", .methods = &.{.{ .name = "UnmarshalBinary", .signature = "([]byte) error" }} },
    .{ .name = "json.Marshaler", .methods = &.{.{ .name = "MarshalJSON", .signature = "() ([]byte, error)" }} },
    .{ .name = "json.Unmarshaler", .methods = &.{.{ .name = "UnmarshalJSON", .signature = "([]byte) error" }} },
    .{ .name = "sort.Interface", .methods = &.{
        .{ .name = "Len", .signature = "() int" },
        .{ .name = "Less", .signature = "(int, int) bool" },
        .{ .name = "Swap", .signature = "(int, int)" },
    } },
};

/// The table entry for a claimed name, or null when the plugin does not know
/// the interface.
fn standardInterface(interface: []const u8) ?StandardInterface {
    for (standard_interfaces) |entry| {
        if (std.mem.eql(u8, entry.name, interface)) return entry;
    }
    return null;
}

/// The assertion goes after the type, in the file that declares it, so the
/// two are read together and `go build` reports them together.
fn visit(context: plugin_api.GoContext, node: plugin_api.Node, b: *plugin_api.Builder) !void {
    if (node != .type) return;
    const declaration = node.type;
    const options = try context.optionsOf(plugin, .type, node) orelse return;
    for (options.interfaces) |interface| try emitAssertion(context, b, declaration.name, b.raw(interface), interface, options.form);
    for (options.generated) |reference| {
        // A reference that resolves to nothing is core's `SATIS002`; there is
        // nothing left for this hook to write.
        const interface = try context.resolveInterface(reference) orelse continue;
        try emitAssertion(context, b, declaration.name, b.ident(interface.name), interface.name, options.form);
    }
}

fn emitAssertion(
    context: plugin_api.GoContext,
    b: *plugin_api.Builder,
    type_name: []const u8,
    interface: plugin_api.gobuild.Expr,
    interface_name: []const u8,
    form: @FieldType(Options, "form"),
) !void {
    const doc = try std.fmt.allocPrint(context.allocator, "{0s} satisfies {1s}; this assertion stops compiling the day it does not.", .{ type_name, interface_name });
    defer context.allocator.free(doc);
    try b.emit(&.{try b.assertImplements(.{
        .doc = .{ .text = doc },
        .interface = interface,
        .type_name = type_name,
        // A typed zero works for enums and other non-struct value types too.
        .form = switch (form) {
            .pointer => .pointer,
            .value => .value,
        },
    })}, .{ .blank_after = true });
}

/// A name Go cannot resolve would reach the user as a compile error in
/// generated code, which is exactly the report a plugin exists to replace.
/// The document alone answers this one: a standard-library name is either in
/// the table or it is not.
fn validateDocument(context: plugin_api.ValidateContext) !void {
    const allocator = context.allocator;
    const document = context.document;
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    errdefer issues.deinit(allocator);
    for (document.types) |declaration| {
        const options = try context.optionsOf(plugin, .type, declaration.ext) orelse continue;
        for (options.interfaces) |interface| {
            if (standardInterface(interface) != null) continue;
            try issues.append(allocator, .{
                .severity = .@"error",
                .code = unknown_interface_code,
                .message = try std.fmt.allocPrint(allocator, "`{s}` claims interface `{s}`, which is not a Go standard-library interface this plugin knows", .{ declaration.name, interface }),
                .site = plugin_api.site.typeSite(declaration),
                .hint = "name one of the standard interfaces the plugin lists, claim an interface this binding declared with `.generated`, or add the interface to the plugin's table",
            });
        }
    }
    for (issues.items) |issue| try context.diagnose(issue);
}

/// The claim itself, once the program exists: every method a claimed
/// interface requires has to be one the handle's generated methods spell the
/// same way.
///
/// Only a handle is checked. An enum or a value struct can be given the
/// method by hand in the public package -- which is how `fmt.Stringer` is
/// usually satisfied -- and absence of a generated method would prove nothing
/// there. For a handle the generated method set is the whole one, so a
/// missing method is a report rather than a `go build` failure later.
fn analyze(context: plugin_api.AnalyzeContext) !void {
    const go = context.go orelse return;
    const allocator = context.render.allocator;
    for (context.render.program.types) |declaration| {
        if (declaration.kind != .@"opaque") continue;
        const options = try context.optionsOf(plugin, .type, declaration.ext) orelse continue;
        if (options.interfaces.len == 0 and options.generated.len == 0) continue;
        const provided = try providedMethodsAlloc(go, declaration);
        defer allocator.free(provided);
        for (options.interfaces) |interface| {
            const entry = standardInterface(interface) orelse continue;
            try reportMissing(context, declaration, interface, entry.methods, provided);
        }
        for (options.generated) |reference| {
            const interface = try context.resolveInterface(reference) orelse continue;
            const required = try requiredMethodsAlloc(go, interface);
            defer allocator.free(required);
            try reportMissing(context, declaration, interface.name, required, provided);
        }
    }
}

/// The first method of `required` the type does not have, reported once per
/// interface: the following ones are usually the same omission read twice.
fn reportMissing(
    context: plugin_api.AnalyzeContext,
    declaration: semantic.TypeDecl,
    interface: []const u8,
    required: []const Method,
    provided: []const Method,
) !void {
    const allocator = context.render.allocator;
    for (required) |method| {
        var mismatched: ?Method = null;
        var covered = false;
        for (provided) |candidate| {
            if (!std.mem.eql(u8, candidate.name, method.name)) continue;
            if (std.mem.eql(u8, candidate.signature, method.signature)) {
                covered = true;
                break;
            }
            mismatched = candidate;
        }
        if (covered) continue;
        try context.diagnose(.{
            .severity = .@"error",
            .code = missing_method_code,
            .message = if (mismatched) |candidate| try std.fmt.allocPrint(allocator, "`{s}` claims interface `{s}`, but its `{s}` is `{s}{s}`, not `{s}{s}`", .{
                declaration.name, interface, method.name, candidate.name, candidate.signature, method.name, method.signature,
            }) else try std.fmt.allocPrint(allocator, "`{s}` claims interface `{s}`, but has no method `{s}{s}`", .{
                declaration.name, interface, method.name, method.signature,
            }),
            .site = plugin_api.site.typeSite(declaration),
            .hint = "bind a method with that name and signature, add it through `zigo.features.implements`, or drop the interface from the declaration",
        });
        return;
    }
}

/// The Go methods the generator writes for `declaration`, in the spelling a
/// claim is compared against.
fn providedMethodsAlloc(context: plugin_api.GoContext, declaration: semantic.TypeDecl) ![]Method {
    const allocator = context.allocator;
    var methods: std.ArrayList(Method) = .empty;
    errdefer methods.deinit(allocator);
    // Every handle that owns or borrows native state is given `Close`, and a
    // handle that has nothing to release is the only one that is not. The
    // credit is deliberate: claiming one method too many leaves the
    // assertion to catch it, while withholding one would report a method the
    // generator did write.
    try methods.append(allocator, close);
    for (context.program.functions) |function| {
        const receiver = function.origin.receiver orelse continue;
        if (!std.mem.eql(u8, receiver, declaration.name)) continue;
        // `.implements` wrappers are standard-library shaped by construction,
        // so the table says what they spell. They are read before the method
        // itself, which the wrappers usually hide.
        if (try context.optionsOf(plugin_api.builtins.implements.plugin, .function, function.origin.ext)) |implements| {
            for (implements.kinds) |kind| {
                const entry = standardInterface(kind.interfaceName()) orelse continue;
                try methods.appendSlice(allocator, entry.methods);
            }
        }
        const info = try context.functionInfo(function);
        if (!info.is_public) continue;
        try methods.append(allocator, .{ .name = info.public_name, .signature = try signatureAlloc(context, function) });
    }
    return methods.toOwnedSlice(allocator);
}

/// The method set a declared interface requires. The first implementing type
/// speaks for the interface, exactly as the file that spells it does, and an
/// interface that embeds `io.Closer` requires `Close` with it.
fn requiredMethodsAlloc(context: plugin_api.GoContext, interface: abi.AbiInterface) ![]Method {
    const allocator = context.allocator;
    var methods: std.ArrayList(Method) = .empty;
    errdefer methods.deinit(allocator);
    for (interface.methods) |method| {
        const function = method.functions[0].*;
        const info = try context.functionInfo(function);
        try methods.append(allocator, .{ .name = info.public_name, .signature = try signatureAlloc(context, function) });
    }
    if (interface.closer) try methods.append(allocator, close);
    return methods.toOwnedSlice(allocator);
}

/// The public signature of `function` without parameter names: Go does not
/// read them when it decides whether a method matches, and the plugin's own
/// table cannot spell them.
fn signatureAlloc(context: plugin_api.GoContext, function: abi.AbiFn) ![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(context.allocator);
    errdefer buffer.deinit();
    try context.writeSignatureWith(&buffer.writer, function, .{ .parameter_names = false });
    return buffer.toOwnedSlice();
}

const testing_support = struct {
    /// A rendering context whose signature writers answer: the test spells
    /// each method's Go name in `origin.name` and its nameless signature in
    /// `origin.doc`, which is what the generator's own writers would produce.
    fn goContext(allocator: std.mem.Allocator, program: abi.Program) plugin_api.GoContext {
        var context = plugin_api.testing.goContext(allocator, program);
        const writers = allocator.create(plugin_api.Writers) catch @panic("OOM");
        writers.* = context.writers.*;
        writers.functionInfo = info;
        writers.writeSignature = signature;
        context.writers = writers;
        return context;
    }

    fn info(_: plugin_api.GoContext, function: abi.AbiFn) anyerror!plugin_api.FunctionInfo {
        return .{ .public_name = function.origin.name, .is_public = true, .has_error = false };
    }

    fn signature(_: plugin_api.GoContext, writer: *std.Io.Writer, function: abi.AbiFn, _: plugin_api.SignatureOptions) anyerror!void {
        try writer.writeAll(function.origin.doc orelse "()");
    }

    fn method(function: *const semantic.SemanticFn) abi.AbiFn {
        return .{ .origin = function, .symbol = function.symbol, .params = &.{}, .ret = .void };
    }
};

test "each claimed interface gets one assertion in the requested form" {
    // Options read off `ext` live on the context's allocator, which the
    // generator backs with the run arena; the test does the same.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context = plugin_api.testing.goContext(arena.allocator(), .{ .package = "streams", .prefix = "zg", .functions = &.{} });
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var b = context.builder();
    b.out = &output.writer;
    const options = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), "{\"form\":\"value\",\"interfaces\":[\"fmt.Stringer\",\"io.Closer\"]}", .{});
    try visit(context, .{ .type = .{ .kind = .@"opaque", .name = "Document", .ext = .{ .entries = &.{.{ .plugin = name, .options = options }} } } }, &b);
    try std.testing.expectEqualStrings(
        "// Document satisfies fmt.Stringer; this assertion stops compiling the day it does not.\nvar _ fmt.Stringer = *new(Document)\n\n" ++
            "// Document satisfies io.Closer; this assertion stops compiling the day it does not.\nvar _ io.Closer = *new(Document)\n\n",
        output.written(),
    );
    output.clearRetainingCapacity();
    try visit(context, .{ .type = .{ .kind = .@"opaque", .name = "Document" } }, &b);
    try std.testing.expectEqualStrings("", output.written());
}

test "a declared interface is asserted under the name the program gives it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context = plugin_api.testing.goContext(arena.allocator(), .{
        .package = "streams",
        .prefix = "zg",
        .functions = &.{},
        .interfaces = &.{.{ .name = "Counter", .types = &.{"Document"}, .methods = &.{} }},
    });
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var b = context.builder();
    b.out = &output.writer;
    const options = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), "{\"generated\":[\"Counter\"]}", .{});
    try visit(context, .{ .type = .{ .kind = .@"opaque", .name = "Document", .ext = .{ .entries = &.{.{ .plugin = name, .options = options }} } } }, &b);
    try std.testing.expectEqualStrings(
        "// Document satisfies Counter; this assertion stops compiling the day it does not.\nvar _ Counter = (*Document)(nil)\n\n",
        output.written(),
    );
    // A reference to an interface the document never declared is core's
    // `SATIS002`; this hook writes nothing for it.
    output.clearRetainingCapacity();
    const missing = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), "{\"generated\":[\"Absent\"]}", .{});
    try visit(context, .{ .type = .{ .kind = .@"opaque", .name = "Document", .ext = .{ .entries = &.{.{ .plugin = name, .options = missing }} } } }, &b);
    try std.testing.expectEqualStrings("", output.written());
}

test "a standard interface outside the table is reported, a known one is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    var facts: plugin_api.Facts = .{};
    const claim = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"interfaces\":[\"io.ReadWriteCloser\",\"io.Nope\"]}", .{});
    const ext: semantic.Extensions = .{ .entries = &.{.{ .plugin = name, .options = claim }} };
    try validateDocument(.{
        .allocator = allocator,
        .document = .{
            .package = "streams",
            .prefix = "zg",
            .zig_version = "0.16.0",
            .types = &.{.{ .kind = .@"opaque", .name = "Document", .ext = ext }},
        },
        .diagnostics = &issues,
        .facts = &facts,
    });
    try std.testing.expectEqual(@as(usize, 1), issues.items.len);
    try std.testing.expectEqualStrings(unknown_interface_code, issues.items[0].code);
    try std.testing.expect(std.mem.indexOf(u8, issues.items[0].message, "`io.Nope`") != null);
}

test "a claimed method set the handle does not cover is reported" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `Document` is given the two standard-shaped wrappers through
    // `.implements` plus a bound `Count`; `Sink` is given nothing.
    const implements: semantic.Extensions = .{ .entries = &.{.{
        .plugin = plugin_api.builtins.implements.plugin.name,
        .options = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"kinds\":[\"reader\",\"writer\"]}", .{}),
    }} };
    const read_into: semantic.SemanticFn = .{ .name = "ReadInto", .doc = "([]byte) (int, error)", .receiver = "Document", .symbol = "zg_document_read_into", .params = &.{}, .@"return" = .{ .void = {} }, .ext = implements };
    const count: semantic.SemanticFn = .{ .name = "Count", .doc = "() (uint, error)", .receiver = "Document", .symbol = "zg_document_count", .params = &.{}, .@"return" = .{ .void = {} } };
    const functions = [_]abi.AbiFn{ testing_support.method(&read_into), testing_support.method(&count) };
    const counter: abi.AbiInterface = .{
        .name = "Counter",
        .closer = false,
        .types = &.{"Document"},
        .methods = &.{.{ .name = "count", .functions = &.{&functions[1]} }},
    };
    const claim: semantic.Extensions = .{ .entries = &.{.{
        .plugin = name,
        .options = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"interfaces\":[\"io.ReadWriteCloser\"],\"generated\":[\"Counter\"]}", .{}),
    }} };
    const program: abi.Program = .{
        .package = "streams",
        .prefix = "zg",
        .functions = &functions,
        .interfaces = &.{counter},
        .types = &.{
            .{ .kind = .@"opaque", .name = "Document", .ext = claim },
            .{ .kind = .@"opaque", .name = "Sink", .ext = claim },
        },
    };
    const go = testing_support.goContext(allocator, program);
    var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
    var facts: plugin_api.Facts = .{};
    try analyze(.{ .render = go.base(), .go = go, .facts = &facts, .diagnostics = &issues });

    // `Document` covers both claims: `Read` and `Write` come from the
    // wrappers, `Close` from the handle, `Count` from the binding. `Sink`
    // covers neither, and each interface reports its first missing method.
    try std.testing.expectEqual(@as(usize, 2), issues.items.len);
    for (issues.items) |issue| {
        try std.testing.expectEqualStrings(missing_method_code, issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "`Sink`") != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, issues.items[0].message, "`Read([]byte) (int, error)`") != null);
    try std.testing.expect(std.mem.indexOf(u8, issues.items[1].message, "`Count() (uint, error)`") != null);
}
