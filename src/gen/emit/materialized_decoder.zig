//! Go owned-snapshot types and checked decoding of lowered layouts.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");
const emit = @import("emit.zig");
const public_writers = @import("public_writers.zig");

fn writeMaterializedPublicType(scope: public_writers.PublicScope, writer: *std.Io.Writer, node: semantic.TypeNode) !void {
    if (node == .slice) {
        const element = node.slice.element.*;
        if (semantic.isByte(element)) return writer.writeAll("string");
        if (element == .slice and semantic.isByte(element.slice.element.*)) return writer.writeAll("[]string");
        try writer.writeAll("[]");
        return writeMaterializedPublicType(scope, writer, element);
    }
    try public_writers.writePublicGoType(scope, writer, node);
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
            try writeMaterializedPublicType(scope, writer, field.node);
            try writer.writeByte('\n');
        }
        try writer.writeAll("}\n\n");
    }
    if (!any) return;
    try writer.writeAll(
        "const zigoMaterializedMagicVersion = uint64(0x00014f47495a)\n\n" ++
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
        try renderMaterializedDecoder(allocator, writer, program, options, layout);
    }
}

fn renderMaterializedDecoder(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options, layout: abi.MaterializedLayout) !void {
    const scope: public_writers.PublicScope = .{ .program = program, .options = options };
    const public_name = try scope.typeNameAlloc(allocator, layout.owner.name);
    defer allocator.free(public_name);
    if (options.emitsHelperFmt("zigoDecode{s}Buffer", .{layout.owner.name})) try writer.print(
        "func zigoDecode{s}Buffer(buffer []byte) {s} {{\n\toffset, count := zigoMaterializedHeader(buffer, {d})\n\tif count != 1 {{ panic(\"zigo: invalid materialized result buffer\") }}\n\treturn zigoDecode{s}At(buffer, offset)\n}}\n\n",
        .{ layout.owner.name, public_name, layout.id, layout.owner.name },
    );
    if (options.emitsHelperFmt("zigoDecode{s}SliceBuffer", .{layout.owner.name})) try writer.print(
        "func zigoDecode{s}SliceBuffer(buffer []byte) []{s} {{\n\toffset, count := zigoMaterializedHeader(buffer, {d})\n\t_ = zigoMaterializedArray(buffer, offset, count, 8)\n\tresult := make([]{s}, int(count))\n\tfor i := range result {{ result[i] = zigoDecode{s}At(buffer, zigoMaterializedU64(buffer, offset+uint64(i)*8)) }}\n\treturn result\n}}\n\n",
        .{ layout.owner.name, public_name, layout.id, public_name, layout.owner.name },
    );
    try writer.print("func zigoDecode{s}At(buffer []byte, offset uint64) {s} {{\n\t_ = zigoMaterializedBytes(buffer, offset, {d})\n\tvar result {s}\n", .{ layout.owner.name, public_name, layout.record_size, public_name });
    for (layout.fields) |field| try writeMaterializedDecodeField(allocator, writer, program, options, field);
    try writer.writeAll("\treturn result\n}\n\n");
}

