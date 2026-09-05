//! Materialized result trees: the Zig walker that serializes them and the Go
//! decoder that reads them back.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");
const common = @import("common.zig");
const emit = @import("emit.zig");
const public_writers = @import("public_writers.zig");
const shim = @import("shim.zig");

pub fn renderMaterializedWalker(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    if (program.materialized_layouts.len == 0) return;
    try writer.print(
        "pub const ZigoMaterializedBuilder = struct {{\n" ++
            "    allocator: std.mem.Allocator,\n" ++
            "    bytes: std.ArrayList(u8) = .empty,\n\n" ++
            "    pub fn init(allocator: std.mem.Allocator) !ZigoMaterializedBuilder {{\n" ++
            "        var self: ZigoMaterializedBuilder = .{{ .allocator = allocator }};\n" ++
            "        try self.bytes.appendNTimes(allocator, 0, {d});\n" ++
            "        self.writeU64(0, 0x0001_4f47495a);\n" ++
            "        return self;\n" ++
            "    }}\n" ++
            "    pub fn deinit(self: *ZigoMaterializedBuilder) void {{\n" ++
            "        self.bytes.deinit(self.allocator);\n" ++
            "    }}\n" ++
            "    fn reserveArray(self: *ZigoMaterializedBuilder, count: usize, stride: usize) !usize {{\n" ++
            "        return self.reserve(try std.math.mul(usize, count, stride));\n" ++
            "    }}\n" ++
            "    fn reserve(self: *ZigoMaterializedBuilder, count: usize) !usize {{\n" ++
            "        const offset = self.bytes.items.len;\n" ++
            "        try self.bytes.appendNTimes(self.allocator, 0, count);\n" ++
            "        return offset;\n" ++
            "    }}\n" ++
            "    fn writeU64(self: *ZigoMaterializedBuilder, offset: usize, value: u64) void {{\n" ++
            "        std.mem.writeInt(u64, self.bytes.items[offset..][0..8], value, .little);\n" ++
            "    }}\n" ++
            "    fn appendBytes(self: *ZigoMaterializedBuilder, value: []const u8) !u64 {{\n" ++
            "        const offset = self.bytes.items.len;\n" ++
            "        try self.bytes.appendSlice(self.allocator, value);\n" ++
            "        return @intCast(offset);\n" ++
            "    }}\n" ++
            "    pub fn finish(self: *ZigoMaterializedBuilder, layout: u32, count: usize, root: usize) ![]u8 {{\n" ++
            "        self.writeU64(8, layout);\n" ++
            "        self.writeU64(16, count);\n" ++
            "        self.writeU64(24, root);\n" ++
            "        self.writeU64(32, self.bytes.items.len);\n" ++
            "        return self.bytes.toOwnedSlice(self.allocator);\n" ++
            "    }}\n" ++
            "}};\n\n" ++
            "fn zigoMaterializedScalar(value: anytype) u64 {{\n" ++
            "    const T = @TypeOf(value);\n" ++
            "    return switch (@typeInfo(T)) {{\n" ++
            "        .bool => @intFromBool(value),\n" ++
            "        .int => @intCast(@as(std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(value))),\n" ++
            "        .float => @intCast(@as(std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(value))),\n" ++
            "        .@\"enum\" => zigoMaterializedScalar(@intFromEnum(value)),\n" ++
            "        else => unreachable,\n" ++
            "    }};\n" ++
            "}}\n\n",
        .{abi.MaterializedLayout.header_size},
    );
    for (program.materialized_layouts) |layout| {
        const function_name = try materializedEncoderNameAlloc(allocator, layout.owner.name);
        defer allocator.free(function_name);
        try writer.print("pub fn {s}(builder: *ZigoMaterializedBuilder, value: ", .{function_name});
        try common.writeTargetType(writer, program, layout.owner.name);
        try writer.print(") !u64 {{\n    const record = try builder.reserve({d});\n", .{layout.record_size});
        for (layout.fields) |field| try writeMaterializedField(allocator, writer, field, "value", "record");
        try writer.writeAll("    return @intCast(record);\n}\n\n");
        try writer.print(
            "pub fn {0s}Buffer(allocator: std.mem.Allocator, value: anytype, comptime is_slice: bool) ![]u8 {{\n" ++
                "    var builder = try ZigoMaterializedBuilder.init(allocator);\n" ++
                "    defer builder.deinit();\n" ++
                "    if (is_slice) {{\n" ++
                "        const roots = try builder.reserveArray(value.len, 8);\n" ++
                "        for (value, 0..) |item, index| builder.writeU64(roots + index * 8, try {0s}(&builder, item));\n" ++
                "        return builder.finish({1d}, value.len, roots);\n" ++
                "    }} else {{\n" ++
                "        const root = try {0s}(&builder, value);\n" ++
                "        return builder.finish({1d}, 1, @intCast(root));\n" ++
                "    }}\n}}\n\n",
            .{ function_name, layout.id },
        );
    }
}

