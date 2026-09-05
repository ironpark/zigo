//! The cgo raw Go package: struct mirrors, string helpers and the raw calls.
const type_spelling = @import("type_spelling.zig");
const target_types = @import("target_types.zig");
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");
const callbacks = @import("callbacks.zig");
const common = @import("common.zig");
const docs = @import("docs.zig");
const emit = @import("emit.zig");
const public = @import("public.zig");
const public_writers = @import("public_writers.zig");
const purego = @import("purego.zig");
const shim = @import("shim.zig");
const lower = @import("lower");

/// The Go mirror of an `extern struct`. cgo converts member by member and does
/// not depend on this layout, but purego hands the address straight to the
/// native call, so the padding is spelled out rather than left to Go happening
/// to agree with C.
pub fn renderRawStructTypes(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.structs) |record| {
        const type_name = try common.structRawTypeNameAlloc(allocator, record.name);
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
        if (type_spelling.isPackedValue(program, field.node)) return type_spelling.writeGoScalar(writer, field.scalar);
        const nested = structRecord(program, field.node.value_struct.ref);
        const nested_name = try common.structRawTypeNameAlloc(allocator, nested.name);
        defer allocator.free(nested_name);
        return writer.writeAll(nested_name);
    }
    try type_spelling.writeGoScalar(writer, field.scalar);
}

/// An `extern struct` whose Go mirror is a bit-for-bit copy of the C layout, so
/// a slice of it can cross as a cast instead of a field-by-field copy. `bool`
/// is the one field kind Go spells differently from C -- one Go `bool` against
/// the mirror's `uint8` -- so a struct carrying one anywhere keeps the copy.
/// The generated layout guards turn the assumption into a compile error rather
/// than leaving it implicit.
/// The lowered mirror a struct member names. Validation rejects a member whose
/// struct was never lowered, so a missing entry is a malformed program.
pub fn structRecord(program: abi.Program, name: []const u8) abi.AbiStruct {
    for (program.structs) |record| if (std.mem.eql(u8, record.name, name)) return record;
    unreachable;
}

pub fn recordHasAtomicFields(program: abi.Program, record: abi.AbiStruct) bool {
    for (record.fields) |field| {
        if (field.atomic) return true;
        if (field.node == .value_struct and !type_spelling.isPackedValue(program, field.node) and
            recordHasAtomicFields(program, structRecord(program, field.node.value_struct.ref))) return true;
    }
    return false;
}

/// Copies an extern value struct member by member at the Zig boundary. Atomic
/// members are deliberately loaded into a fresh wrapper instead of treating
/// the wrapper object as an ordinary scalar value.
pub fn writeZigAtomicStructCopy(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    record: abi.AbiStruct,
    expression: []const u8,
) !void {
    try target_types.writeTargetType(writer, program, record.name);
    try writer.writeByte('{');
    for (record.fields, 0..) |field, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.print(" .{s} = ", .{field.name});
        const child_expression = try std.fmt.allocPrint(allocator, "({s}).{s}", .{ expression, field.name });
        defer allocator.free(child_expression);
        if (field.node == .value_struct and !type_spelling.isPackedValue(program, field.node)) {
            try writeZigAtomicStructCopy(allocator, writer, program, structRecord(program, field.node.value_struct.ref), child_expression);
        } else if (field.atomic) {
            try writer.print(".init({s}.raw)", .{child_expression});
        } else {
            try writer.writeAll(child_expression);
        }
    }
    try writer.writeAll(" }");
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
        if (field.node == .value_struct and !type_spelling.isPackedValue(program, field.node)) {
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
        try type_spelling.writeCgoType(writer, field.scalar);
        try writer.print("({s}.{s})\n", .{ go_name, member });
    }
}

/// Reads a C value back into the Go mirror, again member by member.
fn writeCgoStructRead(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, record: abi.AbiStruct, indent: []const u8, c_name: []const u8) !void {
    const type_name = try common.structRawTypeNameAlloc(allocator, record.name);
    defer allocator.free(type_name);
    try writer.print("{s}{{\n", .{type_name});
    for (record.fields) |field| {
        const member = try naming.pascalAlloc(allocator, field.name);
        defer allocator.free(member);
        try writer.print("{s}\t{s}: ", .{ indent, member });
        if (field.node == .value_struct and !type_spelling.isPackedValue(program, field.node)) {
            const nested = structRecord(program, field.node.value_struct.ref);
            const nested_c = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ c_name, field.name });
            defer allocator.free(nested_c);
            const nested_indent = try std.fmt.allocPrint(allocator, "{s}\t", .{indent});
            defer allocator.free(nested_indent);
            try writeCgoStructRead(allocator, writer, program, nested, nested_indent, nested_c);
        } else {
            try type_spelling.writeGoScalar(writer, field.scalar);
            try writer.print("({s}.{s})", .{ c_name, field.name });
        }
        try writer.writeAll(",\n");
    }
    try writer.print("{s}}}", .{indent});
}

/// The `#cgo LDFLAGS` directives, each on its own line with a leading newline.
///
/// An explicit override is one unqualified line: the caller owns the flags and
/// the target set alike. Without an override, a target list produces one
/// `#cgo <goos>,<goarch>` line per target naming that target's library in its
/// own subdirectory, and an empty list keeps the historical single line so
/// existing trees stay byte-identical.
fn writeCgoLinkDirectives(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    if (options.ldflags_override) |flags| {
        try writer.print("\n#cgo LDFLAGS: {s}", .{flags});
        try writeTrailingLdflags(writer, options);
        return;
    }
    const stem = try purego.libraryStemAlloc(allocator, program, options);
    defer allocator.free(stem);
    if (options.cgo_targets.len == 0) {
        try writer.writeAll("\n#cgo LDFLAGS: ");
        try writeLibraryLdflags(writer, options, options.library_dir, stem);
        try writeTrailingLdflags(writer, options);
        return;
    }
    for (options.cgo_targets) |target| {
        const directory = try std.fmt.allocPrint(allocator, "{s}/{s}_{s}", .{ options.library_dir, target.goos, target.goarch });
        defer allocator.free(directory);
        try writer.print("\n#cgo {s},{s} LDFLAGS: ", .{ target.goos, target.goarch });
        try writeLibraryLdflags(writer, options, directory, stem);
        try writeTrailingLdflags(writer, options);
    }
}

fn writeLibraryLdflags(writer: *std.Io.Writer, options: emit.Options, directory: []const u8, stem: []const u8) !void {
    // Naming the archive keeps a same-named shared library in the install
    // directory from satisfying a static link instead.
    if (options.link_mode == .static)
        try writer.print("{s}/lib{s}.a", .{ directory, stem })
    else
        try writer.print("-L{s} -l{s}", .{ directory, stem });
}

