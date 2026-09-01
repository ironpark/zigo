const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming.zig");

pub const Options = struct {
    pub const Backend = enum { cgo, purego };
    pub const LinkMode = enum { static, dynamic };
    go_module: []const u8,
    cflags_override: ?[]const u8 = null,
    ldflags_override: ?[]const u8 = null,
    system_ldflags: []const u8 = "",
    framework_ldflags: []const u8 = "",
    /// Space-separated pkg-config package names. They become a `#cgo
    /// pkg-config:` line rather than `-l` flags, so cgo asks pkg-config for the
    /// compile and link flags of each one.
    pkg_config_libs: []const u8 = "",
    include_dir: []const u8 = "${SRCDIR}/../../../zig-out/include",
    library_dir: []const u8 = "${SRCDIR}/../../../zig-out/lib",
    raw_package_path: []const u8 = "internal/raw",
    raw_package_name: []const u8 = "raw",
    raw_colocated: bool = false,
    backend: Backend = .cgo,
    link_mode: Options.LinkMode = .static,
    library_stem: []const u8 = "",
    /// Public Go package name. Empty derives it from the binding name.
    go_package: []const u8 = "",
    /// Colon-separated purego candidate locations, in the order they are tried.
    library_search_paths: []const u8 = "",
    /// Comma-separated environment variable names. `null` selects the defaults.
    library_env_vars: ?[]const u8 = null,
    library_automatic: bool = false,
    library_exported_api: bool = true,
};

pub const Emitter = struct {
    pathAlloc: *const fn (std.mem.Allocator, abi.Program, Options) anyerror![]u8,
    render: *const fn (std.mem.Allocator, *std.Io.Writer, abi.Program, Options) anyerror!void,
};

pub const all = [_]Emitter{
    .{ .pathAlloc = shimPath, .render = renderShim },
    .{ .pathAlloc = panicSourcePath, .render = renderPanicSource },
    .{ .pathAlloc = headerPath, .render = renderHeader },
    .{ .pathAlloc = rawPath, .render = renderRaw },
    .{ .pathAlloc = rawLoadPosixPath, .render = renderRawLoadPosix },
    .{ .pathAlloc = rawLoadWindowsPath, .render = renderRawLoadWindows },
    .{ .pathAlloc = publicPath, .render = renderPublic },
    .{ .pathAlloc = publicEnumsPath, .render = renderPublicEnumsFile },
    .{ .pathAlloc = publicStructsPath, .render = renderPublicStructsFile },
    .{ .pathAlloc = publicHandlesPath, .render = renderPublicHandlesFile },
    .{ .pathAlloc = publicRuntimePath, .render = renderPublicRuntimeFile },
    .{ .pathAlloc = publicErrorsPath, .render = renderPublicErrors },
};

fn shimPath(allocator: std.mem.Allocator, _: abi.Program, _: Options) ![]u8 {
    return allocator.dupe(u8, "shim.zig");
}

fn panicSourcePath(allocator: std.mem.Allocator, _: abi.Program, _: Options) ![]u8 {
    return allocator.dupe(u8, "panic.c");
}

fn headerPath(allocator: std.mem.Allocator, program: abi.Program, _: Options) ![]u8 {
    const package = try naming.snakeAlloc(allocator, program.package);
    defer allocator.free(package);
    return std.fmt.allocPrint(allocator, "zigo_{s}.h", .{package});
}

fn rawPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    if (options.raw_colocated) {
        const package = try publicPackageAlloc(allocator, program, options);
        defer allocator.free(package);
        return std.fmt.allocPrint(allocator, "{s}/{s}_{s}_gen.go", .{ package, package, @tagName(options.backend) });
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}_gen.go", .{ options.raw_package_path, options.raw_package_name });
}

/// One naming rule for the concern-scoped companions of the raw package, so a
/// colocated raw package keeps its `<package>_<backend>_...` prefix and a
/// separate one keeps its `<raw package name>_...` prefix.
fn rawConcernPathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options, concern: []const u8) ![]u8 {
    if (options.raw_colocated) {
        const package = try publicPackageAlloc(allocator, program, options);
        defer allocator.free(package);
        return std.fmt.allocPrint(allocator, "{s}/{s}_{s}_{s}_gen.go", .{ package, package, @tagName(options.backend), concern });
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}_{s}_gen.go", .{ options.raw_package_path, options.raw_package_name, concern });
}

fn rawLoadPosixPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return rawConcernPathAlloc(allocator, program, options, "load_posix");
}

fn rawLoadWindowsPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return rawConcernPathAlloc(allocator, program, options, "load_windows");
}

fn publicPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    const package = try publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    return std.fmt.allocPrint(allocator, "{s}/{s}_gen.go", .{ package, package });
}

fn publicEnumsPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return publicConcernPathAlloc(allocator, program, options, "enums");
}

fn publicStructsPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return publicConcernPathAlloc(allocator, program, options, "structs");
}

fn publicHandlesPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return publicConcernPathAlloc(allocator, program, options, "handles");
}

fn publicRuntimePath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return publicConcernPathAlloc(allocator, program, options, "runtime");
}

/// One file per tagged union, named from the union itself so the file set
/// grows with the bindings instead of one file growing with them.
fn publicUnionPathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options, stem: []const u8) ![]u8 {
    const concern = try std.fmt.allocPrint(allocator, "union_{s}", .{stem});
    defer allocator.free(concern);
    return publicConcernPathAlloc(allocator, program, options, concern);
}

/// One naming rule for every concern-scoped file in the public package, so a
/// new concern cannot drift from `<package>_<concern>_gen.go`.
fn publicConcernPathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options, concern: []const u8) ![]u8 {
    const package = try publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    return std.fmt.allocPrint(allocator, "{s}/{s}_{s}_gen.go", .{ package, package, concern });
}

fn publicErrorsPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    const package = try publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    return std.fmt.allocPrint(allocator, "{s}/{s}_errors_gen.go", .{ package, package });
}

fn renderShim(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, _: Options) !void {
    try writer.writeAll(
        "// Code generated by zigo. DO NOT EDIT.\n" ++
            "const std = @import(\"std\");\n" ++
            "const target = @import(\"zigo_target\");\n\n" ++
            "extern fn zg_panic_bridge(message: [*]const u8, length: usize) callconv(.c) noreturn;\n" ++
            "fn panicHandler(message: []const u8, _: ?usize) noreturn {\n" ++
            "    zg_panic_bridge(message.ptr, message.len);\n" ++
            "}\n" ++
            "pub const panic = std.debug.FullPanic(panicHandler);\n\n",
    );
    if (program.backend == .cgo) {
        for (program.functions) |function| {
            for (function.origin.params, 0..) |parameter, parameter_index| {
                if (parameter.type != .callback) continue;
                const name = try callbackTrampolineNameAlloc(allocator, function, parameter_index);
                defer allocator.free(name);
                try writer.print("extern fn {s}(", .{name});
                for (parameter.type.callback.params, 0..) |callback_parameter, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try writer.print("p{d}: ", .{index});
                    try writeZigType(writer, semanticScalar(program, callback_parameter));
                }
                try writer.writeAll(") callconv(.c) ");
                try writeZigType(writer, semanticScalar(program, parameter.type.callback.@"return".*));
                try writer.writeAll(";\n");
            }
        }
    }
    if (program.backend == .purego) try renderCallbackBitThunks(allocator, writer, program);
    if (programHasCallbacks(program)) try writer.writeByte('\n');
    for (program.functions) |function| {
        try writer.print("export fn {s}_impl(", .{function.symbol});
        for (function.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.print("{s}: ", .{parameter.name});
            try writeZigType(writer, parameter.scalar);
        }
        try writer.writeAll(") ");
        try writeZigType(writer, function.ret);
        try writer.writeAll(" {\n");
        try writeCallbackBitBindings(allocator, writer, program, function);
        try writeShimStringSliceSetups(allocator, writer, function);
        try writer.writeAll("    ");

        if (function.origin.@"return" == .slice and !isCStringReturn(function.origin.*)) {
            try writer.writeAll("const result = ");
            try writeTargetCall(allocator, writer, program, function);
            try writer.writeAll(";\n    out_result_ptr.* = result.ptr;\n    out_result_len.* = result.len;\n}\n");
            continue;
        }

        if (function.origin.@"return" == .error_union) {
            const error_union = function.origin.@"return".error_union;
            if (error_union.payload.* == .void) {
                try writeTargetCall(allocator, writer, program, function);
                try writer.writeAll(" catch |err| return switch (err) {");
                try writeErrorSwitch(writer, function);
                try writer.writeAll("\n    };\n");
            } else {
                try writer.writeAll("const result = ");
                try writeTargetCall(allocator, writer, program, function);
                try writer.writeAll(" catch |err| return switch (err) {");
                try writeErrorSwitch(writer, function);
                try writer.writeAll("\n    };\n    out_result.* = ");
                try writeZigReturnConversion(writer, error_union.payload.*, "result");
                try writer.writeAll(";\n");
            }
            try writeSliceWrittenAssignments(writer, function);
            try writer.writeAll("    return 0;\n}\n");
            continue;
        }

        if (function.origin.@"return" == .value_struct) {
            try writer.writeAll("out_result.* = ");
        } else if (function.origin.@"return" != .void) {
            try writer.writeAll("return ");
        }
        try writeTargetCall(allocator, writer, program, function);
        try writer.writeAll(";\n");
        if (function.origin.@"return" == .void) try writeSliceWrittenAssignments(writer, function);
        try writer.writeAll("}\n");
    }
    try renderTaggedUnionShim(writer, program);
    try renderTaggedUnionSnapshotShim(writer, program);
    try renderValueStructShim(writer, program);
}

/// `extern` already fixes the layout on both sides, so the shim asserts rather
/// than converts: if the Zig struct ever stops matching the C mirror the
/// generated code fails to build instead of misreading memory.
///
/// Reflection runs on the build host, so these are also what makes
/// cross-compilation safe: a host layout that does not describe the target
/// fails this compile with a named diagnostic instead of shipping a struct
/// whose C and Go mirrors disagree with the Zig one.
fn renderValueStructShim(writer: *std.Io.Writer, program: abi.Program) !void {
    if (program.structs.len == 0) return;
    try writer.writeAll(abi_guard_helper);
    for (program.structs) |record| {
        try writer.print(
            "\ncomptime {{\n    zigoAbiGuard(\"@sizeOf({0s})\", {1d}, @sizeOf(target.{0s}));\n" ++
                "    zigoAbiGuard(\"@alignOf({0s})\", {2d}, @alignOf(target.{0s}));\n",
            .{ record.name, record.size, record.alignment },
        );
        for (record.fields) |field| {
            try writer.print(
                "    zigoAbiGuard(\"@offsetOf({0s}, \\\"{1s}\\\")\", {2d}, @offsetOf(target.{0s}, \"{1s}\"));\n",
                .{ record.name, field.name, field.offset },
            );
        }
        try writer.writeAll("}\n");
    }
}

/// The guard body, emitted once whenever the shim mirrors at least one user
/// struct. `@compileError` rather than `std.debug.assert` so the failure names
/// the struct, the member, both values, and the cause a user can act on --
/// `assert` reports only "reached unreachable code".
const abi_guard_helper =
    "\n/// Fails this compile when a layout zigo reflected on the build host does\n" ++
    "/// not describe the compilation target. The usual cause is a C type whose\n" ++
    "/// width varies by target -- `c_long` and `c_ulong` are 4 bytes on Windows\n" ++
    "/// and 8 bytes on Linux and macOS, and `c_longdouble` varies too. Use a\n" ++
    "/// fixed-width type in the binding surface, or generate on the target.\n" ++
    "fn zigoAbiGuard(comptime what: []const u8, comptime reflected: usize, comptime actual: usize) void {\n" ++
    "    if (reflected != actual) @compileError(std.fmt.comptimePrint(\n" ++
    "        \"zigo ABI guard: {s} is {d} on this target, but zigo reflected {d} on the build host. \" ++\n" ++
    "            \"The generated C header and Go mirrors use the reflected layout, so this binding \" ++\n" ++
    "            \"cannot be built for this target. A C type whose width varies by target, such as \" ++\n" ++
    "            \"c_long or c_ulong, is the usual cause; replace it with a fixed-width type.\",\n" ++
    "        .{ what, actual, reflected },\n" ++
    "    ));\n" ++
    "}\n";

/// The snapshot struct is zigo's own `extern struct`, never the Zig union's
/// layout: the shim reads the active variant and copies it in.
fn renderTaggedUnionSnapshotShim(writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.snapshots) |snapshot| {
        try writer.print("\nconst {s} = extern struct {{\n", .{snapshot.type_name});
        for (snapshot.fields) |field| {
            try writer.print("    {s}: ", .{field.name});
            if (field.kind == .padding) {
                try writer.print("[{d}]u8", .{field.bytes});
            } else {
                try writeZigType(writer, field.scalar);
            }
            try writer.writeAll(",\n");
        }
        try writer.writeAll("};\n");
        try writer.print(
            "comptime {{\n    std.debug.assert(@sizeOf({0s}) == {1d});\n    std.debug.assert(@alignOf({0s}) == {2d});\n}}\n",
            .{ snapshot.type_name, snapshot.size, snapshot.alignment },
        );
        try writer.print("export fn {s}_impl(", .{snapshot.symbol});
        for (snapshot.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.print("{s}: ", .{parameter.name});
            try writeZigType(writer, parameter.scalar);
        }
        try writer.writeAll(") ");
        try writeZigType(writer, snapshot.ret);
        try writer.print(
            " {{\n    out_snapshot.* = std.mem.zeroes({s});\n    out_snapshot.tag = @intFromEnum(std.meta.activeTag(self.*));\n    switch (self.*) {{\n",
            .{snapshot.type_name},
        );
        for (snapshot.owner.fields) |field| {
            const payload = field.type.?;
            if (payload == .void) {
                try writer.print("        .{s} => {{}},\n", .{field.name});
                continue;
            }
            const member = snapshotMember(snapshot, field.name).?;
            try writer.print("        .{s} => |value| out_snapshot.{s} = ", .{ field.name, member.name });
            switch (payload) {
                .@"enum" => try writer.writeAll("@intFromEnum(value)"),
                .bool => try writer.writeAll("@intFromBool(value)"),
                else => try writer.writeAll("value"),
            }
            try writer.writeAll(",\n");
        }
        try writer.writeAll("    }\n    return 1;\n}\n");
    }
}

fn snapshotMember(snapshot: abi.AbiSnapshot, variant: []const u8) ?abi.AbiSnapshot.Field {
    for (snapshot.fields) |field| {
        const source = field.source orelse continue;
        if (std.mem.eql(u8, source.name, variant)) return field;
    }
    return null;
}

fn renderTaggedUnionShim(writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.projections) |projection| {
        try writer.print("export fn {s}_impl(", .{projection.symbol});
        for (projection.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.print("{s}: ", .{parameter.name});
            try writeZigType(writer, parameter.scalar);
        }
        try writer.writeAll(") ");
        try writeZigType(writer, projection.ret);
        switch (projection.kind) {
            .tag => try writer.writeAll(" {\n    out_value.* = @intFromEnum(std.meta.activeTag(self.*));\n    return 1;\n}\n"),
            .payload => {
                const field = projection.field.?;
                const payload = field.type.?;
                try writer.print(" {{\n    if (std.meta.activeTag(self.*) != .{s}) return 0;\n", .{field.name});
                if (payload == .slice) {
                    try writer.print("    out_value_ptr.* = self.{s}.ptr;\n    out_value_len.* = self.{s}.len;\n", .{ field.name, field.name });
                } else {
                    try writer.writeAll("    out_value.* = ");
                    switch (payload) {
                        .bool => try writer.print("@intFromBool(self.{s})", .{field.name}),
                        .@"enum" => try writer.print("@intFromEnum(self.{s})", .{field.name}),
                        else => try writer.print("self.{s}", .{field.name}),
                    }
                    try writer.writeAll(";\n");
                }
                try writer.writeAll("    return 1;\n}\n");
            },
        }
    }
}

fn renderPanicSource(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, _: Options) !void {
    const package = try naming.snakeAlloc(allocator, program.package);
    defer allocator.free(package);
    try writer.writeAll("// Code generated by zigo. DO NOT EDIT.\n" ++
        "#include <setjmp.h>\n" ++
        "#include <stddef.h>\n" ++
        "#include <stdint.h>\n" ++
        "#include <stdlib.h>\n" ++
        "#include <string.h>\n");
    if (program.projections.len != 0 or program.snapshots.len != 0 or program.structs.len != 0) {
        try writer.print("#include \"zigo_{s}.h\"\n\n", .{package});
    } else {
        try writer.writeByte('\n');
    }
    // The header defines the same macro under the same guard, so including it
    // above or not makes no difference here.
    try writeExportMacro(writer);
    try writer.writeAll(
        "static _Thread_local jmp_buf zg_panic_env;\n" ++
            "static _Thread_local int zg_panic_active;\n" ++
            "static _Thread_local char zg_panic_message[1024];\n\n" ++
            "void zg_panic_bridge(const uint8_t *message, size_t length) {\n" ++
            "    size_t count = length < sizeof(zg_panic_message) - 1 ? length : sizeof(zg_panic_message) - 1;\n" ++
            "    memcpy(zg_panic_message, message, count);\n" ++
            "    zg_panic_message[count] = '\\0';\n" ++
            "    if (zg_panic_active) longjmp(zg_panic_env, 1);\n" ++
            "    abort();\n" ++
            "}\n\n" ++
            "ZIGO_EXPORT const char *zg_last_error_message(void) { return zg_panic_message; }\n",
    );
    for (program.functions) |function| {
        try writer.writeByte('\n');
        try writeCFunctionDeclaration(writer, function, true);
        try writer.writeAll(";\n");
        try writeCFunctionDeclaration(writer, function, false);
        try writer.writeAll(" {\n    zg_panic_active = 1;\n    if (setjmp(zg_panic_env) != 0) {\n        zg_panic_active = 0;\n");
        if (function.ret == .void) {
            try writer.writeAll("        return;\n");
        } else if (function.origin.@"return" == .error_union) {
            try writer.writeAll("        return -2;\n");
        } else {
            try writer.writeAll("        return 0;\n");
        }
        try writer.writeAll("    }\n");
        if (function.ret != .void) {
            try writer.writeAll("    ");
            try writeCType(writer, function.ret);
            try writer.writeAll(" result = ");
        }
        try writer.print("{s}_impl(", .{function.symbol});
        for (function.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.writeAll(parameter.name);
        }
        try writer.writeAll(");\n    zg_panic_active = 0;\n");
        if (function.ret != .void) try writer.writeAll("    return result;\n");
        try writer.writeAll("}\n");
    }
    for (program.projections) |projection| {
        try writer.writeByte('\n');
        try writeCUnionDeclaration(writer, program, projection.owner.name, projection.symbol, projection.params, projection.ret, true);
        try writer.writeAll(";\n");
        try writeCUnionDeclaration(writer, program, projection.owner.name, projection.symbol, projection.params, projection.ret, false);
        try writer.writeAll(" {\n    if (");
        for (projection.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(" || ");
            try writer.print("{s} == NULL", .{parameter.name});
        }
        try writer.writeAll(") return 2;\n");
        try writer.writeAll("    zg_panic_active = 1;\n    if (setjmp(zg_panic_env) != 0) {\n        zg_panic_active = 0;\n        return 3;\n    }\n    uint8_t result = ");
        try writer.print("{s}_impl(", .{projection.symbol});
        for (projection.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.writeAll(parameter.name);
        }
        try writer.writeAll(");\n    zg_panic_active = 0;\n    return result;\n}\n");
    }
    for (program.snapshots) |snapshot| {
        try writer.writeByte('\n');
        try writeCUnionDeclaration(writer, program, snapshot.owner.name, snapshot.symbol, snapshot.params, snapshot.ret, true);
        try writer.writeAll(";\n");
        try writeCUnionDeclaration(writer, program, snapshot.owner.name, snapshot.symbol, snapshot.params, snapshot.ret, false);
        try writer.writeAll(" {\n    if (");
        for (snapshot.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(" || ");
            try writer.print("{s} == NULL", .{parameter.name});
        }
        try writer.writeAll(") return 2;\n");
        try writer.writeAll("    zg_panic_active = 1;\n    if (setjmp(zg_panic_env) != 0) {\n        zg_panic_active = 0;\n        return 3;\n    }\n    uint8_t result = ");
        try writer.print("{s}_impl(", .{snapshot.symbol});
        for (snapshot.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.writeAll(parameter.name);
        }
        try writer.writeAll(");\n    zg_panic_active = 0;\n    return result;\n}\n");
    }
}

/// Writes the C signature of a generated entry point. The public wrapper is
/// what the generated Go loader resolves by name, so it carries the export
/// annotation; the `_impl` half is internal to the artifact and must not.
/// `ZIGO_EXPORT` marks the symbols a consumer resolves out of the built
/// artifact. It expands to nothing outside Windows, so the generated C is the
/// same text on every host and only the Windows compiler acts on it.
fn writeExportMacro(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        "// ELF and Mach-O export every non-static symbol of a shared library;\n" ++
            "// COFF exports nothing without an explicit annotation, so a DLL built\n" ++
            "// without this would load and then resolve none of its entry points.\n" ++
            "#ifndef ZIGO_EXPORT\n" ++
            "#if defined(_WIN32)\n" ++
            "#define ZIGO_EXPORT __declspec(dllexport)\n" ++
            "#else\n" ++
            "#define ZIGO_EXPORT\n" ++
            "#endif\n" ++
            "#endif\n\n",
    );
}

fn writeCFunctionDeclaration(writer: *std.Io.Writer, function: abi.AbiFn, implementation: bool) !void {
    if (!implementation) try writer.writeAll("ZIGO_EXPORT ");
    try writeCType(writer, function.ret);
    try writer.print(" {s}{s}(", .{ function.symbol, if (implementation) "_impl" else "" });
    if (function.params.len == 0) try writer.writeAll("void");
    for (function.params, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        try writeCParam(writer, parameter.scalar, parameter.name);
    }
    try writer.writeByte(')');
}

fn writeTargetCall(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, function: abi.AbiFn) !void {
    const bool_return = function.origin.@"return" == .bool;
    const enum_return = function.origin.@"return" == .@"enum";
    if (bool_return) try writer.writeAll("@intFromBool(");
    if (enum_return) try writer.writeAll("@intFromEnum(");
    const namespace = function.origin.receiver orelse function.origin.namespace;
    if (namespace) |receiver| {
        try writer.print("target.{s}.{s}(", .{ receiver, function.origin.name });
        if (function.origin.receiver != null) {
            try writer.writeAll("self");
            if (function.origin.params.len != 0) try writer.writeAll(", ");
        }
    } else {
        try writer.print("target.{s}(", .{function.origin.name});
    }
    for (function.origin.params, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        switch (parameter.type) {
            .callback => {
                if (needsCallbackBitThunk(program, function, index)) {
                    const thunk = try callbackThunkNameAlloc(allocator, function, index);
                    defer allocator.free(thunk);
                    try writer.print("&{s}", .{thunk});
                } else if (hasCallbackAbiParam(function, index)) {
                    try writer.writeAll(parameter.name);
                } else {
                    const name = try callbackTrampolineNameAlloc(allocator, function, index);
                    defer allocator.free(name);
                    try writer.print("&{s}", .{name});
                }
            },
            .bool => try writer.print("{s} != 0", .{parameter.name}),
            .@"enum" => try writer.print("@enumFromInt({s})", .{parameter.name}),
            .slice => if (isStringSliceParameter(parameter))
                try writer.print("zigoString{d}Strings", .{index})
            else if (isCStringParameter(parameter))
                try writer.writeAll(parameter.name)
            else
                try writer.print("if ({s}_len == 0) &.{{}} else {s}_ptr[0..{s}_len]", .{ parameter.name, parameter.name, parameter.name }),
            .value_struct => try writer.print("{s}.*", .{parameter.name}),
            else => try writer.writeAll(parameter.name),
        }
    }
    try writer.writeByte(')');
    if (bool_return or enum_return) try writer.writeByte(')');
}

/// Floats cannot cross the purego callback ABI as floats: Windows compiles a Go
/// callback through `syscall.NewCallback`, whose `compileCallback` refuses a
/// floating-point argument on anything but 386. The bits have to be handed over
/// as integers, and the only code that can convert them is the shim, because the
/// native side calls the callback pointer directly with real floats.
///
/// So a callback carrying floats is not passed through: the native side receives
/// a static thunk with the natural signature, which `@bitCast`s each float and
/// forwards to the Go dispatcher. The dispatcher address lives in a global
/// because a C function pointer has no room for state -- and it can, because Go
/// builds exactly one dispatcher per callback signature behind a `sync.Once`, so
/// every bind stores the same address. The userdata token, which does vary per
/// callback value, still travels in the userdata parameter untouched.
///
/// The thunk is emitted on every platform. One wire shape everywhere keeps the
/// committed generated tree identical no matter which host or target produced it.
fn renderCallbackBitThunks(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (!needsCallbackBitThunk(program, function, parameter_index)) continue;
            const callback = parameter.type.callback;
            const wire = callbackWireScalar(function, parameter_index) orelse return error.CallbackRequiresUserdata;
            const binding = try callbackBindingNameAlloc(allocator, function, parameter_index);
            defer allocator.free(binding);
            const thunk = try callbackThunkNameAlloc(allocator, function, parameter_index);
            defer allocator.free(thunk);

            try writer.print("var {s}: std.atomic.Value(?", .{binding});
            try writeZigType(writer, wire);
            try writer.writeAll(") = .init(null);\n");
            try writer.print("fn {s}(", .{thunk});
            for (callback.params, 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("p{d}: ", .{index});
                try writeZigType(writer, semanticScalar(program, callback_parameter));
            }
            try writer.writeAll(") callconv(.c) ");
            try writeZigType(writer, semanticScalar(program, callback.@"return".*));
            try writer.print(" {{\n    const dispatch = {s}.load(.acquire) orelse @panic(\"zigo: callback invoked before it was installed\");\n    ", .{binding});
            if (callback.@"return".* != .void) try writer.writeAll("return ");
            try writer.writeAll("dispatch(");
            for (callback.params, 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                if (callback_parameter == .float)
                    try writer.print("@bitCast(p{d})", .{index})
                else
                    try writer.print("p{d}", .{index});
            }
            try writer.writeAll(");\n}\n");
        }
    }
}

/// Records the Go dispatcher a thunk forwards to, before the native side can
/// reach the callback it is being installed for.
fn writeCallbackBitBindings(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, function: abi.AbiFn) !void {
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (!needsCallbackBitThunk(program, function, parameter_index)) continue;
        const binding = try callbackBindingNameAlloc(allocator, function, parameter_index);
        defer allocator.free(binding);
        try writer.print("    {s}.store({s}, .release);\n", .{ binding, parameter.name });
    }
}

fn hasCallbackAbiParam(function: abi.AbiFn, source_index: usize) bool {
    for (function.params) |parameter| {
        if (parameter.source_index == source_index and parameter.scalar == .callback) return true;
    }
    return false;
}

fn writeErrorSwitch(writer: *std.Io.Writer, function: abi.AbiFn) !void {
    for (function.errors) |entry| try writer.print("\n        error.{s} => {d},", .{ entry.name, entry.code });
}

fn writeZigReturnConversion(writer: *std.Io.Writer, node: semantic.TypeNode, expression: []const u8) !void {
    switch (node) {
        .bool => try writer.print("@intFromBool({s})", .{expression}),
        .@"enum" => try writer.print("@intFromEnum({s})", .{expression}),
        else => try writer.writeAll(expression),
    }
}

fn writeSliceWrittenAssignments(writer: *std.Io.Writer, function: abi.AbiFn) !void {
    for (function.origin.params) |parameter| {
        if (parameter.type == .slice and parameter.direction == .out) {
            try writer.print("    {s}_written.* = {s}_len;\n", .{ parameter.name, parameter.name });
        }
    }
}

fn renderHeader(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, _: Options) !void {
    const package = try naming.snakeAlloc(allocator, program.package);
    defer allocator.free(package);
    try writer.print("// Code generated by zigo. DO NOT EDIT.\n#ifndef ZIGO_{s}_H\n#define ZIGO_{s}_H\n\n#include <stddef.h>\n#include <stdint.h>\n\n", .{ package, package });
    // Declaration order, so handle and enum typedefs interleave the way the
    // user wrote them; the names themselves come from lowering.
    for (program.types) |declaration| {
        if (isHandleType(declaration)) {
            const handle = handleRecord(program, declaration.name);
            try writer.print("typedef struct {s} {s};\n", .{ handle.c_name, handle.c_name });
            continue;
        }
        if (declaration.kind != .@"enum") continue;
        const record = enumRecord(program, declaration.name);
        try writer.writeAll("typedef ");
        try writeCType(writer, record.tag);
        try writer.print(" {s};\n", .{record.c_name});
        for (record.constants) |constant|
            try writer.print("#define {s} {d}\n", .{ constant.c_name, constant.value });
        try writer.writeByte('\n');
    }
    try writeExportMacro(writer);
    try renderValueStructTypes(writer, program);
    try renderSnapshotTypes(writer, program);
    for (program.functions) |function| {
        try writer.writeAll("ZIGO_EXPORT ");
        try writeCType(writer, function.ret);
        try writer.print(" {s}(", .{function.symbol});
        if (function.params.len == 0) try writer.writeAll("void");
        for (function.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writeCParam(writer, parameter.scalar, parameter.name);
        }
        try writer.writeAll(");\n");
    }
    try renderTaggedUnionHeader(writer, program);
    try writer.writeAll("ZIGO_EXPORT const char *zg_last_error_message(void);\n");
    try writer.print("\n#endif // ZIGO_{s}_H\n", .{package});
}

