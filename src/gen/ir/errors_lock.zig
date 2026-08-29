const std = @import("std");

pub const ErrorCode = struct {
    code: i32,
    name: []const u8,
};

pub const ErrorsLock = struct {
    codes: std.ArrayList(ErrorCode) = .empty,
    ir_version: u32 = 1,
    next_code: i32 = 1,

    pub fn deinit(self: *ErrorsLock, allocator: std.mem.Allocator) void {
        for (self.codes.items) |entry| allocator.free(entry.name);
        self.codes.deinit(allocator);
        self.* = undefined;
    }

    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !ErrorsLock {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
        defer parsed.deinit();
        const root = switch (parsed.value) {
            .object => |object| object,
            else => return error.UnexpectedToken,
        };
        var result: ErrorsLock = .{
            .ir_version = @intCast(try integerField(root, "ir_version")),
            .next_code = @intCast(try integerField(root, "next_code")),
        };
        errdefer result.deinit(allocator);
        if (result.next_code <= 0) return error.ReservedErrorCode;
        const codes = switch (root.get("codes") orelse return error.MissingField) {
            .object => |object| object,
            else => return error.UnexpectedToken,
        };
        var iterator = codes.iterator();
        var maximum_code: i32 = 0;
        while (iterator.next()) |entry| {
            const code: i32 = @intCast(switch (entry.value_ptr.*) {
                .integer => |value| value,
                else => return error.UnexpectedToken,
            });
            if (code <= 0) return error.ReservedErrorCode;
            for (result.codes.items) |existing| if (existing.code == code) return error.DuplicateErrorCode;
            const name = try allocator.dupe(u8, entry.key_ptr.*);
            errdefer allocator.free(name);
            try result.codes.append(allocator, .{ .name = name, .code = code });
            maximum_code = @max(maximum_code, code);
        }
        if (result.next_code <= maximum_code) return error.ErrorCodeWouldBeReused;
        return result;
    }

    pub fn assign(self: *ErrorsLock, allocator: std.mem.Allocator, names: []const []const u8) !void {
        for (names) |name| {
            if (self.find(name) != null) continue;
            if (self.next_code <= 0) return error.ReservedErrorCode;
            const owned_name = try allocator.dupe(u8, name);
            errdefer allocator.free(owned_name);
            try self.codes.append(allocator, .{ .name = owned_name, .code = self.next_code });
            self.next_code = std.math.add(i32, self.next_code, 1) catch return error.ErrorCodeExhausted;
        }
    }

    pub fn validateAgainst(self: ErrorsLock, baseline: ErrorsLock) !void {
        if (self.next_code < baseline.next_code) return error.ErrorMappingChanged;
        for (self.codes.items, 0..) |entry, index| {
            if (entry.code <= 0 or entry.code >= self.next_code) return error.ErrorMappingChanged;
            for (self.codes.items[index + 1 ..]) |other| {
                if (entry.code == other.code or std.mem.eql(u8, entry.name, other.name)) return error.ErrorMappingChanged;
            }
            if (baseline.find(entry.name) == null and entry.code < baseline.next_code) return error.ErrorMappingChanged;
        }
        for (baseline.codes.items) |entry| {
            const current = self.find(entry.name) orelse return error.ErrorMappingChanged;
            if (current != entry.code) return error.ErrorMappingChanged;
        }
    }

    pub fn serialize(self: ErrorsLock, allocator: std.mem.Allocator) ![]u8 {
        const sorted = try allocator.dupe(ErrorCode, self.codes.items);
        defer allocator.free(sorted);
        std.mem.sort(ErrorCode, sorted, {}, lessThan);

        var allocating: std.Io.Writer.Allocating = .init(allocator);
        defer allocating.deinit();
        var stringify: std.json.Stringify = .{ .writer = &allocating.writer, .options = .{ .whitespace = .indent_2 } };
        try stringify.beginObject();
        try stringify.objectField("codes");
        try stringify.beginObject();
        for (sorted) |entry| {
            try stringify.objectField(entry.name);
            try stringify.write(entry.code);
        }
        try stringify.endObject();
        try stringify.objectField("ir_version");
        try stringify.write(self.ir_version);
        try stringify.objectField("next_code");
        try stringify.write(self.next_code);
        try stringify.objectField("reserved");
        try stringify.write(.{
            .@"-1" = "Unknown",
            .@"-2" = "PanicCaught",
            .@"-3" = "CallbackPanic",
            .@"-4" = "InvalidHandle",
            .@"0" = "OK",
        });
        try stringify.endObject();
        try allocating.writer.writeByte('\n');
        return allocating.toOwnedSlice();
    }

    pub fn find(self: ErrorsLock, name: []const u8) ?i32 {
        for (self.codes.items) |entry| if (std.mem.eql(u8, entry.name, name)) return entry.code;
        return null;
    }
};

fn integerField(object: std.json.ObjectMap, name: []const u8) !i64 {
    return switch (object.get(name) orelse return error.MissingField) {
        .integer => |value| value,
        else => error.UnexpectedToken,
    };
}

fn lessThan(_: void, lhs: ErrorCode, rhs: ErrorCode) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}
