const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const lower = @import("lower.zig");
const naming = @import("naming");

pub const Options = struct {
    pub const Backend = enum { cgo, purego };
    go_module: []const u8 = "",
    raw_package_path: []const u8 = "internal/raw",
    raw_colocated: bool = false,
    backend: Backend = .cgo,
    go_package: []const u8 = "",
    go_package_path: []const u8 = "",
    library_search_paths: []const u8 = "",
    library_env_vars: ?[]const u8 = null,
    library_automatic: bool = false,
    library_exported_api: bool = true,
};

pub fn render(allocator: std.mem.Allocator, writer: *std.Io.Writer, document: semantic.Semantic, options: Options) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const scratch_allocator = scratch.allocator();
    var error_codes: std.ArrayList(abi.ErrorCode) = .empty;
    defer error_codes.deinit(scratch_allocator);
    for (document.functions) |function| if (function.@"return" == .error_union) {
        for (function.@"return".error_union.error_set) |name| {
            var exists = false;
            for (error_codes.items) |entry| if (std.mem.eql(u8, entry.name, name)) {
                exists = true;
                break;
            };
            if (!exists) try error_codes.append(scratch_allocator, .{ .code = @intCast(error_codes.items.len + 1), .name = name });
        }
    };
    const program = try lower.semanticDocumentForBackend(scratch_allocator, document, document.package, document.prefix, error_codes.items, switch (options.backend) {
        .cgo => .cgo,
        .purego => .purego,
    });
    try writer.writeAll("zigo binding report\n");
    try writer.print("package: {s}\n", .{document.package});
    {
        const go_package = if (options.go_package.len != 0)
            try scratch_allocator.dupe(u8, options.go_package)
        else
            try naming.snakeAlloc(scratch_allocator, document.package);
        const go_package_path = if (options.go_package_path.len != 0) options.go_package_path else go_package;
        try writer.print("Go package: {s}\n", .{go_package});
        try writer.print("Go package path: {s}\n", .{go_package_path});
        const base = naming.optionalPathSegment(go_package_path);
        if (options.go_module.len != 0) try writer.print("Go import path: {s}{s}{s}\n", .{
            options.go_module,
            base.separator,
            base.value,
        });
    }
    if (options.go_module.len != 0) try writer.print("go module: {s}\n", .{options.go_module});
    if (document.packages) |packages| for (packages) |package| {
        try writer.print("Go sub-package: {s} ({s})", .{ package.name, package.path });
        if (package.doc) |doc| try writer.print(" - {s}", .{doc});
        try writer.writeByte('\n');
    };
    try writer.print("C prefix: {s}\n", .{document.prefix});
    try writer.print("Zig version: {s}\n", .{document.zig_version});
    try writer.print("raw package: {s}\n", .{if (options.raw_colocated) "colocated" else options.raw_package_path});
    try writer.writeAll("automatic cleanup: always on (Go 1.24+)\n");
    try writer.print("backend: {s}\n", .{@tagName(options.backend)});
    try writer.print("callback ABI: {s}\n", .{@tagName(program.callback_convention)});
    if (options.backend == .purego) {
        try writer.print("library loading: {s}, loader API {s}\n", .{
            if (options.library_automatic) "automatic on first call" else "explicit LoadLibrary",
            if (options.library_exported_api) "exported" else "internal",
        });
        // The default matches the emitter: a package-specific name, then the shared one.
        const package = try naming.snakeAlloc(scratch_allocator, document.package);
        const specific = try naming.libraryPathEnvironmentAlloc(scratch_allocator, package);
        const default_names = try std.fmt.allocPrint(scratch_allocator, "{s},ZIGO_LIBRARY_PATH", .{specific});
        const env_names = options.library_env_vars orelse default_names;
        try writer.print("library environment: {s}\n", .{if (env_names.len == 0) "none" else env_names});
        try writer.print("library search paths: {s}\n", .{
            if (options.library_search_paths.len == 0) "none" else options.library_search_paths,
        });
    }

    try writer.print("\ntypes ({d})\n", .{document.types.len});
    for (document.types) |declaration| {
        try writer.print("- {s}: {s}", .{ declaration.name, @tagName(declaration.kind) });
        if (declaration.package) |package| try writer.print(" | package {s}", .{package});
        if (isHandleType(declaration)) {
            try writer.print(" | Go {s}, {s}Ref", .{ declaration.name, declaration.name });
            if (findConstructorForType(document, declaration.name)) |constructor|
                try writer.print(" | caller-owned via {s}, released by {s}/Close", .{ constructor.init, constructor.deinit })
            else
                try writer.writeAll(" | borrowed/library-owned handle");
        } else {
            try writer.print(" | Go {s}", .{declaration.name});
        }
        if (declaration.zig_path) |path| try writer.print(" | Zig {s}", .{path});
        try writer.writeByte('\n');
    }

    try writer.print("\nfunctions ({d})\n", .{program.functions.len});
    for (program.functions) |function| {
        const origin = function.origin.*;
        const identity = try semanticIdentityAlloc(scratch_allocator, origin);
        defer scratch_allocator.free(identity);
        const public_name = try publicFunctionNameAlloc(scratch_allocator, document, origin);
        defer scratch_allocator.free(public_name);
        try writer.print("- {s} -> {s} | C {s} | return ownership {s}", .{ identity, public_name, function.symbol, @tagName(origin.ownership) });
        if (origin.package) |package| try writer.print(" | package {s}", .{package});
        if (origin.return_semantic) |hint| try writer.print("/{s}", .{@tagName(hint)});
        for (origin.params) |parameter| {
            try writer.print(" | {s}:{s}/{s}/{s}", .{ parameter.name, typeName(parameter.type), @tagName(parameter.retention), @tagName(parameter.name_source) });
            if (parameter.semantic) |hint| try writer.print("/{s}", .{@tagName(hint)});
        }
        try writer.writeByte('\n');
    }

    try writer.print("\nprojections ({d})\n", .{program.projections.len});
    for (program.projections) |projection| switch (projection.kind) {
        .tag => try writer.print(
            "- {s}.tag -> (*{s}).TryTag/Tag and (*{s}Ref).TryTag/Tag | C {s}\n",
            .{ projection.owner.name, projection.owner.name, projection.owner.name, projection.symbol },
        ),
        .payload => {
            const go_field = try naming.pascalAlloc(scratch_allocator, projection.field.?.name);
            defer scratch_allocator.free(go_field);
            try writer.print(
                "- {s}.{s} -> (*{s}).TryAs{s}/As{s} and (*{s}Ref).TryAs{s}/As{s} | C {s}\n",
                .{ projection.owner.name, projection.field.?.name, projection.owner.name, go_field, go_field, projection.owner.name, go_field, go_field, projection.symbol },
            );
        },
    };
}

