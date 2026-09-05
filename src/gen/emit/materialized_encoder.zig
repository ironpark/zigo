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
        try target_types.writeTargetType(writer, program, layout.owner.name);
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
            try writer.print("    const {0s}_data = try builder.reserveArray({1s}.len, {3d});\n    for ({1s}, 0..) |item, index| builder.writeU64({0s}_data + index * {3d}, zigoMaterializedScalar(item));\n    builder.writeU64({2s}, {0s}_data);\n    builder.writeU64({2s} + 8, {1s}.len);\n", .{ field.name, expression, slot, field.kind.elementStride() });
        },
        .string_slice => {
            try writer.print("    const {0s}_data = try builder.reserveArray({1s}.len, {3d});\n    for ({1s}, 0..) |item, index| {{\n        builder.writeU64({0s}_data + index * {3d}, try builder.appendBytes(item));\n        builder.writeU64({0s}_data + index * {3d} + 8, item.len);\n    }}\n    builder.writeU64({2s}, {0s}_data);\n    builder.writeU64({2s} + 8, {1s}.len);\n", .{ field.name, expression, slot, field.kind.elementStride() });
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
            try writer.print("    const {0s}_nodes = try builder.reserveArray({1s}.len, {4d});\n    for ({1s}, 0..) |item, index| builder.writeU64({0s}_nodes + index * {4d}, try {2s}(builder, item));\n    builder.writeU64({3s}, {0s}_nodes);\n    builder.writeU64({3s} + 8, {1s}.len);\n", .{ field.name, expression, name, slot, field.kind.elementStride() });
        },
    }
}

pub fn materializedEncoderNameAlloc(allocator: std.mem.Allocator, type_name: []const u8) ![]u8 {
    const snake = try naming.snakeAlloc(allocator, type_name);
    defer allocator.free(snake);
    return std.fmt.allocPrint(allocator, "zigoMaterialize_{s}", .{snake});
}