fn renderTaggedUnionHeader(writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.projections) |projection| {
        try writeCUnionDeclaration(writer, program, projection.owner.name, projection.symbol, projection.params, projection.ret, false);
        try writer.writeAll(";\n");
    }
    for (program.snapshots) |snapshot| {
        try writeCUnionDeclaration(writer, program, snapshot.owner.name, snapshot.symbol, snapshot.params, snapshot.ret, false);
        try writer.writeAll(";\n");
    }
}

/// The C mirror of a user `extern struct`. The members and their order are the
/// user's own; `extern` means the C compiler's layout rules already apply, so
/// nothing is reordered and no padding is spelled out.
fn renderValueStructTypes(writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.structs) |record| {
        try writer.print("typedef struct {s} {{\n", .{record.c_name});
        for (record.fields) |field| {
            try writer.writeAll("    ");
            try writeCMemberType(writer, program, field.node, field.scalar);
            try writer.print(" {s};\n", .{field.name});
        }
        try writer.print("}} {s};\n\n", .{record.c_name});
    }
}

/// An enum member keeps its C typedef name; everything else is spelled from the
/// lowered scalar. Shared by the extern struct mirror and the value snapshot.
fn writeCMemberType(
    writer: *std.Io.Writer,
    program: abi.Program,
    node: ?semantic.TypeNode,
    scalar: abi.AbiScalar,
) !void {
    if (node) |value| if (value == .@"enum") {
        return writer.writeAll(enumRecord(program, value.@"enum".ref).c_name);
    };
    try writeCType(writer, scalar);
}

/// The value snapshot struct as C sees it. Padding is spelled out so the Zig
/// shim and both Go backends can reproduce the layout without guessing.
fn renderSnapshotTypes(writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.snapshots) |snapshot| {
        try writer.print("typedef struct {s} {{\n", .{snapshot.type_name});
        for (snapshot.fields) |field| {
            try writer.writeAll("    ");
            try writeCMemberType(writer, program, field.node, field.scalar);
            if (field.kind == .padding) {
                try writer.print(" {s}[{d}];\n", .{ field.name, field.bytes });
            } else {
                try writer.print(" {s};\n", .{field.name});
            }
        }
        try writer.print("}} {s};\n\n", .{snapshot.type_name});
    }
}

/// Snapshots and projections share one C declaration form: both take the owning
/// union by const pointer and return a status.
fn writeCUnionDeclaration(
    writer: *std.Io.Writer,
    program: abi.Program,
    owner: []const u8,
    symbol: []const u8,
    params: []const abi.AbiParam,
    ret: abi.AbiScalar,
    implementation: bool,
) !void {
    // Same split as writeCFunctionDeclaration: the public wrapper is resolved
    // by name out of the artifact, the `_impl` half never is.
    if (!implementation) try writer.writeAll("ZIGO_EXPORT ");
    try writeCType(writer, ret);
    try writer.print(" {s}{s}(", .{ symbol, if (implementation) "_impl" else "" });
    for (params, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        try writeUnionCParam(writer, program, owner, parameter);
    }
    try writer.writeByte(')');
}

fn writeUnionCParam(writer: *std.Io.Writer, program: abi.Program, owner: []const u8, parameter: abi.AbiParam) !void {
    if (parameter.role == .receiver) {
        try writer.print("const {s} *{s}", .{ handleRecord(program, owner).c_name, parameter.name });
        return;
    }
    var wrote_pointer = false;
    try writeProjectionCType(writer, parameter.scalar, &wrote_pointer);
    try writer.print("{s}{s}", .{ if (wrote_pointer) "" else " ", parameter.name });
}

fn writeProjectionCType(writer: *std.Io.Writer, value: abi.AbiScalar, wrote_pointer: *bool) !void {
    if (value != .pointer) {
        try writeCType(writer, value);
        return;
    }
    const pointer = value.pointer;
    if (pointer.is_const) try writer.writeAll("const ");
    try writeProjectionCType(writer, pointer.child.*, wrote_pointer);
    try writer.writeAll(if (wrote_pointer.*) "*" else " *");
    wrote_pointer.* = true;
}

/// Public Go package name: the override when set, otherwise the snake_case
/// binding name. The C header and the native library keep the binding name.
fn publicPackageAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    if (options.go_package.len != 0) return allocator.dupe(u8, options.go_package);
    return naming.snakeAlloc(allocator, program.package);
}

/// Go parameter names for one function, computed once per emitted function.
fn goParamNamesForAlloc(allocator: std.mem.Allocator, params: []const semantic.Parameter) ![][]u8 {
    const zig_names = try allocator.alloc([]const u8, params.len);
    defer allocator.free(zig_names);
    for (params, 0..) |parameter, index| zig_names[index] = parameter.name;
    return naming.goParamNamesAlloc(allocator, zig_names);
}

/// Suffix of the raw Go mirror of an `extern struct`. Named once so the
/// declaration and every reference to it cannot drift apart.
const raw_struct_suffix = "Data";

fn structRawTypeNameAlloc(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ name, raw_struct_suffix });
}

/// The Go mirror of an `extern struct`. cgo converts member by member and does
/// not depend on this layout, but purego hands the address straight to the
/// native call, so the padding is spelled out rather than left to Go happening
/// to agree with C.
fn renderRawStructTypes(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.structs) |record| {
        const type_name = try structRawTypeNameAlloc(allocator, record.name);
        defer allocator.free(type_name);
        try writer.print(
            "\n// {s} mirrors the {s} layout, padding included.\ntype {s} struct {{\n",
            .{ type_name, record.c_name, type_name },
        );
        var offset: usize = 0;
        for (record.fields) |field| {
            if (field.offset > offset)
                try writer.print("\t_ [{d}]byte\n", .{field.offset - offset});
            const go_name = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(go_name);
            try writer.print("\t{s} ", .{go_name});
            try writeRawStructFieldType(allocator, writer, program, field);
            try writer.writeByte('\n');
            offset = field.offset + field.bytes;
        }
        if (record.size > offset) try writer.print("\t_ [{d}]byte\n", .{record.size - offset});
        try writer.writeAll("}\n");
    }
}

fn writeRawStructFieldType(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, field: abi.AbiStruct.Field) !void {
    if (field.node == .value_struct) {
        const nested = structRecord(program, field.node.value_struct.ref);
        const nested_name = try structRawTypeNameAlloc(allocator, nested.name);
        defer allocator.free(nested_name);
        return writer.writeAll(nested_name);
    }
    try writeGoScalar(writer, field.scalar);
}

/// The lowered mirror a struct member names. Validation rejects a member whose
/// struct was never lowered, so a missing entry is a malformed program.
fn structRecord(program: abi.Program, name: []const u8) abi.AbiStruct {
    for (program.structs) |record| if (std.mem.eql(u8, record.name, name)) return record;
    unreachable;
}

/// Builds the C value a cgo call passes by address. Converting member by
/// member keeps the generated cgo code independent of the Go mirror's layout.
fn writeCgoStructConversion(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, record: abi.AbiStruct, c_name: []const u8, go_name: []const u8) !void {
    return writeCgoStructConversionIndented(allocator, writer, program, record, c_name, go_name, "\t");
}

fn writeCgoStructConversionIndented(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    record: abi.AbiStruct,
    c_name: []const u8,
    go_name: []const u8,
    indent: []const u8,
) !void {
    try writer.print("{s}var {s} C.{s}\n", .{ indent, c_name, record.c_name });
    for (record.fields) |field| {
        const member = try naming.pascalAlloc(allocator, field.name);
        defer allocator.free(member);
        if (field.node == .value_struct) {
            const nested = structRecord(program, field.node.value_struct.ref);
            const nested_c = try std.fmt.allocPrint(allocator, "{s}{s}", .{ c_name, member });
            defer allocator.free(nested_c);
            const nested_go = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ go_name, member });
            defer allocator.free(nested_go);
            try writeCgoStructConversionIndented(allocator, writer, program, nested, nested_c, nested_go, indent);
            try writer.print("{s}{s}.{s} = {s}\n", .{ indent, c_name, field.name, nested_c });
            continue;
        }
        try writer.print("{s}{s}.{s} = C.", .{ indent, c_name, field.name });
        try writeCgoType(writer, field.scalar);
        try writer.print("({s}.{s})\n", .{ go_name, member });
    }
}

/// Reads a C value back into the Go mirror, again member by member.
fn writeCgoStructRead(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, record: abi.AbiStruct, indent: []const u8, c_name: []const u8) !void {
    const type_name = try structRawTypeNameAlloc(allocator, record.name);
    defer allocator.free(type_name);
    try writer.print("{s}{{\n", .{type_name});
    for (record.fields) |field| {
        const member = try naming.pascalAlloc(allocator, field.name);
        defer allocator.free(member);
        try writer.print("{s}\t{s}: ", .{ indent, member });
        if (field.node == .value_struct) {
            const nested = structRecord(program, field.node.value_struct.ref);
            const nested_c = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ c_name, field.name });
            defer allocator.free(nested_c);
            const nested_indent = try std.fmt.allocPrint(allocator, "{s}\t", .{indent});
            defer allocator.free(nested_indent);
            try writeCgoStructRead(allocator, writer, program, nested, nested_indent, nested_c);
        } else {
            try writeGoScalar(writer, field.scalar);
            try writer.print("({s}.{s})", .{ c_name, field.name });
        }
        try writer.writeAll(",\n");
    }
    try writer.print("{s}}}", .{indent});
}

/// Both build-tagged files define exactly `openLibrary`, `closeLibrary`, and
/// `resolveSymbol`, so `loadCandidate` and the error wrapping around it stay
/// one shared, platform-independent implementation.
const open_library_doc = "// openLibrary opens the shared library at path and returns its handle.\n";

fn renderRawLoadPrelude(writer: *std.Io.Writer, options: Options, constraint: []const u8) !void {
    try writer.print("// Code generated by zigo. DO NOT EDIT.\n\n//go:build {s}\n\npackage {s}\n\n", .{ constraint, options.raw_package_name });
}

/// POSIX halves of the loader primitives. purego's `dlfcn` wrappers are not
/// built on Windows, which is why they cannot live in the shared raw file.
fn renderRawLoadPosix(_: std.mem.Allocator, writer: *std.Io.Writer, _: abi.Program, options: Options) !void {
    if (options.backend != .purego) {
        try writer.print("// Code generated by zigo. DO NOT EDIT.\npackage {s}\n", .{options.raw_package_name});
        return;
    }
    try renderRawLoadPrelude(writer, options, "!windows");
    try writer.writeAll(
        "import \"github.com/ebitengine/purego\"\n\n" ++
            open_library_doc ++
            "func openLibrary(path string) (uintptr, error) {\n" ++
            "\treturn purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)\n}\n\n" ++
            "// closeLibrary releases a handle openLibrary returned.\n" ++
            "func closeLibrary(handle uintptr) { _ = purego.Dlclose(handle) }\n\n" ++
            "// resolveSymbol reports the address symbol is published at in handle.\n" ++
            "func resolveSymbol(handle uintptr, symbol string) (uintptr, error) {\n" ++
            "\treturn purego.Dlsym(handle, symbol)\n}\n",
    );
}

/// Windows halves of the loader primitives. purego v0.10.2 exposes no public
/// Windows loading API — its `loadSymbol` is unexported and `Dlopen` is
/// POSIX-only — so the standard library's `syscall` package is used directly,
/// which keeps the module dependencies unchanged.
fn renderRawLoadWindows(_: std.mem.Allocator, writer: *std.Io.Writer, _: abi.Program, options: Options) !void {
    if (options.backend != .purego) {
        try writer.print("// Code generated by zigo. DO NOT EDIT.\npackage {s}\n", .{options.raw_package_name});
        return;
    }
    try renderRawLoadPrelude(writer, options, "windows");
    try writer.writeAll(
        "import \"syscall\"\n\n" ++
            open_library_doc ++
            "func openLibrary(path string) (uintptr, error) {\n" ++
            "\thandle, err := syscall.LoadLibrary(path)\n" ++
            "\tif err != nil { return 0, err }\n" ++
            "\treturn uintptr(handle), nil\n}\n\n" ++
            "// closeLibrary releases a handle openLibrary returned.\n" ++
            "func closeLibrary(handle uintptr) { _ = syscall.FreeLibrary(syscall.Handle(handle)) }\n\n" ++
            "// resolveSymbol reports the address symbol is published at in handle.\n" ++
            "func resolveSymbol(handle uintptr, symbol string) (uintptr, error) {\n" ++
            "\treturn syscall.GetProcAddress(syscall.Handle(handle), symbol)\n}\n",
    );
}

fn renderRaw(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    if (options.backend == .purego) return renderPuregoRaw(allocator, writer, program, options);
    const package = try naming.snakeAlloc(allocator, program.package);
    defer allocator.free(package);
    try writer.print("// Code generated by zigo. DO NOT EDIT.\npackage {s}\n\n/*\n", .{options.raw_package_name});
    // pkg-config runs before the explicit flags so its `-I` and `-l` results
    // join the same CFLAGS and LDFLAGS cgo builds from this block.
    if (options.pkg_config_libs.len != 0) try writer.print("#cgo pkg-config: {s}\n", .{options.pkg_config_libs});
    try writer.writeAll("#cgo CFLAGS: ");
    if (options.cflags_override) |flags|
        try writer.writeAll(flags)
    else
        try writer.print("-I{s}", .{options.include_dir});
    try writer.writeAll("\n#cgo LDFLAGS: ");
    if (options.ldflags_override) |flags|
        try writer.writeAll(flags)
    else {
        const stem = try libraryStemAlloc(allocator, program, options);
        defer allocator.free(stem);
        // Naming the archive keeps a same-named shared library in the install
        // directory from satisfying a static link instead.
        if (options.link_mode == .static)
            try writer.print("{s}/lib{s}.a", .{ options.library_dir, stem })
        else
            try writer.print("-L{s} -l{s}", .{ options.library_dir, stem });
    }
    if (options.system_ldflags.len != 0) try writer.print(" {s}", .{options.system_ldflags});
    if (options.framework_ldflags.len != 0) try writer.print("\n#cgo darwin LDFLAGS: {s}", .{options.framework_ldflags});
    if (programHasCString(program)) try writer.writeAll("\n#include <stdlib.h>");
    try writer.print("\n#include \"zigo_{s}.h\"\n*/\nimport \"C\"\n", .{package});
    if (programHasCallbacks(program)) try writer.writeAll("import \"runtime/cgo\"\n");
    if (programNeedsUnsafe(program)) try writer.writeAll("import \"unsafe\"\n");
    try writer.writeByte('\n');
    const last_error_name = if (options.raw_colocated) "zigoRawLastErrorMessage" else "LastErrorMessage";
    try writer.print("// {s} returns the most recent native panic message for this binding.\nfunc {s}() string {{ return C.GoString(C.zg_last_error_message()) }}\n\n", .{ last_error_name, last_error_name });
    try renderRawCallbacks(allocator, writer, program);

    for (program.functions) |function| {
        const go_name = try rawGoNameAlloc(allocator, function.origin.*);
        defer allocator.free(go_name);
        const raw_public_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ if (options.raw_colocated) "zigoRaw" else "", go_name });
        defer allocator.free(raw_public_name);
        const go_names = try goParamNamesForAlloc(allocator, function.origin.params);
        defer naming.freeParamNames(allocator, go_names);
        try writer.print("// {s} calls the generated C ABI wrapper for {s}.\nfunc {s}(", .{ raw_public_name, function.symbol, raw_public_name });
        var raw_parameter_index: usize = 0;
        if (function.origin.receiver != null) {
            try writer.writeAll("self unsafe.Pointer");
            raw_parameter_index = 1;
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (callbackForUserdata(function.origin.params, parameter_index) != null) continue;
            if (raw_parameter_index != 0) try writer.writeAll(", ");
            if (parameter.type == .callback) {
                try writer.print("{s}Handle uintptr", .{go_names[parameter_index]});
            } else {
                try writer.print("{s} ", .{go_names[parameter_index]});
                try writeRawParameterType(writer, program, parameter);
            }
            raw_parameter_index += 1;
        }
        try writer.writeByte(')');
        try writeRawReturnType(writer, program, function);
        try writer.writeAll(" {\n");
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (!isCStringParameter(parameter)) continue;
            try writer.print("\t{s}CString := C.CString({s})\n\tdefer C.free(unsafe.Pointer({s}CString))\n", .{
                go_names[parameter_index],
                go_names[parameter_index],
                go_names[parameter_index],
            });
        }
        if (function.origin.@"return" == .slice and !isCStringReturn(function.origin.*)) {
            try writer.writeAll("\tvar outResultPtr *C.");
            if (function.origin.@"return".slice.element.* == .value_struct) {
                const record = structRecord(program, function.origin.@"return".slice.element.*.value_struct.ref);
                try writer.writeAll(record.c_name);
            } else {
                try writeCgoType(writer, semanticScalar(program, function.origin.@"return".slice.element.*));
            }
            try writer.writeAll("\n\tvar outResultLen C.size_t\n");
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type == .value_struct) {
                const record = structRecord(program, parameter.type.value_struct.ref);
                const c_name = try std.fmt.allocPrint(allocator, "c{s}", .{go_names[parameter_index]});
                defer allocator.free(c_name);
                try writeCgoStructConversion(allocator, writer, program, record, c_name, go_names[parameter_index]);
            }
            if (isStringSliceParameter(parameter)) {
                try writeCgoStringSliceSetup(writer, go_names[parameter_index]);
                continue;
            } else if (isCStringParameter(parameter)) {
                continue;
            } else if (parameter.type == .slice and parameter.type.slice.element.* == .value_struct) {
                const slice_name = go_names[parameter_index];
                const record = structRecord(program, parameter.type.slice.element.*.value_struct.ref);
                const c_value_name = try std.fmt.allocPrint(allocator, "c{s}", .{slice_name});
                defer allocator.free(c_value_name);
                const c_values_name = try std.fmt.allocPrint(allocator, "{s}Values", .{slice_name});
                defer allocator.free(c_values_name);
                try writer.print("\tvar {s} []C.{s}\n\tif len({s}) != 0 {{\n\t\t{s} = make([]C.{s}, len({s}))\n\t\tfor i := range {s} {{\n", .{
                    c_values_name,
                    record.c_name,
                    slice_name,
                    c_values_name,
                    record.c_name,
                    slice_name,
                    slice_name,
                });
                const go_value_name = try std.fmt.allocPrint(allocator, "{s}[i]", .{slice_name});
                defer allocator.free(go_value_name);
                try writeCgoStructConversionIndented(allocator, writer, program, record, c_value_name, go_value_name, "\t\t\t");
                try writer.print("\t\t\t{s}[i] = {s}\n\t\t}}\n\t}}\n\tvar {s}Zero C.{s}\n\t{s}Ptr := &{s}Zero\n\tif len({s}) != 0 {{\n\t\t{s}Ptr = (*C.{s})(unsafe.Pointer(&{s}[0]))\n\t}}\n", .{
                    c_values_name,
                    c_value_name,
                    slice_name,
                    record.c_name,
                    slice_name,
                    slice_name,
                    slice_name,
                    slice_name,
                    record.c_name,
                    c_values_name,
                });
                if (parameter.direction == .out) try writer.print("\tvar {s}Written C.size_t\n", .{slice_name});
            } else if (parameter.type == .slice) {
                const slice_name = go_names[parameter_index];
                try writer.print("\tvar {s}Zero C.", .{slice_name});
                try writeCgoType(writer, semanticScalar(program, parameter.type.slice.element.*));
                try writer.print("\n\t{s}Ptr := &{s}Zero\n\tif len({s}) != 0 {{\n\t\t{s}Ptr = (*C.", .{ slice_name, slice_name, slice_name, slice_name });
                try writeCgoType(writer, semanticScalar(program, parameter.type.slice.element.*));
                try writer.print(")(unsafe.Pointer(&{s}[0]))\n\t}}\n", .{slice_name});
                if (parameter.direction == .out) try writer.print("\tvar {s}Written C.size_t\n", .{slice_name});
            }
        }
        const returns_error = function.origin.@"return" == .error_union;
        const error_payload = if (returns_error) function.origin.@"return".error_union.payload.* else semantic.TypeNode{ .void = {} };
        if (function.ret_struct) |record| {
            try writer.print("\tvar outResult C.{s}\n", .{record.c_name});
        }
        if (returns_error and error_payload != .void) {
            if (error_payload == .opaque_ptr) {
                try writer.writeAll("\tvar outResult unsafe.Pointer\n");
            } else if (function.payload_struct) |record| {
                try writer.print("\tvar outResult C.{s}\n", .{record.c_name});
            } else {
                try writer.writeAll("\tvar outResult C.");
                try writeCgoType(writer, semanticScalar(program, error_payload));
                try writer.writeByte('\n');
            }
        }
        try writer.writeByte('\t');
        if (returns_error) {
            try writer.writeAll("code := int32(");
        } else if ((function.origin.@"return" == .slice and !isCStringReturn(function.origin.*)) or function.ret_struct != null) {
            // The out parameters are converted after the C call.
        } else if (isCStringReturn(function.origin.*)) {
            try writer.writeAll("return C.GoString(");
        } else if (function.origin.@"return" != .void) {
            try writer.writeAll("return ");
            try writeRawConversionPrefix(writer, program, function.origin.@"return");
        }
        try writer.print("C.{s}(", .{function.symbol});
        for (function.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            switch (parameter.role) {
                .receiver => try writer.writeAll("self"),
                .struct_in => try writer.print("&c{s}", .{go_names[parameter.source_index]}),
                .struct_out => try writer.writeAll("&outResult"),
                .value => {
                    if (callbackForUserdataIndex(function.origin.params, parameter.source_index)) |callback_index| {
                        try writer.writeAll("C.");
                        try writeCgoType(writer, parameter.scalar);
                        try writer.print("({s}Handle)", .{go_names[callback_index]});
                    } else if (isCStringParameter(function.origin.params[parameter.source_index])) {
                        try writer.print("{s}CString", .{go_names[parameter.source_index]});
                    } else if (parameter.scalar == .pointer) {
                        try writer.writeAll(go_names[parameter.source_index]);
                    } else {
                        try writer.writeAll("C.");
                        try writeCgoType(writer, parameter.scalar);
                        try writer.print("({s})", .{go_names[parameter.source_index]});
                    }
                },
                .slice_pointer => try writer.print("{s}Ptr", .{go_names[parameter.source_index]}),
                .slice_length => try writer.print("C.size_t(len({s}))", .{go_names[parameter.source_index]}),
                .slice_written => try writer.print("&{s}Written", .{go_names[parameter.source_index]}),
                .string_data => try writer.print("{s}DataPtr", .{go_names[parameter.source_index]}),
                .string_data_length => try writer.print("C.size_t(len({s}Data))", .{go_names[parameter.source_index]}),
                .string_lengths => try writer.print("{s}LensPtr", .{go_names[parameter.source_index]}),
                .string_count => try writer.print("C.size_t(len({s}))", .{go_names[parameter.source_index]}),
                .payload_out => try writer.writeAll("&outResult"),
                .return_slice_pointer => try writer.writeAll("&outResultPtr"),
                .return_slice_length => try writer.writeAll("&outResultLen"),
            }
        }
        try writer.writeByte(')');
        if (returns_error) try writer.writeByte(')');
        if (!returns_error and isCStringReturn(function.origin.*)) try writer.writeByte(')');
        if (!returns_error and function.origin.@"return" != .void and
            function.origin.@"return" != .slice and function.ret_struct == null) try writer.writeByte(')');
        try writer.writeByte('\n');
        if (function.origin.@"return" == .slice and !isCStringReturn(function.origin.*)) {
            try writeCgoSliceReturn(allocator, writer, program, function.origin.@"return".slice.element.*, "outResultPtr", "outResultLen", function.release_symbol, if (releaseFunction(program, function)) |release| release.origin.receiver != null else false);
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .slice or parameter.direction != .out or parameter.type.slice.element.* != .value_struct) continue;
            const slice_name = go_names[parameter_index];
            const c_values_name = try std.fmt.allocPrint(allocator, "{s}Values", .{slice_name});
            defer allocator.free(c_values_name);
            const c_name = try std.fmt.allocPrint(allocator, "c{s}", .{slice_name});
            defer allocator.free(c_name);
            const c_value_name = try std.fmt.allocPrint(allocator, "{s}[i]", .{c_values_name});
            defer allocator.free(c_value_name);
            const record = structRecord(program, parameter.type.slice.element.*.value_struct.ref);
            try writer.print("\tfor i := 0; i < int({s}Written) && i < len({s}); i++ {{\n\t\t{s}[i] = ", .{ slice_name, slice_name, slice_name });
            try writeCgoStructRead(allocator, writer, program, record, "\t\t", c_value_name);
            try writer.writeAll("\n\t}\n");
        }
        if (function.ret_struct) |record| {
            try writer.writeAll("\treturn ");
            try writeCgoStructRead(allocator, writer, program, record.*, "\t", "outResult");
            try writer.writeByte('\n');
        }
        if (returns_error) {
            if (error_payload == .void) {
                try writer.writeAll("\treturn code\n");
            } else if (function.payload_struct) |record| {
                try writer.writeAll("\treturn ");
                try writeCgoStructRead(allocator, writer, program, record.*, "\t", "outResult");
                try writer.writeAll(", code\n");
            } else {
                try writer.writeAll("\treturn ");
                try writeRawResultConversion(writer, program, error_payload, "outResult", options);
                try writer.writeAll(", code\n");
            }
        }
        try writer.writeAll("}\n");
    }
    try renderRawStructTypes(allocator, writer, program);
    try renderRawSnapshotTypes(allocator, writer, program);
    try renderRawTaggedUnionAccessors(allocator, writer, program, options);
    try renderRawSnapshotAccessors(allocator, writer, program);
}

/// cgo keeps the flattened byte and length arrays in Go memory. Both arrays
/// contain no Go pointers, so the C call can borrow them without allocating a
/// C string for every element.
fn writeCgoStringSliceSetup(writer: *std.Io.Writer, name: []const u8) !void {
    try writer.print(
        "\tvar {0s}Data []byte\n" ++
            "\tvar {0s}Lens []C.size_t\n" ++
            "\tif len({0s}) != 0 {{\n" ++
            "\t\t{0s}Lens = make([]C.size_t, len({0s}))\n" ++
            "\t\t{0s}DataLen := 0\n" ++
            "\t\tfor _, value := range {0s} {{ {0s}DataLen += len(value) + 1 }}\n" ++
            "\t\t{0s}Data = make([]byte, {0s}DataLen)\n" ++
            "\t\t{0s}Offset := 0\n" ++
            "\t\tfor i, value := range {0s} {{\n" ++
            "\t\t\t{0s}Lens[i] = C.size_t(len(value))\n" ++
            "\t\t\tcopy({0s}Data[{0s}Offset:], value)\n" ++
            "\t\t\t{0s}Offset += len(value) + 1\n" ++
            "\t\t}}\n" ++
            "\t}}\n" ++
            "\tvar {0s}DataZero C.uint8_t\n" ++
            "\t{0s}DataPtr := &{0s}DataZero\n" ++
            "\tif len({0s}Data) != 0 {{ {0s}DataPtr = (*C.uint8_t)(unsafe.Pointer(&{0s}Data[0])) }}\n" ++
            "\tvar {0s}LensZero C.size_t\n" ++
            "\t{0s}LensPtr := &{0s}LensZero\n" ++
            "\tif len({0s}Lens) != 0 {{ {0s}LensPtr = (*C.size_t)(unsafe.Pointer(&{0s}Lens[0])) }}\n",
        .{name},
    );
}

/// A cgo slice return must not expose native memory. `C.GoBytes` is the byte
/// special case; every other element gets a typed Go allocation so the result
/// has the same element type as the raw function signature.
fn writeCgoSliceReturn(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    element: semantic.TypeNode,
    pointer_name: []const u8,
    length_name: []const u8,
    release_symbol: ?[]const u8,
    release_has_receiver: bool,
) !void {
    if (release_symbol) |symbol| {
        const release_receiver = if (release_has_receiver) "self, " else "";
        // The payload is copied first and released immediately after, so the
        // returned Go slice never aliases memory the library still owns.
        try writer.print("\tvar result []", .{});
        try writeRawGoType(writer, program, element);
        try writer.print("\n\tif {s} != 0 {{\n", .{length_name});
        try writeCgoSliceCopyInto(allocator, writer, program, element, pointer_name, length_name, "\t\t");
        try writer.print("\t}}\n\tC.{s}({s}{s}, {s})\n\treturn result\n", .{ symbol, release_receiver, pointer_name, length_name });
        return;
    }
    if (element == .value_struct) {
        const record = structRecord(program, element.value_struct.ref);
        try writer.print("\tif {s} == 0 {{ return nil }}\n\tcResult := unsafe.Slice((*C.{s})(unsafe.Pointer({s})), int({s}))\n\tresult := make([]", .{ length_name, record.c_name, pointer_name, length_name });
        try writeRawGoType(writer, program, element);
        try writer.print(", int({s}))\n\tfor i := range result {{\n\t\tresult[i] = ", .{length_name});
        try writeCgoStructRead(allocator, writer, program, record, "\t\t", "cResult[i]");
        try writer.writeAll("\n\t}\n\treturn result\n");
        return;
    }
    if (isByteType(element)) {
        try writer.print("\treturn C.GoBytes(unsafe.Pointer({s}), C.int({s}))\n", .{ pointer_name, length_name });
        return;
    }
    try writer.print("\tif {s} == 0 {{ return nil }}\n\tresult := make([]", .{length_name});
    try writeRawGoType(writer, program, element);
    try writer.print(", int({s}))\n\tcopy(result, unsafe.Slice((*", .{length_name});
    try writeRawGoType(writer, program, element);
    try writer.print(")(unsafe.Pointer({s})), int({s})))\n\treturn result\n", .{ pointer_name, length_name });
}