fn writeTrailingLdflags(writer: *std.Io.Writer, options: emit.Options) !void {
    if (options.extra_ldflags.len != 0) try writer.print(" {s}", .{options.extra_ldflags});
    if (options.system_ldflags.len != 0) try writer.print(" {s}", .{options.system_ldflags});
}

pub fn renderRaw(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    if (options.backend == .purego) return purego.renderPuregoRaw(allocator, writer, program, options);
    const package = try naming.snakeAlloc(allocator, program.package);
    defer allocator.free(package);
    try writer.writeAll("// Code generated by zigo. DO NOT EDIT.\n\n");
    // A colocated raw package is the public package; its doc is already there.
    if (!options.raw_colocated) try docs.writeRawPackageDoc(writer, options);
    try writer.print("package {s}\n\n/*\n", .{options.raw_package_name});
    // pkg-config runs before the explicit flags so its `-I` and `-l` results
    // join the same CFLAGS and LDFLAGS cgo builds from this block.
    if (options.pkg_config_libs.len != 0) try writer.print("#cgo pkg-config: {s}\n", .{options.pkg_config_libs});
    try writer.writeAll("#cgo CFLAGS: ");
    if (options.cflags_override) |flags|
        try writer.writeAll(flags)
    else
        try writer.print("-I{s}", .{options.include_dir});
    if (!options.ldflags_external) try writeCgoLinkDirectives(allocator, writer, program, options);
    // Platform-only additions never name the archive, so they stay in this
    // file even when the archive line moves to the volatile one.
    for (options.target_ldflags) |entry| try writer.print("\n#cgo {s} LDFLAGS: {s}", .{ entry.constraint, entry.flags });
    if (options.framework_ldflags.len != 0) try writer.print("\n#cgo darwin LDFLAGS: {s}", .{options.framework_ldflags});
    if (common.programHasCString(program)) try writer.writeAll("\n#include <stdlib.h>");
    if (options.header_name.len != 0)
        try writer.print("\n#include \"{s}\"\n*/\nimport \"C\"\n", .{options.header_name})
    else
        try writer.print("\n#include \"zigo_{s}.h\"\n*/\nimport \"C\"\n", .{package});
    if (common.programHasStreams(program)) try writer.writeAll("import \"io\"\n");
    // The callback panic counter needs sync/atomic whenever callbacks exist,
    // which covers the cancellation flag's use of it too.
    if (common.programHasCallbacks(program)) try writer.writeAll("import \"runtime/cgo\"\nimport \"runtime/debug\"\nimport \"sync\"\nimport \"sync/atomic\"\n");
    if (common.programNeedsUnsafe(program)) try writer.writeAll("import \"unsafe\"\n");
    try writer.writeByte('\n');
    const last_error_name = if (options.raw_colocated) "zigoRawLastErrorMessage" else "LastErrorMessage";
    try writer.print("// {0s} returns the most recent native panic message for this binding.\nfunc {0s}() string {{ return C.GoString(C.{1s}_last_error_message()) }}\n\n", .{ last_error_name, program.prefix });
    try renderCgoStringHelpers(writer, program);
    try callbacks.renderRawCallbacks(allocator, writer, program, options);

    for (program.functions) |function| {
        const go_name = try common.rawGoNameAlloc(allocator, function.origin.*);
        defer allocator.free(go_name);
        const raw_public_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ if (options.raw_colocated) "zigoRaw" else "", go_name });
        defer allocator.free(raw_public_name);
        const go_names = try common.goParamNamesForAlloc(allocator, function.origin.params);
        defer naming.freeParamNames(allocator, go_names);
        try writer.print("// {s} calls the generated C ABI wrapper for {s}.\nfunc {s}(", .{ raw_public_name, function.symbol, raw_public_name });
        var raw_parameter_index: usize = 0;
        if (function.origin.receiver != null) {
            try writer.writeAll("self unsafe.Pointer");
            raw_parameter_index = 1;
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (function.userdataFor(parameter_index) != null) continue;
            if (parameter.injected != null) continue;
            if (parameter.flatten) |fields| {
                for (fields, 0..) |field, field_index| {
                    const abi_parameter = function.flattenedParam(parameter_index, field_index);
                    const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                    defer allocator.free(name);
                    if (raw_parameter_index != 0) try writer.writeAll(", ");
                    try writer.print("{s} ", .{name});
                    try public_writers.writeRawGoType(writer, program, field.type);
                    raw_parameter_index += 1;
                }
                continue;
            }
            if (common.isTaggedUnionValue(program, parameter.type)) {
                for (function.params) |abi_parameter| {
                    if (abi_parameter.source_index != parameter_index or
                        (abi_parameter.role != .union_tag and abi_parameter.role != .union_payload)) continue;
                    if (raw_parameter_index != 0) try writer.writeAll(", ");
                    try writer.print("{s} ", .{abi_parameter.name});
                    try type_spelling.writeGoScalar(writer, abi_parameter.scalar);
                    raw_parameter_index += 1;
                }
                continue;
            }
            if (raw_parameter_index != 0) try writer.writeAll(", ");
            if (parameter.type == .cancel_flag) {
                try writer.print("{s} *uint32", .{go_names[parameter_index]});
            } else if (parameter.type == .atomic_ptr) {
                try writer.print("{s} unsafe.Pointer", .{go_names[parameter_index]});
            } else if (parameter.type == .callback or parameter.type == .io_stream) {
                try writer.print("{s}Handle uintptr", .{go_names[parameter_index]});
                // A reader also carries the byte-slice fast path: a non-nil
                // slice is handed to the shim whole and the trampoline is
                // never called.
                if (common.isReaderStream(parameter)) try writer.print(", {s}Data []byte", .{go_names[parameter_index]});
            } else {
                try writer.print("{s} ", .{go_names[parameter_index]});
                if (function.materializesParam(parameter_index))
                    try writer.writeAll("int")
                else
                    try public_writers.writeRawParameterType(writer, program, parameter);
            }
            raw_parameter_index += 1;
        }
        try writer.writeByte(')');
        try public_writers.writeRawReturnType(writer, program, function);
        try writer.writeAll(" {\n");
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (function.paramString(parameter_index).role != .c_string) continue;
            const name = go_names[parameter_index];
            // An absent optional string stays a NULL `char *`; an empty one is
            // still copied, so the two never look alike to the callee.
            if (semantic.isOptionalSlice(parameter.type)) {
                try writer.print("\tvar {0s}CString *C.char\n\tif {0s} != nil {{\n\t\t{0s}CString = zigoCString(*{0s})\n\t}}\n", .{name});
                continue;
            }
            try writer.print("\t{s}CString := zigoCString({s})\n", .{ name, name });
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (!common.isReaderStream(parameter)) continue;
            // A nil slice means "no fast path"; a non-nil but empty one still
            // has to reach the shim as a non-NULL pointer, or the shim would
            // read it as the callback path rather than as an empty stream.
            try writer.print(
                "\tvar {0s}DataPtr *C.uint8_t\n\tif {0s}Data != nil {{\n\t\tif len({0s}Data) != 0 {{\n\t\t\t{0s}DataPtr = (*C.uint8_t)(unsafe.Pointer(&{0s}Data[0]))\n\t\t}} else {{\n\t\t\t{0s}DataPtr = (*C.uint8_t)(unsafe.Pointer(&zigoEmptyStreamData))\n\t\t}}\n\t}}\n",
                .{go_names[parameter_index]},
            );
        }
        if (function.slice_return_element) |element| {
            try writer.writeAll("\tvar outResultPtr *C.");
            if (element == .value_struct) {
                const record = structRecord(program, element.value_struct.ref);
                try writer.writeAll(record.c_name);
            } else {
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, element));
            }
            try writer.writeAll("\n\tvar outResultLen C.size_t\n");
        } else if (function.materialized_out != null) {
            try writer.writeAll("\tvar outResultPtr *C.uint8_t\n\tvar outResultLen C.size_t\n");
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.flatten == null and parameter.type == .value_struct and
                !common.isTaggedUnionValue(program, parameter.type) and !type_spelling.isPackedValue(program, parameter.type))
            {
                const record = structRecord(program, parameter.type.value_struct.ref);
                const c_name = try std.fmt.allocPrint(allocator, "c{s}", .{go_names[parameter_index]});
                defer allocator.free(c_name);
                try writeCgoStructConversion(allocator, writer, program, record, c_name, go_names[parameter_index]);
            }
            if (parameter.flatten) |fields| for (fields, 0..) |field, field_index| {
                if (field.type != .optional) continue;
                const abi_parameter = function.flattenedParam(parameter_index, field_index);
                const name = try common.flattenedGoNameAlloc(allocator, abi_parameter.name);
                defer allocator.free(name);
                try writer.print("\tvar {0s}Value C.", .{name});
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, field.type.optional.child.*));
                try writer.print("\n\tvar {0s}Ptr *C.", .{name});
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, field.type.optional.child.*));
                try writer.print("\n\tif {0s} != nil {{\n\t\t{0s}Value = C.", .{name});
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, field.type.optional.child.*));
                try writer.print("(*{0s})\n\t\t{0s}Ptr = &{0s}Value\n\t}}\n", .{name});
            };
            // An optional slice reuses the slice setup below; only a scalar
            // or struct optional needs a local of the C type to point at.
            if (parameter.type == .optional and parameter.type.optional.child.* != .slice) {
                // The C side takes one nullable pointer, so an absent value is
                // a nil one and a present value is copied into a local of the
                // C type -- the Go mirror and the C type are different types
                // even when they have the same width.
                const name = go_names[parameter_index];
                const child = parameter.type.optional.child.*;
                if (child == .value_struct and !type_spelling.isPackedValue(program, child)) {
                    const record = structRecord(program, child.value_struct.ref);
                    try writer.print("\tvar {s}Ptr *C.{s}\n\tif {s} != nil {{\n", .{ name, record.c_name, name });
                    const c_name = try std.fmt.allocPrint(allocator, "c{s}", .{name});
                    defer allocator.free(c_name);
                    const go_value = try std.fmt.allocPrint(allocator, "(*{s})", .{name});
                    defer allocator.free(go_value);
                    try writeCgoStructConversionIndented(allocator, writer, program, record, c_name, go_value, "\t\t");
                    try writer.print("\t\t{s}Ptr = &{s}\n\t}}\n", .{ name, c_name });
                } else {
                    try writer.print("\tvar {s}Value C.", .{name});
                    try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, child));
                    try writer.print("\n\tvar {s}Ptr *C.", .{name});
                    try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, child));
                    try writer.print("\n\tif {0s} != nil {{\n\t\t{0s}Value = C.", .{name});
                    try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, child));
                    try writer.print("(*{0s})\n\t\t{0s}Ptr = &{0s}Value\n\t}}\n", .{name});
                }
                continue;
            }
            if (function.paramString(parameter_index).role == .string_slice) {
                try writeCgoStringSliceSetup(writer, go_names[parameter_index]);
                continue;
            } else if (function.paramString(parameter_index).role == .c_string) {
                continue;
            } else if (parameter.type == .slice and parameter.type.slice.element.* == .value_struct) {
                const slice_name = go_names[parameter_index];
                const record = structRecord(program, parameter.type.slice.element.*.value_struct.ref);
                const c_value_name = try std.fmt.allocPrint(allocator, "c{s}", .{slice_name});
                defer allocator.free(c_value_name);
                const c_values_name = try std.fmt.allocPrint(allocator, "{s}Values", .{slice_name});
                defer allocator.free(c_values_name);
                // The layout guards make the Go mirror a bit-for-bit copy of
                // the C struct, so a castable element goes over as the address
                // of the caller's own slice, exactly as purego passes it.
                if (record.castable) {
                    try writer.print("\tvar {s}Zero C.{s}\n\t{s}Ptr := &{s}Zero\n\tif len({s}) != 0 {{\n\t\t{s}Ptr = (*C.{s})(unsafe.Pointer(&{s}[0]))\n\t}}\n", .{
                        slice_name,
                        record.c_name,
                        slice_name,
                        slice_name,
                        slice_name,
                        slice_name,
                        record.c_name,
                        slice_name,
                    });
                } else {
                    try writer.print("\tvar {s} []C.{s}\n\tif len({s}) != 0 {{\n\t\t{s} = make([]C.{s}, len({s}))\n", .{
                        c_values_name,
                        record.c_name,
                        slice_name,
                        c_values_name,
                        record.c_name,
                        slice_name,
                    });
                    // An output buffer is written, never read, so converting
                    // what the caller happened to leave in it is wasted work.
                    if (parameter.direction != .out) {
                        try writer.print("\t\tfor i := range {s} {{\n", .{slice_name});
                        const go_value_name = try std.fmt.allocPrint(allocator, "{s}[i]", .{slice_name});
                        defer allocator.free(go_value_name);
                        try writeCgoStructConversionIndented(allocator, writer, program, record, c_value_name, go_value_name, "\t\t\t");
                        try writer.print("\t\t\t{s}[i] = {s}\n\t\t}}\n", .{ c_values_name, c_value_name });
                    }
                    try writer.print("\t}}\n\tvar {s}Zero C.{s}\n\t{s}Ptr := &{s}Zero\n\tif len({s}) != 0 {{\n\t\t{s}Ptr = (*C.{s})(unsafe.Pointer(&{s}[0]))\n\t}}\n", .{
                        slice_name,
                        record.c_name,
                        slice_name,
                        slice_name,
                        slice_name,
                        slice_name,
                        record.c_name,
                        c_values_name,
                    });
                }
                if (shim.hasWrittenOutParam(parameter)) try writer.print("\tvar {s}Written C.size_t\n", .{slice_name});
            } else if (semantic.isOptionalSlice(parameter.type)) {
                // The pointer is what says "present", so a present-but-empty
                // slice still points at something: the zero local below.
                const slice_name = go_names[parameter_index];
                const element = parameter.type.optional.child.slice.element.*;
                try writer.print("\tvar {s}Zero C.", .{slice_name});
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, element));
                try writer.print("\n\tvar {s}Len C.size_t\n\tvar {s}Ptr *C.", .{ slice_name, slice_name });
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, element));
                try writer.print("\n\tif {0s} != nil {{\n\t\t{0s}Ptr = &{0s}Zero\n\t\t{0s}Len = C.size_t(len(*{0s}))\n\t\tif {0s}Len != 0 {{\n\t\t\t{0s}Ptr = (*C.", .{slice_name});
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, element));
                try writer.print(")(unsafe.Pointer(&(*{s})[0]))\n\t\t}}\n\t}}\n", .{slice_name});
            } else if (parameter.type == .slice and
                !(function.materializesParam(parameter_index)))
            {
                const slice_name = go_names[parameter_index];
                try writer.print("\tvar {s}Zero C.", .{slice_name});
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, parameter.type.slice.element.*));
                try writer.print("\n\t{s}Ptr := &{s}Zero\n\tif len({s}) != 0 {{\n\t\t{s}Ptr = (*C.", .{ slice_name, slice_name, slice_name, slice_name });
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, parameter.type.slice.element.*));
                try writer.print(")(unsafe.Pointer(&{s}[0]))\n\t}}\n", .{slice_name});
                if (shim.hasWrittenOutParam(parameter)) try writer.print("\tvar {s}Written C.size_t\n", .{slice_name});
            }
        }
        const returns_error = function.origin.@"return" == .error_union;
        const error_payload = if (returns_error) function.origin.@"return".error_union.payload.* else semantic.TypeNode{ .void = {} };
        if (function.ret_struct) |record| {
            try writer.print("\tvar outResult C.{s}\n", .{record.c_name});
        } else if (function.ret_optional) {
            // A scalar `?T` return still needs an out parameter to carry the
            // value; only the struct case declares one above.
            try writer.writeAll("\tvar outResult C.");
            try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, function.origin.@"return".optional.child.*));
            try writer.writeByte('\n');
        }
        // An optional slice payload takes the slice-return out parameters
        // above; only a value payload needs a local of its own here.
        if (returns_error and error_payload != .void and error_payload != .slice and
            function.slice_return_element == null)
        {
            if (error_payload == .optional) {
                try writer.writeAll("\tvar outResultHas C.");
                try type_spelling.writeCgoType(writer, .bool_u8);
                try writer.writeByte('\n');
                const child = error_payload.optional.child.*;
                if (function.payload_struct) |record| {
                    try writer.print("\tvar outResult C.{s}\n", .{record.c_name});
                } else {
                    try writer.writeAll("\tvar outResult C.");
                    try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, child));
                    try writer.writeByte('\n');
                }
            } else if (error_payload == .opaque_ptr) {
                try writer.print("\tvar outResult *C.{s}\n", .{common.payloadOutHandleCName(function)});
            } else if (function.payload_struct) |record| {
                try writer.print("\tvar outResult C.{s}\n", .{record.c_name});
            } else {
                try writer.writeAll("\tvar outResult C.");
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, error_payload));
                try writer.writeByte('\n');
            }
        }
        // A copied output slice is read back after the call, so a plain result
        // has to be named rather than returned straight out of the call
        // expression -- otherwise the copy would sit after the `return`.
        const binds_raw_result = !returns_error and !function.ret_optional and
            function.slice_return_element == null and
            function.ret_struct == null and
            function.origin.@"return" != .void and
            (public.hasCopiedOutValueStructSlice(program, function.origin.*) or function.materialized_out != null);
        try writer.writeByte('\t');
        if (returns_error) {
            try writer.writeAll("code := int32(");
        } else if (function.ret_optional) {
            // The C call's own return is the presence bool; the value comes
            // back through `outResult` (or the struct read below).
            try writer.writeAll("outResultHas := ");
        } else if (function.slice_return_element != null or function.ret_struct != null) {
            // The out parameters are converted after the C call.
        } else if ((function.ret_string == .c_string)) {
            try writer.writeAll(if (binds_raw_result) "result := C.GoString(" else "return C.GoString(");
        } else if (function.origin.@"return" != .void) {
            try writer.writeAll(if (function.materialized_out != null) "written := " else if (binds_raw_result) "result := " else "return ");
            try public_writers.writeRawConversionPrefix(writer, program, function.origin.@"return");
        }
        try writer.print("C.{s}(", .{function.symbol});
        for (function.params, 0..) |parameter, index| {
            if (index != 0) try writer.writeAll(", ");
            switch (parameter.role) {
                .receiver => try writeCgoHandleArgument(writer, parameter.scalar, "self"),
                .flattened_field => {
                    const field = common.flattenedField(function.origin.params[parameter.source_index], parameter);
                    const name = try common.flattenedGoNameAlloc(allocator, parameter.name);
                    defer allocator.free(name);
                    if (field.type == .optional) {
                        try writer.print("{s}Ptr", .{name});
                    } else {
                        try writer.writeAll("C.");
                        try type_spelling.writeCgoType(writer, parameter.scalar);
                        try writer.print("({s})", .{name});
                    }
                },
                .struct_in => try writer.print("&c{s}", .{go_names[parameter.source_index]}),
                .union_tag, .union_payload => {
                    try writer.writeAll("C.");
                    try type_spelling.writeCgoType(writer, parameter.scalar);
                    try writer.print("({s})", .{parameter.name});
                },
                .struct_out => try writer.writeAll("&outResult"),
                .value => {
                    if (function.userdataFor(parameter.source_index)) |callback_index| {
                        try writer.writeAll("C.");
                        try type_spelling.writeCgoType(writer, parameter.scalar);
                        try writer.print("({s}Handle)", .{go_names[callback_index]});
                    } else if (function.paramString(parameter.source_index).role == .c_string) {
                        try writer.print("{s}CString", .{go_names[parameter.source_index]});
                    } else if (parameter.scalar == .pointer) {
                        try writeCgoHandleArgument(writer, parameter.scalar, go_names[parameter.source_index]);
                    } else {
                        try writer.writeAll("C.");
                        try type_spelling.writeCgoType(writer, parameter.scalar);
                        try writer.print("({s})", .{go_names[parameter.source_index]});
                    }
                },
                .slice_pointer => try writer.print("{s}Ptr", .{go_names[parameter.source_index]}),
                .slice_length => if (function.materializesParam(parameter.source_index))
                    try writer.print("C.size_t({s})", .{go_names[parameter.source_index]})
                else if (semantic.isOptionalSlice(function.origin.params[parameter.source_index].type))
                    try writer.print("{s}Len", .{go_names[parameter.source_index]})
                else
                    try writer.print("C.size_t(len({s}))", .{go_names[parameter.source_index]}),
                .slice_written => try writer.print("&{s}Written", .{go_names[parameter.source_index]}),
                .string_data => try writer.print("{s}DataPtr", .{go_names[parameter.source_index]}),
                .string_data_length => try writer.print("C.size_t(len({s}Data))", .{go_names[parameter.source_index]}),
                .string_lengths => try writer.print("{s}LensPtr", .{go_names[parameter.source_index]}),
                .string_count => try writer.print("C.size_t(len({s}))", .{go_names[parameter.source_index]}),
                .payload_out => try writer.writeAll("&outResult"),
                .optional_in => try writer.print("{s}Ptr", .{go_names[parameter.source_index]}),
                .payload_has_out => try writer.writeAll("&outResultHas"),
                .return_slice_pointer => try writer.writeAll("&outResultPtr"),
                .return_slice_length => try writer.writeAll("&outResultLen"),
                // cgo binds the trampoline by its `//export` name inside the
                // shim, so nothing about it travels in the call.
                .stream_callback => unreachable,
                // The byte-slice fast path: non-NULL when the Go reader could
                // hand its remaining bytes over whole, and then the shim wraps
                // them with `Reader.fixed` instead of calling the trampoline.
                // Go owns the word and hands over its address; cgo allows it
                // because the memory holds no Go pointers, and the call is the
                // whole of the time it has to stay valid.
                .cancel_flag => try writer.print("(*C.uint32_t)(unsafe.Pointer({s}))", .{go_names[parameter.source_index]}),
                .atomic_ptr => {
                    try writer.writeAll("(*C.");
                    try type_spelling.writeCgoType(writer, parameter.scalar.pointer.child.*);
                    try writer.print(")({s})", .{go_names[parameter.source_index]});
                },
                .stream_data => try writer.print("{s}DataPtr", .{go_names[parameter.source_index]}),
                .stream_data_length => try writer.print("C.size_t(len({s}Data))", .{go_names[parameter.source_index]}),
                .stream_userdata => try writer.print("C.size_t({s}Handle)", .{go_names[parameter.source_index]}),
            }
        }
        try writer.writeByte(')');
        if (returns_error) try writer.writeByte(')');
        if (!returns_error and (function.ret_string == .c_string)) try writer.writeByte(')');
        if (!returns_error and function.origin.@"return" != .void and
            function.origin.@"return" != .slice and function.ret_struct == null and !function.ret_optional and
            function.slice_return_element == null) try writer.writeByte(')');
        if (!returns_error and function.ret_optional) try writer.writeAll(" != 0");
        try writer.writeByte('\n');
        if (!returns_error) {
            if (function.slice_return_element) |element| {
                const optional = returnsOptionalSlice(function);
                if (optional) try writeSliceAbsentReturn(writer, "outResultPtr", "");
                try writeCgoSliceReturn(allocator, writer, program, element, "outResultPtr", "outResultLen", function.ownership.asBuffer(), if (optional) ", true" else "");
            } else if (function.materialized_out != null) {
                const byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
                try writeCgoSliceReturn(allocator, writer, program, byte, "outResultPtr", "outResultLen", function.ownership.asBuffer(), ", written");
            } else if (function.ret_optional) {
                try writer.writeAll("\treturn ");
                if (function.ret_struct) |record| {
                    try writeCgoStructRead(allocator, writer, program, record.*, "\t", "outResult");
                } else {
                    try public_writers.writeRawConversionPrefix(writer, program, function.origin.@"return".optional.child.*);
                    try writer.writeAll("outResult)");
                }
                try writer.writeAll(", outResultHas\n");
            }
        }
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .slice or parameter.direction != .out or parameter.type.slice.element.* != .value_struct) continue;
            // A castable element was written straight into the caller's slice.
            if (program.structCastable(parameter.type.slice.element.*.value_struct.ref)) continue;
            const slice_name = go_names[parameter_index];
            const c_values_name = try std.fmt.allocPrint(allocator, "{s}Values", .{slice_name});
            defer allocator.free(c_values_name);
            const c_name = try std.fmt.allocPrint(allocator, "c{s}", .{slice_name});
            defer allocator.free(c_name);
            const c_value_name = try std.fmt.allocPrint(allocator, "{s}[i]", .{c_values_name});
            defer allocator.free(c_value_name);
            const record = structRecord(program, parameter.type.slice.element.*.value_struct.ref);
            // `.all` reads the count out of the `_written` out parameter;
            // `.return` has none, and the count is the call's own result.
            const written_count = if (parameter.writtenHint() == .all)
                try std.fmt.allocPrint(allocator, "int({s}Written)", .{slice_name})
            else
                try allocator.dupe(u8, if (returns_error) "int(outResult)" else "int(result)");
            defer allocator.free(written_count);
            try writer.print("\tfor i := 0; i < {s} && i < len({s}); i++ {{\n\t\t{s}[i] = ", .{ written_count, slice_name, slice_name });
            try writeCgoStructRead(allocator, writer, program, record, "\t\t", c_value_name);
            try writer.writeAll("\n\t}\n");
        }
        if (binds_raw_result and function.materialized_out == null) try writer.writeAll("\treturn result\n");
        if (function.ret_struct != null and !function.ret_optional) {
            try writer.writeAll("\treturn ");
            try writeCgoStructRead(allocator, writer, program, function.ret_struct.?.*, "\t", "outResult");
            try writer.writeByte('\n');
        }
        if (returns_error) {
            if (function.materialized_out != null) {
                try writer.writeAll("\tif code != 0 {\n\t\treturn nil, 0, code\n\t}\n");
                const byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
                try writeCgoSliceReturn(allocator, writer, program, byte, "outResultPtr", "outResultLen", function.ownership.asBuffer(), ", uint(outResult), code");
            } else if (error_payload == .void) {
                try writer.writeAll("\treturn code\n");
            } else if (function.slice_return_element) |element| {
                // The failure path returns before the copy, so the out
                // parameters the shim never wrote are never read -- and a
                // declared release runs only after a successful call.
                try writer.print("\tif code != 0 {{\n\t\treturn nil, {s}code\n\t}}\n", .{if (returnsOptionalSlice(function)) "false, " else ""});
                const optional = returnsOptionalSlice(function);
                if (optional) try writeSliceAbsentReturn(writer, "outResultPtr", ", code");
                try writeCgoSliceReturn(allocator, writer, program, element, "outResultPtr", "outResultLen", function.ownership.asBuffer(), if (optional) ", true, code" else ", code");
            } else if (error_payload == .optional) {
                try writer.writeAll("\treturn ");
                if (function.payload_struct) |record| {
                    try writeCgoStructRead(allocator, writer, program, record.*, "\t", "outResult");
                } else {
                    try public_writers.writeRawConversionPrefix(writer, program, error_payload.optional.child.*);
                    try writer.writeAll("outResult)");
                }
                try writer.writeAll(", outResultHas != 0, code\n");
            } else if (function.payload_struct) |record| {
                try writer.writeAll("\treturn ");
                try writeCgoStructRead(allocator, writer, program, record.*, "\t", "outResult");
                try writer.writeAll(", code\n");
            } else {
                try writer.writeAll("\treturn ");
                try public_writers.writeRawResultConversion(writer, program, error_payload, "outResult", options);
                try writer.writeAll(", code\n");
            }
        }
        try writer.writeAll("}\n");
    }
    try renderRawStructTypes(allocator, writer, program);
    try renderCgoStructLayoutGuards(allocator, writer, program);
    try renderRawSnapshotTypes(allocator, writer, program);
    try renderRawTaggedUnionAccessors(allocator, writer, program, options);
    try renderRawSnapshotAccessors(allocator, writer, program);
}

