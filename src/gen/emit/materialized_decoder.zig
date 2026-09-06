//! Go owned-snapshot types and checked decoding of lowered layouts.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");
const emit = @import("emit.zig");
const public_writers = @import("public_writers.zig");
const type_spelling = @import("type_spelling.zig");

/// The Go type of a field or nested element. `?T` is `*T` as everywhere in
/// the public API; byte slices are `string` unless the field asked for
/// `[]byte`; other slices nest as Go slices.
fn writeShapeGoType(scope: public_writers.PublicScope, writer: *std.Io.Writer, shape: abi.MaterializedLayout.Shape, node: semantic.TypeNode) !void {
    switch (shape) {
        .string => |string| {
            if (string.nullable) try writer.writeByte('*');
            try writer.writeAll(if (string.bytes) "[]byte" else "string");
        },
        .optional => |child| {
            try writer.writeByte('*');
            try writeShapeGoType(scope, writer, child.*, node.optional.child.*);
        },
        .sequence => |element| {
            try writer.writeAll("[]");
            try writeShapeGoType(scope, writer, element.*, node.slice.element.*);
        },
        .node => |value| {
            if (value.pointer or value.nullable) try writer.writeByte('*');
            try scope.writeTypeName(writer, value.ref);
        },
        .scalar, .value_struct => try public_writers.writePublicGoType(scope, writer, node),
    }
}

pub fn renderPublicMaterializedStructs(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    const scope: public_writers.PublicScope = .{ .program = program, .options = options };
    const used = try allocator.alloc(bool, program.materialized_layouts.len);
    defer allocator.free(used);
    for (program.materialized_layouts, used) |layout, *flag| flag.* = options.emitsHelper(layout.owner.name);
    var any = false;
    for (program.materialized_layouts, used) |layout, is_used| {
        if (!is_used) continue;
        if (!public_writers.typeBelongsToPackage(program, layout.owner.name, options.active_package)) continue;
        any = true;
        try writer.print("// {s} is an owned Go snapshot of the Zig struct of the same name.\ntype {s} struct {{\n", .{ layout.owner.name, layout.owner.name });
        for (layout.fields) |field| {
            const member = try naming.pascalAlloc(allocator, field.name);
            defer allocator.free(member);
            try writer.print("\t{s} ", .{member});
            try writeShapeGoType(scope, writer, field.shape, field.node);
            try writer.writeByte('\n');
        }
        try writer.writeAll("}\n\n");
    }
    if (!any) return;
    try writer.writeAll(
        "const zigoMaterializedMagicVersion = uint64(0x00024f47495a)\n\n" ++
            "func zigoMaterializedU64(buffer []byte, offset uint64) uint64 {\n" ++
            "\tif offset > uint64(len(buffer)) || uint64(len(buffer))-offset < 8 {\n" ++
            "\t\tpanic(\"zigo: invalid materialized result buffer\")\n" ++
            "\t}\n" ++
            "\treturn binary.LittleEndian.Uint64(buffer[int(offset):int(offset)+8])\n" ++
            "}\n\n" ++
            "func zigoMaterializedBytes(buffer []byte, offset, length uint64) []byte {\n" ++
            "\tif offset > uint64(len(buffer)) || length > uint64(len(buffer))-offset {\n" ++
            "\t\tpanic(\"zigo: invalid materialized result buffer\")\n" ++
            "\t}\n" ++
            "\treturn buffer[int(offset):int(offset+length)]\n" ++
            "}\n\n",
    );
    if (options.emitsHelper("zigoMaterializedWord")) try writer.writeAll(
        "// zigoMaterializedWord reads a little-endian value of width bytes.\n" ++
            "func zigoMaterializedWord(buffer []byte, offset, width uint64) uint64 {\n" ++
            "\tvar value uint64\n" ++
            "\tfor i, b := range zigoMaterializedBytes(buffer, offset, width) {\n" ++
            "\t\tvalue |= uint64(b) << (8 * uint(i))\n" ++
            "\t}\n" ++
            "\treturn value\n" ++
            "}\n\n",
    );
    if (options.emitsHelper("zigoMaterializedArray")) try writer.writeAll(
        "func zigoMaterializedArray(buffer []byte, offset, count, stride uint64) []byte {\n" ++
            "\tif offset > uint64(len(buffer)) || count > (uint64(len(buffer))-offset)/stride {\n" ++
            "\t\tpanic(\"zigo: invalid materialized result buffer\")\n" ++
            "\t}\n\treturn zigoMaterializedBytes(buffer, offset, count*stride)\n}\n\n",
    );
    try writer.writeAll(
        "func zigoMaterializedHeader(buffer []byte, layout uint64) (uint64, uint64) {\n" ++
            "\tif len(buffer) < 40 || zigoMaterializedU64(buffer, 0) != zigoMaterializedMagicVersion ||\n" ++
            "\tzigoMaterializedU64(buffer, 8) != layout || zigoMaterializedU64(buffer, 32) != uint64(len(buffer)) {\n" ++
            "\t\tpanic(\"zigo: invalid materialized result buffer\")\n" ++
            "\t}\n" ++
            "\treturn zigoMaterializedU64(buffer, 24), zigoMaterializedU64(buffer, 16)\n" ++
            "}\n\n",
    );
    for (program.materialized_layouts, used) |layout, is_used| {
        if (!is_used) continue;
        try renderMaterializedDecoder(allocator, writer, scope, layout);
    }
}