/// The lowered release function for a caller-owned slice return, if any. The
/// symbol alone is enough for cgo, but purego calls through the bindings table
/// and needs the function's Go name and receiver too.
/// Whether this function is some other function's declared release target.
fn isReleaseTarget(program: abi.Program, function: semantic.SemanticFn) bool {
    for (program.functions) |candidate| {
        const release = candidate.origin.release orelse continue;
        if (std.mem.eql(u8, release, function.name)) return true;
    }
    return false;
}

fn releaseFunction(program: abi.Program, function: abi.AbiFn) ?abi.AbiFn {
    const symbol = function.release_symbol orelse return null;
    for (program.functions) |candidate| {
        if (std.mem.eql(u8, candidate.symbol, symbol)) return candidate;
    }
    return null;
}

/// Fills an already declared `result` from the native `ptr, len` pair. It exists
/// so the release path can copy and then free without duplicating the per
/// element-kind conversion.
fn writeCgoSliceCopyInto(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    element: semantic.TypeNode,
    pointer_name: []const u8,
    length_name: []const u8,
    indent: []const u8,
) !void {
    if (element == .value_struct) {
        const record = structRecord(program, element.value_struct.ref);
        try writer.print("{s}cResult := unsafe.Slice((*C.{s})(unsafe.Pointer({s})), int({s}))\n{s}result = make([]", .{ indent, record.c_name, pointer_name, length_name, indent });
        try writeRawGoType(writer, program, element);
        try writer.print(", int({s}))\n{s}for i := range result {{\n{s}\tresult[i] = ", .{ length_name, indent, indent });
        const nested = try std.fmt.allocPrint(allocator, "{s}\t", .{indent});
        defer allocator.free(nested);
        try writeCgoStructRead(allocator, writer, program, record, nested, "cResult[i]");
        try writer.print("\n{s}}}\n", .{indent});
        return;
    }
    if (isByteType(element)) {
        try writer.print("{s}result = C.GoBytes(unsafe.Pointer({s}), C.int({s}))\n", .{ indent, pointer_name, length_name });
        return;
    }
    try writer.print("{s}result = make([]", .{indent});
    try writeRawGoType(writer, program, element);
    try writer.print(", int({s}))\n{s}copy(result, unsafe.Slice((*", .{ length_name, indent });
    try writeRawGoType(writer, program, element);
    try writer.print(")(unsafe.Pointer({s})), int({s})))\n", .{ pointer_name, length_name });
}

/// Base name of the installed native library, without the platform prefix and
/// suffix. `build.zig` always passes it; direct generator callers may omit it
/// and get the package-derived default.
fn libraryStemAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    if (options.library_stem.len != 0) return allocator.dupe(u8, options.library_stem);
    const package = try naming.snakeAlloc(allocator, program.package);
    defer allocator.free(package);
    return std.fmt.allocPrint(allocator, "{s}_zigo", .{package});
}

/// Environment variable names the generated loader consults, in order.
fn libraryEnvNamesAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    if (options.library_env_vars) |names| return allocator.dupe(u8, names);
    const package = try naming.snakeAlloc(allocator, program.package);
    defer allocator.free(package);
    const specific = try naming.libraryPathEnvironmentAlloc(allocator, package);
    defer allocator.free(specific);
    return std.fmt.allocPrint(allocator, "{s},ZIGO_LIBRARY_PATH", .{specific});
}

/// True when any configured search path expands the executable directory.
fn usesExecutableDir(options: Options) bool {
    return std.mem.indexOf(u8, options.library_search_paths, executable_dir_token) != null;
}

const executable_dir_token = "${EXECUTABLE_DIR}";

/// Emits the ordered candidate resolution the loader and the automatic path share.
/// A colocated raw package *is* the public package, so an internal loader
/// policy can only be honoured by not exporting the loader identifiers.
fn loaderPrefix(options: Options) []const u8 {
    return if (options.raw_colocated and !options.library_exported_api) "zigoRaw" else "";
}

fn renderPuregoCandidates(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    const env_names = try libraryEnvNamesAlloc(allocator, program, options);
    defer allocator.free(env_names);
    if (env_names.len != 0) {
        try writer.writeAll("// libraryEnvVars are consulted in order when no explicit path is given.\nvar libraryEnvVars = []string{");
        var names = std.mem.splitScalar(u8, env_names, ',');
        var index: usize = 0;
        while (names.next()) |name| : (index += 1) {
            if (index != 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{name});
        }
        try writer.writeAll("}\n\n");
    }
    if (options.library_search_paths.len != 0) {
        try writer.writeAll("// librarySearchPaths are tried after the environment, in order.\nvar librarySearchPaths = []string{");
        var paths = std.mem.splitScalar(u8, options.library_search_paths, ':');
        var index: usize = 0;
        while (paths.next()) |path| : (index += 1) {
            if (index != 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{path});
        }
        try writer.writeAll("}\n\n");
        try writer.writeAll(
            "// resolveSearchPath joins a directory entry with the platform library\n" ++
                "// name. It returns \"\" when the entry cannot be formed.\n" ++
                "func resolveSearchPath(entry string) string {\n",
        );
        // The executable lookup is only emitted for a policy that asks for it.
        if (usesExecutableDir(options)) try writer.print(
            "\tif strings.Contains(entry, \"{0s}\") {{\n" ++
                "\t\texecutable, err := os.Executable()\n" ++
                "\t\tif err != nil {{ return \"\" }}\n" ++
                "\t\tentry = strings.ReplaceAll(entry, \"{0s}\", filepath.Dir(executable))\n\t}}\n",
            .{executable_dir_token},
        );
        try writer.print(
            "\tif {0s}DefaultLibraryName == \"\" {{ return \"\" }}\n" ++
                "\tif strings.HasSuffix(entry, filepath.Ext({0s}DefaultLibraryName)) {{ return entry }}\n" ++
                "\treturn filepath.Join(entry, {0s}DefaultLibraryName)\n}}\n\n",
            .{loaderPrefix(options)},
        );
    }
    try writer.writeAll(
        "// libraryCandidates lists the paths a load attempt tries, in order.\n" ++
            "func libraryCandidates(explicit string) []string {\n" ++
            "\tif explicit != \"\" { return []string{explicit} }\n" ++
            "\tcandidates := make([]string, 0, ",
    );
    try writer.print("{d})\n", .{@as(usize, 1) +
        @as(usize, if (env_names.len != 0) 1 else 0) +
        @as(usize, if (options.library_search_paths.len != 0) 1 else 0)});
    if (env_names.len != 0) try writer.writeAll(
        "\tfor _, name := range libraryEnvVars {\n" ++
            "\t\tif value := os.Getenv(name); value != \"\" { candidates = append(candidates, value) }\n\t}\n",
    );
    if (options.library_search_paths.len != 0) try writer.writeAll(
        "\tfor _, entry := range librarySearchPaths {\n" ++
            "\t\tif resolved := resolveSearchPath(entry); resolved != \"\" { candidates = append(candidates, resolved) }\n\t}\n",
    );
    try writer.print(
        "\tif {0s}DefaultLibraryName != \"\" {{ candidates = append(candidates, {0s}DefaultLibraryName) }}\n" ++
            "\treturn candidates\n}}\n\n",
        .{loaderPrefix(options)},
    );
}

fn renderPuregoRaw(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    const library_stem = try libraryStemAlloc(allocator, program, options);
    defer allocator.free(library_stem);
    const env_names = try libraryEnvNamesAlloc(allocator, program, options);
    defer allocator.free(env_names);
    const search_paths = options.library_search_paths.len != 0;
    // `os` is only reachable through the environment lookup and the executable
    // directory expansion, so an empty policy must not import it.
    const needs_os = env_names.len != 0 or usesExecutableDir(options);
    try writer.print("// Code generated by zigo. DO NOT EDIT.\npackage {s}\n\nimport (\n\t\"errors\"\n\t\"fmt\"\n", .{options.raw_package_name});
    // Only the dispatchers that rebuild a float from its bits need `math`.
    if (programHasFloatCallbackParam(program)) try writer.writeAll("\t\"math\"\n");
    if (needs_os) try writer.writeAll("\t\"os\"\n");
    if (search_paths) try writer.writeAll("\t\"path/filepath\"\n");
    try writer.writeAll("\t\"runtime\"\n");
    if (search_paths) try writer.writeAll("\t\"strings\"\n");
    try writer.writeAll("\t\"sync\"\n\t\"sync/atomic\"\n\t\"unsafe\"\n\n\t\"github.com/ebitengine/purego\"\n)\n\n");
    try writer.print(
        "// {1s}DefaultLibraryName is the installed shared-library basename for the running platform.\n" ++
            "// It is empty on platforms this backend does not support.\n" ++
            "var {1s}DefaultLibraryName = map[string]string{{\"darwin\": \"lib{0s}.dylib\", \"linux\": \"lib{0s}.so\", \"windows\": \"{0s}.dll\"}}[runtime.GOOS]\n\n" ++
            "// ErrLibraryLoad identifies a shared-library load or symbol resolution failure.\n" ++
            "var ErrLibraryLoad = errors.New(\"zigo: shared library unavailable\")\n\n" ++
            "// LibraryError reports a native library loading or symbol resolution failure.\n" ++
            "type LibraryError struct {{\n\tPath string\n\tSymbol string\n\tOperation string\n\tCause error\n}}\n\n" ++
            "// Error describes the failed loading operation.\n" ++
            "func (err *LibraryError) Error() string {{\n\tif err.Symbol != \"\" {{ return fmt.Sprintf(\"zigo: %s %q from %q: %v\", err.Operation, err.Symbol, err.Path, err.Cause) }}\n\tif err.Path == \"\" {{ return fmt.Sprintf(\"zigo: %s: %v\", err.Operation, err.Cause) }}\n\treturn fmt.Sprintf(\"zigo: %s %q: %v\", err.Operation, err.Path, err.Cause)\n}}\n" ++
            "// Is reports ErrLibraryLoad so every generated error classifies the same way.\n" ++
            "func (err *LibraryError) Is(target error) bool {{ return target == ErrLibraryLoad }}\n" ++
            "// Unwrap returns the platform loader error.\n" ++
            "func (err *LibraryError) Unwrap() error {{ return err.Cause }}\n\n" ++
            "type nativeBindings struct {{\n",
        .{ library_stem, loaderPrefix(options) },
    );
    // An unsafe.Pointer return keeps the message read free of uintptr
    // round-trips, which `go vet` reports as a possible stale pointer.
    try writer.writeAll("\tlastError func() unsafe.Pointer\n");
    for (program.functions) |function| {
        const name = try rawGoNameAlloc(allocator, function.origin.*);
        defer allocator.free(name);
        try writer.print("\tfn{s} func(", .{name});
        for (function.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writePuregoAbiType(writer, parameter.scalar);
        }
        try writer.writeByte(')');
        if (function.ret != .void) {
            try writer.writeByte(' ');
            try writePuregoAbiType(writer, function.ret);
        }
        try writer.writeByte('\n');
    }
    for (program.projections, 0..) |projection, projection_index| {
        try writer.print("\tfnProjection{d} func(", .{projection_index});
        for (projection.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writePuregoAbiType(writer, parameter.scalar);
        }
        try writer.writeAll(") uint8\n");
    }
    for (program.snapshots, 0..) |snapshot, snapshot_index| {
        try writer.print("\tfnSnapshot{d} func(", .{snapshot_index});
        for (snapshot.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            try writePuregoAbiType(writer, parameter.scalar);
        }
        try writer.writeAll(") uint8\n");
    }
    try writer.writeAll("}\n\n");
    if (programHasCallbacks(program)) try renderPuregoCallbackRegistry(allocator, writer, program, options);
    try writer.print(
        "var loadedBindings atomic.Pointer[nativeBindings]\nvar loadMu sync.Mutex\nvar successfulLibraryPath string\n\n" ++
            "// {0s}LibraryLoaded reports whether every required native symbol was published.\n" ++
            "func {0s}LibraryLoaded() bool {{ return loadedBindings.Load() != nil }}\n\n",
        .{loaderPrefix(options)},
    );
    if (options.library_automatic)
        try writer.writeAll("var automaticLoadAttempted bool\nvar automaticLoadError error\n\n");
    try renderPuregoCandidates(allocator, writer, program, options);
    try writer.print(
        "// {0s}LoadLibrary atomically loads and registers every required native symbol.\n" ++
            "// An empty path uses the configured candidates. A failed load leaves the\n" ++
            "// binding retryable; a successful handle is never unloaded.\n" ++
            "func {0s}LoadLibrary(path string) error {{\n\tloadMu.Lock()\n\tdefer loadMu.Unlock()\n\treturn loadLibraryLocked(path)\n}}\n\n",
        .{loaderPrefix(options)},
    );
    try writer.writeAll(
        "func loadLibraryLocked(explicit string) error {\n" ++
            "\tcandidates := libraryCandidates(explicit)\n" ++
            "\tif len(candidates) == 0 { return &LibraryError{Operation: \"load\", Cause: errors.New(\"no shared-library candidate is configured for this platform; pass an explicit path\")} }\n" ++
            "\tif loadedBindings.Load() != nil {\n" ++
            "\t\tfor _, candidate := range candidates { if candidate == successfulLibraryPath { return nil } }\n" ++
            "\t\treturn &LibraryError{Path: candidates[0], Operation: \"load\", Cause: errors.New(\"a different library is already loaded\")}\n\t}\n",
    );
    if (programHasCallbacks(program)) try writer.writeAll("\tensureCallbackDispatchers()\n");
    try writer.writeAll(
        "\tattempts := make([]error, 0, len(candidates))\n" ++
            "\tfor _, candidate := range candidates {\n" ++
            "\t\tif err := loadCandidate(candidate); err != nil { attempts = append(attempts, err); continue }\n" ++
            "\t\tsuccessfulLibraryPath = candidate\n\t\treturn nil\n\t}\n" ++
            "\t// One candidate keeps the precise path and symbol of its own failure.\n" ++
            "\tif len(attempts) == 1 { return attempts[0] }\n" ++
            "\treturn &LibraryError{Operation: \"load\", Cause: errors.Join(attempts...)}\n}\n\n" ++
            "// loadCandidate publishes the call surface only after every symbol resolves.\n" ++
            "func loadCandidate(path string) error {\n" ++
            "\thandle, err := openLibrary(path)\n" ++
            "\tif err != nil { return &LibraryError{Path: path, Operation: \"open\", Cause: err} }\n" ++
            "\tfail := func(symbol string, cause error) error { closeLibrary(handle); return &LibraryError{Path: path, Symbol: symbol, Operation: \"resolve\", Cause: cause} }\n",
    );
    try writePuregoResolve(writer, "addrLastError", "zg_last_error_message");
    for (program.functions) |function| {
        const name = try rawGoNameAlloc(allocator, function.origin.*);
        defer allocator.free(name);
        const variable = try std.fmt.allocPrint(allocator, "addr{s}", .{name});
        defer allocator.free(variable);
        try writePuregoResolve(writer, variable, function.symbol);
    }
    for (program.projections, 0..) |projection, index| {
        const variable = try std.fmt.allocPrint(allocator, "addrProjection{d}", .{index});
        defer allocator.free(variable);
        try writePuregoResolve(writer, variable, projection.symbol);
    }
    for (program.snapshots, 0..) |snapshot, index| {
        const variable = try std.fmt.allocPrint(allocator, "addrSnapshot{d}", .{index});
        defer allocator.free(variable);
        try writePuregoResolve(writer, variable, snapshot.symbol);
    }
    try writer.writeAll("\tvar next nativeBindings\n\tpurego.RegisterFunc(&next.lastError, addrLastError)\n");
    for (program.functions) |function| {
        const name = try rawGoNameAlloc(allocator, function.origin.*);
        defer allocator.free(name);
        try writer.print("\tpurego.RegisterFunc(&next.fn{s}, addr{s})\n", .{ name, name });
    }
    for (program.projections, 0..) |_, index|
        try writer.print("\tpurego.RegisterFunc(&next.fnProjection{d}, addrProjection{d})\n", .{ index, index });
    for (program.snapshots, 0..) |_, index|
        try writer.print("\tpurego.RegisterFunc(&next.fnSnapshot{d}, addrSnapshot{d})\n", .{ index, index });
    try writer.writeAll("\tloadedBindings.Store(&next)\n\treturn nil\n}\n\n");
    if (options.library_automatic) {
        try writer.writeAll(
            "// ensureLoaded performs the one automatic load attempt. A later explicit\n" ++
                "// call can still succeed with a different path.\n" ++
                "func ensureLoaded() {\n" ++
                "\tloadMu.Lock()\n\tdefer loadMu.Unlock()\n" ++
                "\tif loadedBindings.Load() != nil || automaticLoadAttempted { return }\n" ++
                "\tautomaticLoadAttempted = true\n\tautomaticLoadError = loadLibraryLocked(\"\")\n}\n\n" ++
                "func bindings() *nativeBindings {\n" ++
                "\tvalue := loadedBindings.Load()\n" ++
                "\tif value == nil {\n\t\tensureLoaded()\n\t\tvalue = loadedBindings.Load()\n\t}\n" ++
                "\tif value == nil { panic(automaticLoadError) }\n\treturn value\n}\n\n",
        );
    } else {
        try writer.writeAll("func bindings() *nativeBindings {\n\tvalue := loadedBindings.Load()\n\tif value == nil { panic(\"zigo: native library is not loaded; call " ++
            "LoadLibrary first\") }\n\treturn value\n}\n\n");
    }
    const last_error_name = if (options.raw_colocated) "zigoRawLastErrorMessage" else "LastErrorMessage";
    try writer.print("// {s} returns the most recent native panic message for this binding.\nfunc {s}() string {{\n" ++
        "\tp := bindings().lastError()\n\tif p == nil {{ return \"\" }}\n" ++
        "\tlength := 0\n\tfor *(*byte)(unsafe.Add(p, length)) != 0 {{ length++ }}\n" ++
        "\treturn string(unsafe.Slice((*byte)(p), length))\n}}\n", .{ last_error_name, last_error_name });
    if (programHasCString(program)) try writer.writeAll(
        "\nfunc zigoCStringString(p unsafe.Pointer) string {\n" ++
            "\tif p == nil { return \"\" }\n" ++
            "\tlength := 0\n" ++
            "\tfor *(*byte)(unsafe.Add(p, length)) != 0 { length++ }\n" ++
            "\treturn string(unsafe.Slice((*byte)(p), length))\n" ++
            "}\n",
    );
    try renderRawStructTypes(allocator, writer, program);
    try renderRawSnapshotTypes(allocator, writer, program);
    for (program.functions) |function| {
        try renderPuregoFunction(allocator, writer, program, function, options);
    }
    try renderPuregoProjections(allocator, writer, program);
    try renderRawSnapshotAccessors(allocator, writer, program);
}

fn renderPuregoCallbackRegistry(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    const prefix = if (options.raw_colocated) "zigoRaw" else "";
    try writer.writeAll(
        "type callbackEntry struct {\n\tmu sync.Mutex\n\tcond *sync.Cond\n\tvalue any\n\tclosing bool\n\tactive int\n}\n\n" ++
            "// callbackRegistry maps a userdata token to its entry without a global lock,\n// mirroring the sync.Map behind runtime/cgo.Handle on the cgo backend.\n// Delete races an in-flight acquire safely through the entry's closing flag:\n// an acquire either takes active++ before closing is set, in which case\n// DeleteCallbackHandle waits for it to drain, or it observes closing and\n// reports the token as gone.\nvar callbackRegistry sync.Map // uintptr -> *callbackEntry\nvar nextCallbackToken atomic.Uint64\nvar activeCallbackHandles atomic.Int64\n\n",
    );
    try writer.print("// {s}NewCallbackHandle stores a callback value and returns its native userdata token.\nfunc {s}NewCallbackHandle(value any) uintptr {{\n", .{ prefix, prefix });
    try writer.writeAll("\tentry := &callbackEntry{value: value}\n\tentry.cond = sync.NewCond(&entry.mu)\n\ttoken := uintptr(nextCallbackToken.Add(1))\n\tif token == 0 { token = uintptr(nextCallbackToken.Add(1)) }\n\tcallbackRegistry.Store(token, entry)\n\tactiveCallbackHandles.Add(1)\n\treturn token\n}\n\n");
    try writer.print("// {s}DeleteCallbackHandle releases a callback token after in-flight calls finish.\nfunc {s}DeleteCallbackHandle(token uintptr) {{\n", .{ prefix, prefix });
    try writer.writeAll("\tif token == 0 { return }\n\tstored, loaded := callbackRegistry.LoadAndDelete(token)\n\tif !loaded { return }\n\tentry := stored.(*callbackEntry)\n\tentry.mu.Lock()\n\tentry.closing = true\n\tfor entry.active != 0 { entry.cond.Wait() }\n\tentry.value = nil\n\tentry.mu.Unlock()\n\tactiveCallbackHandles.Add(-1)\n}\n\n");
    try writer.print("// {s}ActiveCallbackHandleCount reports the number of live callback tokens.\nfunc {s}ActiveCallbackHandleCount() int64 {{ return activeCallbackHandles.Load() }}\n\n", .{ prefix, prefix });
    try writer.writeAll("func acquireCallback(token uintptr) (*callbackEntry, any, bool) {\n\tstored, loaded := callbackRegistry.Load(token)\n\tif !loaded { return nil, nil, false }\n\tentry := stored.(*callbackEntry)\n\tentry.mu.Lock()\n\tif entry.closing { entry.mu.Unlock(); return nil, nil, false }\n\tentry.active++\n\tvalue := entry.value\n\tentry.mu.Unlock()\n\treturn entry, value, true\n}\n\nfunc releaseCallback(entry *callbackEntry) {\n\tentry.mu.Lock()\n\tentry.active--\n\tif entry.closing && entry.active == 0 { entry.cond.Broadcast() }\n\tentry.mu.Unlock()\n}\n\n");

    if (programHasWideningCallbackResult(program)) try writer.writeAll(
        "// callbackResult widens a signed 32-bit callback result to the uintptr\n" ++
            "// every dispatcher must return. The native caller declares the callback as\n" ++
            "// returning int32_t and reads only the low word, so the value round-trips.\n" ++
            "func callbackResult(value int32) uintptr { return uintptr(uint32(value)) }\n\n",
    );
    const count = uniqueCallbackSignatureCount(program);
    try writer.print("var callbackPointers [{d}]uintptr\nvar callbackDispatchersOnce sync.Once\n\nfunc ensureCallbackDispatchers() {{\n\tcallbackDispatchersOnce.Do(func() {{\n", .{count});
    var signature_index: usize = 0;
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .callback or !isFirstCallbackSignatureAt(program, function.origin, parameter_index)) continue;
            try writer.print("\t\tcallbackPointers[{d}] = purego.NewCallback(func(", .{signature_index});
            const callback = parameter.type.callback;
            for (callback.params, 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("p{d} ", .{index});
                // A float parameter arrives as its IEEE-754 bit pattern in an
                // integer of the same width; the shim thunk converted it so the
                // Windows callback compiler never sees a floating-point argument.
                if (callback_parameter == .float)
                    try writer.print("uint{d}", .{callback_parameter.float.bits})
                else
                    try writeRawGoType(writer, program, callback_parameter);
            }
            // Every dispatcher returns uintptr, including the ones whose Zig
            // callback returns nothing. Windows compiles callbacks through
            // `syscall.NewCallback`, which rejects any function that does not
            // have exactly one pointer-sized result; a narrower result is not
            // an option, and a void one even less so. The C caller reads only
            // the low word, so an int32 result survives the widening on both
            // supported architectures, and a void callback's value is ignored.
            try writer.writeAll(") (result uintptr) {\n");
            try writer.writeAll("\t\t\tdefer func() { if recover() != nil { result = ");
            try writeCallbackFailureValue(writer, callback.@"return".*, true);
            try writer.writeAll(" } }()\n");
            const userdata_index = callback.params.len - 1;
            try writer.print("\t\t\tentry, stored, ok := acquireCallback(uintptr(p{d}))\n\t\t\tif !ok {{ return ", .{userdata_index});
            try writeCallbackFailureValue(writer, callback.@"return".*, false);
            try writer.writeAll(" }\n\t\t\tdefer releaseCallback(entry)\n\t\t\tcallback := stored.(func(");
            for (callback.params[0..userdata_index], 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writeRawGoType(writer, program, callback_parameter);
            }
            try writer.writeByte(')');
            if (callback.@"return".* != .void) {
                try writer.writeByte(' ');
                try writeRawGoType(writer, program, callback.@"return".*);
            }
            try writer.writeAll(")\n\t\t\t");
            const widens = callbackResultWidens(callback.@"return".*);
            if (widens) try writer.writeAll("return callbackResult(");
            try writer.writeAll("callback(");
            for (callback.params[0..userdata_index], 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                if (callback_parameter == .float)
                    try writer.print("math.Float{d}frombits(p{d})", .{ callback_parameter.float.bits, index })
                else
                    try writer.print("p{d}", .{index});
            }
            try writer.writeAll(")");
            if (widens) try writer.writeAll(")") else try writer.writeAll("\n\t\t\treturn 0");
            try writer.writeAll("\n\t\t})\n");
            signature_index += 1;
        }
    }
    try writer.writeAll("\t})\n}\n\n");
    for (0..count) |index|
        try writer.print("// {s}CallbackPointer{d} returns the permanent dispatcher for callback ABI signature {d}.\nfunc {s}CallbackPointer{d}() uintptr {{ ensureCallbackDispatchers(); return callbackPointers[{d}] }}\n", .{ prefix, index, index, prefix, index, index });
    try writer.print("// {s}CallbackDispatcherCount reports the number of unique callback ABI dispatchers.\nfunc {s}CallbackDispatcherCount() int {{ ensureCallbackDispatchers(); return len(callbackPointers) }}\n", .{ prefix, prefix });
    try writer.writeByte('\n');
    _ = allocator;
}

/// The signed 32-bit result is the only callback ABI that carries failure
/// codes; every other shape reports failure as a plain zero.
fn callbackResultWidens(node: semantic.TypeNode) bool {
    return node == .int and node.int.signed and node.int.bits == 32;
}

fn writeCallbackFailureValue(writer: *std.Io.Writer, node: semantic.TypeNode, panic_value: bool) !void {
    if (callbackResultWidens(node))
        try writer.writeAll(if (panic_value) "callbackResult(-3)" else "callbackResult(-4)")
    else
        try writer.writeAll("0");
}

/// True when any callback signature returns the signed 32-bit ABI, which is
/// the only one whose dispatcher needs the widening helper.
/// True when any callback carries a float parameter, and so any dispatcher has
/// to rebuild one from its bits.
fn programHasFloatCallbackParam(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (parameter.type != .callback) continue;
            if (callbackHasFloatParam(parameter.type.callback)) return true;
        }
    }
    return false;
}

fn programHasWideningCallbackResult(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (parameter.type != .callback) continue;
            if (callbackResultWidens(parameter.type.callback.@"return".*)) return true;
        }
    }
    return false;
}

fn uniqueCallbackSignatureCount(program: abi.Program) usize {
    var count: usize = 0;
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type == .callback and isFirstCallbackSignatureAt(program, function.origin, parameter_index)) count += 1;
        }
    }
    return count;
}

fn callbackSignatureIndex(program: abi.Program, wanted: semantic.Callback) usize {
    var index: usize = 0;
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .callback or !isFirstCallbackSignatureAt(program, function.origin, parameter_index)) continue;
            if (callbackSignatureEqual(parameter.type.callback, wanted)) return index;
            index += 1;
        }
    }
    unreachable;
}

fn isFirstCallbackSignatureAt(program: abi.Program, origin: *const semantic.SemanticFn, parameter_index: usize) bool {
    const wanted = origin.params[parameter_index].type.callback;
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, candidate_index| {
            if (function.origin == origin and candidate_index == parameter_index) return true;
            if (parameter.type == .callback and callbackSignatureEqual(parameter.type.callback, wanted)) return false;
        }
    }
    unreachable;
}

fn callbackSignatureEqual(lhs: semantic.Callback, rhs: semantic.Callback) bool {
    if (lhs.params.len != rhs.params.len or !semanticTypeEqual(lhs.@"return".*, rhs.@"return".*)) return false;
    for (lhs.params, rhs.params) |a, b| if (!semanticTypeEqual(a, b)) return false;
    return true;
}