/// Closes the layout chain the cast path rests on: the Zig ABI guard pins the
/// native struct against the header, and these pin the Go mirror against what
/// cgo made of that header. A mismatch is an index out of range at compile
/// time, naming the struct that drifted.
fn renderCgoStructLayoutGuards(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.structs) |record| {
        if (!record.castable) continue;
        const type_name = try common.structRawTypeNameAlloc(allocator, record.name);
        defer allocator.free(type_name);
        try writer.print(
            "\n// {s} crosses to C as a cast, so it must match {s} byte for byte.\n" ++
                "var _ = [1]struct{{}}{{}}[unsafe.Sizeof({s}{{}})-unsafe.Sizeof(C.{s}{{}})]\n",
            .{ type_name, record.c_name, type_name, record.c_name },
        );
        for (record.fields) |field| {
            const member = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(member);
            try writer.print(
                "var _ = [1]struct{{}}{{}}[unsafe.Offsetof({s}{{}}.{s})-unsafe.Offsetof(C.{s}{{}}.{s})]\n",
                .{ type_name, member, record.c_name, field.name },
            );
        }
    }
}

/// cgo keeps the flattened byte and length arrays in Go memory. Both arrays
/// contain no Go pointers, so the C call can borrow them without allocating a
/// C string for every element.
fn writeCgoStringSliceSetup(writer: *std.Io.Writer, name: []const u8) !void {
    try writer.print(
        "\t{0s}Data, {0s}Lens := zigoStringSliceArgs({0s})\n" ++
            "\t{0s}DataPtr := zigoBytesPtr({0s}Data)\n" ++
            "\t{0s}LensPtr := zigoSizePtr({0s}Lens)\n",
        .{name},
    );
}