fn writeMaterializedField(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    field: abi.MaterializedLayout.Field,
    value: []const u8,
    record: []const u8,
) !void {
    const expression = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ value, field.name });
    defer allocator.free(expression);
    const slot = try std.fmt.allocPrint(allocator, "{s} + {d}", .{ record, field.offset });
    defer allocator.free(slot);
    switch (field.kind) {
        .scalar => try writer.print("    builder.writeU64({s}, zigoMaterializedScalar({s}));\n", .{ slot, expression }),
        .string => try writer.print("    builder.writeU64({0s}, try builder.appendBytes({1s}));\n    builder.writeU64({0s} + 8, {1s}.len);\n", .{ slot, expression }),
        .scalar_slice => {
            try writer.print("    const {0s}_data = try builder.reserveArray({1s}.len, 8);\n    for ({1s}, 0..) |item, index| builder.writeU64({0s}_data + index * 8, zigoMaterializedScalar(item));\n    builder.writeU64({2s}, {0s}_data);\n    builder.writeU64({2s} + 8, {1s}.len);\n", .{ field.name, expression, slot });
        },
        .string_slice => {
            try writer.print("    const {0s}_data = try builder.reserveArray({1s}.len, 16);\n    for ({1s}, 0..) |item, index| {{\n        builder.writeU64({0s}_data + index * 16, try builder.appendBytes(item));\n        builder.writeU64({0s}_data + index * 16 + 8, item.len);\n    }}\n    builder.writeU64({2s}, {0s}_data);\n    builder.writeU64({2s} + 8, {1s}.len);\n", .{ field.name, expression, slot });
        },
        .node => {
            const name = try materializedEncoderNameAlloc(allocator, field.node.materialized.ref);
            defer allocator.free(name);
            try writer.print("    builder.writeU64({s}, try {s}(builder, {s}));\n", .{ slot, name, expression });
        },
        .node_pointer => {
            const node = field.node.materialized;
            const name = try materializedEncoderNameAlloc(allocator, node.ref);
            defer allocator.free(name);
            if (node.nullable)
                try writer.print("    builder.writeU64({s}, if ({s}) |item| try {s}(builder, item.*) else 0);\n", .{ slot, expression, name })
            else
                try writer.print("    builder.writeU64({s}, try {s}(builder, {s}.*));\n", .{ slot, name, expression });
        },
        .node_slice => {
            const name = try materializedEncoderNameAlloc(allocator, field.node.slice.element.materialized.ref);
            defer allocator.free(name);
            try writer.print("    const {0s}_nodes = try builder.reserveArray({1s}.len, 8);\n    for ({1s}, 0..) |item, index| builder.writeU64({0s}_nodes + index * 8, try {2s}(builder, item));\n    builder.writeU64({3s}, {0s}_nodes);\n    builder.writeU64({3s} + 8, {1s}.len);\n", .{ field.name, expression, name, slot });
        },
    }
}

fn materializedEncoderNameAlloc(allocator: std.mem.Allocator, type_name: []const u8) ![]u8 {
    const snake = try naming.snakeAlloc(allocator, type_name);
    defer allocator.free(snake);
    return std.fmt.allocPrint(allocator, "zigoMaterialize_{s}", .{snake});
}

/// Every materialization step allocates into the same builder, so they all
/// fail the same way. Naming the panic once keeps the eleven emit sites from
/// drifting apart in wording.
pub const materialize_oom = "catch @panic(\"zigo: materialization allocation failed\")";

pub fn writeMaterializedReturn(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    function: abi.AbiFn,
    materialized: abi.AbiFn.MaterializedReturn,
) !void {
    try writer.writeAll("const result = ");
    try shim.writeTargetCall(allocator, writer, program, function);
    if (materialized.fallible) try shim.writeShimErrorCatch(writer, function) else try writer.writeAll(";\n");
    const encoder = try materializedEncoderNameAlloc(allocator, materialized.root);
    defer allocator.free(encoder);
    try writer.print("    const buffer = {s}Buffer({s}, result, {}) " ++ materialize_oom ++ ";\n", .{ encoder, program.allocator orelse "std.heap.c_allocator", materialized.is_slice });
    try writer.writeAll("    out_result_ptr.* = buffer.ptr;\n    out_result_len.* = buffer.len;\n");
    if (materialized.fallible) try writer.writeAll("    return 0;\n");
    try writer.writeAll("}\n");
}

pub fn writeMaterializedOutput(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    program: abi.Program,
    function: abi.AbiFn,
    output: abi.AbiFn.MaterializedOut,
) !void {
    const parameter = function.origin.params[output.source_index];
    try writer.writeAll("const result = ");
    try shim.writeTargetCall(allocator, writer, program, function);
    if (output.fallible) try shim.writeShimErrorCatch(writer, function) else try writer.writeAll(";\n");
    try writer.print("    const written = @min(result, {s}_len);\n", .{parameter.name});
    const encoder = try materializedEncoderNameAlloc(allocator, output.root);
    defer allocator.free(encoder);
    // The C panic bridge does not unwind Zig defers. Free staging storage
    // explicitly after the helper has cleaned up its partial buffer.
    try writer.print("    const buffer = {s}Buffer({s}, zigo_{s}_slice[0..written], true) catch {{\n        {s}.free(zigo_{s}_slice);\n        @panic(\"zigo: materialization allocation failed\");\n    }};\n", .{ encoder, program.allocator orelse "std.heap.c_allocator", parameter.name, program.allocator orelse "std.heap.c_allocator", parameter.name });
    try writer.writeAll("    out_result_ptr.* = buffer.ptr;\n    out_result_len.* = buffer.len;\n");
    if (output.fallible) {
        try writer.writeAll("    out_written.* = result;\n    return 0;\n");
    } else {
        try writer.writeAll("    return result;\n");
    }
    try writer.writeAll("}\n");
}

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