fn semanticTypeEqual(lhs: semantic.TypeNode, rhs: semantic.TypeNode) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .void, .bool => true,
        .int => |value| value.bits == rhs.int.bits and value.signed == rhs.int.signed and value.is_usize == rhs.int.is_usize,
        .float => |value| value.bits == rhs.float.bits,
        .@"enum" => |value| std.mem.eql(u8, value.ref, rhs.@"enum".ref),
        .opaque_ptr => |value| value.@"const" == rhs.opaque_ptr.@"const" and value.nullable == rhs.opaque_ptr.nullable and std.mem.eql(u8, value.ref, rhs.opaque_ptr.ref),
        .slice => |value| value.@"const" == rhs.slice.@"const" and value.sentinel == rhs.slice.sentinel and
            value.sentinel_many == rhs.slice.sentinel_many and semanticTypeEqual(value.element.*, rhs.slice.element.*),
        else => false,
    };
}

/// purego uses the same pointer-free representation as cgo, but the ABI
/// registration accepts uintptr-sized length arrays and unsafe.Pointer values.
fn writePuregoStringSliceSetup(writer: *std.Io.Writer, name: []const u8) !void {
    try writer.print(
        "\tvar {0s}Data []byte\n" ++
            "\tvar {0s}Lens []uintptr\n" ++
            "\tif len({0s}) != 0 {{\n" ++
            "\t\t{0s}Lens = make([]uintptr, len({0s}))\n" ++
            "\t\t{0s}DataLen := 0\n" ++
            "\t\tfor _, value := range {0s} {{ {0s}DataLen += len(value) + 1 }}\n" ++
            "\t\t{0s}Data = make([]byte, {0s}DataLen)\n" ++
            "\t\t{0s}Offset := 0\n" ++
            "\t\tfor i, value := range {0s} {{\n" ++
            "\t\t\t{0s}Lens[i] = uintptr(len(value))\n" ++
            "\t\t\tcopy({0s}Data[{0s}Offset:], value)\n" ++
            "\t\t\t{0s}Offset += len(value) + 1\n" ++
            "\t\t}}\n" ++
            "\t}}\n" ++
            "\tvar {0s}DataPtr unsafe.Pointer\n" ++
            "\tif len({0s}Data) != 0 {{ {0s}DataPtr = unsafe.Pointer(&{0s}Data[0]) }}\n" ++
            "\tvar {0s}LensPtr unsafe.Pointer\n" ++
            "\tif len({0s}Lens) != 0 {{ {0s}LensPtr = unsafe.Pointer(&{0s}Lens[0]) }}\n",
        .{name},
    );
}

fn renderPuregoFunction(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, function: abi.AbiFn, options: Options) !void {
    const go_name = try rawGoNameAlloc(allocator, function.origin.*);
    defer allocator.free(go_name);
    const raw_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ if (options.raw_colocated) "zigoRaw" else "", go_name });
    defer allocator.free(raw_name);
    const go_names = try goParamNamesForAlloc(allocator, function.origin.params);
    defer naming.freeParamNames(allocator, go_names);
    try writer.print("\n// {s} calls the generated purego ABI wrapper for {s}.\nfunc {s}(", .{ raw_name, function.symbol, raw_name });
    var parameter_count: usize = 0;
    if (function.origin.receiver != null) {
        try writer.writeAll("self unsafe.Pointer");
        parameter_count = 1;
    }
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (callbackForUserdata(function.origin.params, parameter_index) != null) continue;
        if (parameter_count != 0) try writer.writeAll(", ");
        if (parameter.type == .callback) {
            try writer.print("{s}Callback, {s}Token uintptr", .{ go_names[parameter_index], go_names[parameter_index] });
        } else {
            try writer.print("{s} ", .{go_names[parameter_index]});
            try writeRawParameterType(writer, program, parameter);
        }
        parameter_count += 1;
    }
    try writer.writeByte(')');
    try writeRawReturnType(writer, program, function);
    try writer.writeAll(" {\n");
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (!isStringSliceParameter(parameter)) continue;
        try writePuregoStringSliceSetup(writer, go_names[parameter_index]);
    }
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (!isCStringParameter(parameter)) continue;
        const name = go_names[parameter_index];
        try writer.print("\t{s}Bytes := make([]byte, len({s})+1)\n\tcopy({s}Bytes, {s})\n\t{s}Ptr := unsafe.Pointer(&{s}Bytes[0])\n", .{
            name,
            name,
            name,
            name,
            name,
            name,
        });
    }
    for (function.origin.params, 0..) |parameter, parameter_index| if (parameter.type == .slice) {
        if (isStringSliceParameter(parameter) or isCStringParameter(parameter)) continue;
        const slice_name = go_names[parameter_index];
        try writer.print("\tvar {s}Ptr unsafe.Pointer\n\tif len({s}) != 0 {{ {s}Ptr = unsafe.Pointer(&{s}[0]) }}\n", .{ slice_name, slice_name, slice_name, slice_name });
        if (parameter.direction == .out) try writer.print("\tvar {s}Written uintptr\n", .{slice_name});
    };
    if (function.origin.@"return" == .slice and !isCStringReturn(function.origin.*)) try writer.writeAll("\tvar outResultPtr unsafe.Pointer\n\tvar outResultLen uintptr\n");
    if (function.ret_struct != null) {
        try writer.writeAll("\tvar outResult ");
        try writeRawGoType(writer, program, function.origin.@"return");
        try writer.writeByte('\n');
    }
    const returns_error = function.origin.@"return" == .error_union;
    const error_payload = if (returns_error) function.origin.@"return".error_union.payload.* else semantic.TypeNode{ .void = {} };
    if (returns_error and error_payload != .void) {
        try writer.writeAll("\tvar outResult ");
        if (error_payload == .value_struct)
            try writeRawGoType(writer, program, error_payload)
        else if (puregoPayloadNeedsConversion(error_payload))
            try writePuregoAbiType(writer, semanticScalar(program, error_payload))
        else
            try writeRawGoType(writer, program, error_payload);
        try writer.writeByte('\n');
    }
    try writer.writeByte('\t');
    if (returns_error)
        try writer.writeAll("code := ")
    else if ((function.origin.@"return" != .void and function.origin.@"return" != .slice and function.ret_struct == null) or isCStringReturn(function.origin.*))
        try writer.writeAll("result := ");
    try writer.print("bindings().fn{s}(", .{go_name});
    for (function.params, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        switch (parameter.role) {
            .receiver => try writer.writeAll("self"),
            .struct_in => try writer.print("unsafe.Pointer(&{s})", .{go_names[parameter.source_index]}),
            .struct_out => try writer.writeAll("unsafe.Pointer(&outResult)"),
            .value => {
                const source_name = go_names[parameter.source_index];
                if (isCStringParameter(function.origin.params[parameter.source_index])) {
                    try writer.print("{s}Ptr", .{source_name});
                } else if (isStringSliceParameter(function.origin.params[parameter.source_index])) {
                    try writer.print("{s}DataPtr", .{source_name});
                } else if (parameter.scalar == .callback) {
                    try writer.print("{s}Callback", .{source_name});
                } else if (callbackForUserdataIndex(function.origin.params, parameter.source_index)) |callback_index| {
                    try writer.print("{s}Token", .{go_names[callback_index]});
                } else if (parameter.scalar == .usize)
                    try writer.print("uintptr({s})", .{source_name})
                else
                    try writer.writeAll(source_name);
            },
            .slice_pointer => try writer.print("{s}Ptr", .{go_names[parameter.source_index]}),
            .slice_length => try writer.print("uintptr(len({s}))", .{go_names[parameter.source_index]}),
            .slice_written => try writer.print("&{s}Written", .{go_names[parameter.source_index]}),
            .string_data => try writer.print("{s}DataPtr", .{go_names[parameter.source_index]}),
            .string_data_length => try writer.print("uintptr(len({s}Data))", .{go_names[parameter.source_index]}),
            .string_lengths => try writer.print("{s}LensPtr", .{go_names[parameter.source_index]}),
            .string_count => try writer.print("uintptr(len({s}))", .{go_names[parameter.source_index]}),
            // A struct payload crosses as a raw address, matching the
            // unsafe.Pointer the bindings table declares for it.
            // An aggregate payload crosses as a raw address, exactly as the
            // lowered scalar for this parameter already says.
            .payload_out => try writer.writeAll(if (parameter.scalar == .pointer and
                parameter.scalar.pointer.child.* == .value_struct) "unsafe.Pointer(&outResult)" else "&outResult"),
            .return_slice_pointer => try writer.writeAll("&outResultPtr"),
            .return_slice_length => try writer.writeAll("&outResultLen"),
        }
    }
    try writer.writeAll(")\n");
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (isStringSliceParameter(parameter)) {
            try writer.print("\truntime.KeepAlive({s}Data)\n\truntime.KeepAlive({s}Lens)\n", .{ go_names[parameter_index], go_names[parameter_index] });
        }
        if (isCStringParameter(parameter)) try writer.print("\truntime.KeepAlive({s}Bytes)\n", .{go_names[parameter_index]});
    }
    if (isCStringReturn(function.origin.*)) {
        try writer.writeAll("\treturn zigoCStringString(result)\n");
    } else if (function.origin.@"return" == .slice) {
        const element = function.origin.@"return".slice.element.*;
        if (releaseFunction(program, function)) |release| {
            // Copy first, then hand the native buffer straight back, so the
            // returned slice is Go memory before the library frees anything.
            const release_name = try rawGoNameAlloc(allocator, release.origin.*);
            defer allocator.free(release_name);
            try writer.writeAll("\tvar result []");
            try writeRawGoType(writer, program, element);
            try writer.writeAll("\n\tif outResultLen != 0 {\n\t\tresult = make([]");
            try writeRawGoType(writer, program, element);
            try writer.writeAll(", int(outResultLen))\n\t\tcopy(result, unsafe.Slice((*");
            try writeRawGoType(writer, program, element);
            try writer.writeAll(")(outResultPtr), int(outResultLen)))\n\t}\n");
            try writer.print("\tbindings().fn{s}({s}outResultPtr, outResultLen)\n\treturn result\n", .{
                release_name,
                if (release.origin.receiver != null) "self, " else "",
            });
        } else {
            try writer.writeAll("\tif outResultLen == 0 { return nil }\n\tresult := make([]");
            try writeRawGoType(writer, program, element);
            try writer.writeAll(", int(outResultLen))\n\tcopy(result, unsafe.Slice((*");
            try writeRawGoType(writer, program, element);
            try writer.writeAll(")(outResultPtr), int(outResultLen)))\n\treturn result\n");
        }
    } else if (returns_error) {
        if (error_payload == .void) {
            try writer.writeAll("\treturn code\n");
        } else if (puregoPayloadNeedsConversion(error_payload)) {
            try writer.writeAll("\treturn ");
            try writeRawResultConversion(writer, program, error_payload, "outResult", options);
            try writer.writeAll(", code\n");
        } else {
            try writer.writeAll("\treturn outResult, code\n");
        }
    } else if (function.ret_struct != null) {
        try writer.writeAll("\treturn outResult\n");
    } else if (function.origin.@"return" != .void) {
        try writer.writeAll("\treturn ");
        try writeRawResultConversion(writer, program, function.origin.@"return", "result", options);
        try writer.writeByte('\n');
    }
    try writer.writeAll("}\n");
}

fn puregoPayloadNeedsConversion(node: semantic.TypeNode) bool {
    return node == .int and node.int.is_usize;
}

fn renderPuregoProjections(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.projections, 0..) |projection, projection_index| {
        const declaration = projection.owner.*;
        switch (projection.kind) {
            .tag => {
                try writer.print("\n// {s}ProjectTag returns the active tag and a projection status.\nfunc {s}ProjectTag(self unsafe.Pointer) (", .{ declaration.name, declaration.name });
                try writeRawGoType(writer, program, declaration.tag_type.?);
                try writer.writeAll(", uint8) {\n\tvar outValue ");
                try writeRawGoType(writer, program, declaration.tag_type.?);
                try writer.print("\n\tstatus := bindings().fnProjection{d}(self, &outValue)\n\treturn outValue, status\n}}\n", .{projection_index});
            },
            .payload => {
                const field = projection.field.?.*;
                const payload = field.type.?;
                const field_name = try naming.pascalAlloc(allocator, field.name);
                defer allocator.free(field_name);
                try writer.print("\n// {s}Project{s} returns the payload and a projection status.\nfunc {s}Project{s}(self unsafe.Pointer) (", .{ declaration.name, field_name, declaration.name, field_name });
                try writeRawGoType(writer, program, payload);
                try writer.writeAll(", uint8) {\n");
                if (payload == .slice) {
                    try writer.writeAll("\tvar outValuePtr unsafe.Pointer\n\tvar outValueLen uintptr\n");
                    try writer.print("\tstatus := bindings().fnProjection{d}(self, &outValuePtr, &outValueLen)\n", .{projection_index});
                    try writer.writeAll("\tif status != 1 || outValueLen == 0 { return nil, status }\n\tresult := make([]");
                    try writeRawGoType(writer, program, payload.slice.element.*);
                    try writer.writeAll(", int(outValueLen))\n\tcopy(result, unsafe.Slice((*");
                    try writeRawGoType(writer, program, payload.slice.element.*);
                    try writer.writeAll(")(outValuePtr), int(outValueLen)))\n\treturn result, status\n");
                } else {
                    try writer.writeAll("\tvar outValue ");
                    try writeRawGoType(writer, program, payload);
                    try writer.print("\n\tstatus := bindings().fnProjection{d}(self, &outValue)\n\treturn outValue, status\n", .{projection_index});
                }
                try writer.writeAll("}\n");
            },
        }
    }
}

fn writePuregoResolve(writer: *std.Io.Writer, variable: []const u8, symbol: []const u8) !void {
    try writer.print("\t{s}, err := resolveSymbol(handle, \"{s}\")\n\tif err != nil {{ return fail(\"{s}\", err) }}\n", .{ variable, symbol, symbol });
}

fn writePuregoAbiType(writer: *std.Io.Writer, scalar: abi.AbiScalar) !void {
    switch (scalar) {
        .void => {},
        .bool_u8 => try writer.writeAll("uint8"),
        .isize => try writer.writeAll("int"),
        .usize => try writer.writeAll("uintptr"),
        .signed_int => |bits| try writer.print("int{d}", .{bits}),
        .unsigned_int => |bits| try writer.print("uint{d}", .{bits}),
        .float => |bits| try writer.print("float{d}", .{bits}),
        .@"opaque" => try writer.writeAll("byte"),
        .snapshot, .value_struct => try writer.writeAll("unsafe.Pointer"),
        .pointer => |pointer| {
            // Aggregates cross as a raw address; purego never needs to know
            // their Go spelling.
            if (pointer.is_many or pointer.child.* == .@"opaque" or
                pointer.child.* == .snapshot or pointer.child.* == .value_struct)
                return writer.writeAll("unsafe.Pointer");
            try writer.writeByte('*');
            try writePuregoAbiType(writer, pointer.child.*);
        },
        .callback => try writer.writeAll("uintptr"),
    }
}

/// The Go spelling of a snapshot member. Padding keeps the layout without
/// becoming part of the API, so it is written to the blank identifier.
fn snapshotGoFieldAlloc(allocator: std.mem.Allocator, field: abi.AbiSnapshot.Field) ![]u8 {
    if (field.kind == .padding) return allocator.dupe(u8, "_");
    return naming.pascalAlloc(allocator, field.name);
}

fn snapshotRawTypeNameAlloc(allocator: std.mem.Allocator, snapshot: abi.AbiSnapshot) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}SnapshotData", .{snapshot.owner.name});
}

fn snapshotRawFunctionNameAlloc(allocator: std.mem.Allocator, snapshot: abi.AbiSnapshot) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}ReadSnapshot", .{snapshot.owner.name});
}

/// The raw layout struct, shared verbatim by both backends: cgo converts into
/// it member by member, purego lets the native call fill it in place.
fn renderRawSnapshotTypes(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.snapshots) |snapshot| {
        const type_name = try snapshotRawTypeNameAlloc(allocator, snapshot);
        defer allocator.free(type_name);
        try writer.print(
            "\n// {s} mirrors the {s} value snapshot layout, padding included.\ntype {s} struct {{\n",
            .{ type_name, snapshot.type_name, type_name },
        );
        for (snapshot.fields) |field| {
            const go_name = try snapshotGoFieldAlloc(allocator, field);
            defer allocator.free(go_name);
            try writer.print("\t{s} ", .{go_name});
            if (field.kind == .padding) {
                try writer.print("[{d}]byte\n", .{field.bytes});
            } else {
                try writeGoScalar(writer, field.scalar);
                try writer.writeByte('\n');
            }
        }
        try writer.writeAll("}\n");
    }
}

fn renderRawSnapshotAccessors(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.snapshots, 0..) |snapshot, snapshot_index| {
        const type_name = try snapshotRawTypeNameAlloc(allocator, snapshot);
        defer allocator.free(type_name);
        const function_name = try snapshotRawFunctionNameAlloc(allocator, snapshot);
        defer allocator.free(function_name);
        try writer.print(
            "\n// {s} fills a value snapshot in one native call and returns a projection status.\nfunc {s}(self unsafe.Pointer) ({s}, uint8) {{\n",
            .{ function_name, function_name, type_name },
        );
        if (program.backend == .purego) {
            try writer.print("\tvar out {s}\n", .{type_name});
            try writer.print("\tstatus := bindings().fnSnapshot{d}(self, unsafe.Pointer(&out))\n", .{snapshot_index});
            try writer.print("\tif status != 1 {{\n\t\treturn {s}{{}}, status\n\t}}\n\treturn out, status\n}}\n", .{type_name});
            continue;
        }
        try writer.print("\tvar out C.{s}\n", .{snapshot.type_name});
        try writer.print("\tstatus := C.{s}((*C.{s})(self), &out)\n", .{ snapshot.symbol, handleRecord(program, snapshot.owner.name).c_name });
        try writer.print("\tif status != 1 {{\n\t\treturn {s}{{}}, uint8(status)\n\t}}\n\treturn {s}{{\n", .{ type_name, type_name });
        for (snapshot.fields) |field| {
            if (field.kind == .padding) continue;
            const go_name = try snapshotGoFieldAlloc(allocator, field);
            defer allocator.free(go_name);
            try writer.print("\t\t{s}: ", .{go_name});
            try writeGoScalar(writer, field.scalar);
            try writer.print("(out.{s}),\n", .{field.name});
        }
        try writer.writeAll("\t}, uint8(status)\n}\n");
    }
}

fn renderRawTaggedUnionAccessors(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    for (program.projections) |projection| {
        const declaration = projection.owner.*;
        const union_c_name = handleRecord(program, declaration.name).c_name;
        switch (projection.kind) {
            .tag => {
                try writer.print("\n// {s}ProjectTag returns the active tag and a projection status.\nfunc {s}ProjectTag(self unsafe.Pointer) (", .{ declaration.name, declaration.name });
                try writeRawGoType(writer, program, declaration.tag_type.?);
                try writer.writeAll(", uint8) {\n\tvar outValue C.");
                try writeCgoType(writer, semanticScalar(program, declaration.tag_type.?));
                try writer.writeAll("\n\tstatus := C.");
                try writer.print("{s}((*C.{s})(self), &outValue)\n\treturn ", .{ projection.symbol, union_c_name });
                try writeRawGoType(writer, program, declaration.tag_type.?);
                try writer.writeAll("(outValue), uint8(status)\n}\n");
            },
            .payload => {
                const field = projection.field.?.*;
                const payload = field.type.?;
                const field_name = try naming.pascalAlloc(allocator, field.name);
                defer allocator.free(field_name);
                try writer.print("\n// {s}Project{s} returns the payload and a projection status.\nfunc {s}Project{s}(self unsafe.Pointer) (", .{ declaration.name, field_name, declaration.name, field_name });
                try writeRawGoType(writer, program, payload);
                try writer.writeAll(", uint8) {\n");
                if (payload == .slice) {
                    try writer.writeAll("\tvar outValuePtr *C.");
                    try writeCgoType(writer, semanticScalar(program, payload.slice.element.*));
                    try writer.writeAll("\n\tvar outValueLen C.size_t\n\tstatus := C.");
                    try writer.print("{s}((*C.{s})(self), &outValuePtr, &outValueLen)\n", .{ projection.symbol, union_c_name });
                    try writer.writeAll("\tif status != 1 {\n\t\treturn nil, uint8(status)\n\t}\n");
                    if (isByteType(payload.slice.element.*)) {
                        try writer.writeAll("\treturn C.GoBytes(unsafe.Pointer(outValuePtr), C.int(outValueLen)), uint8(status)\n");
                    } else {
                        try writer.writeAll("\tif outValueLen == 0 { return nil, uint8(status) }\n\tresult := make([]");
                        try writeRawGoType(writer, program, payload.slice.element.*);
                        try writer.writeAll(", int(outValueLen))\n\tcopy(result, unsafe.Slice((*");
                        try writeRawGoType(writer, program, payload.slice.element.*);
                        try writer.writeAll(")(unsafe.Pointer(outValuePtr)), int(outValueLen)))\n\treturn result, uint8(status)\n");
                    }
                } else {
                    if (payload == .opaque_ptr) {
                        try writer.writeAll("\tvar outValue unsafe.Pointer\n");
                    } else {
                        try writer.writeAll("\tvar outValue C.");
                        try writeCgoType(writer, semanticScalar(program, payload));
                        try writer.writeByte('\n');
                    }
                    try writer.print("\tstatus := C.{s}((*C.{s})(self), &outValue)\n\tif status != 1 {{\n\t\treturn ", .{ projection.symbol, union_c_name });
                    try writer.writeAll(rawGoZero(payload));
                    try writer.writeAll(", uint8(status)\n\t}\n\treturn ");
                    try writeRawResultConversion(writer, program, payload, "outValue", options);
                    try writer.writeAll(", uint8(status)\n");
                }
                try writer.writeAll("}\n");
            },
        }
    }
}

fn renderRawCallbacks(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .callback) continue;
            const callback = parameter.type.callback;
            if (!callback.has_userdata or callback.params.len == 0) return error.CallbackRequiresUserdata;
            const name = try callbackTrampolineNameAlloc(allocator, function, parameter_index);
            defer allocator.free(name);
            try writer.print("//export {s}\nfunc {s}(", .{ name, name });
            for (callback.params, 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("p{d} C.", .{index});
                try writeCgoType(writer, semanticScalar(program, callback_parameter));
            }
            try writer.writeAll(") (result C.");
            try writeCgoType(writer, semanticScalar(program, callback.@"return".*));
            try writer.writeAll(") {\n\tdefer func() {\n\t\tif recover() != nil {\n");
            if (callback.@"return".* == .int and callback.@"return".int.signed and callback.@"return".int.bits == 32) {
                try writer.writeAll("\t\t\tresult = C.int32_t(-3)\n");
            } else {
                try writer.writeAll("\t\t\tresult = 0\n");
            }
            try writer.writeAll("\t\t}\n\t}()\n\tcallback := cgo.Handle(");
            try writer.print("p{d}", .{callback.params.len - 1});
            try writer.writeAll(").Value().(func(");
            const value_count = callback.params.len - 1;
            for (callback.params[0..value_count], 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writeRawGoType(writer, program, callback_parameter);
            }
            try writer.writeByte(')');
            if (callback.@"return".* != .void) try writer.writeByte(' ');
            try writeRawGoType(writer, program, callback.@"return".*);
            try writer.writeAll(")\n\treturn C.");
            try writeCgoType(writer, semanticScalar(program, callback.@"return".*));
            try writer.writeAll("(callback(");
            for (callback.params[0..value_count], 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writeRawGoType(writer, program, callback_parameter);
                try writer.print("(p{d})", .{index});
            }
            try writer.writeAll("))\n}\n\n");
        }
    }
}

fn isValueStructSlice(node: semantic.TypeNode) bool {
    return node == .slice and node.slice.element.* == .value_struct;
}

fn hasOutValueStructSlice(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| {
        if (parameter.direction == .out and isValueStructSlice(parameter.type)) return true;
    }
    return false;
}

fn isCountReturn(node: semantic.TypeNode) bool {
    return node == .int and node.int.is_usize and !node.int.signed;
}

fn writePublicValueStructSliceCopyBacks(
    writer: *std.Io.Writer,
    function: semantic.SemanticFn,
    go_names: [][]u8,
) !void {
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.direction != .out or !isValueStructSlice(parameter.type)) continue;
        const name = go_names[parameter_index];
        try writer.print("\tzigo{s}SliceCopyFromRaw({s}, {s}Raw, ", .{ parameter.type.slice.element.*.value_struct.ref, name, name });
        const return_node = if (function.@"return" == .error_union) function.@"return".error_union.payload.* else function.@"return";
        if (isCountReturn(return_node))
            try writer.writeAll("int(result)")
        else
            try writer.print("len({s})", .{name});
        try writer.writeAll(")\n");
    }
}

fn writePublicCapturedReturn(writer: *std.Io.Writer, function: semantic.SemanticFn, needs_handle_check: bool) !void {
    try writer.writeAll("\treturn ");
    switch (function.@"return") {
        .value_struct => |value| try writer.print("zigo{s}FromRaw(result)", .{value.ref}),
        .slice => |value| if (value.element.* == .value_struct)
            try writer.print("zigo{s}SliceFromRaw(result)", .{value.element.*.value_struct.ref})
        else if (isUtf8Slice(function.@"return", function.return_semantic))
            try writer.writeAll("string(result)")
        else
            try writer.writeAll("result"),
        .bool => try writer.writeAll("result != 0"),
        .@"enum" => |value| try writer.print("{s}(result)", .{value.ref}),
        else => try writer.writeAll("result"),
    }
    if (needs_handle_check) try writer.writeAll(", nil");
    try writer.writeByte('\n');
}