fn publicFunctionNameAlloc(allocator: std.mem.Allocator, document: semantic.Semantic, function: semantic.SemanticFn) ![]u8 {
    if (constructorForInit(document, function)) |constructor|
        return std.fmt.allocPrint(allocator, "New{s}", .{constructor.type});
    const name = try naming.pascalAlloc(allocator, function.name);
    defer allocator.free(name);
    if (constructorForDeinit(document, function) != null)
        return std.fmt.allocPrint(allocator, "(*{s}).Close [lifecycle mapping]", .{function.receiver.?});
    if (function.receiver) |receiver|
        return std.fmt.allocPrint(allocator, "(*{s}).{s}", .{ receiver, name });
    return allocator.dupe(u8, name);
}

fn semanticIdentityAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]u8 {
    if (function.receiver orelse function.namespace) |owner|
        return std.fmt.allocPrint(allocator, "{s}.{s}", .{ owner, function.name });
    return allocator.dupe(u8, function.name);
}

fn constructorForInit(document: semantic.Semantic, function: semantic.SemanticFn) ?semantic.Constructor {
    if (function.receiver != null) return null;
    for (document.constructors) |constructor| {
        if (std.mem.eql(u8, constructor.init, function.name) and std.mem.eql(u8, constructor.type, function.goOwner() orelse ""))
            return constructor;
    }
    return null;
}

fn constructorForDeinit(document: semantic.Semantic, function: semantic.SemanticFn) ?semantic.Constructor {
    const receiver = function.receiver orelse return null;
    for (document.constructors) |constructor| {
        if (std.mem.eql(u8, constructor.type, receiver) and std.mem.eql(u8, constructor.deinit, function.name))
            return constructor;
    }
    return null;
}

fn findConstructorForType(document: semantic.Semantic, name: []const u8) ?semantic.Constructor {
    for (document.constructors) |constructor| if (std.mem.eql(u8, constructor.type, name)) return constructor;
    return null;
}