pub fn programHasStringSliceParam(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params, 0..) |_, index| if (function.paramString(index).role == .string_slice) return true;
    }
    return false;
}

/// The string marshalling every cgo call shares. Strings and string slices
/// travel in Go memory: a NUL-terminated copy for a C string, one flattened
/// NUL-separated buffer plus a length per element for a slice. None of it
/// holds a Go pointer, so the native call may borrow it for its duration
/// and nothing is allocated on the C heap or freed afterwards.
fn renderCgoStringHelpers(writer: *std.Io.Writer, program: abi.Program) !void {
    if (common.programHasReaderStream(program)) try writer.writeAll(
        "// zigoEmptyStreamData is what a present but empty byte-slice reader points\n" ++
            "// at. The shim tells the fast path from the trampoline path by the pointer\n" ++
            "// being non-NULL, so an empty stream still needs an address.\n" ++
            "var zigoEmptyStreamData byte\n\n",
    );
    if (common.programHasCString(program)) try writer.writeAll(
        "// zigoCString copies value into a NUL-terminated Go buffer the native call\n" ++
            "// may read for its duration.\n" ++
            "func zigoCString(value string) *C.char {\n" ++
            "\tbuffer := make([]byte, len(value)+1)\n" ++
            "\tcopy(buffer, value)\n" ++
            "\treturn (*C.char)(unsafe.Pointer(&buffer[0]))\n" ++
            "}\n\n",
    );
    if (programHasStringSliceParam(program)) try writer.writeAll(
        "// zigoStringSliceArgs flattens values into one NUL-separated byte buffer and\n" ++
            "// a length per element, both in Go memory and free of Go pointers, so the\n" ++
            "// native call borrows them without a C allocation per element.\n" ++
            "func zigoStringSliceArgs(values []string) (data []byte, lens []C.size_t) {\n" ++
            "\tif len(values) == 0 {\n" ++
            "\t\treturn nil, nil\n" ++
            "\t}\n" ++
            "\tlens = make([]C.size_t, len(values))\n" ++
            "\ttotal := 0\n" ++
            "\tfor _, value := range values {\n" ++
            "\t\ttotal += len(value) + 1\n" ++
            "\t}\n" ++
            "\tdata = make([]byte, total)\n" ++
            "\toffset := 0\n" ++
            "\tfor i, value := range values {\n" ++
            "\t\tlens[i] = C.size_t(len(value))\n" ++
            "\t\tcopy(data[offset:], value)\n" ++
            "\t\toffset += len(value) + 1\n" ++
            "\t}\n" ++
            "\treturn data, lens\n" ++
            "}\n\n" ++
            "// The pointers an empty slice passes instead of NULL, so the native side\n" ++
            "// always receives a valid address with a zero length.\n" ++
            "var zigoZeroByte C.uint8_t\n" ++
            "var zigoZeroSize C.size_t\n\n" ++
            "func zigoBytesPtr(data []byte) *C.uint8_t {\n" ++
            "\tif len(data) == 0 {\n" ++
            "\t\treturn &zigoZeroByte\n" ++
            "\t}\n" ++
            "\treturn (*C.uint8_t)(unsafe.Pointer(&data[0]))\n" ++
            "}\n\n" ++
            "func zigoSizePtr(lens []C.size_t) *C.size_t {\n" ++
            "\tif len(lens) == 0 {\n" ++
            "\t\treturn &zigoZeroSize\n" ++
            "\t}\n" ++
            "\treturn (*C.size_t)(unsafe.Pointer(&lens[0]))\n" ++
            "}\n\n",
    );
}

