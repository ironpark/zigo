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

test "semantic parser rejects malformed unknown and incomplete documents" {
    try expectSemanticParseFailure("{");
    try expectSemanticParseFailure(
        \\{"package":"bad","prefix":"zg","zig_version":"0.16.0","functions":[{"name":"run","params":[],"return":{"kind":"mystery"},"symbol":"zg_run"}]}
    );
    try expectSemanticParseFailure(
        \\{"prefix":"zg","zig_version":"0.16.0"}
    );
    try expectSemanticParseFailure(
        \\{"package":"bad","prefix":"zg","zig_version":"0.16.0","functions":[{"name":"run","params":[],"return":{"kind":"int","bits":32},"symbol":"zg_run"}]}
    );
}

fn expectSemanticParseFailure(bytes: []const u8) !void {
    if (semantic.Semantic.parse(std.testing.allocator, bytes)) |parsed_value| {
        var parsed = parsed_value;
        parsed.deinit();
        return error.ExpectedParseFailure;
    } else |_| {}
}

test "semantic parser applies defaults and preserves nested type nodes" {
    const minimal =
        \\{"package":"minimal","prefix":"zg","zig_version":"0.16.0"}
    ;
    var parsed_minimal = try semantic.Semantic.parse(std.testing.allocator, minimal);
    defer parsed_minimal.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed_minimal.value.ir_version);
    try std.testing.expectEqual(@as(usize, 0), parsed_minimal.value.functions.len);
    try std.testing.expectEqual(@as(usize, 0), parsed_minimal.value.types.len);
    try std.testing.expectEqual(@as(usize, 0), parsed_minimal.value.constructors.len);

    const nested =
        \\{"functions":[{"name":"install","params":[{"name":"callback","type":{"has_userdata":true,"kind":"callback","params":[{"child":{"const":true,"element":{"kind":"enum","ref":"Mode"},"kind":"slice"},"kind":"optional"}],"return":{"kind":"void"}}}],"return":{"kind":"void"},"symbol":"zg_install"}],"package":"nested","prefix":"zg","types":[{"fields":[{"name":"ready","value":1}],"kind":"enum","name":"Mode","tag_type":{"bits":8,"kind":"int","signed":false}}],"zig_version":"0.16.0"}
    ;
    var parsed_nested = try semantic.Semantic.parse(std.testing.allocator, nested);
    defer parsed_nested.deinit();
    const callback = parsed_nested.value.functions[0].params[0].type.callback;
    try std.testing.expect(callback.c_callconv);
    try std.testing.expect(callback.has_userdata);
    try std.testing.expectEqual(@as(usize, 1), callback.params.len);
    const optional = callback.params[0].optional;
    try std.testing.expect(optional.child.* == .slice);
    try std.testing.expect(optional.child.slice.element.* == .@"enum");
    try std.testing.expectEqualStrings("Mode", optional.child.slice.element.@"enum".ref);

    const serialized = try parsed_nested.value.serialize(std.testing.allocator);
    defer std.testing.allocator.free(serialized);
    var reparsed = try semantic.Semantic.parse(std.testing.allocator, serialized);
    defer reparsed.deinit();
    try std.testing.expectEqualStrings("Mode", reparsed.value.functions[0].params[0].type.callback.params[0].optional.child.slice.element.@"enum".ref);
}

test "semantic parser releases every partial allocation on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parseAndSerializeNestedSemantic, .{});
}

fn parseAndSerializeNestedSemantic(allocator: std.mem.Allocator) !void {
    const nested =
        \\{"functions":[{"name":"install","params":[{"name":"callback","type":{"has_userdata":true,"kind":"callback","params":[{"const":true,"element":{"kind":"enum","ref":"Mode"},"kind":"slice"}],"return":{"kind":"void"}}}],"return":{"kind":"void"},"symbol":"zg_install"}],"package":"nested","prefix":"zg","types":[{"kind":"enum","name":"Mode","tag_type":{"bits":8,"kind":"int","signed":false}}],"zig_version":"0.16.0"}
    ;
    var parsed = try semantic.Semantic.parse(allocator, nested);
    defer parsed.deinit();
    const serialized = try parsed.value.serialize(allocator);
    defer allocator.free(serialized);
    try std.testing.expect(serialized.len != 0);
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

test "the written hint round trips and defaults to all when absent" {
    const document =
        \\{"functions":[{"name":"fill","params":[{"direction":"out","name":"dst","type":{"const":false,"element":{"bits":32,"kind":"int","signed":true},"kind":"slice"},"written":"return"},{"name":"limit","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"bits":64,"is_usize":true,"kind":"int","signed":false},"symbol":"zg_fill"}],"package":"written","prefix":"zg","zig_version":"0.16.0"}
    ;
    var parsed = try semantic.Semantic.parse(std.testing.allocator, document);
    defer parsed.deinit();
    const params = parsed.value.functions[0].params;
    try std.testing.expectEqual(semantic.Written.@"return", params[0].writtenHint());
    try std.testing.expectEqual(@as(?semantic.Written, null), params[1].written);
    try std.testing.expectEqual(semantic.Written.all, params[1].writtenHint());

    const serialized = try parsed.value.serialize(std.testing.allocator);
    defer std.testing.allocator.free(serialized);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "\"written\": \"return\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "\"written\": \"all\"") == null);
}