fn renderPublic(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    const package = try publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    try writer.print("// Code generated by zigo. DO NOT EDIT.\npackage {s}\n\n", .{package});
    const needs_runtime = publicNeedsRuntime(program);
    const needs_raw = !options.raw_colocated;
    const import_count = @as(usize, @intFromBool(needs_runtime)) + @as(usize, @intFromBool(needs_raw));
    if (import_count > 1) {
        try writer.writeAll("import (\n");
        if (needs_runtime) try writer.writeAll("\t\"runtime\"\n");
        if (needs_raw) {
            if (needs_runtime) try writer.writeByte('\n');
            try writeRawImport(writer, options, "\t");
        }
        try writer.writeAll(")\n\n");
    } else if (needs_runtime) {
        try writer.writeAll("import \"runtime\"\n\n");
    } else if (needs_raw) {
        try writer.writeAll("import ");
        try writeRawImport(writer, options, "");
        try writer.writeByte('\n');
    }
    // An internal loader keeps the public package limited to the bound API.
    if (options.backend == .purego and !options.raw_colocated and options.library_exported_api) try writer.writeAll(
        "// LibraryError reports a native shared-library loading failure.\n" ++
            "type LibraryError = raw.LibraryError\n\n" ++
            "// LoadLibrary atomically loads all generated native entry points.\n" ++
            "func LoadLibrary(path string) error { return raw.LoadLibrary(path) }\n\n" ++
            "// LibraryLoaded reports whether the native call surface is ready.\n" ++
            "func LibraryLoaded() bool { return raw.LibraryLoaded() }\n\n" ++
            "// DefaultLibraryName is the installed shared-library basename for the running platform.\n" ++
            "// LoadLibrary falls back to it when no explicit path and no ZIGO_LIBRARY_PATH are set.\n" ++
            "var DefaultLibraryName = raw.DefaultLibraryName\n\n",
    );
    for (program.functions) |function| {
        const constructor = constructorForInit(program, function.origin.*);
        if (constructor == null and constructorForDeinit(program, function.origin.*) != null) continue;
        // A release function is called for the caller by the raw layer. Exposing
        // it publicly would invite freeing a Go-owned copy, so it stays internal.
        if (isReleaseTarget(program, function.origin.*)) continue;
        const owned_type = if (constructor) |value| value.type else ownedOpaqueReturn(program, function.origin.*);
        const go_names = try goParamNamesForAlloc(allocator, function.origin.params);
        defer naming.freeParamNames(allocator, go_names);
        const go_name = if (constructor) |value|
            try std.fmt.allocPrint(allocator, "New{s}", .{value.type})
        else
            try naming.pascalAlloc(allocator, function.origin.name);
        defer allocator.free(go_name);
        const operation = if (function.origin.receiver) |receiver|
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ receiver, go_name })
        else
            try allocator.dupe(u8, go_name);
        defer allocator.free(operation);
        // A nil or closed handle is a caller error, so it leaves through the
        // return value instead of a panic. Functions that do not touch a
        // handle keep their plain signature.
        const needs_handle_check = function.origin.receiver != null or hasOpaqueParameter(function.origin.*);
        try writePublicFunctionDoc(writer, function.origin.*, go_name, owned_type);
        if (function.origin.receiver) |receiver| {
            const receiver_name = try receiverVariableAlloc(allocator, receiver);
            defer allocator.free(receiver_name);
            try writer.print("func ({s} *{s}) {s}(", .{ receiver_name, receiver, go_name });
        } else {
            try writer.print("func {s}(", .{go_name});
        }
        var public_parameter_index: usize = 0;
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (callbackForUserdata(function.origin.params, parameter_index) != null) continue;
            if (public_parameter_index != 0) try writer.writeAll(", ");
            try writer.print("{s} ", .{go_names[parameter_index]});
            if (parameter.type == .callback) {
                const callback_name = try callbackTypeNameAlloc(allocator, program, function, parameter_index);
                defer allocator.free(callback_name);
                try writer.writeAll(callback_name);
            } else {
                try writePublicParameterType(writer, parameter);
            }
            public_parameter_index += 1;
        }
        try writer.writeByte(')');
        if (constructor) |value| {
            try writer.print(" (*{s}, error)", .{value.type});
        } else if (needs_handle_check and function.origin.@"return" != .error_union) {
            try writeCheckedFunctionReturnType(writer, function.origin.*);
        } else {
            try writePublicFunctionReturnType(writer, function.origin.*);
        }
        try writer.writeAll(" {\n");
        try renderKeepAliveDefers(allocator, writer, program, function);
        // The handle checks run before any callback handle is registered, so
        // an early return cannot strand a retained callback.
        if (needs_handle_check)
            try renderHandleChecks(allocator, writer, function.origin.*, go_names, operation, constructor);
        try renderCallbackHandleSetup(allocator, writer, program, function);
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (!isValueStructSlice(parameter.type)) continue;
            try writer.print("\t{s}Raw := zigo{s}SliceToRaw({s})\n", .{ go_names[parameter_index], parameter.type.slice.element.*.value_struct.ref, go_names[parameter_index] });
        }
        try writer.writeByte('\t');
        const returns_error = function.origin.@"return" == .error_union;
        const error_payload = if (returns_error) function.origin.@"return".error_union.payload.* else semantic.TypeNode{ .void = {} };
        const borrowed_direct = function.origin.@"return" == .opaque_ptr and function.origin.ownership == .borrowed;
        // A caller-owned handle returned without an error union still has to be
        // wrapped, so it is captured into `result` exactly like a borrowed one.
        const owned_direct = !returns_error and owned_type != null;
        const captures_return = !returns_error and !borrowed_direct and !owned_direct and
            hasOutValueStructSlice(function.origin.*) and function.origin.@"return" != .void;
        if (returns_error) {
            if (error_payload == .void) try writer.writeAll("code := ") else try writer.writeAll("result, code := ");
            try writeRawReferencePrefix(writer, options);
        } else if (borrowed_direct or owned_direct) {
            try writer.writeAll("result := ");
            try writeRawReferencePrefix(writer, options);
        } else if (captures_return) {
            try writer.writeAll("result := ");
            try writeRawReferencePrefix(writer, options);
        } else if (isCStringReturn(function.origin.*)) {
            try writer.writeAll("return ");
            try writeRawReferencePrefix(writer, options);
        } else if (isUtf8Slice(function.origin.@"return", function.origin.return_semantic)) {
            try writer.writeAll("return string(");
            try writeRawReferencePrefix(writer, options);
        } else if (function.origin.@"return" != .void) {
            if (function.origin.@"return" == .@"enum") {
                try writer.print("return {s}(", .{function.origin.@"return".@"enum".ref});
                try writeRawReferencePrefix(writer, options);
            } else if (function.origin.@"return" == .value_struct) {
                try writer.print("return zigo{s}FromRaw(", .{function.origin.@"return".value_struct.ref});
                try writeRawReferencePrefix(writer, options);
            } else if (isValueStructSlice(function.origin.@"return")) {
                try writer.print("return zigo{s}SliceFromRaw(", .{function.origin.@"return".slice.element.*.value_struct.ref});
                try writeRawReferencePrefix(writer, options);
            } else {
                try writer.writeAll("return ");
                try writeRawReferencePrefix(writer, options);
            }
        } else {
            try writeRawReferencePrefix(writer, options);
        }
        const raw_name = try rawGoNameAlloc(allocator, function.origin.*);
        defer allocator.free(raw_name);
        try writer.print("{s}(", .{raw_name});
        var call_index: usize = 0;
        if (function.origin.receiver != null) {
            try writer.writeAll("ptr");
            call_index = 1;
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (callbackForUserdata(function.origin.params, parameter_index) != null) continue;
            if (call_index != 0) try writer.writeAll(", ");
            switch (parameter.type) {
                .callback => {
                    if (options.backend == .purego) {
                        const signature_index = callbackSignatureIndex(program, parameter.type.callback);
                        try writeRawReferencePrefix(writer, options);
                        try writer.print("CallbackPointer{d}(), uintptr({s}Handle)", .{ signature_index, go_names[parameter_index] });
                        call_index += 1;
                    } else {
                        try writer.print("uintptr({s}Handle)", .{go_names[parameter_index]});
                    }
                },
                .bool => try writer.print("boolToUint8({s})", .{go_names[parameter_index]}),
                .value_struct => |value| try writer.print("zigo{s}ToRaw({s})", .{ value.ref, go_names[parameter_index] }),
                .@"enum" => {
                    try writer.writeAll(rawGoTypeName(program, parameter.type));
                    try writer.print("({s})", .{go_names[parameter_index]});
                },
                .opaque_ptr => try writer.print("{s}Ptr", .{go_names[parameter_index]}),
                .slice => if (isValueStructSlice(parameter.type))
                    try writer.print("{s}Raw", .{go_names[parameter_index]})
                else if (isStringSliceParameter(parameter))
                    try writer.writeAll(go_names[parameter_index])
                else if (isCStringParameter(parameter))
                    try writer.writeAll(go_names[parameter_index])
                else if (isUtf8Slice(parameter.type, parameter.semantic))
                    try writer.print("[]byte({s})", .{go_names[parameter_index]})
                else
                    try writer.writeAll(go_names[parameter_index]),
                else => try writer.writeAll(go_names[parameter_index]),
            }
            call_index += 1;
        }
        try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .@"enum") try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .value_struct) try writer.writeByte(')');
        if (!returns_error and !captures_return and isValueStructSlice(function.origin.@"return")) try writer.writeByte(')');
        if (!returns_error and !captures_return and function.origin.@"return" == .bool) try writer.writeAll(" != 0");
        if (!returns_error and !captures_return and isUtf8Slice(function.origin.@"return", function.origin.return_semantic)) try writer.writeByte(')');
        if (!returns_error and !captures_return and !borrowed_direct and !owned_direct and needs_handle_check and function.origin.@"return" != .void) try writer.writeAll(", nil");
        try writer.writeByte('\n');
        if (!returns_error and hasOutValueStructSlice(function.origin.*)) {
            try writePublicValueStructSliceCopyBacks(writer, function.origin.*, go_names);
            if (captures_return) try writePublicCapturedReturn(writer, function.origin.*, needs_handle_check);
        }
        if (borrowed_direct or owned_direct) {
            try writer.writeAll("\treturn ");
            if (owned_type) |type_name|
                try writeOwnedHandleResult(allocator, writer, program, function.origin.*, type_name, "result")
            else
                try writeBorrowedResult(allocator, writer, function.origin.*, "result");
            if (needs_handle_check) try writer.writeAll(", nil");
            try writer.writeByte('\n');
        }
        if (!returns_error and needs_handle_check and function.origin.@"return" == .void) try writer.writeAll("\treturn nil\n");
        if (returns_error) {
            try writer.writeAll("\tif code != 0 {\n");
            if (hasRetainedCallback(function.origin.*)) {
                try writeDeleteRetainedCallbacks(allocator, writer, function.origin.*);
            }
            try writer.writeAll("\t\treturn ");
            if (error_payload != .void) {
                try writeGoZeroValue(writer, error_payload);
                try writer.writeAll(", ");
            }
            try writer.print("errorForCode(\"{s}\", code)\n\t}}\n", .{operation});
            if (hasOutValueStructSlice(function.origin.*)) {
                try writePublicValueStructSliceCopyBacks(writer, function.origin.*, go_names);
            }
            if (error_payload == .void) {
                try writer.writeAll("\treturn nil\n");
            } else {
                try writer.writeAll("\treturn ");
                if (owned_type) |type_name| {
                    try writeOwnedHandleResult(allocator, writer, program, function.origin.*, type_name, "result");
                } else if (error_payload == .opaque_ptr and function.origin.ownership == .borrowed) {
                    try writeBorrowedResult(allocator, writer, function.origin.*, "result");
                } else {
                    try writePublicResultConversion(writer, error_payload, "result");
                }
                try writer.writeAll(", nil\n");
            }
        }
        try writer.writeAll("}\n");
    }
}

/// Renders one concern-scoped file of the public package: the generated
/// marker, the package clause, the import block the body actually needs, and
/// the body. A body that declares nothing leaves the file at its prelude, and
/// the generator drops it.
fn renderPublicFile(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: Options,
    renderBody: *const fn (std.mem.Allocator, *std.Io.Writer, abi.Program, Options) anyerror!void,
) !void {
    const package = try publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    try writer.print("// Code generated by zigo. DO NOT EDIT.\npackage {s}\n", .{package});
    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();
    try renderBody(allocator, &body.writer, program, options);
    const text = body.written();
    if (text.len == 0) return;
    try writePublicImports(writer, text, options);
    try writer.writeAll(text);
}

/// Every standard-library package a generated public file can need, in the
/// order gofmt sorts them. The qualifier is what the body writes, so the
/// import block is derived from the body instead of from a second, parallel
/// set of predicates that could disagree with it.
const public_std_imports = [_]struct { qualifier: []const u8, path: []const u8 }{
    .{ .qualifier = "runtime", .path = "runtime" },
    .{ .qualifier = "cgo", .path = "runtime/cgo" },
    .{ .qualifier = "strconv", .path = "strconv" },
    .{ .qualifier = "sync", .path = "sync" },
    .{ .qualifier = "atomic", .path = "sync/atomic" },
    .{ .qualifier = "unsafe", .path = "unsafe" },
};

fn writePublicImports(writer: *std.Io.Writer, body: []const u8, options: Options) !void {
    var needed: [public_std_imports.len][]const u8 = undefined;
    var count: usize = 0;
    for (public_std_imports) |entry| {
        if (!bodyUsesQualifier(body, entry.qualifier)) continue;
        needed[count] = entry.path;
        count += 1;
    }
    // The raw package is always reached through the `raw` qualifier: a raw
    // package with another name is imported under that alias.
    const raw = !options.raw_colocated and bodyUsesQualifier(body, "raw");
    if (count == 0 and !raw) return writer.writeByte('\n');
    if (count + @as(usize, @intFromBool(raw)) == 1) {
        try writer.writeAll("\nimport ");
        if (raw) {
            try writeRawImport(writer, options, "");
        } else {
            try writer.print("\"{s}\"\n", .{needed[0]});
        }
        return writer.writeByte('\n');
    }
    try writer.writeAll("\nimport (\n");
    for (needed[0..count]) |path| try writer.print("\t\"{s}\"\n", .{path});
    if (raw) {
        if (count != 0) try writer.writeByte('\n');
        try writeRawImport(writer, options, "\t");
    }
    try writer.writeAll(")\n\n");
}

/// True when the body uses `qualifier.` as a package selector in code. Line
/// comments and string literals are skipped: a generated doc comment ending in
/// a Zig tag name, or a `String()` case returning one, must not be mistaken for
/// an import the file does not have.
fn bodyUsesQualifier(body: []const u8, qualifier: []const u8) bool {
    var index: usize = 0;
    while (index < body.len) {
        const byte = body[index];
        if (byte == '/' and index + 1 < body.len and body[index + 1] == '/') {
            index = std.mem.indexOfScalarPos(u8, body, index, '\n') orelse body.len;
            continue;
        }
        if (byte == '`') {
            index = 1 + (std.mem.indexOfScalarPos(u8, body, index + 1, '`') orelse body.len - 1);
            continue;
        }
        if (byte == '"' or byte == '\'') {
            index += 1;
            while (index < body.len and body[index] != byte) : (index += 1) {
                if (body[index] == '\\') index += 1;
            }
            index += 1;
            continue;
        }
        if (!isGoIdentifierByte(byte)) {
            index += 1;
            continue;
        }
        const begin = index;
        while (index < body.len and isGoIdentifierByte(body[index])) index += 1;
        if (index < body.len and body[index] == '.' and std.mem.eql(u8, body[begin..index], qualifier)) return true;
    }
    return false;
}

fn isGoIdentifierByte(byte: u8) bool {
    return byte == '_' or std.ascii.isAlphanumeric(byte);
}

fn renderPublicEnumsFile(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    try renderPublicFile(allocator, writer, program, options, renderPublicEnumsBody);
}

fn renderPublicEnumsBody(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, _: Options) !void {
    try renderGoEnums(allocator, writer, program);
}

fn renderPublicStructsFile(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    try renderPublicFile(allocator, writer, program, options, renderPublicValueStructs);
}

fn renderPublicHandlesFile(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    try renderPublicFile(allocator, writer, program, options, renderGoHandles);
}

fn renderPublicRuntimeFile(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    try renderPublicFile(allocator, writer, program, options, renderPublicRuntimeBody);
}

/// The fixed part of every generated public package: the handle interface the
/// projections take, the projection status vocabulary, the `Must*` wrappers,
/// and the callback plumbing. None of it grows with the binding.
fn renderPublicRuntimeBody(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    try renderGoHandleRuntime(writer, program);
    try renderGoProjectionRuntime(writer, program, options);
    try renderGoCallbackTypes(allocator, writer, program);
    try renderPublicHelpers(allocator, writer, program, options);
}

/// One generated file, produced outside the fixed emitter table because how
/// many there are depends on the bindings.
pub const File = struct {
    path: []u8,
    contents: []u8,
};

/// The per-union files: each tagged union's projections, snapshot, and sealed
/// variant hierarchy, in the order the union was declared.
pub fn unionFilesAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]File {
    const variants = try unionVariantNamesAlloc(allocator, program);
    defer freeUnionVariantNames(allocator, variants);

    var files: std.ArrayList(File) = .empty;
    errdefer {
        for (files.items) |file| {
            allocator.free(file.path);
            allocator.free(file.contents);
        }
        files.deinit(allocator);
    }
    var stems: std.ArrayList([]u8) = .empty;
    defer {
        for (stems.items) |stem| allocator.free(stem);
        stems.deinit(allocator);
    }
    for (variants) |entry| {
        const stem = try naming.unionFileStemAlloc(allocator, entry.owner.name, @ptrCast(stems.items));
        try stems.append(allocator, stem);
        const path = try publicUnionPathAlloc(allocator, program, options, stem);
        errdefer allocator.free(path);
        var rendered: std.Io.Writer.Allocating = .init(allocator);
        defer rendered.deinit();
        try renderUnionFile(allocator, &rendered.writer, program, options, entry);
        try files.append(allocator, .{ .path = path, .contents = try rendered.toOwnedSlice() });
    }
    return files.toOwnedSlice(allocator);
}

fn renderUnionFile(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: Options,
    entry: UnionVariantNames,
) !void {
    const package = try publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    try writer.print("// Code generated by zigo. DO NOT EDIT.\npackage {s}\n", .{package});
    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();
    try renderPublicTaggedUnionAccessors(allocator, &body.writer, program, options, entry.owner);
    try renderPublicSnapshots(allocator, &body.writer, program, options, entry.owner);
    try renderPublicUnionVariants(allocator, &body.writer, program, entry);
    const text = body.written();
    if (text.len == 0) return;
    try writePublicImports(writer, text, options);
    try writer.writeAll(text);
}

/// The public face of an `extern struct` is an ordinary Go value type. The
/// pointer that actually crosses the boundary is taken inside the generated
/// call, so callers never see it.
fn renderPublicValueStructs(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    for (program.structs) |record| {
        try writer.print("// {s} mirrors the Zig `extern struct` of the same name.\ntype {s} struct {{\n", .{ record.name, record.name });
        for (record.fields) |field| {
            const member = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(member);
            try writer.print("\t// {s} corresponds to the Zig field {s}.\n\t{s} ", .{ member, field.name, member });
            try writePublicGoType(writer, field.node);
            try writer.writeByte('\n');
        }
        try writer.writeAll("}\n\n");
    }
    for (program.structs) |record| {
        const raw_type = try structRawTypeNameAlloc(allocator, record.name);
        defer allocator.free(raw_type);
        try writer.print("func zigo{s}ToRaw(value {s}) ", .{ record.name, record.name });
        try writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s} {{\n\treturn ", .{raw_type});
        try writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s}{{\n", .{raw_type});
        for (record.fields) |field| {
            const member = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(member);
            try writer.print("\t\t{s}: ", .{member});
            switch (field.node) {
                .value_struct => |nested| try writer.print("zigo{s}ToRaw(value.{s})", .{ nested.ref, member }),
                .bool => try writer.print("boolToUint8(value.{s})", .{member}),
                .@"enum" => {
                    try writer.writeAll(rawGoTypeName(program, field.node));
                    try writer.print("(value.{s})", .{member});
                },
                else => try writer.print("value.{s}", .{member}),
            }
            try writer.writeAll(",\n");
        }
        try writer.writeAll("\t}\n}\n\n");

        try writer.print("func zigo{s}FromRaw(value ", .{record.name});
        try writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s}) {s} {{\n\treturn {s}{{\n", .{ raw_type, record.name, record.name });
        for (record.fields) |field| {
            const member = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(member);
            try writer.print("\t\t{s}: ", .{member});
            switch (field.node) {
                .value_struct => |nested| try writer.print("zigo{s}FromRaw(value.{s})", .{ nested.ref, member }),
                else => {
                    const expression = try std.fmt.allocPrint(allocator, "value.{s}", .{member});
                    defer allocator.free(expression);
                    try writePublicResultConversion(writer, field.node, expression);
                },
            }
            try writer.writeAll(",\n");
        }
        try writer.writeAll("\t}\n}\n\n");

        try writer.print("func zigo{s}SliceToRaw(values []{s}) []", .{ record.name, record.name });
        try writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s} {{\n\tresult := make([]", .{raw_type});
        try writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s}, len(values))\n\tfor i := range values {{\n\t\tresult[i] = zigo{s}ToRaw(values[i])\n\t}}\n\treturn result\n}}\n\n", .{ raw_type, record.name });

        try writer.print("func zigo{s}SliceFromRaw(values []", .{record.name});
        try writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s}) []{s} {{\n\tresult := make([]{s}, len(values))\n\tfor i := range values {{\n\t\tresult[i] = zigo{s}FromRaw(values[i])\n\t}}\n\treturn result\n}}\n\n", .{ raw_type, record.name, record.name, record.name });

        try writer.print("func zigo{s}SliceCopyFromRaw(dst []{s}, values []", .{ record.name, record.name });
        try writeRawTypeReferencePrefix(writer, options);
        try writer.print("{s}, count int) {{\n\tif count > len(dst) {{ count = len(dst) }}\n\tif count > len(values) {{ count = len(values) }}\n\tfor i := 0; i < count; i++ {{\n\t\tdst[i] = zigo{s}FromRaw(values[i])\n\t}}\n}}\n\n", .{ raw_type, record.name });
    }
}

/// The public snapshot type and its one-call reader. This is added next to
/// `Tag`/`As*`, never in place of them.
fn renderPublicSnapshots(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: Options,
    owner: semantic.TypeDecl,
) !void {
    for (program.snapshots) |snapshot| {
        const declaration = snapshot.owner.*;
        if (!std.mem.eql(u8, declaration.name, owner.name)) continue;
        const tag_type = declaration.tag_type.?.@"enum".ref;
        const type_name = try std.fmt.allocPrint(allocator, "{s}Snapshot", .{declaration.name});
        defer allocator.free(type_name);
        const raw_function = try snapshotRawFunctionNameAlloc(allocator, snapshot);
        defer allocator.free(raw_function);
        const recv = try receiverVariableAlloc(allocator, declaration.name);
        defer allocator.free(recv);

        try writer.print(
            "// {s} is a value copy of a {s}: one native call carries the active tag\n" ++
                "// and every scalar payload back together.\ntype {s} struct {{\n\ttag {s}\n",
            .{ type_name, declaration.name, type_name, tag_type },
        );
        for (snapshot.fields) |field| {
            if (field.kind != .payload) continue;
            const member = try naming.camelAlloc(allocator, field.name);
            defer allocator.free(member);
            try writer.print("\t{s} ", .{member});
            try writePublicGoType(writer, field.node.?);
            try writer.writeByte('\n');
        }
        try writer.print("}}\n\n// Tag returns the variant the snapshot captured.\nfunc (snapshot {s}) Tag() {s} {{\n\treturn snapshot.tag\n}}\n\n", .{ type_name, tag_type });
        for (snapshot.fields) |field| {
            if (field.kind != .payload) continue;
            const member = try naming.camelAlloc(allocator, field.name);
            defer allocator.free(member);
            const accessor = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(accessor);
            const tag_constant = try naming.pascalAlloc(allocator, field.source.?.name);
            defer allocator.free(tag_constant);
            try writer.print("// {s} returns the {s} payload and whether it is the captured variant.\nfunc (snapshot {s}) {s}() (", .{ accessor, field.source.?.name, type_name, accessor });
            try writePublicGoType(writer, field.node.?);
            try writer.print(", bool) {{\n\treturn snapshot.{s}, snapshot.tag == {s}{s}\n}}\n\n", .{ member, tag_type, tag_constant });
        }

        // One reader per union, shared by the owned and borrowed handles.
        try writer.print(
            "func zigo{0s}Snapshot(receiver zigoHandle) ({1s}, error) {{\n\tdefer zigoReadLock(receiver)()\n\tdefer runtime.KeepAlive(receiver)\n" ++
                "\tptr, err := zigoCheckedPointer(\"{0s}.Snapshot receiver\", receiver)\n\tif err != nil {{\n\t\treturn {1s}{{}}, err\n\t}}\n\tdata, status := ",
            .{ declaration.name, type_name },
        );
        try writeRawReferencePrefix(writer, options);
        try writer.print(
            "{0s}(ptr)\n\tif status != zigoProjectionSuccess {{\n\t\treturn {1s}{{}}, zigoProjectionError(\"{2s}.Snapshot\", status)\n\t}}\n\treturn {1s}{{\n\t\ttag: {3s}(data.Tag),\n",
            .{ raw_function, type_name, declaration.name, tag_type },
        );
        for (snapshot.fields) |field| {
            if (field.kind != .payload) continue;
            const member = try naming.camelAlloc(allocator, field.name);
            defer allocator.free(member);
            const raw_member = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(raw_member);
            try writer.print("\t\t{s}: ", .{member});
            const temp = try std.fmt.allocPrint(allocator, "data.{s}", .{raw_member});
            defer allocator.free(temp);
            try writePublicResultConversion(writer, field.node.?, temp);
            try writer.writeAll(",\n");
        }
        try writer.writeAll("\t}, nil\n}\n\n");

        inline for (.{ false, true }) |borrowed| {
            const suffix = if (borrowed) "Ref" else "";
            try writer.print(
                "// Snapshot reads the tag and every payload in one native call, or\n" ++
                    "// returns a typed lifecycle/native error.\nfunc ({0s} *{1s}{2s}) Snapshot() ({3s}, error) {{ return zigo{1s}Snapshot({0s}) }}\n\n",
                .{ recv, declaration.name, suffix, type_name },
            );
            try writer.print(
                "// MustSnapshot reads the tag and every payload in one native call and panics\n" ++
                    "// with a typed error on failure.\nfunc ({0s} *{1s}{2s}) MustSnapshot() {3s} {{ return zigoMust(zigo{1s}Snapshot({0s})) }}\n\n",
                .{ recv, declaration.name, suffix, type_name },
            );
        }
    }
}

/// Every top-level Go identifier the public package already declares. A
/// derived variant type name is checked against this so the sealed hierarchy
/// can never shadow a handle, an enum constant, or a tag type.
fn publicIdentifiersAlloc(allocator: std.mem.Allocator, program: abi.Program) ![][]u8 {
    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }
    for (program.types) |declaration| {
        try names.append(allocator, try allocator.dupe(u8, declaration.name));
        switch (declaration.kind) {
            .@"opaque" => try names.append(allocator, try std.fmt.allocPrint(allocator, "{s}Ref", .{declaration.name})),
            .tagged_union => {
                try names.append(allocator, try std.fmt.allocPrint(allocator, "{s}Ref", .{declaration.name}));
                try names.append(allocator, try std.fmt.allocPrint(allocator, "{s}Snapshot", .{declaration.name}));
                try names.append(allocator, try std.fmt.allocPrint(allocator, "{s}Variant", .{declaration.name}));
            },
            .@"enum" => for (declaration.fields) |field| {
                const constant = try naming.pascalAlloc(allocator, field.name);
                defer allocator.free(constant);
                try names.append(allocator, try std.fmt.allocPrint(allocator, "{s}{s}", .{ declaration.name, constant }));
            },
            else => {},
        }
    }
    return names.toOwnedSlice(allocator);
}

fn freeIdentifiers(allocator: std.mem.Allocator, names: [][]u8) void {
    for (names) |name| allocator.free(name);
    allocator.free(names);
}

/// One tagged union and the variant type name each of its fields settled on.
const UnionVariantNames = struct {
    owner: semantic.TypeDecl,
    names: [][]u8,
};

/// Variant type names for every tagged union, resolved in declaration order
/// against one shared identifier set. The names are settled for the whole
/// program before any file is written, so splitting the unions across files
/// cannot change the name a later union would have picked.
fn unionVariantNamesAlloc(allocator: std.mem.Allocator, program: abi.Program) ![]UnionVariantNames {
    var identifiers = try publicIdentifiersAlloc(allocator, program);
    defer freeIdentifiers(allocator, identifiers);

    var entries: std.ArrayList(UnionVariantNames) = .empty;
    errdefer freeUnionVariantNames(allocator, entries.toOwnedSlice(allocator) catch &.{});
    for (program.projections) |tag_projection| {
        if (tag_projection.kind != .tag) continue;
        const declaration = tag_projection.owner.*;
        var names: std.ArrayList([]u8) = .empty;
        errdefer {
            for (names.items) |name| allocator.free(name);
            names.deinit(allocator);
        }
        for (declaration.fields) |field| {
            const name = try naming.variantTypeNameAlloc(allocator, declaration.name, field.name, identifiers);
            errdefer allocator.free(name);
            try names.append(allocator, name);
            const owned = try allocator.dupe(u8, name);
            errdefer allocator.free(owned);
            identifiers = try appendIdentifier(allocator, identifiers, owned);
        }
        try entries.append(allocator, .{ .owner = declaration, .names = try names.toOwnedSlice(allocator) });
    }
    return entries.toOwnedSlice(allocator);
}

fn freeUnionVariantNames(allocator: std.mem.Allocator, entries: []UnionVariantNames) void {
    for (entries) |entry| {
        for (entry.names) |name| allocator.free(name);
        allocator.free(entry.names);
    }
    allocator.free(entries);
}

/// The sealed variant hierarchy for one tagged union: the marker interface,
/// one concrete type per Zig variant, and one builder both the owned and the
/// borrowed handle delegate to. This is added next to `Tag`/`As*`/`Snapshot`,
/// never in place of them.
fn renderPublicUnionVariants(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    entry: UnionVariantNames,
) !void {
    {
        const declaration = entry.owner;
        const variant_names = entry;
        const tag_type = declaration.tag_type.?.@"enum".ref;
        const recv = try receiverVariableAlloc(allocator, declaration.name);
        defer allocator.free(recv);

        try writer.print(
            "// {0s}Variant is the sealed interface every {0s} variant implements. A type\n" ++
                "// switch over the concrete variant types reads the active payload without\n" ++
                "// probing each projection in turn.\ntype {0s}Variant interface{{ is{0s}Variant() }}\n\n",
            .{declaration.name},
        );
        for (declaration.fields, variant_names.names) |field, variant_name| {
            const payload = field.type.?;
            if (payload == .void) {
                try writer.print(
                    "// {0s} is the {1s} variant of {2s}. It carries no payload.\ntype {0s} struct{{}}\n\n",
                    .{ variant_name, field.name, declaration.name },
                );
            } else {
                try writer.print(
                    "// {0s} is the {1s} variant of {2s}.\ntype {0s} struct {{\n\t// Value is the payload the {1s} variant carries.\n\tValue ",
                    .{ variant_name, field.name, declaration.name },
                );
                try writePayloadType(writer, payload);
                try writer.writeAll("\n}\n\n");
            }
            try writer.print("func ({0s}) is{1s}Variant() {{}}\n\n", .{ variant_name, declaration.name });
        }

        // One builder per union. A union whose payloads all fit the value
        // snapshot reads tag and payload together in a single native call;
        // any other union reads the tag and then calls only the projection
        // the active variant needs, so reading never costs one call per
        // variant either way.
        const snapshot = snapshotForOwner(program, declaration.name);
        if (snapshot) |record| {
            try writer.print(
                "// The snapshot reader takes the receiver's read lock for its single\n" ++
                    "// native call, so tag and payload are always read together.\n" ++
                    "func zigo{0s}Variant(receiver zigoHandle) ({0s}Variant, error) {{\n" ++
                    "\tdata, err := zigo{0s}Snapshot(receiver)\n\tif err != nil {{\n\t\treturn nil, err\n\t}}\n\tswitch data.tag {{\n",
                .{declaration.name},
            );
            for (declaration.fields, variant_names.names) |field, variant_name| {
                const tag_constant = try naming.pascalAlloc(allocator, field.name);
                defer allocator.free(tag_constant);
                try writer.print("\tcase {s}{s}:\n", .{ tag_type, tag_constant });
                if (field.type.? == .void) {
                    try writer.print("\t\treturn {s}{{}}, nil\n", .{variant_name});
                    continue;
                }
                const member = try naming.camelAlloc(allocator, snapshotMember(record, field.name).?.name);
                defer allocator.free(member);
                try writer.print("\t\treturn {s}{{Value: data.{s}}}, nil\n", .{ variant_name, member });
            }
        } else {
            try writer.print(
                "// The builder holds no lock of its own: it delegates to the tag and\n" ++
                    "// payload readers, each of which takes the receiver's read lock for its\n" ++
                    "// own native call. Locks never nest, so a concurrent Close can never\n" ++
                    "// deadlock here; it only makes the payload read report a closed handle.\n" ++
                    "func zigo{0s}Variant(receiver zigoHandle) ({0s}Variant, error) {{\n" ++
                    "\ttag, err := zigo{0s}Tag(receiver)\n\tif err != nil {{\n\t\treturn nil, err\n\t}}\n\tswitch tag {{\n",
                .{declaration.name},
            );
            for (declaration.fields, variant_names.names) |field, variant_name| {
                const tag_constant = try naming.pascalAlloc(allocator, field.name);
                defer allocator.free(tag_constant);
                try writer.print("\tcase {s}{s}:\n", .{ tag_type, tag_constant });
                if (field.type.? == .void) {
                    try writer.print("\t\treturn {s}{{}}, nil\n", .{variant_name});
                    continue;
                }
                try writer.print(
                    "\t\tpayload, matched, err := zigo{0s}As{1s}(receiver)\n\t\tif err != nil {{\n\t\t\treturn nil, err\n\t\t}}\n" ++
                        "\t\tif !matched {{\n\t\t\treturn nil, zigoProjectionError(\"{0s}.Variant\", zigoProjectionMismatch)\n\t\t}}\n" ++
                        "\t\treturn {2s}{{Value: payload}}, nil\n",
                    .{ declaration.name, tag_constant, variant_name },
                );
            }
        }
        try writer.print(
            "\tdefault:\n\t\treturn nil, zigoProjectionError(\"{0s}.Variant\", zigoProjectionMismatch)\n\t}}\n}}\n\n",
            .{declaration.name},
        );

        inline for (.{ false, true }) |borrowed| {
            const suffix = if (borrowed) "Ref" else "";
            try writer.print(
                "// Variant returns the active variant as a concrete {1s}Variant, or a typed\n" ++
                    "// lifecycle/native error.\nfunc ({0s} *{1s}{2s}) Variant() ({1s}Variant, error) {{ return zigo{1s}Variant({0s}) }}\n\n",
                .{ recv, declaration.name, suffix },
            );
            try writer.print(
                "// MustVariant returns the active variant as a concrete {1s}Variant and panics\n" ++
                    "// with a typed error on failure.\nfunc ({0s} *{1s}{2s}) MustVariant() {1s}Variant {{ return zigoMust(zigo{1s}Variant({0s})) }}\n\n",
                .{ recv, declaration.name, suffix },
            );
        }
    }
}