/// A cgo slice return must not expose native memory. `C.GoBytes` is the byte
/// special case; every other element gets a typed Go allocation so the result
/// has the same element type as the raw function signature.
/// True when the function hands back `?[]T` rather than `[]T`. The out
/// pointer being NULL is the absence, so every slice return below only has to
/// answer that question once, before the copy it would otherwise make.
pub fn returnsOptionalSlice(function: abi.AbiFn) bool {
    if (function.slice_return_element == null) return false;
    return switch (function.origin.@"return") {
        .optional => true,
        .error_union => |value| value.payload.* == .optional,
        else => false,
    };
}

/// The `nil, false` early return an optional slice needs before the present
/// path copies anything. `suffix` is whatever the present returns also carry.
pub fn writeSliceAbsentReturn(writer: *std.Io.Writer, pointer_name: []const u8, suffix: []const u8) !void {
    try writer.print("\tif {s} == nil {{ return nil, false{s} }}\n", .{ pointer_name, suffix });
}

fn writeCgoSliceReturn(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    element: semantic.TypeNode,
    pointer_name: []const u8,
    length_name: []const u8,
    /// The ownership record of a buffer the library hands over, or null when
    /// the slice stays library-owned and is only copied.
    buffer: ?abi.Ownership.Buffer,
    /// Appended to every `return` this writes, so a fallible slice return can
    /// hand the error code back alongside the copied payload.
    suffix: []const u8,
) !void {
    if (buffer) |owned| {
        // The payload is copied first and released immediately after, so the
        // returned Go slice never aliases memory the library still owns.
        try writer.print("\tvar result []", .{});
        try public_writers.writeRawGoType(writer, program, element);
        try writer.print("\n\tif {s} != 0 {{\n", .{length_name});
        try writeCgoSliceCopyInto(allocator, writer, program, element, pointer_name, length_name, "\t\t");
        try writer.print("\t}}\n\tC.{s}(", .{program.functions[owned.release].symbol});
        if (owned.release_receiver_c_name) |c_name| try writer.print("(*C.{s})(self), ", .{c_name});
        try writer.print("{s}, {s})\n\treturn result{s}\n", .{ pointer_name, length_name, suffix });
        return;
    }
    // A castable element shares the C layout, so the copy below is one `copy`
    // of the whole run rather than a per-field read. The contract is unchanged:
    // the result is still a fresh Go allocation, never a view of native memory.
    if (element == .value_struct and !program.structCastable(element.value_struct.ref)) {
        const record = structRecord(program, element.value_struct.ref);
        try writer.print("\tif {s} == 0 {{ return nil{s} }}\n\tcResult := unsafe.Slice((*C.{s})(unsafe.Pointer({s})), int({s}))\n\tresult := make([]", .{ length_name, suffix, record.c_name, pointer_name, length_name });
        try public_writers.writeRawGoType(writer, program, element);
        try writer.print(", int({s}))\n\tfor i := range result {{\n\t\tresult[i] = ", .{length_name});
        try writeCgoStructRead(allocator, writer, program, record, "\t\t", "cResult[i]");
        try writer.print("\n\t}}\n\treturn result{s}\n", .{suffix});
        return;
    }
    if (semantic.isByte(element)) {
        try writer.print("\treturn C.GoBytes(unsafe.Pointer({s}), C.int({s})){s}\n", .{ pointer_name, length_name, suffix });
        return;
    }
    try writer.print("\tif {s} == 0 {{ return nil{s} }}\n\tresult := make([]", .{ length_name, suffix });
    try public_writers.writeRawGoType(writer, program, element);
    try writer.print(", int({s}))\n\tcopy(result, unsafe.Slice((*", .{length_name});
    try public_writers.writeRawGoType(writer, program, element);
    try writer.print(")(unsafe.Pointer({s})), int({s})))\n\treturn result{s}\n", .{ pointer_name, length_name, suffix });
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
    // A castable element shares the C layout, so the copy below is one `copy`
    // of the whole run rather than a per-field read. The contract is unchanged:
    // the result is still a fresh Go allocation, never a view of native memory.
    if (element == .value_struct and !program.structCastable(element.value_struct.ref)) {
        const record = structRecord(program, element.value_struct.ref);
        try writer.print("{s}cResult := unsafe.Slice((*C.{s})(unsafe.Pointer({s})), int({s}))\n{s}result = make([]", .{ indent, record.c_name, pointer_name, length_name, indent });
        try public_writers.writeRawGoType(writer, program, element);
        try writer.print(", int({s}))\n{s}for i := range result {{\n{s}\tresult[i] = ", .{ length_name, indent, indent });
        const nested = try std.fmt.allocPrint(allocator, "{s}\t", .{indent});
        defer allocator.free(nested);
        try writeCgoStructRead(allocator, writer, program, record, nested, "cResult[i]");
        try writer.print("\n{s}}}\n", .{indent});
        return;
    }
    if (semantic.isByte(element)) {
        try writer.print("{s}result = C.GoBytes(unsafe.Pointer({s}), C.int({s}))\n", .{ indent, pointer_name, length_name });
        return;
    }
    try writer.print("{s}result = make([]", .{indent});
    try public_writers.writeRawGoType(writer, program, element);
    try writer.print(", int({s}))\n{s}copy(result, unsafe.Slice((*", .{ length_name, indent });
    try public_writers.writeRawGoType(writer, program, element);
    try writer.print(")(unsafe.Pointer({s})), int({s})))\n", .{ pointer_name, length_name });
}