fn isHandleType(declaration: semantic.TypeDecl) bool {
    return declaration.kind == .@"opaque" or declaration.kind == .tagged_union;
}

fn typeName(node: semantic.TypeNode) []const u8 {
    return switch (node) {
        .@"enum" => "enum",
        .opaque_ptr => "opaque_ptr",
        .value_struct => "value_struct",
        .error_union => "error_union",
        .optional => "optional",
        .callback => "callback",
        .io_stream => |value| switch (value.direction) {
            .writer => "io_writer",
            .reader => "io_reader",
        },
        .slice => "slice",
        .int => "int",
        .float => "float",
        .bool => "bool",
        .cancel_flag => "cancel_flag",
        .void => "void",
    };
}

test "report exposes final public names symbols ownership and projections" {
    var payload: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const document: semantic.Semantic = .{
        .constructors = &.{.{ .type = "Value", .init = "create", .deinit = "deinit" }},
        .functions = &.{
            .{ .name = "create", .namespace = "Value", .ownership = .caller, .params = &.{}, .@"return" = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Value" } }, .symbol = "ignored" },
            .{ .name = "set", .receiver = "Value", .params = &.{.{ .name = "input", .name_source = .ast, .retention = .retained, .type = .{ .slice = .{ .@"const" = true, .element = &payload } } }}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
            .{ .name = "deinit", .receiver = "Value", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
        },
        .package = "sample",
        .prefix = "zs",
        .types = &.{
            .{ .kind = .tagged_union, .name = "Value", .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } }, .fields = &.{.{ .name = "number", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 0 }} },
            .{ .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } }, .fields = &.{.{ .name = "number", .value = 0 }} },
        },
        .zig_version = "0.16.0",
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try render(std.testing.allocator, &output.writer, document, .{ .go_module = "example.com/sample" });
    const actual = output.written();
    try std.testing.expect(std.mem.indexOf(u8, actual, "Go package path: sample\nGo import path: example.com/sample/sample\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "Value.create -> NewValue | C zs_value_create | return ownership caller") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "Value.deinit -> (*Value).Close [lifecycle mapping]") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "input:slice/retained/ast") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "Value.number -> (*Value).TryAsNumber/AsNumber") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "backend: cgo\ncallback ABI: fixed_go_export") != null);

    var purego_output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer purego_output.deinit();
    try render(std.testing.allocator, &purego_output.writer, document, .{ .backend = .purego });
    try std.testing.expect(std.mem.indexOf(u8, purego_output.written(), "backend: purego\ncallback ABI: function_pointer_userdata_v2") != null);
}

test "purego report states the effective loading policy" {
    const document: semantic.Semantic = .{
        .functions = &.{},
        .package = "scalar",
        .prefix = "zg",
        .types = &.{},
        .zig_version = "0.16.0",
    };
    var explicit: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer explicit.deinit();
    try render(std.testing.allocator, &explicit.writer, document, .{ .backend = .purego });
    try std.testing.expect(std.mem.indexOf(u8, explicit.written(), "library loading: explicit LoadLibrary, loader API exported") != null);
    try std.testing.expect(std.mem.indexOf(u8, explicit.written(), "library environment: ZIGO_SCALAR_LIBRARY_PATH,ZIGO_LIBRARY_PATH") != null);
    try std.testing.expect(std.mem.indexOf(u8, explicit.written(), "library search paths: none") != null);

    var automatic: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer automatic.deinit();
    try render(std.testing.allocator, &automatic.writer, document, .{
        .backend = .purego,
        .library_search_paths = "${EXECUTABLE_DIR}:/opt/app/lib",
        .library_env_vars = "",
        .library_automatic = true,
        .library_exported_api = false,
    });
    try std.testing.expect(std.mem.indexOf(u8, automatic.written(), "library loading: automatic on first call, loader API internal") != null);
    try std.testing.expect(std.mem.indexOf(u8, automatic.written(), "library environment: none") != null);
    try std.testing.expect(std.mem.indexOf(u8, automatic.written(), "library search paths: ${EXECUTABLE_DIR}:/opt/app/lib") != null);

    // A cgo report has no loading policy to explain.
    var cgo: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer cgo.deinit();
    try render(std.testing.allocator, &cgo.writer, document, .{});
    try std.testing.expect(std.mem.indexOf(u8, cgo.written(), "library loading:") == null);
}