/// The value snapshot lowered for one tagged union, when the union has one.
/// Its single native call carries the tag and every payload, so the variant
/// builder can skip the projections entirely.
fn snapshotForOwner(program: abi.Program, name: []const u8) ?abi.AbiSnapshot {
    for (program.snapshots) |snapshot| {
        if (std.mem.eql(u8, snapshot.owner.name, name)) return snapshot;
    }
    return null;
}

fn appendIdentifier(allocator: std.mem.Allocator, names: [][]u8, name: []u8) ![][]u8 {
    var list: std.ArrayList([]u8) = .fromOwnedSlice(names);
    errdefer list.deinit(allocator);
    try list.append(allocator, name);
    return list.toOwnedSlice(allocator);
}

fn renderPublicErrors(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    const package = try publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    try writer.print("// Code generated by zigo. DO NOT EDIT.\npackage {s}\n", .{package});
    const has_handles = programHasOpaqueTypes(program);
    const has_codes = program.error_codes.len != 0;
    const has_status = programHasTaggedUnionTypes(program);
    // The raw package declares the loader sentinel. A colocated raw package is
    // the public package, so it needs no alias.
    const has_library = options.backend == .purego and !options.raw_colocated;
    // A Zig panic reaches Go from two boundaries: a projection status and an
    // error-returning call. Both report it as the same error, so the file is
    // needed whenever either exists.
    if (!has_handles and !has_codes and !has_library) return;
    // errorForCode names an unrecognized code with its number.
    const raw_import = (has_codes or has_library) and !options.raw_colocated;
    const import_count = 1 + @as(usize, @intFromBool(has_codes)) + @as(usize, @intFromBool(raw_import));
    if (import_count == 1) {
        try writer.writeAll("\nimport \"errors\"\n");
    } else {
        try writer.writeAll("\nimport (\n\t\"errors\"\n");
        if (has_codes) try writer.writeAll("\t\"strconv\"\n");
        if (raw_import) {
            try writer.writeByte('\n');
            try writeRawImport(writer, options, "\t");
        }
        try writer.writeAll(")\n");
    }
    try writer.writeByte('\n');
    try renderGoSentinels(writer, .{
        .handles = has_handles,
        .panics = has_handles or has_codes,
        .status = has_status,
        .library = has_library,
    }, options);
    try renderGoErrors(allocator, writer, program, options);
}

const SentinelSet = struct { handles: bool, panics: bool, status: bool, library: bool };

/// One discrimination rule: every generated error is classified with
/// `errors.Is` against an exported sentinel, and `errors.As` is only for
/// reading details. Each error type therefore unwraps to exactly one sentinel.
fn renderGoSentinels(writer: *std.Io.Writer, set: SentinelSet, options: Options) !void {
    if (set.handles) try writer.writeAll(
        "// ErrInvalidHandle identifies a nil, closed, or invalid borrowed handle.\n" ++
            "var ErrInvalidHandle = errors.New(\"zigo: nil or closed handle\")\n",
    );
    if (set.panics) try writer.writeAll(
        "// ErrNativePanic identifies a Zig panic caught at the native boundary.\n" ++
            "var ErrNativePanic = errors.New(\"zigo: native panic\")\n",
    );
    if (set.status) try writer.writeAll(
        "// ErrNativeStatus identifies a native status this binding does not recognize.\n" ++
            "var ErrNativeStatus = errors.New(\"zigo: unrecognized native status\")\n",
    );
    if (set.library) {
        try writer.writeAll("// ErrLibraryLoad identifies a shared-library load or symbol resolution failure.\nvar ErrLibraryLoad = ");
        try writeRawReferencePrefix(writer, options);
        try writer.writeAll("ErrLibraryLoad\n");
    }
    try writer.writeByte('\n');
    if (set.handles) try writer.writeAll(
        "// HandleError reports which generated operation received an invalid handle.\n" ++
            "type HandleError struct {\n" ++
            "\t// Operation names the generated operation and offending receiver or parameter.\n" ++
            "\tOperation string\n" ++
            "}\n\n" ++
            "// Error implements error.\nfunc (err *HandleError) Error() string {\n" ++
            "\treturn \"zigo: \" + err.Operation + \": nil or closed handle\"\n" ++
            "}\n\n" ++
            "// Unwrap returns ErrInvalidHandle for errors.Is classification.\nfunc (err *HandleError) Unwrap() error { return ErrInvalidHandle }\n\n",
    );
    if (set.panics) try writer.writeAll(
        "// NativePanicError reports a Zig panic caught at the native boundary.\n" ++
            "type NativePanicError struct {\n" ++
            "\t// Operation names the generated call or projection.\n\tOperation string\n" ++
            "\t// Message is the native panic message when available.\n\tMessage string\n" ++
            "}\n\n" ++
            "// Error implements error.\nfunc (err *NativePanicError) Error() string {\n" ++
            "\tif err.Message == \"\" {\n" ++
            "\t\treturn \"zigo: \" + err.Operation + \": native panic\"\n" ++
            "\t}\n" ++
            "\treturn \"zigo: \" + err.Operation + \": native panic: \" + err.Message\n" ++
            "}\n\n" ++
            "// Unwrap returns ErrNativePanic for errors.Is classification.\nfunc (err *NativePanicError) Unwrap() error { return ErrNativePanic }\n\n",
    );
    if (set.status) try writer.writeAll(
        "// StatusError reports a native status code this binding does not recognize.\n" ++
            "type StatusError struct {\n" ++
            "\t// Operation names the generated call or projection.\n\tOperation string\n" ++
            "\t// Status is the unexpected native status code.\n\tStatus uint8\n" ++
            "}\n\n" ++
            "// Error implements error.\nfunc (err *StatusError) Error() string {\n" ++
            "\treturn \"zigo: \" + err.Operation + \": unrecognized native status\"\n" ++
            "}\n\n" ++
            "// Unwrap returns ErrNativeStatus for errors.Is classification.\nfunc (err *StatusError) Unwrap() error { return ErrNativeStatus }\n\n",
    );
}

fn renderPublicHelpers(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    const has_callbacks = programHasCallbacks(program);
    const needs_bool = programNeedsBoolHelper(program);
    if (!has_callbacks and !needs_bool) return;
    if (needs_bool) try writer.writeAll(
        "func boolToUint8(value bool) uint8 {\n" ++
            "\tif value {\n" ++
            "\t\treturn 1\n" ++
            "\t}\n" ++
            "\treturn 0\n" ++
            "}\n\n",
    );
    if (has_callbacks) {
        if (options.backend == .purego) {
            try writer.writeAll("type zigoCallbackHandle = uintptr\n\n");
            for (program.functions) |function| {
                for (function.origin.params, 0..) |parameter, parameter_index| {
                    if (parameter.type != .callback) continue;
                    const callback_name = try callbackTypeNameAlloc(allocator, program, function, parameter_index);
                    defer allocator.free(callback_name);
                    try writer.print("func new{s}Handle(value {s}) zigoCallbackHandle {{\n\treturn ", .{ callback_name, callback_name });
                    try writeRawReferencePrefix(writer, options);
                    try writer.writeAll("NewCallbackHandle((");
                    try writePublicCallbackType(writer, parameter.type.callback);
                    try writer.writeAll(")(value))\n}\n\n");
                }
            }
            try writer.writeAll("func deleteCallbackHandle(handle zigoCallbackHandle) { ");
            try writeRawReferencePrefix(writer, options);
            try writer.writeAll("DeleteCallbackHandle(handle) }\n\nfunc activeCallbackHandleCount() int64 { return ");
            try writeRawReferencePrefix(writer, options);
            try writer.writeAll("ActiveCallbackHandleCount() }\n");
            try writer.writeAll("func callbackDispatcherCount() int { return ");
            try writeRawReferencePrefix(writer, options);
            try writer.writeAll("CallbackDispatcherCount() }\n");
            return;
        }
        try writer.writeAll("var activeCallbackHandles atomic.Int64\n\n");
        try writer.writeAll("type zigoCallbackHandle = cgo.Handle\n\n");
        for (program.functions) |function| {
            for (function.origin.params, 0..) |parameter, parameter_index| {
                if (parameter.type != .callback) continue;
                const callback_name = try callbackTypeNameAlloc(allocator, program, function, parameter_index);
                defer allocator.free(callback_name);
                try writer.print("func new{s}Handle(value {s}) zigoCallbackHandle {{\n\tstored := (", .{ callback_name, callback_name });
                try writePublicCallbackType(writer, parameter.type.callback);
                try writer.writeAll(")(value)\n\thandle := cgo.NewHandle(stored)\n\tactiveCallbackHandles.Add(1)\n\treturn handle\n}\n\n");
            }
        }
        try writer.writeAll(
            "func deleteCallbackHandle(handle zigoCallbackHandle) {\n" ++
                "\thandle.Delete()\n" ++
                "\tactiveCallbackHandles.Add(-1)\n" ++
                "}\n\n" ++
                "func activeCallbackHandleCount() int64 { return activeCallbackHandles.Load() }\n",
        );
    }
}

/// One lifecycle for every handle. Fields are `ptr` and `mu` on any
/// handle, `cleanup` on the ones this binding constructs, and
/// `callbackHandles` only on the ones that retain callbacks. `mu` serializes
/// Close against in-flight calls; `cleanup` is the safety net for a handle
/// the caller drops without closing.
fn renderGoHandles(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    for (program.types) |declaration| {
        if (!isHandleType(declaration)) continue;
        const owns_callbacks = typeOwnsCallbacks(program, declaration.name);
        const auto_cleanup = isAutoCleanupType(program, declaration.name);
        if (constructorForType(program, declaration.name) != null) {
            try writer.print("// {s} is a caller-owned native handle. Call Close when it is no longer needed.\n", .{declaration.name});
        } else {
            try writer.print("// {s} represents a native Zig handle.\n", .{declaration.name});
        }
        try writer.print("type {s} struct {{\n", .{declaration.name});
        // gofmt aligns a struct's field types on the longest field name, and
        // the goldens are compared unformatted, so the padding is computed
        // from the field set rather than hard-coded per shape.
        const width = fieldNameWidth(&.{ "ptr", "mu", if (auto_cleanup) "cleanup" else "", if (owns_callbacks) "callbackHandles" else "" });
        try writeStructField(writer, "ptr", width, "unsafe.Pointer");
        try writeStructField(writer, "mu", width, "sync.RWMutex");
        if (owns_callbacks) try writeStructField(writer, "callbackHandles", width, "[]zigoCallbackHandle");
        if (auto_cleanup) try writeStructField(writer, "cleanup", width, "runtime.Cleanup");
        try writer.print(
            "}}\n\n" ++
                "// {s}Ref is a borrowed {s} reference that remains valid only while its parent is open.\n" ++
                "type {s}Ref struct {{\n\tptr    unsafe.Pointer\n\tparent zigoHandle\n}}\n\n",
            .{ declaration.name, declaration.name, declaration.name },
        );
        // One receiver name per type, matching the methods emitted elsewhere.
        const recv = try receiverVariableAlloc(allocator, declaration.name);
        defer allocator.free(recv);
        try writer.print(
            "func ({0s} *{1s}) zigoPointer() unsafe.Pointer {{\n\tif {0s} == nil {{\n\t\treturn nil\n\t}}\n\treturn {0s}.ptr\n}}\n\n" ++
                "func ({0s} *{1s}Ref) zigoPointer() unsafe.Pointer {{\n\tif {0s} == nil || {0s}.ptr == nil {{\n\t\treturn nil\n\t}}\n\tif parent := {0s}.parent; parent != nil && parent.zigoPointer() == nil {{\n\t\treturn nil\n\t}}\n\treturn {0s}.ptr\n}}\n\n" ++
                "func ({0s} *{1s}) zigoLocker() *sync.RWMutex {{\n\tif {0s} == nil {{\n\t\treturn nil\n\t}}\n\treturn &{0s}.mu\n}}\n\n" ++
                "func ({0s} *{1s}Ref) zigoLocker() *sync.RWMutex {{\n\tif {0s} == nil || {0s}.parent == nil {{\n\t\treturn nil\n\t}}\n\treturn {0s}.parent.zigoLocker()\n}}\n\n",
            .{ recv, declaration.name },
        );
        if (constructorForType(program, declaration.name)) |constructor| {
            const raw_deinit = try rawNameForSemanticAlloc(allocator, program, constructor.deinit, constructor.type) orelse continue;
            defer allocator.free(raw_deinit);
            const private_name = try naming.camelAlloc(allocator, declaration.name);
            defer allocator.free(private_name);
            // The cleanup state copies what has to be released. It must not
            // reach the handle itself, or the handle stays reachable and the
            // cleanup never runs.
            try writer.print("type {s}CleanupState struct {{\n", .{private_name});
            const state_width = fieldNameWidth(&.{ "ptr", if (owns_callbacks) "callbackHandles" else "" });
            try writeStructField(writer, "ptr", state_width, "unsafe.Pointer");
            if (owns_callbacks) try writeStructField(writer, "callbackHandles", state_width, "[]zigoCallbackHandle");
            try writer.writeAll("}\n\n");
            try writer.print("func new{s}(ptr unsafe.Pointer", .{declaration.name});
            if (owns_callbacks) try writer.writeAll(", callbackHandles []zigoCallbackHandle");
            try writer.print(") *{s} {{\n\tvalue := &{s}{{ptr: ptr", .{ declaration.name, declaration.name });
            if (owns_callbacks) try writer.writeAll(", callbackHandles: callbackHandles");
            try writer.print("}}\n\tstate := {s}CleanupState{{ptr: ptr", .{private_name});
            if (owns_callbacks) try writer.writeAll(", callbackHandles: callbackHandles");
            try writer.print("}}\n\tvalue.cleanup = runtime.AddCleanup(value, cleanup{s}, state)\n\treturn value\n}}\n\n", .{declaration.name});
            try writer.print("func cleanup{s}(state {s}CleanupState) {{\n\tif state.ptr != nil {{\n\t\t", .{ declaration.name, private_name });
            try writeRawReferencePrefix(writer, options);
            try writer.print("{s}(state.ptr)\n\t}}\n", .{raw_deinit});
            if (owns_callbacks) try writer.writeAll("\tfor _, handle := range state.callbackHandles {\n\t\tdeleteCallbackHandle(handle)\n\t}\n");
            try writer.writeAll("}\n\n");
            // The write lock plus the nil-pointer check carry idempotency:
            // a second Close waits for the first, then finds ptr already nil.
            try writer.print("// Close releases the native {1s} resources. It is safe to call more than once.\n// The error result is always nil; it exists so {1s} satisfies io.Closer.\nfunc ({0s} *{1s}) Close() error {{\n\tif {0s} == nil {{\n\t\treturn nil\n\t}}\n", .{ recv, declaration.name });
            try writer.print("\t{0s}.mu.Lock()\n\tdefer {0s}.mu.Unlock()\n\tif {0s}.ptr == nil {{\n\t\treturn nil\n\t}}\n", .{recv});
            try writer.print("\t{0s}.cleanup.Stop()\n\tcleanup{1s}({2s}CleanupState{{ptr: {0s}.ptr", .{ recv, declaration.name, private_name });
            if (owns_callbacks) try writer.print(", callbackHandles: {0s}.callbackHandles", .{recv});
            try writer.print("}})\n\t{0s}.ptr = nil\n", .{recv});
            if (owns_callbacks) try writer.print("\t{0s}.callbackHandles = nil\n", .{recv});
            try writer.print("\truntime.KeepAlive({0s})\n\treturn nil\n}}\n\n", .{recv});
        }
    }
}

/// The column gofmt aligns struct field types on: the longest name plus one
/// space. Empty names stand for fields this handle does not carry.
fn fieldNameWidth(names: []const []const u8) usize {
    var longest: usize = 0;
    for (names) |name| longest = @max(longest, name.len);
    return longest + 1;
}

fn writeStructField(writer: *std.Io.Writer, name: []const u8, width: usize, type_name: []const u8) !void {
    try writer.print("\t{s}", .{name});
    try writer.splatByteAll(' ', width - name.len);
    try writer.print("{s}\n", .{type_name});
}

/// The handle interface and its two pointer checks. Every projection and
/// operation reaches a handle through this, so it lives with the runtime
/// rather than with the handle types themselves.
fn renderGoHandleRuntime(writer: *std.Io.Writer, program: abi.Program) !void {
    if (programHasOpaqueTypes(program)) try writer.writeAll(
        "type zigoHandle interface {\n" ++
            "\tzigoPointer() unsafe.Pointer\n" ++
            "\tzigoLocker() *sync.RWMutex\n" ++
            "}\n\n" ++
            "func zigoCheckedPointer(operation string, value zigoHandle) (unsafe.Pointer, error) {\n" ++
            "\tptr := value.zigoPointer()\n" ++
            "\tif ptr == nil {\n" ++
            "\t\treturn nil, &HandleError{Operation: operation}\n" ++
            "\t}\n" ++
            "\treturn ptr, nil\n" ++
            "}\n\n" ++
            "func zigoOptionalPointer(operation string, absent bool, value zigoHandle) (unsafe.Pointer, error) {\n" ++
            "\tif absent {\n" ++
            "\t\treturn nil, nil\n" ++
            "\t}\n" ++
            "\treturn zigoCheckedPointer(operation, value)\n" ++
            "}\n\n" ++
            "// zigoReadLock holds the owner's read lock for the rest of the call, so a\n" ++
            "// concurrent Close cannot release the handle between the pointer check and\n" ++
            "// the native call. Use it as `defer zigoReadLock(receiver)()`. A borrowed\n" ++
            "// ref delegates to its parent's lock; a nil receiver or a ref without a\n" ++
            "// parent locks nothing.\n" ++
            "func zigoReadLock(value zigoHandle) func() {\n" ++
            "\tmu := value.zigoLocker()\n" ++
            "\tif mu == nil {\n" ++
            "\t\treturn func() {}\n" ++
            "\t}\n" ++
            "\tmu.RLock()\n" ++
            "\treturn mu.RUnlock\n" ++
            "}\n\n",
    );
}

/// The projection status vocabulary shared by every tagged-union accessor and
/// the two wrappers the `Must*` methods delegate to.
fn renderGoProjectionRuntime(writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    if (program.projections.len == 0) return;
    try writer.writeAll(
        "const (\n" ++
            "\tzigoProjectionMismatch uint8 = iota\n" ++
            "\tzigoProjectionSuccess\n" ++
            "\tzigoProjectionInvalidHandle\n" ++
            "\tzigoProjectionPanic\n" ++
            ")\n\n" ++
            "func zigoProjectionError(operation string, status uint8) error {\n" ++
            "\tswitch status {\n" ++
            "\tcase zigoProjectionInvalidHandle:\n" ++
            "\t\treturn &HandleError{Operation: operation}\n" ++
            "\tcase zigoProjectionPanic:\n" ++
            "\t\treturn &NativePanicError{Operation: operation, Message: ",
    );
    try writeRawReferencePrefix(writer, options);
    try writer.writeAll(
        "LastErrorMessage()}\n" ++
            "\tdefault:\n" ++
            "\t\treturn &StatusError{Operation: operation, Status: status}\n" ++
            "\t}\n" ++
            "}\n\n" ++
            // The Must* accessors differ from their checked counterparts only
            // in what they do with the error, so they share one wrapper each.
            "func zigoMust[T any](value T, err error) T {\n" ++
            "\tif err != nil {\n" ++
            "\t\tpanic(err)\n" ++
            "\t}\n" ++
            "\treturn value\n" ++
            "}\n\n" ++
            "func zigoMustMatch[T any](value T, matched bool, err error) (T, bool) {\n" ++
            "\tif err != nil {\n" ++
            "\t\tpanic(err)\n" ++
            "\t}\n" ++
            "\treturn value, matched\n" ++
            "}\n\n",
    );
}

fn renderPublicTaggedUnionAccessors(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    options: Options,
    owner: semantic.TypeDecl,
) !void {
    for (program.projections) |tag_projection| {
        if (tag_projection.kind != .tag) continue;
        const declaration = tag_projection.owner.*;
        if (!std.mem.eql(u8, declaration.name, owner.name)) continue;
        const recv = try receiverVariableAlloc(allocator, declaration.name);
        defer allocator.free(recv);
        const tag_type = declaration.tag_type.?.@"enum".ref;

        // One implementation per projection, reached through the handle
        // interface so the owned and borrowed methods can both delegate to it.
        try writer.print(
            "func zigo{0s}Tag(receiver zigoHandle) ({1s}, error) {{\n\tdefer zigoReadLock(receiver)()\n\tdefer runtime.KeepAlive(receiver)\n" ++
                "\tptr, err := zigoCheckedPointer(\"{0s}.Tag receiver\", receiver)\n\tif err != nil {{\n\t\treturn 0, err\n\t}}\n\tresult, status := ",
            .{ declaration.name, tag_type },
        );
        try writeRawReferencePrefix(writer, options);
        try writer.print(
            "{0s}ProjectTag(ptr)\n\tif status != zigoProjectionSuccess {{\n\t\treturn 0, zigoProjectionError(\"{0s}.Tag\", status)\n\t}}\n\treturn {1s}(result), nil\n}}\n\n",
            .{ declaration.name, tag_type },
        );
        inline for (.{ false, true }) |borrowed| {
            const suffix = if (borrowed) "Ref" else "";
            try writer.print(
                "// Tag returns the active tagged-union tag or a typed lifecycle/native error.\n" ++
                    "func ({0s} *{1s}{2s}) Tag() ({3s}, error) {{ return zigo{1s}Tag({0s}) }}\n\n",
                .{ recv, declaration.name, suffix, tag_type },
            );
            try writer.print(
                "// MustTag returns the active tagged-union tag and panics with a typed error on failure.\n" ++
                    "func ({0s} *{1s}{2s}) MustTag() {3s} {{ return zigoMust(zigo{1s}Tag({0s})) }}\n\n",
                .{ recv, declaration.name, suffix, tag_type },
            );
        }
        for (program.projections) |payload_projection| {
            if (payload_projection.kind != .payload or !std.mem.eql(u8, payload_projection.owner.name, declaration.name)) continue;
            const field = payload_projection.field.?.*;
            const payload = field.type.?;
            const field_name = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(field_name);

            try writer.print("func zigo{s}As{s}(receiver zigoHandle) (", .{ declaration.name, field_name });
            try writePayloadType(writer, payload);
            try writer.print(", bool, error) {{\n\tdefer zigoReadLock(receiver)()\n\tdefer runtime.KeepAlive(receiver)\n\tptr, err := zigoCheckedPointer(\"{s}.As{s} receiver\", receiver)\n\tif err != nil {{\n\t\treturn ", .{ declaration.name, field_name });
            try writer.writeAll(goZero(payload));
            try writer.writeAll(", false, err\n\t}\n\tresult, status := ");
            try writeRawReferencePrefix(writer, options);
            try writer.print("{s}Project{s}(ptr)\n\tif status == zigoProjectionMismatch {{\n\t\treturn ", .{ declaration.name, field_name });
            try writer.writeAll(goZero(payload));
            try writer.writeAll(", false, nil\n\t}\n\tif status != zigoProjectionSuccess {\n\t\treturn ");
            try writer.writeAll(goZero(payload));
            try writer.print(", false, zigoProjectionError(\"{s}.As{s}\", status)\n\t}}\n\treturn ", .{ declaration.name, field_name });
            if (payload == .opaque_ptr) {
                try writer.print("&{s}Ref{{ptr: result, parent: receiver}}", .{payload.opaque_ptr.ref});
            } else if (payload == .slice and payload.slice.element.* == .@"enum") {
                try writer.writeAll("func() []");
                try writePublicGoType(writer, payload.slice.element.*);
                try writer.writeAll(" {\n\t\tconverted := make([]");
                try writePublicGoType(writer, payload.slice.element.*);
                try writer.writeAll(", len(result))\n\t\tfor i, item := range result {\n\t\t\tconverted[i] = ");
                try writePublicGoType(writer, payload.slice.element.*);
                try writer.writeAll("(item)\n\t\t}\n\t\treturn converted\n\t}()");
            } else if (payload == .slice) {
                try writer.writeAll("append(");
                try writePublicGoType(writer, payload);
                try writer.writeAll("(nil), result...)");
            } else {
                try writePublicResultConversion(writer, payload, "result");
            }
            try writer.writeAll(", true, nil\n}\n\n");

            inline for (.{ false, true }) |borrowed| {
                const suffix = if (borrowed) "Ref" else "";
                try writer.print("// As{0s} returns the {1s} payload, whether it is active, and any lifecycle/native error.\nfunc ({2s} *{3s}{4s}) As{0s}() (", .{ field_name, field.name, recv, declaration.name, suffix });
                try writePayloadType(writer, payload);
                try writer.print(", bool, error) {{ return zigo{0s}As{1s}({2s}) }}\n\n", .{ declaration.name, field_name, recv });
                try writer.print("// MustAs{0s} returns the {1s} payload when active and panics with a typed error on failure.\nfunc ({2s} *{3s}{4s}) MustAs{0s}() (", .{ field_name, field.name, recv, declaration.name, suffix });
                try writePayloadType(writer, payload);
                try writer.print(", bool) {{ return zigoMustMatch(zigo{0s}As{1s}({2s})) }}\n\n", .{ declaration.name, field_name, recv });
            }
        }
    }
}

/// A handle payload surfaces as a borrowed reference; everything else keeps
/// its ordinary public Go type.
fn writePayloadType(writer: *std.Io.Writer, payload: semantic.TypeNode) !void {
    if (payload == .opaque_ptr) return writer.print("*{s}Ref", .{payload.opaque_ptr.ref});
    try writePublicGoType(writer, payload);
}

/// Resolves every handle a call needs into a local pointer, returning the
/// caller's error on the first nil or closed one.
fn renderHandleChecks(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    function: semantic.SemanticFn,
    go_names: []const []const u8,
    operation: []const u8,
    constructor: ?semantic.Constructor,
) !void {
    if (function.receiver) |receiver| {
        const receiver_name = try receiverVariableAlloc(allocator, receiver);
        defer allocator.free(receiver_name);
        try writer.print("\tptr, err := zigoCheckedPointer(\"{s} receiver\", {s})\n", .{ operation, receiver_name });
        try writer.writeAll("\tif err != nil {\n\t\t");
        try writeHandleErrorReturn(writer, function, constructor);
        try writer.writeAll("\t}\n");
    }
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .opaque_ptr) continue;
        const name = go_names[parameter_index];
        if (parameter.type.opaque_ptr.nullable) {
            try writer.print(
                "\t{0s}Ptr, err := zigoOptionalPointer(\"{1s} parameter {0s}\", {0s} == nil, {0s})\n",
                .{ name, operation },
            );
        } else {
            try writer.print("\t{0s}Ptr, err := zigoCheckedPointer(\"{1s} parameter {0s}\", {0s})\n", .{ name, operation });
        }
        try writer.writeAll("\tif err != nil {\n\t\t");
        try writeHandleErrorReturn(writer, function, constructor);
        try writer.writeAll("\t}\n");
    }
}