/// The raw layout struct, shared verbatim by both backends: cgo converts into
/// it member by member, purego lets the native call fill it in place.
pub fn renderRawSnapshotTypes(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.snapshots) |snapshot| {
        const type_name = try common.snapshotRawTypeNameAlloc(allocator, snapshot);
        defer allocator.free(type_name);
        try writer.print(
            "\n// {s} mirrors the {s} value snapshot layout, padding included.\ntype {s} struct {{\n",
            .{ type_name, snapshot.type_name, type_name },
        );
        for (snapshot.fields) |field| {
            const go_name = try common.snapshotGoFieldAlloc(allocator, field);
            defer allocator.free(go_name);
            try writer.print("\t{s} ", .{go_name});
            if (field.kind == .padding) {
                try writer.print("[{d}]byte\n", .{field.bytes});
            } else {
                try type_spelling.writeGoScalar(writer, field.scalar);
                try writer.writeByte('\n');
            }
        }
        try writer.writeAll("}\n");
    }
}

pub fn renderRawSnapshotAccessors(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    for (program.snapshots, 0..) |snapshot, snapshot_index| {
        const type_name = try common.snapshotRawTypeNameAlloc(allocator, snapshot);
        defer allocator.free(type_name);
        const function_name = try common.snapshotRawFunctionNameAlloc(allocator, snapshot);
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
        try writer.print("\tstatus := C.{s}((*C.{s})(self), &out)\n", .{ snapshot.symbol, type_spelling.handleRecord(program, snapshot.owner.name).c_name });
        try writer.print("\tif status != 1 {{\n\t\treturn {s}{{}}, uint8(status)\n\t}}\n\treturn {s}{{\n", .{ type_name, type_name });
        for (snapshot.fields) |field| {
            if (field.kind == .padding) continue;
            const go_name = try common.snapshotGoFieldAlloc(allocator, field);
            defer allocator.free(go_name);
            try writer.print("\t\t{s}: ", .{go_name});
            try type_spelling.writeGoScalar(writer, field.scalar);
            try writer.print("(out.{s}),\n", .{field.name});
        }
        try writer.writeAll("\t}, uint8(status)\n}\n");
    }
}

