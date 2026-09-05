const std = @import("std");

pub const current_ir_version: u32 = 1;

const reserved_codes = [_]struct { code: []const u8, name: []const u8 }{
    .{ .code = "0", .name = "OK" },
    .{ .code = "-1", .name = "Unknown" },
    .{ .code = "-2", .name = "PanicCaught" },
    .{ .code = "-3", .name = "CallbackPanic" },
    .{ .code = "-4", .name = "InvalidHandle" },
};

pub const ErrorCode = struct {
    code: i32,
    name: []const u8,
};

pub const ErrorsLock = struct {
    codes: std.ArrayList(ErrorCode) = .empty,
    ir_version: u32 = current_ir_version,
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
        const parsed_version = try integerField(root, "ir_version");
        if (parsed_version != current_ir_version) return error.UnsupportedIrVersion;
        const parsed_next_code = std.math.cast(i32, try integerField(root, "next_code")) orelse return error.InvalidErrorCode;
        var result: ErrorsLock = .{ .next_code = parsed_next_code };
        errdefer result.deinit(allocator);
        try validateReserved(root);
        const codes = switch (root.get("codes") orelse return error.MissingField) {
            .object => |object| object,
            else => return error.UnexpectedToken,
        };
        var iterator = codes.iterator();
        while (iterator.next()) |entry| {
            if (entry.key_ptr.*.len == 0) return error.InvalidErrorName;
            const raw_code = switch (entry.value_ptr.*) {
                .integer => |value| value,
                else => return error.UnexpectedToken,
            };
            const code = std.math.cast(i32, raw_code) orelse return error.InvalidErrorCode;
            const name = try allocator.dupe(u8, entry.key_ptr.*);
            errdefer allocator.free(name);
            try result.codes.append(allocator, .{ .name = name, .code = code });
        }
        try result.validateState();
        return result;
    }

    pub fn assign(self: *ErrorsLock, allocator: std.mem.Allocator, names: []const []const u8) !void {
        try self.validateState();
        var addition_count: usize = 0;
        for (names, 0..) |name, index| {
            if (name.len == 0) return error.InvalidErrorName;
            if (self.find(name) != null) continue;
            var repeated = false;
            for (names[0..index]) |previous| {
                if (std.mem.eql(u8, previous, name)) {
                    repeated = true;
                    break;
                }
            }
            if (!repeated) addition_count += 1;
        }
        const addition_count_i32 = std.math.cast(i32, addition_count) orelse return error.ErrorCodeExhausted;
        const new_next_code = std.math.add(i32, self.next_code, addition_count_i32) catch return error.ErrorCodeExhausted;

        var additions: std.ArrayList(ErrorCode) = .empty;
        defer additions.deinit(allocator);
        errdefer for (additions.items) |entry| allocator.free(entry.name);
        for (names) |name| {
            if (self.find(name) != null or findIn(additions.items, name) != null) continue;
            if (self.next_code <= 0) return error.ReservedErrorCode;
            const owned_name = try allocator.dupe(u8, name);
            errdefer allocator.free(owned_name);
            try additions.append(allocator, .{
                .name = owned_name,
                .code = self.next_code + @as(i32, @intCast(additions.items.len)),
            });
        }
        try self.codes.ensureUnusedCapacity(allocator, additions.items.len);
        for (additions.items) |entry| self.codes.appendAssumeCapacity(entry);
        self.next_code = new_next_code;
    }

    pub fn validateAgainst(self: ErrorsLock, baseline: ErrorsLock) !void {
        self.validateState() catch return error.ErrorMappingChanged;
        baseline.validateState() catch return error.ErrorMappingChanged;
        if (self.ir_version != baseline.ir_version) return error.ErrorMappingChanged;
        if (self.next_code < baseline.next_code) return error.ErrorMappingChanged;
        for (self.codes.items) |entry| {
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
        // The only way writing into memory fails is running out of it, and
        // callers treat this as the allocation failure it is.
        writeJson(sorted, self, &allocating.writer) catch return error.OutOfMemory;
        return allocating.toOwnedSlice();
    }

    fn writeJson(sorted: []const ErrorCode, self: ErrorsLock, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var stringify: std.json.Stringify = .{ .writer = writer, .options = .{ .whitespace = .indent_2 } };
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
        try writer.writeByte('\n');
    }

    pub fn find(self: ErrorsLock, name: []const u8) ?i32 {
        return findIn(self.codes.items, name);
    }

    fn validateState(self: ErrorsLock) !void {
        if (self.ir_version != current_ir_version) return error.UnsupportedIrVersion;
        if (self.next_code <= 0) return error.ReservedErrorCode;
        if (self.codes.items.len != @as(usize, @intCast(self.next_code - 1))) return error.ErrorCodeWouldBeReused;
        for (self.codes.items, 0..) |entry, index| {
            if (entry.name.len == 0) return error.InvalidErrorName;
            if (entry.code <= 0 or entry.code >= self.next_code) return error.ReservedErrorCode;
            for (self.codes.items[index + 1 ..]) |other| {
                if (entry.code == other.code) return error.DuplicateErrorCode;
                if (std.mem.eql(u8, entry.name, other.name)) return error.DuplicateErrorName;
            }
        }
    }
};

