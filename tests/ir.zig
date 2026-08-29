const std = @import("std");
const semantic = @import("semantic");
const errors_lock = @import("errors_lock");

test "semantic fixture round trips byte-identically" {
    const fixture =
        \\{
        \\  "constructors": [],
        \\  "functions": [
        \\    {
        \\      "name": "add",
        \\      "ownership": "borrowed",
        \\      "params": [
        \\        {
        \\          "direction": "in",
        \\          "name": "p0",
        \\          "name_source": "fallback",
        \\          "retention": "borrowed",
        \\          "type": {
        \\            "bits": 32,
        \\            "is_usize": false,
        \\            "kind": "int",
        \\            "signed": true
        \\          }
        \\        }
        \\      ],
        \\      "return": {
        \\        "bits": 32,
        \\        "is_usize": false,
        \\        "kind": "int",
        \\        "signed": true
        \\      },
        \\      "symbol": "zg_add"
        \\    }
        \\  ],
        \\  "ir_version": 1,
        \\  "package": "scalar",
        \\  "prefix": "zg",
        \\  "types": [],
        \\  "zig_version": "0.16.0"
        \\}
        \\
    ;
    var parsed = try semantic.Semantic.parse(std.testing.allocator, fixture);
    defer parsed.deinit();
    const serialized = try parsed.value.serialize(std.testing.allocator);
    defer std.testing.allocator.free(serialized);
    try std.testing.expectEqualStrings(fixture, serialized);

    var reparsed = try semantic.Semantic.parse(std.testing.allocator, serialized);
    defer reparsed.deinit();
    const second = try reparsed.value.serialize(std.testing.allocator);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings(serialized, second);
}

test "error lock appends codes and rejects edited mappings" {
    const fixture =
        \\{"ir_version":1,"next_code":3,"codes":{"OutOfMemory":1,"InvalidInput":2},"reserved":{"0":"OK","-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle"}}
    ;
    var baseline = try errors_lock.ErrorsLock.parse(std.testing.allocator, fixture);
    defer baseline.deinit(std.testing.allocator);
    var current = try errors_lock.ErrorsLock.parse(std.testing.allocator, fixture);
    defer current.deinit(std.testing.allocator);
    try current.assign(std.testing.allocator, &.{ "InvalidInput", "Timeout" });
    try current.validateAgainst(baseline);
    try std.testing.expectEqual(@as(?i32, 1), current.find("OutOfMemory"));
    try std.testing.expectEqual(@as(?i32, 3), current.find("Timeout"));

    const canonical = try current.serialize(std.testing.allocator);
    defer std.testing.allocator.free(canonical);
    var round_trip = try errors_lock.ErrorsLock.parse(std.testing.allocator, canonical);
    defer round_trip.deinit(std.testing.allocator);
    const canonical_again = try round_trip.serialize(std.testing.allocator);
    defer std.testing.allocator.free(canonical_again);
    try std.testing.expectEqualStrings(canonical, canonical_again);

    for (current.codes.items) |*entry| {
        if (std.mem.eql(u8, entry.name, "InvalidInput")) entry.code = 9;
    }
    try std.testing.expectError(error.ErrorMappingChanged, current.validateAgainst(baseline));
}