fn renderRawTaggedUnionAccessors(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    for (program.projections) |projection| {
        const declaration = projection.owner.*;
        const union_c_name = type_spelling.handleRecord(program, declaration.name).c_name;
        switch (projection.kind) {
            .tag => {
                try writer.print("\n// {s}ProjectTag returns the active tag and a projection status.\nfunc {s}ProjectTag(self unsafe.Pointer) (", .{ declaration.name, declaration.name });
                try public_writers.writeRawGoType(writer, program, declaration.tag_type.?);
                try writer.writeAll(", uint8) {\n\tvar outValue C.");
                try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, declaration.tag_type.?));
                try writer.writeAll("\n\tstatus := C.");
                try writer.print("{s}((*C.{s})(self), &outValue)\n\treturn ", .{ projection.symbol, union_c_name });
                try public_writers.writeRawGoType(writer, program, declaration.tag_type.?);
                try writer.writeAll("(outValue), uint8(status)\n}\n");
            },
            .payload => {
                const field = projection.field.?.*;
                const payload = field.type.?;
                const field_name = try naming.pascalAlloc(allocator, field.name);
                defer allocator.free(field_name);
                try writer.print("\n// {s}Project{s} returns the payload and a projection status.\nfunc {s}Project{s}(self unsafe.Pointer) (", .{ declaration.name, field_name, declaration.name, field_name });
                try public_writers.writeRawGoType(writer, program, payload);
                try writer.writeAll(", uint8) {\n");
                if (payload == .slice) {
                    try writer.writeAll("\tvar outValuePtr *C.");
                    try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, payload.slice.element.*));
                    try writer.writeAll("\n\tvar outValueLen C.size_t\n\tstatus := C.");
                    try writer.print("{s}((*C.{s})(self), &outValuePtr, &outValueLen)\n", .{ projection.symbol, union_c_name });
                    try writer.writeAll("\tif status != 1 {\n\t\treturn nil, uint8(status)\n\t}\n");
                    if (semantic.isByte(payload.slice.element.*)) {
                        try writer.writeAll("\treturn C.GoBytes(unsafe.Pointer(outValuePtr), C.int(outValueLen)), uint8(status)\n");
                    } else {
                        try writer.writeAll("\tif outValueLen == 0 { return nil, uint8(status) }\n\tresult := make([]");
                        try public_writers.writeRawGoType(writer, program, payload.slice.element.*);
                        try writer.writeAll(", int(outValueLen))\n\tcopy(result, unsafe.Slice((*");
                        try public_writers.writeRawGoType(writer, program, payload.slice.element.*);
                        try writer.writeAll(")(unsafe.Pointer(outValuePtr)), int(outValueLen)))\n\treturn result, uint8(status)\n");
                    }
                } else {
                    if (payload == .opaque_ptr) {
                        try writer.print("\tvar outValue *C.{s}\n", .{type_spelling.handleRecord(program, payload.opaque_ptr.ref).c_name});
                    } else {
                        try writer.writeAll("\tvar outValue C.");
                        try type_spelling.writeCgoType(writer, type_spelling.semanticScalar(program, payload));
                        try writer.writeByte('\n');
                    }
                    try writer.print("\tstatus := C.{s}((*C.{s})(self), &outValue)\n\tif status != 1 {{\n\t\treturn ", .{ projection.symbol, union_c_name });
                    try writer.writeAll(type_spelling.rawGoZero(payload));
                    try writer.writeAll(", uint8(status)\n\t}\n\treturn ");
                    try public_writers.writeRawResultConversion(writer, program, payload, "outValue", options);
                    try writer.writeAll(", uint8(status)\n");
                }
                try writer.writeAll("}\n");
            },
        }
    }
}

/// A handle argument crosses cgo as the header's typedef pointer, converted
/// from the unsafe.Pointer the raw signature carries; anything else passes
/// as it is.
pub fn writeCgoHandleArgument(writer: *std.Io.Writer, scalar: abi.AbiScalar, name: []const u8) !void {
    if (scalar == .pointer and scalar.pointer.child.* == .@"opaque") {
        try writer.print("(*C.{s})({s})", .{ scalar.pointer.child.@"opaque".c_name, name });
        return;
    }
    try writer.writeAll(name);
}