fn renderMaterializedDecoder(allocator: std.mem.Allocator, writer: *std.Io.Writer, scope: public_writers.PublicScope, layout: abi.MaterializedLayout) !void {
    const options = scope.options;
    const public_name = try scope.typeNameAlloc(allocator, layout.owner.name);
    defer allocator.free(public_name);
    if (options.emitsHelperFmt("zigoDecode{s}Buffer", .{layout.owner.name})) try writer.print(
        "func zigoDecode{s}Buffer(buffer []byte) {s} {{\n\toffset, count := zigoMaterializedHeader(buffer, {d})\n\tif count != 1 {{ panic(\"zigo: invalid materialized result buffer\") }}\n\tvar result {s}\n\tzigoDecode{s}Into(buffer, offset, &result)\n\treturn result\n}}\n\n",
        .{ layout.owner.name, public_name, layout.id, public_name, layout.owner.name },
    );
    if (options.emitsHelperFmt("zigoDecode{s}SliceBuffer", .{layout.owner.name})) try writer.print(
        "func zigoDecode{s}SliceBuffer(buffer []byte) []{s} {{\n\toffset, count := zigoMaterializedHeader(buffer, {d})\n\t_ = zigoMaterializedArray(buffer, offset, count, 8)\n\tresult := make([]{s}, int(count))\n\tfor i := range result {{ zigoDecode{s}Into(buffer, zigoMaterializedU64(buffer, offset+uint64(i)*8), &result[i]) }}\n\treturn result\n}}\n\n",
        .{ layout.owner.name, public_name, layout.id, public_name, layout.owner.name },
    );
    try writer.print("func zigoDecode{s}Into(buffer []byte, offset uint64, result *{s}) {{\n\t_ = zigoMaterializedBytes(buffer, offset, {d})\n", .{ layout.owner.name, public_name, layout.record_size });
    for (layout.fields) |field| try writeDecodeField(allocator, writer, scope, field, "result", "offset", 0);
    try writer.writeAll("}\n\n");
}

fn writeDecodeField(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    scope: public_writers.PublicScope,
    field: abi.MaterializedLayout.Field,
    target: []const u8,
    base: []const u8,
    depth: usize,
) !void {
    const member = try naming.pascalAlloc(allocator, field.name);
    defer allocator.free(member);
    const lvalue = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ target, member });
    defer allocator.free(lvalue);
    const offset = try std.fmt.allocPrint(allocator, "{s}+{d}", .{ base, field.offset });
    defer allocator.free(offset);
    try writeDecodeShape(allocator, writer, scope, field.shape, field.node, lvalue, offset, depth);
}

