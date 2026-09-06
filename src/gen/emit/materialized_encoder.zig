//! Zig serialization of layouts already decided by lowering.
const target_types = @import("target_types.zig");
const std = @import("std");
const abi = @import("abi");
const naming = @import("naming");
const common = @import("common.zig");

pub fn renderMaterializedWalker(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program) !void {
    if (program.materialized_layouts.len == 0) return;
    try writer.print(
        "pub const ZigoMaterializedBuilder = struct {{\n" ++
            "    allocator: std.mem.Allocator,\n" ++
            "    bytes: std.ArrayList(u8) = .empty,\n\n" ++
            "    pub fn init(allocator: std.mem.Allocator) !ZigoMaterializedBuilder {{\n" ++
            "        var self: ZigoMaterializedBuilder = .{{ .allocator = allocator }};\n" ++
            "        try self.bytes.appendNTimes(allocator, 0, {d});\n" ++
            "        self.writeU64(0, 0x{x});\n" ++
            "        return self;\n" ++
            "    }}\n" ++
            "    pub fn deinit(self: *ZigoMaterializedBuilder) void {{\n" ++
            "        self.bytes.deinit(self.allocator);\n" ++
            "    }}\n" ++
            "    fn reserveArray(self: *ZigoMaterializedBuilder, count: usize, stride: usize) !usize {{\n" ++
            "        return self.reserve(try std.math.mul(usize, count, stride));\n" ++
            "    }}\n" ++
            "    // Records and arrays start 8-aligned so every stored value sits at\n" ++
            "    // its natural alignment relative to the buffer.\n" ++
            "    fn reserve(self: *ZigoMaterializedBuilder, count: usize) !usize {{\n" ++
            "        const padding = (8 - self.bytes.items.len % 8) % 8;\n" ++
            "        try self.bytes.appendNTimes(self.allocator, 0, padding);\n" ++
            "        const offset = self.bytes.items.len;\n" ++
            "        try self.bytes.appendNTimes(self.allocator, 0, count);\n" ++
            "        return offset;\n" ++
            "    }}\n" ++
            "    fn writeU64(self: *ZigoMaterializedBuilder, offset: usize, value: u64) void {{\n" ++
            "        std.mem.writeInt(u64, self.bytes.items[offset..][0..8], value, .little);\n" ++
            "    }}\n" ++
            "    fn writeWord(self: *ZigoMaterializedBuilder, offset: usize, comptime width: u8, value: u64) void {{\n" ++
            "        const Word = std.meta.Int(.unsigned, width * 8);\n" ++
            "        std.mem.writeInt(Word, self.bytes.items[offset..][0..width], @intCast(value), .little);\n" ++
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
            "        .@\"struct\" => |info| zigoMaterializedScalar(@as(info.backing_integer.?, @bitCast(value))),\n" ++
            "        else => unreachable,\n" ++
            "    }};\n" ++
            "}}\n\n",
        .{ abi.MaterializedLayout.header_size, abi.MaterializedLayout.magic },
    );
    for (program.materialized_layouts) |layout| {
        const function_name = try materializedEncoderNameAlloc(allocator, layout.owner.name);
        defer allocator.free(function_name);
        try writer.print("pub fn {s}(builder: *ZigoMaterializedBuilder, value: ", .{function_name});
        try target_types.writeTargetType(writer, program, layout.owner.name);
        try writer.print(") !u64 {{\n    const record = try builder.reserve({d});\n", .{layout.record_size});
        for (layout.fields) |field| try writeField(allocator, writer, field, "value", "record", 0);
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

fn writeField(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    field: abi.MaterializedLayout.Field,
    value: []const u8,
    base: []const u8,
    depth: usize,
) !void {
    const expression = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ value, field.name });
    defer allocator.free(expression);
    const offset = try std.fmt.allocPrint(allocator, "{s} + {d}", .{ base, field.offset });
    defer allocator.free(offset);
    try writeShape(allocator, writer, field.shape, expression, offset, depth);
}