/// The `return` statement a failed handle check uses. It mirrors whatever the
/// function already returns, with `err` in the error position.
fn writeHandleErrorReturn(writer: *std.Io.Writer, function: semantic.SemanticFn, constructor: ?semantic.Constructor) !void {
    if (constructor != null) return writer.writeAll("return nil, err\n");
    const payload = if (function.@"return" == .error_union) function.@"return".error_union.payload.* else function.@"return";
    if (payload == .void) return writer.writeAll("return err\n");
    try writer.writeAll("return ");
    try writePublicZeroValue(writer, function, payload);
    try writer.writeAll(", err\n");
}

/// The zero value of a public result type. A UTF-8 slice surfaces as a string,
/// so its zero is the empty string rather than `nil`.
fn writePublicZeroValue(writer: *std.Io.Writer, function: semantic.SemanticFn, payload: semantic.TypeNode) !void {
    if (isStringSlice(payload, function.return_semantic)) return writer.writeAll("\"\"");
    try writeGoZeroValue(writer, payload);
}

/// The public return type when a nil or closed handle reaches the caller as an
/// error: a value return grows into a tuple, a void return becomes `error`.
fn writeCheckedFunctionReturnType(writer: *std.Io.Writer, function: semantic.SemanticFn) !void {
    if (function.@"return" == .void) return writer.writeAll(" error");
    try writer.writeAll(" (");
    if (isStringSlice(function.@"return", function.return_semantic)) {
        try writer.writeAll("string");
    } else if (function.@"return" == .opaque_ptr and function.ownership == .borrowed) {
        try writer.print("*{s}Ref", .{function.@"return".opaque_ptr.ref});
    } else {
        try writePublicGoType(writer, function.@"return");
    }
    try writer.writeAll(", error)");
}

fn writePublicFunctionReturnType(writer: *std.Io.Writer, function: semantic.SemanticFn) !void {
    if (isStringSlice(function.@"return", function.return_semantic)) {
        try writer.writeAll(" string");
        return;
    }
    if (function.@"return" == .opaque_ptr and function.ownership == .borrowed) {
        try writer.print(" *{s}Ref", .{function.@"return".opaque_ptr.ref});
        return;
    }
    if (function.@"return" == .error_union and function.@"return".error_union.payload.* == .opaque_ptr and function.ownership == .borrowed) {
        try writer.print(" (*{s}Ref, error)", .{function.@"return".error_union.payload.opaque_ptr.ref});
        return;
    }
    try writePublicReturnType(writer, function.@"return", function.return_semantic);
}

fn writeBorrowedResult(allocator: std.mem.Allocator, writer: *std.Io.Writer, function: semantic.SemanticFn, expression: []const u8) !void {
    const node = if (function.@"return" == .error_union) function.@"return".error_union.payload.* else function.@"return";
    const parent = if (function.receiver) |receiver| try receiverVariableAlloc(allocator, receiver) else null;
    defer if (parent) |value| allocator.free(value);
    try writer.print("&{s}Ref{{ptr: {s}, parent: {s}}}", .{ node.opaque_ptr.ref, expression, parent orelse "nil" });
}

fn renderGoEnums(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.types) |declaration| {
        if (declaration.kind != .@"enum") continue;
        try writer.print("// {s} represents the corresponding Zig enum.\ntype {s} ", .{ declaration.name, declaration.name });
        try writePublicGoType(writer, declaration.tag_type.?);
        try writer.writeAll("\n\n");
        // One const block per enum. Every constant keeps its own leading
        // comment so godoc still names it.
        try writer.writeAll("const (\n");
        for (declaration.fields) |field| {
            const field_name = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(field_name);
            try writer.print("\t// {s}{s} corresponds to the Zig tag {s}.\n\t{s}{s} {s} = {d}\n", .{ declaration.name, field_name, field.name, declaration.name, field_name, declaration.name, field.value.? });
        }
        try writer.print(")\n\n// String returns the Zig tag name.\nfunc (value {s}) String() string {{\n\tswitch value {{\n", .{declaration.name});
        for (declaration.fields) |field| {
            const field_name = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(field_name);
            try writer.print("\tcase {s}{s}:\n\t\treturn \"{s}\"\n", .{ declaration.name, field_name, field.name });
        }
        try writer.print("\tdefault:\n\t\treturn \"{s}(\" + ", .{declaration.name});
        try writeEnumNumberFormat(writer, declaration.tag_type.?);
        try writer.writeAll(" + \")\"\n\t}\n}\n\n");
    }
}

/// How an unknown enum value prints itself. `strconv.Itoa` covers every width
/// that fits an `int`; only the widths that can outrun it need the 64-bit
/// formatters.
fn writeEnumNumberFormat(writer: *std.Io.Writer, tag_type: semantic.TypeNode) !void {
    const integer = tag_type.int;
    const wide = integer.is_usize or integer.bits >= 64;
    if (!wide) return writer.writeAll("strconv.Itoa(int(value))");
    if (integer.signed) return writer.writeAll("strconv.FormatInt(int64(value), 10)");
    try writer.writeAll("strconv.FormatUint(uint64(value), 10)");
}

fn renderGoCallbackTypes(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .callback) continue;
            const callback_name = try callbackTypeNameAlloc(allocator, program, function, parameter_index);
            defer allocator.free(callback_name);
            try writer.print("// {s} is the Go callback signature accepted by the generated binding.\ntype {s} ", .{ callback_name, callback_name });
            try writePublicCallbackType(writer, parameter.type.callback);
            try writer.writeAll("\n\n");
        }
    }
}

fn renderGoErrors(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    if (program.error_codes.len == 0) return;
    try writer.writeAll(
        "// Error is a stable Zig error-set value returned by the generated binding.\n" ++
            "type Error struct {\n" ++
            "\t// Code is the stable integer stored in errors.lock.json.\n\tCode int32\n" ++
            "\t// Name is the Zig error name, optionally followed by native panic context.\n\tName string\n" ++
            "}\n\n" ++
            "// Error implements error.\nfunc (err *Error) Error() string { return err.Name }\n" ++
            "// Is compares generated errors by stable code.\nfunc (err *Error) Is(target error) bool {\n\tother, ok := target.(*Error)\n\treturn ok && err.Code == other.Code\n}\n\n",
    );
    for (program.error_codes) |entry| {
        const name = try naming.pascalAlloc(allocator, entry.name);
        defer allocator.free(name);
        try writer.print("// Err{s} represents Zig error.{s}.\nvar Err{s} = &Error{{Code: {d}, Name: \"{s}\"}}\n", .{ name, entry.name, name, entry.code, entry.name });
    }
    try writer.writeAll("\nfunc errorForCode(operation string, code int32) error {\n\tswitch code {\n\tcase -2:\n\t\treturn &NativePanicError{Operation: operation, Message: ");
    try writeRawReferencePrefix(writer, options);
    try writer.writeAll("LastErrorMessage()}\n");
    for (program.error_codes) |entry| {
        const name = try naming.pascalAlloc(allocator, entry.name);
        defer allocator.free(name);
        try writer.print("\tcase {d}:\n\t\treturn Err{s}\n", .{ entry.code, name });
    }
    try writer.writeAll("\tdefault:\n\t\treturn &Error{Code: code, Name: \"Unknown(\" + strconv.Itoa(int(code)) + \")\"}\n\t}\n}\n");
}

fn writeRawImport(writer: *std.Io.Writer, options: Options, indent: []const u8) !void {
    try writer.writeAll(indent);
    if (!std.mem.eql(u8, options.raw_package_name, "raw")) try writer.writeAll("raw ");
    try writer.print("\"{s}/{s}\"\n", .{ options.go_module, options.raw_package_path });
}

fn writeRawReferencePrefix(writer: *std.Io.Writer, options: Options) !void {
    try writer.writeAll(if (options.raw_colocated) "zigoRaw" else "raw.");
}

fn writeRawTypeReferencePrefix(writer: *std.Io.Writer, options: Options) !void {
    if (!options.raw_colocated) try writer.writeAll("raw.");
}

fn writeRawReturnType(writer: *std.Io.Writer, program: abi.Program, function: abi.AbiFn) !void {
    if (isCStringReturn(function.origin.*)) return writer.writeAll(" string");
    switch (function.origin.@"return") {
        .void => {},
        .error_union => |value| {
            if (value.payload.* == .void) {
                try writer.writeAll(" int32");
            } else {
                try writer.writeAll(" (");
                try writeRawGoType(writer, program, value.payload.*);
                try writer.writeAll(", int32)");
            }
        },
        else => {
            try writer.writeByte(' ');
            try writeRawGoType(writer, program, function.origin.@"return");
        },
    }
}

fn writeRawParameterType(writer: *std.Io.Writer, program: abi.Program, parameter: semantic.Parameter) !void {
    if (isStringSliceParameter(parameter)) return writer.writeAll("[]string");
    if (isCStringParameter(parameter)) return writer.writeAll("string");
    try writeRawGoType(writer, program, parameter.type);
}

fn writePublicReturnType(writer: *std.Io.Writer, node: semantic.TypeNode, hint: ?semantic.SemanticHint) !void {
    switch (node) {
        .void => {},
        .error_union => |value| {
            if (value.payload.* == .void) {
                try writer.writeAll(" error");
            } else {
                try writer.writeAll(" (");
                if (isStringSlice(value.payload.*, hint))
                    try writer.writeAll("string")
                else
                    try writePublicGoType(writer, value.payload.*);
                try writer.writeAll(", error)");
            }
        },
        else => {
            try writer.writeByte(' ');
            try writePublicGoType(writer, node);
        },
    }
}

fn writeRawConversionPrefix(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode) !void {
    try writeRawGoType(writer, program, node);
    try writer.writeByte('(');
}

fn writeRawResultConversion(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode, expression: []const u8, options: Options) !void {
    // A purego handle already arrives as an unsafe.Pointer; only the cgo
    // backend has a C pointer type to convert.
    if (options.backend == .purego and node == .opaque_ptr) return writer.writeAll(expression);
    try writeRawGoType(writer, program, node);
    try writer.print("({s})", .{expression});
}

fn writePublicResultConversion(writer: *std.Io.Writer, node: semantic.TypeNode, expression: []const u8) !void {
    switch (node) {
        .bool => try writer.print("{s} != 0", .{expression}),
        .value_struct => |value| try writer.print("zigo{s}FromRaw({s})", .{ value.ref, expression }),
        .slice => |value| if (value.element.* == .value_struct)
            try writer.print("zigo{s}SliceFromRaw({s})", .{ value.element.*.value_struct.ref, expression })
        else
            try writer.writeAll(expression),
        .@"enum" => |value| try writer.print("{s}({s})", .{ value.ref, expression }),
        else => try writer.writeAll(expression),
    }
}

fn writeRawGoType(writer: *std.Io.Writer, program: abi.Program, node: semantic.TypeNode) !void {
    switch (node) {
        .slice => |value| {
            try writer.writeAll("[]");
            try writeRawGoType(writer, program, value.element.*);
        },
        .@"enum" => try writer.writeAll(rawGoTypeName(program, node)),
        .opaque_ptr => try writer.writeAll("unsafe.Pointer"),
        .value_struct => |value| try writer.print("{s}{s}", .{ value.ref, raw_struct_suffix }),
        else => try writeGoScalar(writer, semanticScalar(program, node)),
    }
}

fn writePublicGoType(writer: *std.Io.Writer, node: semantic.TypeNode) !void {
    switch (node) {
        .slice => |value| {
            if (isByteType(value.element.*)) {
                try writer.writeAll("[]byte");
            } else {
                try writer.writeAll("[]");
                try writePublicGoType(writer, value.element.*);
            }
        },
        .@"enum" => |value| try writer.writeAll(value.ref),
        .bool => try writer.writeAll("bool"),
        .int => |integer| if (integer.is_usize)
            try writer.writeAll(if (integer.signed) "int" else "uint")
        else
            try writeIntegerName(writer, integer.signed, integer.bits, false),
        .float => |value| try writer.print("float{d}", .{value.bits}),
        .opaque_ptr => |value| try writer.print("*{s}", .{value.ref}),
        .value_struct => |value| try writer.writeAll(value.ref),
        else => unreachable,
    }
}

fn writePublicParameterType(writer: *std.Io.Writer, parameter: semantic.Parameter) !void {
    if (isStringSliceParameter(parameter)) return writer.writeAll("[]string");
    if (isStringSlice(parameter.type, parameter.semantic)) return writer.writeAll("string");
    try writePublicGoType(writer, parameter.type);
}

fn writePublicCallbackType(writer: *std.Io.Writer, callback: semantic.Callback) !void {
    const value_count = if (callback.has_userdata and callback.params.len != 0) callback.params.len - 1 else callback.params.len;
    try writer.writeAll("func(");
    for (callback.params[0..value_count], 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        try writePublicGoType(writer, parameter);
    }
    try writer.writeByte(')');
    if (callback.@"return".* != .void) {
        try writer.writeByte(' ');
        try writePublicGoType(writer, callback.@"return".*);
    }
}

fn renderCallbackHandleSetup(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, function: abi.AbiFn) !void {
    const go_names = try goParamNamesForAlloc(allocator, function.origin.params);
    defer naming.freeParamNames(allocator, go_names);
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .callback) continue;
        const callback_name = try callbackTypeNameAlloc(allocator, program, function, parameter_index);
        defer allocator.free(callback_name);
        try writer.print("\t{s}Handle := new{s}Handle({s})\n", .{ go_names[parameter_index], callback_name, go_names[parameter_index] });
        if (parameter.retention == .borrowed) {
            try writer.print("\tdefer deleteCallbackHandle({s}Handle)\n", .{go_names[parameter_index]});
        }
    }
}

fn renderKeepAliveDefers(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, function: abi.AbiFn) !void {
    const go_names = try goParamNamesForAlloc(allocator, function.origin.params);
    defer naming.freeParamNames(allocator, go_names);
    // Every handle carries `mu`, so the read lock is unconditional: it holds
    // Close off for the length of the native call, whether or not the program
    // uses callbacks anywhere.
    if (function.origin.receiver) |receiver| {
        const receiver_name = try receiverVariableAlloc(allocator, receiver);
        defer allocator.free(receiver_name);
        try writer.print("\tif {s} != nil {{ {s}.mu.RLock(); defer {s}.mu.RUnlock() }}\n", .{ receiver_name, receiver_name, receiver_name });
    }
    for (function.origin.params, 0..) |parameter, parameter_index| switch (parameter.type) {
        .opaque_ptr => try writer.print("\tif {s} != nil {{ {s}.mu.RLock(); defer {s}.mu.RUnlock() }}\n", .{ go_names[parameter_index], go_names[parameter_index], go_names[parameter_index] }),
        else => {},
    };
    if (function.origin.receiver) |receiver| {
        if (isAutoCleanupType(program, receiver)) {
            const receiver_name = try receiverVariableAlloc(allocator, receiver);
            defer allocator.free(receiver_name);
            try writer.print("\tdefer runtime.KeepAlive({s})\n", .{receiver_name});
        }
    }
    for (function.origin.params, 0..) |parameter, parameter_index| switch (parameter.type) {
        .opaque_ptr => |pointer| if (isAutoCleanupType(program, pointer.ref))
            try writer.print("\tdefer runtime.KeepAlive({s})\n", .{go_names[parameter_index]}),
        else => {},
    };
}

fn writeDeleteRetainedCallbacks(allocator: std.mem.Allocator, writer: *std.Io.Writer, function: semantic.SemanticFn) !void {
    const go_names = try goParamNamesForAlloc(allocator, function.params);
    defer naming.freeParamNames(allocator, go_names);
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type == .callback and parameter.retention == .retained)
            try writer.print("\t\tdeleteCallbackHandle({s}Handle)\n", .{go_names[parameter_index]});
    }
}

fn writeRetainedCallbackHandles(allocator: std.mem.Allocator, writer: *std.Io.Writer, function: semantic.SemanticFn) !void {
    const go_names = try goParamNamesForAlloc(allocator, function.params);
    defer naming.freeParamNames(allocator, go_names);
    var index: usize = 0;
    for (function.params, 0..) |parameter, parameter_index| {
        if (parameter.type != .callback or parameter.retention != .retained) continue;
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s}Handle", .{go_names[parameter_index]});
        index += 1;
    }
}

fn isUtf8Slice(node: semantic.TypeNode, hint: ?semantic.SemanticHint) bool {
    return hint == .utf8_string and node == .slice and isByteType(node.slice.element.*);
}

const StringSliceForm = enum { unsentinel, sentinel_slice, sentinel_many };
const string_slice_stack_capacity = 16;

fn stringSliceForm(node: semantic.TypeNode, hint: ?semantic.SemanticHint) ?StringSliceForm {
    if (node != .slice or !node.slice.@"const") return null;
    const element = node.slice.element.*;
    if (element != .slice or !element.slice.@"const" or !isByteType(element.slice.element.*)) return null;
    if (element.slice.sentinel) |sentinel| {
        if (sentinel != 0) return null;
        return if (element.slice.sentinel_many) .sentinel_many else .sentinel_slice;
    }
    return if (hint == .utf8_string) .unsentinel else null;
}

fn isStringSliceParameter(parameter: semantic.Parameter) bool {
    return parameter.direction == .in and stringSliceForm(parameter.type, parameter.semantic) != null;
}

fn writeStringSliceElementType(writer: *std.Io.Writer, form: StringSliceForm) !void {
    switch (form) {
        .unsentinel => try writer.writeAll("[]const u8"),
        .sentinel_slice => try writer.writeAll("[:0]const u8"),
        .sentinel_many => try writer.writeAll("[*:0]const u8"),
    }
}

fn writeShimStringSliceSetups(allocator: std.mem.Allocator, writer: *std.Io.Writer, function: abi.AbiFn) !void {
    for (function.origin.params, 0..) |parameter, parameter_index| {
        if (!isStringSliceParameter(parameter)) continue;
        const form = stringSliceForm(parameter.type, parameter.semantic) orelse continue;
        const base = try std.fmt.allocPrint(allocator, "zigoString{d}", .{parameter_index});
        defer allocator.free(base);
        try writer.print("    var {s}Stack: [{d}]", .{ base, string_slice_stack_capacity });
        try writeStringSliceElementType(writer, form);
        try writer.writeAll(" = undefined;\n    var ");
        try writer.print("{s}Strings: []", .{base});
        try writeStringSliceElementType(writer, form);
        try writer.print(" = undefined;\n    if ({s}_count <= {s}Stack.len) {{\n        {s}Strings = {s}Stack[0..{s}_count];\n    }} else {{\n        {s}Strings = std.heap.page_allocator.alloc(", .{
            parameter.name,
            base,
            base,
            base,
            parameter.name,
            base,
        });
        try writeStringSliceElementType(writer, form);
        try writer.print(", {s}_count) catch @panic(\"zigo: flattened string slice allocation failed\");\n    }}\n    defer {{\n        if ({s}_count > {s}Stack.len) std.heap.page_allocator.free({s}Strings);\n    }}\n    var {s}Offset: usize = 0;\n    for (0..{s}_count) |i| {{\n        const length = {s}_lens[i];\n        if ({s}Offset >= {s}_data_len or length > {s}_data_len - {s}Offset - 1) @panic(\"zigo: invalid flattened string slice\");\n        {s}Strings[i] = ", .{
            parameter.name,
            parameter.name,
            base,
            base,
            base,
            parameter.name,
            parameter.name,
            base,
            parameter.name,
            parameter.name,
            base,
            base,
        });
        switch (form) {
            .unsentinel, .sentinel_slice => {
                try writer.print("{s}_data[{s}Offset .. {s}Offset + length", .{ parameter.name, base, base });
                if (form == .sentinel_slice) try writer.writeAll(" :0");
                try writer.writeAll("];\n");
            },
            .sentinel_many => try writer.print("@as([*:0]const u8, @ptrCast({s}_data + {s}Offset));\n", .{ parameter.name, base }),
        }
        try writer.print("        {s}Offset += length + 1;\n    }}\n", .{ base });
    }
}

fn isCStringSlice(node: semantic.TypeNode, hint: ?semantic.SemanticHint) bool {
    return hint == .c_string and node == .slice and node.slice.@"const" and isByteType(node.slice.element.*);
}

fn isStringSlice(node: semantic.TypeNode, hint: ?semantic.SemanticHint) bool {
    return isUtf8Slice(node, hint) or isCStringSlice(node, hint);
}

fn isCStringParameter(parameter: semantic.Parameter) bool {
    return isCStringSlice(parameter.type, parameter.semantic);
}

fn isCStringReturn(function: semantic.SemanticFn) bool {
    return isCStringSlice(function.@"return", function.return_semantic);
}

fn isByteType(node: semantic.TypeNode) bool {
    return node == .int and !node.int.signed and node.int.bits == 8;
}

fn writeGoDoc(writer: *std.Io.Writer, go_name: []const u8, zig_name: []const u8, doc: []const u8) !void {
    try writer.writeByte('\n');
    var lines = std.mem.splitScalar(u8, doc, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (first) {
            // Go doc comments read as one sentence starting with the identifier,
            // so a Zig sentence like "Echoes text" must not keep its capital.
            const body = withoutLeadingName(line, go_name, zig_name);
            if (body.len == 0) {
                try writer.print("// {s}\n", .{go_name});
                first = false;
                continue;
            }
            try writer.print("// {s} ", .{go_name});
            if (continuesSentence(body)) {
                try writer.writeByte(std.ascii.toLower(body[0]));
                try writer.print("{s}\n", .{body[1..]});
            } else {
                try writer.print("{s}\n", .{body});
            }
            first = false;
        } else {
            try writer.print("// {s}\n", .{line});
        }
    }
}

/// Zig doc comments conventionally open with the declaration's own name, and
/// the Go prefix is unconditional, so the two together read as
/// "AlgorithmID algorithmId names ...". Dropping a leading word that is the
/// declaration's name under either naming convention leaves exactly one.
fn withoutLeadingName(line: []const u8, go_name: []const u8, zig_name: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
    const word = line[0..end];
    if (!std.ascii.eqlIgnoreCase(word, go_name) and !std.ascii.eqlIgnoreCase(word, zig_name)) return line;
    // A doc that is only the name has nothing left to say; the Go prefix
    // already carries it, so the caller emits the name on its own.
    return std.mem.trimStart(u8, line[end..], " ");
}

/// A capitalized ordinary word continues the sentence the identifier starts.
/// An acronym or a name that is already capitalized in Zig is left alone.
fn continuesSentence(line: []const u8) bool {
    if (line.len < 2 or !std.ascii.isUpper(line[0])) return false;
    return std.ascii.isLower(line[1]);
}

fn writePublicFunctionDoc(writer: *std.Io.Writer, function: semantic.SemanticFn, go_name: []const u8, owned_type: ?[]const u8) !void {
    if (function.doc) |doc| {
        try writeGoDoc(writer, go_name, function.name, doc);
    } else if (owned_type) |type_name| {
        try writer.print("\n// {s} creates a caller-owned {s}.\n", .{ go_name, type_name });
    } else if (function.receiver) |receiver| {
        try writer.print("\n// {s} invokes the bound Zig {s}.{s} operation.\n", .{ go_name, receiver, function.name });
    } else {
        try writer.print("\n// {s} invokes the bound Zig {s} operation.\n", .{ go_name, function.name });
    }
    if (owned_type != null)
        try writer.writeAll("// The caller must call Close on the returned handle.\n");
    if (returnsBorrowedHandle(function))
        try writer.writeAll("// The returned reference remains valid only while its parent handle remains open.\n");
    if (function.receiver != null or hasOpaqueParameter(function))
        try writer.writeAll("// It returns *HandleError if a required handle is nil or closed.\n");
    if (function.@"return" == .error_union)
        try writer.writeAll("// Native failures are returned as generated error values.\n");
}

fn returnsBorrowedHandle(function: semantic.SemanticFn) bool {
    const node = if (function.@"return" == .error_union) function.@"return".error_union.payload.* else function.@"return";
    return node == .opaque_ptr and function.ownership == .borrowed;
}

fn hasOpaqueParameter(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| if (parameter.type == .opaque_ptr) return true;
    return false;
}

fn rawGoTypeName(program: abi.Program, node: semantic.TypeNode) []const u8 {
    const scalar = semanticScalar(program, node);
    return switch (scalar) {
        .usize => "uint",
        .isize => "int",
        .bool_u8 => "uint8",
        .signed_int => |bits| switch (bits) {
            8 => "int8",
            16 => "int16",
            32 => "int32",
            64 => "int64",
            else => unreachable,
        },
        .unsigned_int => |bits| switch (bits) {
            8 => "uint8",
            16 => "uint16",
            32 => "uint32",
            64 => "uint64",
            else => unreachable,
        },
        .float => |bits| switch (bits) {
            32 => "float32",
            64 => "float64",
            else => unreachable,
        },
        else => unreachable,
    };
}

fn goZero(node: semantic.TypeNode) []const u8 {
    return switch (node) {
        .bool => "false",
        .slice, .opaque_ptr => "nil",
        else => "0",
    };
}

/// The zero value an error path returns. A struct needs its own composite
/// literal, so callers that can see one use this instead of `goZero`.
fn writeGoZeroValue(writer: *std.Io.Writer, node: semantic.TypeNode) !void {
    if (node == .value_struct) return writer.print("{s}{{}}", .{node.value_struct.ref});
    try writer.writeAll(goZero(node));
}

fn rawGoZero(node: semantic.TypeNode) []const u8 {
    return switch (node) {
        .slice, .opaque_ptr => "nil",
        else => "0",
    };
}

fn semanticScalar(program: abi.Program, node: semantic.TypeNode) abi.AbiScalar {
    return switch (node) {
        .bool => .bool_u8,
        .int => |value| if (value.is_usize) (if (value.signed) .isize else .usize) else if (value.signed) .{ .signed_int = value.bits } else .{ .unsigned_int = value.bits },
        .float => |value| .{ .float = value.bits },
        .@"enum" => |value| semanticScalar(program, enumDecl(program, value.ref).tag_type.?),
        .opaque_ptr => |value| .{ .@"opaque" = handleRecord(program, value.ref) },
        else => unreachable,
    };
}

/// The lowered handle for a semantic type name. Lowering records one for every
/// `opaque` and tagged union, so a missing entry is a malformed program.
fn handleRecord(program: abi.Program, name: []const u8) abi.AbiOpaque {
    for (program.handles) |handle| if (std.mem.eql(u8, handle.name, name)) return handle;
    unreachable;
}

/// The lowered enum for a semantic type name, on the same terms as
/// `handleRecord`.
fn enumRecord(program: abi.Program, name: []const u8) abi.AbiEnum {
    for (program.enums) |record| if (std.mem.eql(u8, record.name, name)) return record;
    unreachable;
}

fn isHandleType(declaration: semantic.TypeDecl) bool {
    return declaration.kind == .@"opaque" or declaration.kind == .tagged_union;
}

fn enumDecl(program: abi.Program, name: []const u8) semantic.TypeDecl {
    for (program.types) |declaration| if (std.mem.eql(u8, declaration.name, name)) return declaration;
    unreachable;
}

fn writeZigType(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("u8"),
        .usize => try writer.writeAll("usize"),
        .isize => try writer.writeAll("isize"),
        .signed_int => |bits| try writer.print("i{d}", .{bits}),
        .unsigned_int => |bits| try writer.print("u{d}", .{bits}),
        .float => |bits| try writer.print("f{d}", .{bits}),
        .@"opaque" => |handle| try writer.print("target.{s}", .{handle.name}),
        .snapshot => |name| try writer.writeAll(name),
        .value_struct => |record| try writer.print("target.{s}", .{record.name}),
        .pointer => |pointer| {
            if (pointer.is_optional and !pointer.is_many) try writer.writeByte('?');
            try writer.writeAll(if (pointer.is_c_string) "[*:0]" else if (pointer.is_many) "[*c]" else "*");
            if (pointer.is_const) try writer.writeAll("const ");
            try writeZigType(writer, pointer.child.*);
        },
        .callback => |callback| {
            try writer.writeAll("*const fn (");
            for (callback.params, 0..) |parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writeZigType(writer, parameter);
            }
            try writer.writeAll(") callconv(.c) ");
            try writeZigType(writer, callback.ret.*);
        },
    }
}

fn writeCType(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("uint8_t"),
        .usize => try writer.writeAll("size_t"),
        .isize => try writer.writeAll("ptrdiff_t"),
        .signed_int => |bits| try writer.print("int{d}_t", .{bits}),
        .unsigned_int => |bits| try writer.print("uint{d}_t", .{bits}),
        .float => |bits| try writer.writeAll(if (bits == 32) "float" else "double"),
        .@"opaque" => try writer.writeAll("void"),
        .snapshot => |name| try writer.writeAll(name),
        .value_struct => |record| try writer.writeAll(record.c_name),
        .pointer => |pointer| {
            if (pointer.is_c_string) return writer.writeAll("const char *");
            if (pointer.is_const) try writer.writeAll("const ");
            try writeCType(writer, pointer.child.*);
            try writer.writeAll(" *");
        },
        .callback => unreachable,
    }
}

fn writeCParam(writer: *std.Io.Writer, value: abi.AbiScalar, name: []const u8) !void {
    if (value != .callback) {
        try writeCType(writer, value);
        try writer.print(" {s}", .{name});
        return;
    }
    const callback = value.callback;
    try writeCType(writer, callback.ret.*);
    try writer.print(" (*{s})(", .{name});
    if (callback.params.len == 0) try writer.writeAll("void");
    for (callback.params, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        try writeCType(writer, parameter);
    }
    try writer.writeByte(')');
}