/// Decodes the value stored at byte `offset` into the Go lvalue `target`.
/// Every value the result keeps is copied out of the buffer here, so the
/// caller may release the buffer as soon as decoding returns.
fn writeDecodeShape(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    scope: public_writers.PublicScope,
    shape: abi.MaterializedLayout.Shape,
    node: semantic.TypeNode,
    target: []const u8,
    offset: []const u8,
    depth: usize,
) anyerror!void {
    switch (shape) {
        .scalar => |scalar| {
            const word = if (scalar.width == 8)
                try std.fmt.allocPrint(allocator, "zigoMaterializedU64(buffer, {s})", .{offset})
            else
                try std.fmt.allocPrint(allocator, "zigoMaterializedWord(buffer, {s}, {d})", .{ offset, scalar.width });
            defer allocator.free(word);
            try writer.print("\t{s} = ", .{target});
            try writeScalarConversion(scope, writer, node, word);
            try writer.writeByte('\n');
        },
        .string => |string| {
            const copy = if (string.bytes) "append([]byte(nil), " else "string(";
            if (string.nullable) {
                try writer.print("\t{{\n\tzigoOff{0d} := zigoMaterializedU64(buffer, {1s})\n\tif zigoOff{0d} != 0 {{\n\t\tzigoVal{0d} := {2s}zigoMaterializedBytes(buffer, zigoOff{0d}, zigoMaterializedU64(buffer, {1s}+8)){3s})\n\t\t{4s} = &zigoVal{0d}\n\t}}\n\t}}\n", .{ depth, offset, copy, if (string.bytes) "..." else "", target });
            } else {
                try writer.print("\t{0s} = {1s}zigoMaterializedBytes(buffer, zigoMaterializedU64(buffer, {2s}), zigoMaterializedU64(buffer, {2s}+8)){3s})\n", .{ target, copy, offset, if (string.bytes) "..." else "" });
            }
        },
        .optional => |child| {
            const value = try std.fmt.allocPrint(allocator, "zigoVal{d}", .{depth});
            defer allocator.free(value);
            const child_offset = try std.fmt.allocPrint(allocator, "{s}+{d}", .{ offset, child.alignment() });
            defer allocator.free(child_offset);
            try writer.print("\tif zigoMaterializedWord(buffer, {s}, 1) != 0 {{\n\t\tvar {s} ", .{ offset, value });
            try writeShapeGoType(scope, writer, child.*, node.optional.child.*);
            try writer.writeByte('\n');
            try writeDecodeShape(allocator, writer, scope, child.*, node.optional.child.*, value, child_offset, depth + 1);
            try writer.print("\t\t{s} = &{s}\n\t}}\n", .{ target, value });
        },
        .sequence => |element| {
            const element_node = node.slice.element.*;
            const item = try std.fmt.allocPrint(allocator, "{s}[zigoI{d}]", .{ target, depth });
            defer allocator.free(item);
            const element_offset = try std.fmt.allocPrint(allocator, "zigoOff{d}+uint64(zigoI{d})*{d}", .{ depth, depth, element.stride() });
            defer allocator.free(element_offset);
            // Blocks scope the temporaries so sibling fields can reuse them.
            try writer.print("\t{{\n\tzigoOff{0d} := zigoMaterializedU64(buffer, {1s})\n\tzigoCount{0d} := zigoMaterializedU64(buffer, {1s}+8)\n\t_ = zigoMaterializedArray(buffer, zigoOff{0d}, zigoCount{0d}, {2d})\n\t{3s} = make(", .{ depth, offset, element.stride(), target });
            try writeShapeGoType(scope, writer, shape, node);
            try writer.print(", int(zigoCount{0d}))\n\tfor zigoI{0d} := range {1s} {{\n", .{ depth, target });
            try writeDecodeShape(allocator, writer, scope, element.*, element_node, item, element_offset, depth + 1);
            try writer.writeAll("\t}\n\t}\n");
        },
        .node => |value| {
            try writer.print("\t{{\n\tzigoOff{d} := zigoMaterializedU64(buffer, {s})\n", .{ depth, offset });
            if (value.pointer or value.nullable) {
                if (value.nullable) try writer.print("\tif zigoOff{d} != 0 {{\n", .{depth});
                try writer.print("\tvar zigoVal{d} ", .{depth});
                try scope.writeTypeName(writer, value.ref);
                try writer.print("\n\tzigoDecode{s}Into(buffer, zigoOff{d}, &zigoVal{d})\n\t{s} = &zigoVal{d}\n", .{ value.ref, depth, depth, target, depth });
                if (value.nullable) try writer.writeAll("\t}\n");
            } else {
                try writer.print("\tzigoDecode{s}Into(buffer, zigoOff{d}, &{s})\n", .{ value.ref, depth, target });
            }
            try writer.writeAll("\t}\n");
        },
        .value_struct => |record| for (record.fields) |field| try writeDecodeField(allocator, writer, scope, field, target, offset, depth),
    }
}

/// The Go expression that turns one decoded word into the field's type.
fn writeScalarConversion(scope: public_writers.PublicScope, writer: *std.Io.Writer, node: semantic.TypeNode, source: []const u8) !void {
    switch (node) {
        .bool => try writer.print("{s} != 0", .{source}),
        .int => {
            try public_writers.writePublicGoType(scope, writer, node);
            try writer.print("({s})", .{source});
        },
        .float => |value| try writer.print("math.Float{d}frombits(uint{d}({s}))", .{ value.bits, value.bits, source }),
        .@"enum" => |value| {
            try scope.writeTypeName(writer, value.ref);
            try writer.print("({s})", .{source});
        },
        .value_struct => |value| try writer.print("{s}FromBacking({s}({s}))", .{ value.ref, type_spelling.rawGoTypeName(scope.program, node), source }),
        else => unreachable,
    }
}