fn writeMaterializedDecodeField(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options, field: abi.MaterializedLayout.Field) !void {
    const scope: public_writers.PublicScope = .{ .program = program, .options = options };
    const member = try naming.pascalAlloc(allocator, field.name);
    defer allocator.free(member);
    try writer.print("\tzigo{s}Offset := zigoMaterializedU64(buffer, offset+{d})\n", .{ member, field.offset });
    switch (field.kind) {
        .scalar_slice, .string_slice, .node_slice => try writer.print(
            "\t_ = zigoMaterializedArray(buffer, zigo{s}Offset, zigoMaterializedU64(buffer, offset+{d}), {d})\n",
            .{ member, field.offset + 8, @as(u8, if (field.kind == .string_slice) 16 else 8) },
        ),
        else => {},
    }
    switch (field.kind) {
        .scalar => {
            try writer.print("\tresult.{s} = ", .{member});
            switch (field.node) {
                .bool => try writer.print("zigo{s}Offset != 0", .{member}),
                .int => try public_writers.writePublicGoType(scope, writer, field.node),
                .float => |value| try writer.print("math.Float{d}frombits(uint{d}(zigo{s}Offset))", .{ value.bits, value.bits, member }),
                .@"enum" => |value| {
                    try scope.writeTypeName(writer, value.ref);
                    try writer.print("(zigo{s}Offset)", .{member});
                },
                else => unreachable,
            }
            if (field.node == .int) try writer.print("(zigo{s}Offset)", .{member});
            try writer.writeByte('\n');
        },
        .string => try writer.print("\tzigo{s}Count := zigoMaterializedU64(buffer, offset+{d})\n\tresult.{s} = string(zigoMaterializedBytes(buffer, zigo{s}Offset, zigo{s}Count))\n", .{ member, field.offset + 8, member, member, member }),
        .scalar_slice => {
            try writer.print("\tzigo{s}Count := zigoMaterializedU64(buffer, offset+{d})\n\tresult.{s} = make(", .{ member, field.offset + 8, member });
            try writeMaterializedPublicType(scope, writer, field.node);
            try writer.print(", int(zigo{s}Count))\n\tfor i := range result.{s} {{\n\t\tzigoValue := zigoMaterializedU64(buffer, zigo{s}Offset+uint64(i)*8)\n\t\tresult.{s}[i] = ", .{ member, member, member, member });
            const element = field.node.slice.element.*;
            switch (element) {
                .bool => try writer.writeAll("zigoValue != 0"),
                .float => |value| try writer.print("math.Float{d}frombits(uint{d}(zigoValue))", .{ value.bits, value.bits }),
                .@"enum" => |value| {
                    try scope.writeTypeName(writer, value.ref);
                    try writer.writeAll("(zigoValue)");
                },
                else => {
                    try public_writers.writePublicGoType(scope, writer, element);
                    try writer.writeAll("(zigoValue)");
                },
            }
            try writer.writeAll("\n\t}\n");
        },
        .string_slice => try writer.print("\tzigo{s}Count := zigoMaterializedU64(buffer, offset+{d})\n\tresult.{s} = make([]string, int(zigo{s}Count))\n\tfor i := range result.{s} {{\n\t\tzigoItem := zigo{s}Offset + uint64(i)*16\n\t\tresult.{s}[i] = string(zigoMaterializedBytes(buffer, zigoMaterializedU64(buffer, zigoItem), zigoMaterializedU64(buffer, zigoItem+8)))\n\t}}\n", .{ member, field.offset + 8, member, member, member, member, member }),
        .node => try writer.print("\tresult.{s} = zigoDecode{s}At(buffer, zigo{s}Offset)\n", .{ member, field.node.materialized.ref, member }),
        .node_pointer => {
            if (field.node.materialized.nullable) try writer.print("\tif zigo{s}Offset != 0 {{\n", .{member});
            try writer.print("\tzigo{s}Value := zigoDecode{s}At(buffer, zigo{s}Offset)\n\tresult.{s} = &zigo{s}Value\n", .{ member, field.node.materialized.ref, member, member, member });
            if (field.node.materialized.nullable) try writer.writeAll("\t}\n");
        },
        .node_slice => try writer.print("\tzigo{s}Count := zigoMaterializedU64(buffer, offset+{d})\n\tresult.{s} = make([]{s}, int(zigo{s}Count))\n\tfor i := range result.{s} {{ result.{s}[i] = zigoDecode{s}At(buffer, zigoMaterializedU64(buffer, zigo{s}Offset+uint64(i)*8)) }}\n", .{ member, field.offset + 8, member, field.node.slice.element.materialized.ref, member, member, member, field.node.slice.element.materialized.ref, member }),
    }
}