/// Serializes `expression`, whose storage starts at byte `offset`, according
/// to `shape`. Nested shapes get a fresh depth so their temporaries do not
/// shadow the enclosing ones.
fn writeShape(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    shape: abi.MaterializedLayout.Shape,
    expression: []const u8,
    offset: []const u8,
    depth: usize,
) anyerror!void {
    switch (shape) {
        .scalar => |scalar| if (scalar.width == 8)
            try writer.print("    builder.writeU64({s}, zigoMaterializedScalar({s}));\n", .{ offset, expression })
        else
            try writer.print("    builder.writeWord({s}, {d}, zigoMaterializedScalar({s}));\n", .{ offset, scalar.width, expression }),
        .string => |string| if (string.nullable)
            try writer.print("    if ({1s}) |zigo_item{2d}| {{\n        builder.writeU64({0s}, try builder.appendBytes(zigo_item{2d}[0..]));\n        builder.writeU64({0s} + 8, zigo_item{2d}.len);\n    }}\n", .{ offset, expression, depth })
        else
            try writer.print("    builder.writeU64({0s}, try builder.appendBytes({1s}[0..]));\n    builder.writeU64({0s} + 8, {1s}.len);\n", .{ offset, expression }),
        .optional => |child| {
            const item = try std.fmt.allocPrint(allocator, "zigo_item{d}", .{depth});
            defer allocator.free(item);
            const child_offset = try std.fmt.allocPrint(allocator, "{s} + {d}", .{ offset, child.alignment() });
            defer allocator.free(child_offset);
            try writer.print("    if ({s}) |{s}| {{\n        builder.writeWord({s}, 1, 1);\n", .{ expression, item, offset });
            try writeShape(allocator, writer, child.*, item, child_offset, depth + 1);
            try writer.writeAll("    }\n");
        },
        .sequence => |element| {
            const data = try std.fmt.allocPrint(allocator, "zigo_data{d}", .{depth});
            defer allocator.free(data);
            const item = try std.fmt.allocPrint(allocator, "zigo_item{d}", .{depth});
            defer allocator.free(item);
            const element_offset = try std.fmt.allocPrint(allocator, "{s} + zigo_index{d} * {d}", .{ data, depth, element.stride() });
            defer allocator.free(element_offset);
            // Each sequence keeps its temporaries in a block so sibling
            // fields at the same depth can reuse the names.
            try writer.print("    {{\n    const {0s} = try builder.reserveArray({1s}.len, {2d});\n    for ({1s}[0..], 0..) |{3s}, zigo_index{4d}| {{\n", .{ data, expression, element.stride(), item, depth });
            try writeShape(allocator, writer, element.*, item, element_offset, depth + 1);
            try writer.print("    }}\n    builder.writeU64({0s}, {1s});\n    builder.writeU64({0s} + 8, {2s}.len);\n    }}\n", .{ offset, data, expression });
        },
        .node => |node| {
            const name = try materializedEncoderNameAlloc(allocator, node.ref);
            defer allocator.free(name);
            const deref: []const u8 = if (node.pointer) ".*" else "";
            if (node.nullable)
                try writer.print("    builder.writeU64({s}, if ({s}) |zigo_item{d}| try {s}(builder, zigo_item{d}{s}) else 0);\n", .{ offset, expression, depth, name, depth, deref })
            else
                try writer.print("    builder.writeU64({s}, try {s}(builder, {s}{s}));\n", .{ offset, name, expression, deref });
        },
        .value_struct => |record| for (record.fields) |field| try writeField(allocator, writer, field, expression, offset, depth),
    }
}

pub fn materializedEncoderNameAlloc(allocator: std.mem.Allocator, type_name: []const u8) ![]u8 {
    const snake = try naming.snakeAlloc(allocator, type_name);
    defer allocator.free(snake);
    return std.fmt.allocPrint(allocator, "zigoMaterialize_{s}", .{snake});
}