fn findIn(codes: []const ErrorCode, name: []const u8) ?i32 {
    for (codes) |entry| if (std.mem.eql(u8, entry.name, name)) return entry.code;
    return null;
}

fn validateReserved(root: std.json.ObjectMap) !void {
    const reserved = switch (root.get("reserved") orelse return error.MissingField) {
        .object => |object| object,
        else => return error.UnexpectedToken,
    };
    if (reserved.count() != reserved_codes.len) return error.ReservedMappingChanged;
    for (reserved_codes) |expected| {
        const actual = switch (reserved.get(expected.code) orelse return error.ReservedMappingChanged) {
            .string => |value| value,
            else => return error.ReservedMappingChanged,
        };
        if (!std.mem.eql(u8, actual, expected.name)) return error.ReservedMappingChanged;
    }
}

fn integerField(object: std.json.ObjectMap, name: []const u8) !i64 {
    return switch (object.get(name) orelse return error.MissingField) {
        .integer => |value| value,
        else => error.UnexpectedToken,
    };
}

fn lessThan(_: void, lhs: ErrorCode, rhs: ErrorCode) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}

const canonical_empty =
    \\{"codes":{},"ir_version":1,"next_code":1,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
;

test "canonical lock parses and serializes" {
    var lock = try ErrorsLock.parse(std.testing.allocator, canonical_empty);
    defer lock.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 1), lock.next_code);
    const serialized = try lock.serialize(std.testing.allocator);
    defer std.testing.allocator.free(serialized);
    var reparsed = try ErrorsLock.parse(std.testing.allocator, serialized);
    defer reparsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(lock.next_code, reparsed.next_code);
}

test "lock rejects unsupported versions and changed reserved mappings" {
    const unsupported =
        \\{"codes":{},"ir_version":2,"next_code":1,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    ;
    const changed =
        \\{"codes":{},"ir_version":1,"next_code":1,"reserved":{"-1":"Other","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    ;
    const extra =
        \\{"codes":{},"ir_version":1,"next_code":1,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","-5":"Other","0":"OK"}}
    ;
    try std.testing.expectError(error.UnsupportedIrVersion, ErrorsLock.parse(std.testing.allocator, unsupported));
    try std.testing.expectError(error.ReservedMappingChanged, ErrorsLock.parse(std.testing.allocator, changed));
    try std.testing.expectError(error.ReservedMappingChanged, ErrorsLock.parse(std.testing.allocator, extra));
}

test "lock rejects missing reused and out-of-range positive codes" {
    const missing =
        \\{"codes":{"A":1},"ir_version":1,"next_code":3,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    ;
    const reused =
        \\{"codes":{"A":1,"B":1},"ir_version":1,"next_code":3,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    ;
    const out_of_range =
        \\{"codes":{"A":2},"ir_version":1,"next_code":2,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    ;
    try std.testing.expectError(error.ErrorCodeWouldBeReused, ErrorsLock.parse(std.testing.allocator, missing));
    try std.testing.expectError(error.DuplicateErrorCode, ErrorsLock.parse(std.testing.allocator, reused));
    try std.testing.expectError(error.ReservedErrorCode, ErrorsLock.parse(std.testing.allocator, out_of_range));
}

test "assign is append-only and retains codes for absent errors" {
    var lock = try ErrorsLock.parse(std.testing.allocator,
        \\{"codes":{"Retired":1},"ir_version":1,"next_code":2,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    );
    defer lock.deinit(std.testing.allocator);
    try lock.assign(std.testing.allocator, &.{ "Active", "Active", "Later" });
    try std.testing.expectEqual(@as(?i32, 1), lock.find("Retired"));
    try std.testing.expectEqual(@as(?i32, 2), lock.find("Active"));
    try std.testing.expectEqual(@as(?i32, 3), lock.find("Later"));
    try std.testing.expectEqual(@as(i32, 4), lock.next_code);
    try lock.assign(std.testing.allocator, &.{"Active"});
    try std.testing.expectEqual(@as(i32, 4), lock.next_code);
}

test "transition validation rejects deletion remapping and historical insertion" {
    var baseline = try ErrorsLock.parse(std.testing.allocator,
        \\{"codes":{"A":1,"B":2},"ir_version":1,"next_code":3,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    );
    defer baseline.deinit(std.testing.allocator);
    var appended = try ErrorsLock.parse(std.testing.allocator,
        \\{"codes":{"A":1,"B":2,"C":3},"ir_version":1,"next_code":4,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    );
    defer appended.deinit(std.testing.allocator);
    try appended.validateAgainst(baseline);

    var remapped = try ErrorsLock.parse(std.testing.allocator,
        \\{"codes":{"A":2,"B":1},"ir_version":1,"next_code":3,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    );
    defer remapped.deinit(std.testing.allocator);
    try std.testing.expectError(error.ErrorMappingChanged, remapped.validateAgainst(baseline));

    var renamed = try ErrorsLock.parse(std.testing.allocator,
        \\{"codes":{"A":1,"Replacement":2},"ir_version":1,"next_code":3,"reserved":{"-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    );
    defer renamed.deinit(std.testing.allocator);
    try std.testing.expectError(error.ErrorMappingChanged, renamed.validateAgainst(baseline));
}