fn writeCgoType(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .void => try writer.writeAll("void"),
        .bool_u8 => try writer.writeAll("uint8_t"),
        .usize => try writer.writeAll("size_t"),
        .isize => try writer.writeAll("ptrdiff_t"),
        .signed_int => |bits| try writer.print("int{d}_t", .{bits}),
        .unsigned_int => |bits| try writer.print("uint{d}_t", .{bits}),
        .float => |bits| try writer.writeAll(if (bits == 32) "float" else "double"),
        .@"opaque" => try writer.writeAll("void"),
        .snapshot => |name| try writer.writeAll(name),
        .value_struct => |record| try writer.writeAll(record.c_name),
        .pointer => unreachable,
        .callback => unreachable,
    }
}

fn writeGoScalar(writer: *std.Io.Writer, value: abi.AbiScalar) !void {
    switch (value) {
        .bool_u8 => try writer.writeAll("uint8"),
        .usize => try writer.writeAll("uint"),
        .isize => try writer.writeAll("int"),
        .signed_int => |bits| try writeIntegerName(writer, true, bits, false),
        .unsigned_int => |bits| try writeIntegerName(writer, false, bits, false),
        .float => |bits| try writer.print("float{d}", .{bits}),
        .@"opaque", .pointer => try writer.writeAll("unsafe.Pointer"),
        .callback => try writer.writeAll("uintptr"),
        else => unreachable,
    }
}

fn writeIntegerName(writer: *std.Io.Writer, signed: bool, bits: u16, c_name: bool) !void {
    _ = c_name;
    try writer.print("{s}{d}", .{ if (signed) "int" else "uint", bits });
}

fn programHasSlices(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| if (parameter.type == .slice) return true;
        if (function.origin.@"return" == .slice) return true;
    }
    return false;
}

fn programHasCString(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| if (isCStringParameter(parameter)) return true;
        if (isCStringReturn(function.origin.*)) return true;
    }
    return false;
}

fn programHasEnums(program: abi.Program) bool {
    for (program.types) |declaration| if (declaration.kind == .@"enum") return true;
    return false;
}

fn programHasOpaqueTypes(program: abi.Program) bool {
    for (program.types) |declaration| if (isHandleType(declaration)) return true;
    return false;
}

fn programHasCallbacks(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| if (parameter.type == .callback) return true;
    }
    return false;
}

fn programHasTaggedUnionTypes(program: abi.Program) bool {
    for (program.types) |declaration| if (declaration.kind == .tagged_union) return true;
    return false;
}

/// Every constructed handle carries the `runtime.AddCleanup` safety net, so
/// owning a constructor is the whole test. Handle types the binding never
/// constructs have nothing to release and stay plain.
fn isAutoCleanupType(program: abi.Program, type_name: []const u8) bool {
    return constructorForType(program, type_name) != null;
}

/// Whether a handle type retains callback handles for its own lifetime. This
/// is a per-type question: a program can mix types that take callbacks with
/// types that do not, and only the former need the bookkeeping.
fn typeOwnsCallbacks(program: abi.Program, type_name: []const u8) bool {
    for (program.functions) |function| {
        const produced = if (constructorForInit(program, function.origin.*)) |constructor|
            constructor.type
        else
            ownedOpaqueReturn(program, function.origin.*) orelse continue;
        if (!std.mem.eql(u8, produced, type_name)) continue;
        if (hasRetainedCallback(function.origin.*)) return true;
    }
    return false;
}

fn publicNeedsRuntime(program: abi.Program) bool {
    for (program.functions) |function| {
        if (constructorForInit(program, function.origin.*) == null and constructorForDeinit(program, function.origin.*) != null) continue;
        if (function.origin.receiver) |receiver| {
            if (isAutoCleanupType(program, receiver)) return true;
        }
        for (function.origin.params) |parameter| switch (parameter.type) {
            .opaque_ptr => |pointer| if (isAutoCleanupType(program, pointer.ref)) return true,
            else => {},
        };
    }
    return false;
}

fn publicNeedsCgo(program: abi.Program) bool {
    for (program.functions) |function| {
        const produces_handle = constructorForInit(program, function.origin.*) != null or
            ownedOpaqueReturn(program, function.origin.*) != null;
        if (produces_handle and hasRetainedCallback(function.origin.*)) return true;
    }
    return false;
}

fn hasRetainedCallback(function: semantic.SemanticFn) bool {
    for (function.params) |parameter| if (parameter.type == .callback and parameter.retention == .retained) return true;
    return false;
}

/// Index of the callback parameter whose userdata this parameter carries.
fn callbackForUserdataIndex(parameters: []const semantic.Parameter, index: usize) ?usize {
    if (callbackForUserdata(parameters, index) == null) return null;
    return index - 1;
}

fn callbackForUserdata(parameters: []const semantic.Parameter, index: usize) ?semantic.Parameter {
    if (index == 0) return null;
    const callback = parameters[index - 1];
    if (callback.type != .callback or !callback.type.callback.has_userdata) return null;
    return callback;
}

fn callbackTrampolineNameAlloc(allocator: std.mem.Allocator, function: abi.AbiFn, parameter_index: usize) ![]u8 {
    const parameter_name = try naming.snakeAlloc(allocator, function.origin.params[parameter_index].name);
    defer allocator.free(parameter_name);
    return std.fmt.allocPrint(allocator, "{s}_go_callback_{s}", .{ function.symbol, parameter_name });
}

/// The static shim function the native side actually receives when a callback
/// carries floats, and the global holding the Go dispatcher it forwards to.
fn callbackThunkNameAlloc(allocator: std.mem.Allocator, function: abi.AbiFn, parameter_index: usize) ![]u8 {
    const parameter_name = try naming.snakeAlloc(allocator, function.origin.params[parameter_index].name);
    defer allocator.free(parameter_name);
    return std.fmt.allocPrint(allocator, "{s}_bits_thunk_{s}", .{ function.symbol, parameter_name });
}

fn callbackBindingNameAlloc(allocator: std.mem.Allocator, function: abi.AbiFn, parameter_index: usize) ![]u8 {
    const parameter_name = try naming.snakeAlloc(allocator, function.origin.params[parameter_index].name);
    defer allocator.free(parameter_name);
    return std.fmt.allocPrint(allocator, "{s}_bits_target_{s}", .{ function.symbol, parameter_name });
}

/// True when the callback's own parameters include a float, which the purego
/// callback ABI carries as an integer bit pattern instead.
fn callbackHasFloatParam(callback: semantic.Callback) bool {
    for (callback.params) |parameter| if (parameter == .float) return true;
    return false;
}

/// The lowered wire signature for a callback parameter: the same shape the
/// header and the exported shim function spell, with floats already replaced
/// by integers.
fn callbackWireScalar(function: abi.AbiFn, source_index: usize) ?abi.AbiScalar {
    for (function.params) |parameter| {
        if (parameter.source_index == source_index and parameter.scalar == .callback) return parameter.scalar;
    }
    return null;
}

/// Every purego callback parameter that carries a float needs the shim to sit
/// between the native caller and Go: the native side calls with real floats and
/// Go must receive their bits.
fn needsCallbackBitThunk(program: abi.Program, function: abi.AbiFn, parameter_index: usize) bool {
    if (program.backend != .purego) return false;
    const parameter = function.origin.params[parameter_index];
    if (parameter.type != .callback) return false;
    return callbackHasFloatParam(parameter.type.callback);
}

fn callbackTypeNameAlloc(allocator: std.mem.Allocator, program: abi.Program, function: abi.AbiFn, parameter_index: usize) ![]u8 {
    const base = try callbackTypeBaseNameAlloc(allocator, function, parameter_index);
    defer allocator.free(base);
    var duplicate_base = false;
    for (program.functions) |candidate| {
        for (candidate.origin.params, 0..) |parameter, candidate_index| {
            if (parameter.type != .callback) continue;
            if (candidate.origin == function.origin and candidate_index == parameter_index) continue;
            const candidate_base = try callbackTypeBaseNameAlloc(allocator, candidate, candidate_index);
            defer allocator.free(candidate_base);
            if (std.mem.eql(u8, base, candidate_base)) duplicate_base = true;
        }
    }

    const qualified = if (duplicate_base and (function.origin.receiver orelse function.origin.namespace) != null) blk: {
        const owner = (function.origin.receiver orelse function.origin.namespace).?;
        const function_name = try naming.pascalAlloc(allocator, function.origin.name);
        defer allocator.free(function_name);
        const parameter_name = try naming.pascalAlloc(allocator, function.origin.params[parameter_index].name);
        defer allocator.free(parameter_name);
        break :blk try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ owner, function_name, parameter_name });
    } else try allocator.dupe(u8, base);
    defer allocator.free(qualified);

    if (publicTypeNameExists(program, qualified)) return std.fmt.allocPrint(allocator, "{s}Callback", .{qualified});
    return allocator.dupe(u8, qualified);
}

fn callbackTypeBaseNameAlloc(allocator: std.mem.Allocator, function: abi.AbiFn, parameter_index: usize) ![]u8 {
    const parameter_name = try naming.pascalAlloc(allocator, function.origin.params[parameter_index].name);
    defer allocator.free(parameter_name);
    if (function.origin.receiver orelse function.origin.namespace) |owner| {
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ owner, parameter_name });
    }
    const function_name = try naming.pascalAlloc(allocator, function.origin.name);
    defer allocator.free(function_name);
    // A parameter already called `callback` would otherwise stutter into
    // `ApplyCallbackCallback`.
    if (std.mem.eql(u8, parameter_name, "Callback"))
        return std.fmt.allocPrint(allocator, "{s}Callback", .{function_name});
    return std.fmt.allocPrint(allocator, "{s}{s}Callback", .{ function_name, parameter_name });
}

fn publicTypeNameExists(program: abi.Program, name: []const u8) bool {
    for (program.types) |declaration| if (std.mem.eql(u8, declaration.name, name)) return true;
    return false;
}

fn programNeedsUnsafe(program: abi.Program) bool {
    if (programHasSlices(program) or programHasOpaqueTypes(program)) return true;
    for (program.functions) |function| {
        if (function.origin.receiver != null) return true;
        for (function.origin.params) |parameter| if (parameter.type == .opaque_ptr) return true;
        if (function.origin.@"return" == .opaque_ptr) return true;
        if (function.origin.@"return" == .error_union and function.origin.@"return".error_union.payload.* == .opaque_ptr) return true;
    }
    return false;
}

fn rawGoNameAlloc(allocator: std.mem.Allocator, function: semantic.SemanticFn) ![]u8 {
    const function_name = try naming.pascalAlloc(allocator, function.name);
    defer allocator.free(function_name);
    if (function.receiver orelse function.namespace) |receiver| return std.fmt.allocPrint(allocator, "{s}{s}", .{ receiver, function_name });
    return allocator.dupe(u8, function_name);
}

fn receiverVariableAlloc(allocator: std.mem.Allocator, receiver: []const u8) ![]u8 {
    const snake = try naming.snakeAlloc(allocator, receiver);
    defer allocator.free(snake);
    return allocator.dupe(u8, snake[0..@min(snake.len, 1)]);
}

fn constructorForInit(program: abi.Program, function: semantic.SemanticFn) ?semantic.Constructor {
    if (function.receiver != null) return null;
    for (program.constructors) |constructor| {
        if (std.mem.eql(u8, constructor.init, function.name) and
            std.mem.eql(u8, constructor.type, function.namespace orelse "")) return constructor;
    }
    return null;
}

fn constructorForDeinit(program: abi.Program, function: semantic.SemanticFn) ?semantic.Constructor {
    const receiver = function.receiver orelse return null;
    for (program.constructors) |constructor| {
        if (std.mem.eql(u8, constructor.type, receiver) and std.mem.eql(u8, constructor.deinit, function.name)) return constructor;
    }
    return null;
}

fn constructorForType(program: abi.Program, type_name: []const u8) ?semantic.Constructor {
    for (program.constructors) |constructor| if (std.mem.eql(u8, constructor.type, type_name)) return constructor;
    return null;
}

/// The handle type a caller-owned return hands over.
///
/// Ownership metadata is authoritative, not the function name: `.returns =
/// .caller` makes any function a factory, so a `clone` or `openChild` produces
/// the same owned handle a named constructor does. Registration in
/// `program.constructors` stays name-based because that list also names the
/// deinit that `newX` schedules; this is the wider question of which returns
/// need wrapping at all.
fn ownedOpaqueReturn(program: abi.Program, function: semantic.SemanticFn) ?[]const u8 {
    if (function.ownership != .caller) return null;
    const node = if (function.@"return" == .error_union) function.@"return".error_union.payload.* else function.@"return";
    if (node != .opaque_ptr) return null;
    if (constructorForType(program, node.opaque_ptr.ref) == null) return null;
    return node.opaque_ptr.ref;
}

/// Every constructed handle goes through its `new` helper, which is what
/// registers the cleanup and adopts the callback handles the call retained.
fn writeOwnedHandleResult(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    function: semantic.SemanticFn,
    type_name: []const u8,
    expression: []const u8,
) !void {
    try writer.print("new{s}({s}", .{ type_name, expression });
    if (typeOwnsCallbacks(program, type_name)) {
        try writer.writeAll(", ");
        if (hasRetainedCallback(function)) {
            try writer.writeAll("[]zigoCallbackHandle{");
            try writeRetainedCallbackHandles(allocator, writer, function);
            try writer.writeByte('}');
        } else {
            try writer.writeAll("nil");
        }
    }
    try writer.writeByte(')');
}

fn rawNameForSemanticAlloc(allocator: std.mem.Allocator, program: abi.Program, name: []const u8, receiver: []const u8) !?[]u8 {
    for (program.functions) |function| {
        if (function.origin.receiver) |actual_receiver| {
            if (std.mem.eql(u8, actual_receiver, receiver) and std.mem.eql(u8, function.origin.name, name)) {
                return try rawGoNameAlloc(allocator, function.origin.*);
            }
        }
    }
    return null;
}

fn programNeedsBoolHelper(program: abi.Program) bool {
    for (program.structs) |record| {
        for (record.fields) |field| if (field.node == .bool) return true;
    }
    for (program.functions) |function| for (function.origin.params) |parameter| if (parameter.type == .bool) return true;
    return false;
}

test "tagged union emitters generate checked pointer-only projections" {
    var i16_node: semantic.TypeNode = .{ .int = .{ .bits = 16, .signed = true } };
    const document: semantic.Semantic = .{
        .package = "variant",
        .prefix = "zg",
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "integer", .type = .{ .int = .{ .bits = 32, .signed = true } }, .value = 1 },
                    .{ .name = "flag", .type = .{ .bool = {} }, .value = 2 },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } }, .value = 3 },
                    .{ .name = "child", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Child" } }, .value = 4 },
                    .{ .name = "samples", .type = .{ .slice = .{ .@"const" = true, .element = &i16_node } }, .value = 5 },
                },
                .kind = .tagged_union,
                .name = "Value",
                .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } },
            },
            .{
                .fields = &.{
                    .{ .name = "none", .value = 0 },
                    .{ .name = "integer", .value = 1 },
                    .{ .name = "flag", .value = 2 },
                    .{ .name = "mode", .value = 3 },
                    .{ .name = "child", .value = 4 },
                    .{ .name = "samples", .value = 5 },
                },
                .kind = .@"enum",
                .name = "ValueTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{
                .fields = &.{ .{ .name = "off", .value = 0 }, .{ .name = "on", .value = 1 } },
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{
                .fields = &.{.{ .name = "URLValue", .type = .{ .int = .{ .bits = 64, .signed = false } }, .value = 0 }},
                .kind = .tagged_union,
                .name = "HTTPResult",
                .tag_type = .{ .@"enum" = .{ .ref = "HTTPResultTag" } },
            },
            .{ .fields = &.{.{ .name = "URLValue", .value = 0 }}, .kind = .@"enum", .name = "HTTPResultTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            .{ .kind = .@"opaque", .name = "Child" },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower.zig").semanticDocument(arena.allocator(), document, "variant", "zg", &.{});

    const shim = try renderForTest(renderShim, program);
    defer std.testing.allocator.free(shim);
    try std.testing.expect(std.mem.indexOf(u8, shim, "export fn zg_value_project_tag_impl(self: *const target.Value, out_value: *u8) u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "out_value.* = @intFromEnum(std.meta.activeTag(self.*));") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "if (std.meta.activeTag(self.*) != .integer) return 0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "out_value.* = @intFromBool(self.flag);") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "out_value_ptr.* = self.samples.ptr;") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "project_none") == null);
    const integer_projection = std.mem.indexOf(u8, shim, "export fn zg_value_project_integer_impl").?;
    const mismatch_check = std.mem.indexOfPos(u8, shim, integer_projection, "if (std.meta.activeTag(self.*) != .integer) return 0;").?;
    const output_write = std.mem.indexOfPos(u8, shim, integer_projection, "out_value.* = self.integer;").?;
    try std.testing.expect(mismatch_check < output_write);

    const header = try renderForTest(renderHeader, program);
    defer std.testing.allocator.free(header);
    try std.testing.expect(std.mem.indexOf(u8, header, "typedef struct zg_value zg_value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "uint8_t zg_value_project_tag(const zg_value *self, uint8_t *out_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "uint8_t zg_value_project_integer(const zg_value *self, int32_t *out_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "uint8_t zg_value_project_samples(const zg_value *self, const int16_t **out_value_ptr, size_t *out_value_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "uint8_t zg_http_result_project_url_value(const zg_http_result *self, uint64_t *out_value);") != null);

    const panic_source = try renderForTest(renderPanicSource, program);
    defer std.testing.allocator.free(panic_source);
    try std.testing.expect(std.mem.indexOf(u8, panic_source, "uint8_t zg_value_project_tag_impl(const zg_value *self, uint8_t *out_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, panic_source, "if (self == NULL || out_value == NULL) return 2;") != null);
    try std.testing.expect(std.mem.indexOf(u8, panic_source, "return 3;") != null);

    const raw = try renderForTest(renderRaw, program);
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "func ValueProjectTag(self unsafe.Pointer) (uint8, uint8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "func ValueProjectInteger(self unsafe.Pointer) (int32, uint8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "func HTTPResultProjectURLValue(self unsafe.Pointer) (uint64, uint8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "if status != 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "result := make([]int16, int(outValueLen))") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "copy(result, unsafe.Slice((*int16)(unsafe.Pointer(outValuePtr)), int(outValueLen)))") != null);

    const public_types = try renderUnionFilesForTest(program);
    defer std.testing.allocator.free(public_types);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "\t\"runtime\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) Tag() (ValueTag, error)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *ValueRef) Tag() (ValueTag, error)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) AsInteger() (int32, bool, error)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) MustAsInteger() (int32, bool)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *ValueRef) MustAsInteger() (int32, bool)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) MustAsChild() (*ChildRef, bool)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (h *HTTPResult) MustAsURLValue() (uint64, bool)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "append([]int16(nil), result...)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "ptr, err := zigoCheckedPointer") != null);
    const public_runtime = try renderForTest(renderPublicRuntimeFile, program);
    defer std.testing.allocator.free(public_runtime);
    // The Must* wrappers are runtime, not per-union, so they moved with it.
    try std.testing.expect(std.mem.indexOf(u8, public_runtime, "panic(err)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "panic(err)") == null);
    // One KeepAlive per projection implementation: the owned and borrowed
    // methods share it instead of each carrying a copy.
    try std.testing.expectEqual(@as(usize, 8), std.mem.count(u8, public_types, "defer runtime.KeepAlive("));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, public_types, "func zigoValueTag(receiver zigoHandle)"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, public_types, "ValueProjectInteger(ptr)"));
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *ValueRef) AsInteger() (int32, bool, error) { return zigoValueAsInteger(v) }") != null);

    // The sealed variant hierarchy sits beside the projections: one concrete
    // type per Zig variant, and a builder that reads the tag and then only
    // the projection the active variant needs.
    try std.testing.expect(std.mem.indexOf(u8, public_types, "type ValueVariant interface{ isValueVariant() }") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "type ValueNone struct{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (ValueNone) isValueVariant() {}") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "type ValueChild struct {\n\t// Value is the payload the child variant carries.\n\tValue *ChildRef\n}") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "type HTTPResultURLValue struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "tag, err := zigoValueTag(receiver)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "payload, matched, err := zigoValueAsInteger(receiver)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) Variant() (ValueVariant, error) { return zigoValueVariant(v) }") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *ValueRef) Variant() (ValueVariant, error) { return zigoValueVariant(v) }") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *Value) MustVariant() ValueVariant { return zigoMust(zigoValueVariant(v)) }") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (v *ValueRef) MustVariant() ValueVariant { return zigoMust(zigoValueVariant(v)) }") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, public_types, "func zigoValueVariant(receiver zigoHandle)"));

    const public_errors = try renderForTest(renderPublicErrors, program);
    defer std.testing.allocator.free(public_errors);
    try std.testing.expect(std.mem.indexOf(u8, public_errors, "var ErrInvalidHandle = errors.New") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_errors, "type HandleError struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_errors, "type NativePanicError struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_errors, "type StatusError struct") != null);
}

/// The per-union files concatenated, so a test can assert over the whole
/// tagged-union surface the way it did when one file held it.
fn renderUnionFilesForTest(program: abi.Program) ![]u8 {
    const files = try unionFilesAlloc(std.testing.allocator, program, .{ .go_module = "example.com/test" });
    defer {
        for (files) |file| {
            std.testing.allocator.free(file.path);
            std.testing.allocator.free(file.contents);
        }
        std.testing.allocator.free(files);
    }
    var joined: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer joined.deinit();
    for (files) |file| try joined.writer.writeAll(file.contents);
    return joined.toOwnedSlice();
}

fn renderForTest(render: *const fn (std.mem.Allocator, *std.Io.Writer, abi.Program, Options) anyerror!void, program: abi.Program) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    errdefer output.deinit();
    try render(std.testing.allocator, &output.writer, program, .{ .go_module = "example.com/variant" });
    return output.toOwnedSlice();
}

test "snapshot-backed unions build their variants from one native call" {
    const document: semantic.Semantic = .{
        .package = "signal",
        .prefix = "zg",
        .types = &.{
            .{
                .access = .snapshot,
                .fields = &.{
                    .{ .name = "idle", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "ticks", .type = .{ .int = .{ .bits = 32, .signed = false } }, .value = 1 },
                    .{ .name = "level", .type = .{ .float = .{ .bits = 64 } }, .value = 2 },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } }, .value = 3 },
                    .{ .name = "active", .type = .{ .bool = {} }, .value = 4 },
                },
                .kind = .tagged_union,
                .name = "Signal",
                .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
            },
            .{
                .fields = &.{
                    .{ .name = "idle", .value = 0 },
                    .{ .name = "ticks", .value = 1 },
                    .{ .name = "level", .value = 2 },
                    .{ .name = "mode", .value = 3 },
                    .{ .name = "active", .value = 4 },
                },
                .kind = .@"enum",
                .name = "SignalTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{
                .fields = &.{ .{ .name = "idle", .value = 0 }, .{ .name = "active", .value = 1 } },
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower.zig").semanticDocument(arena.allocator(), document, "signal", "zg", &.{});

    const public_types = try renderUnionFilesForTest(program);
    defer std.testing.allocator.free(public_types);

    const builder = std.mem.indexOf(u8, public_types, "func zigoSignalVariant(receiver zigoHandle) (SignalVariant, error) {").?;
    const builder_end = std.mem.indexOfPos(u8, public_types, builder, "\n}\n").?;
    const body = public_types[builder..builder_end];
    // The whole variant costs one native call: the snapshot read. Not one
    // projection per variant, and not a tag read on top of it.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "zigoSignalSnapshot(receiver)"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "zigoSignalTag(receiver)"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "zigoSignalAs"));
    try std.testing.expect(std.mem.indexOf(u8, body, "return SignalIdle{}, nil") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "return SignalLevel{Value: data.level}, nil") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "return SignalMode{Value: data.mode}, nil") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "return SignalActive{Value: data.active}, nil") != null);
    // The projection surface stays: the fast path is additive.
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (s *Signal) AsTicks() (uint32, bool, error)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_types, "func (s *SignalRef) MustVariant() SignalVariant { return zigoMust(zigoSignalVariant(s)) }") != null);
}

test "a colocated internal loader keeps the loader out of the exported names" {
    const origin: semantic.SemanticFn = .{
        .name = "ping",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "zg_ping",
    };
    const program: abi.Program = .{
        .backend = .purego,
        .callback_convention = .function_pointer_userdata_v2,
        .functions = &.{.{ .symbol = "zg_ping", .params = &.{}, .ret = .void, .origin = &origin }},
        .package = "hub",
        .prefix = "zg",
    };
    const options: Options = .{
        .go_module = "example.com/hub",
        .backend = .purego,
        .raw_colocated = true,
        .library_exported_api = false,
        .library_automatic = true,
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try renderRaw(std.testing.allocator, &output.writer, program, options);
    const raw = output.written();

    // The raw package is the public package here, so the loader can only be
    // kept internal by not exporting its names.
    try std.testing.expect(std.mem.indexOf(u8, raw, "func zigoRawLoadLibrary(") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "func zigoRawLibraryLoaded(") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "var zigoRawDefaultLibraryName = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "func LoadLibrary(") == null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "func LibraryLoaded(") == null);
    // The error type is not part of the loader API; callers still inspect it.
    try std.testing.expect(std.mem.indexOf(u8, raw, "type LibraryError struct") != null);

    var exported: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer exported.deinit();
    var exported_options = options;
    exported_options.raw_colocated = false;
    exported_options.library_exported_api = true;
    try renderRaw(std.testing.allocator, &exported.writer, program, exported_options);
    try std.testing.expect(std.mem.indexOf(u8, exported.written(), "func LoadLibrary(") != null);
}

test "every entry point the loader resolves is annotated for the COFF export table" {
    const origin: semantic.SemanticFn = .{
        .name = "ping",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "zg_ping",
    };
    const program: abi.Program = .{
        .backend = .purego,
        .callback_convention = .function_pointer_userdata_v2,
        .functions = &.{.{ .symbol = "zg_ping", .params = &.{}, .ret = .void, .origin = &origin }},
        .package = "unit",
        .prefix = "zg",
    };
    const options: Options = .{ .go_module = "example.com/unit", .backend = .purego };

    inline for (.{ renderPanicSource, renderHeader }) |render| {
        var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer output.deinit();
        try render(std.testing.allocator, &output.writer, program, options);
        const text = output.written();
        try std.testing.expect(std.mem.indexOf(u8, text, "#define ZIGO_EXPORT __declspec(dllexport)") != null);
        // The public wrapper is what the generated loader looks up by name;
        // the `_impl` half is internal to the artifact and must stay unexported
        // so the DLL publishes exactly the documented surface.
        try std.testing.expect(std.mem.indexOf(u8, text, "ZIGO_EXPORT void zg_ping(") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "ZIGO_EXPORT const char *zg_last_error_message(void)") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "ZIGO_EXPORT void zg_ping_impl(") == null);
    }
}

test "a doc that opens with the declaration's own name is not repeated" {
    const cases = [_]struct {
        go_name: []const u8,
        zig_name: []const u8,
        doc: []const u8,
        expected: []const u8,
    }{
        // The reported shape: the Zig doc opens with the Zig spelling.
        .{
            .go_name = "AlgorithmID",
            .zig_name = "algorithmId",
            .doc = "algorithmId names the negotiated algorithm.",
            .expected = "\n// AlgorithmID names the negotiated algorithm.\n",
        },
        // The Go spelling counts too, and so does any other casing of either.
        .{
            .go_name = "Clone",
            .zig_name = "clone",
            .doc = "Clone copies the queue.",
            .expected = "\n// Clone copies the queue.\n",
        },
        .{
            .go_name = "AlgorithmID",
            .zig_name = "algorithmId",
            .doc = "ALGORITHMID names the negotiated algorithm.",
            .expected = "\n// AlgorithmID names the negotiated algorithm.\n",
        },
        // An unrelated first word keeps the existing behaviour, including the
        // lowercasing that makes the Go prefix read as one sentence.
        .{
            .go_name = "Echo",
            .zig_name = "echo",
            .doc = "Echoes UTF-8 text without changing its bytes.",
            .expected = "\n// Echo echoes UTF-8 text without changing its bytes.\n",
        },
        // A name that only prefixes the first word is not the first word.
        .{
            .go_name = "Clone",
            .zig_name = "clone",
            .doc = "clones the queue.",
            .expected = "\n// Clone clones the queue.\n",
        },
        // Only the first line is rewritten; the rest is copied verbatim.
        .{
            .go_name = "Clone",
            .zig_name = "clone",
            .doc = "clone copies the queue.\nThe caller owns the copy.",
            .expected = "\n// Clone copies the queue.\n// The caller owns the copy.\n",
        },
        // A doc that is nothing but the name leaves the prefix alone.
        .{
            .go_name = "Clone",
            .zig_name = "clone",
            .doc = "clone",
            .expected = "\n// Clone\n",
        },
    };
    for (cases) |case| {
        var rendered: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer rendered.deinit();
        try writeGoDoc(&rendered.writer, case.go_name, case.zig_name, case.doc);
        try std.testing.expectEqualStrings(case.expected, rendered.written());
    }
}
