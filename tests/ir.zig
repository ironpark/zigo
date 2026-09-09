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
        \\  "ir_version": 2,
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

// Version 1 spelled the Go-specific fields as siblings of the language-neutral
// ones. Documents written then -- including the generator cases' checked-in
// inputs -- still have to load, so parsing one has to produce exactly what
// parsing its version-2 spelling produces.
test "a version 1 document parses as its version 2 spelling" {
    const v1 =
        \\{"functions":[{"go_name":"Translate","go_owner":"Canvas","name":"translate","params":[{"go_adapter":{"from_raw":"pointFromRaw","import":"image","to_raw":"pointToRaw","type":"image.Point"},"name":"origin","type":{"kind":"int","bits":32,"signed":true}},{"go_error":true,"name":"observer","type":{"kind":"int","bits":32,"signed":true}}],"return_go_adapter":{"from_raw":"durationFromRaw","import":"time","to_raw":"durationToRaw","type":"time.Duration"},"return":{"kind":"void"},"symbol":"zg_translate"}],"ir_version":1,"package":"geometry","prefix":"zg","types":[{"go_adapter":{"from_raw":"modeFromRaw","to_raw":"modeToRaw","type":"Mode"},"kind":"opaque","name":"Canvas"}],"zig_version":"0.16.0"}
    ;
    const v2 =
        \\{"functions":[{"go":{"name":"Translate","owner":"Canvas","return_adapter":{"from_raw":"durationFromRaw","import":"time","to_raw":"durationToRaw","type":"time.Duration"}},"name":"translate","params":[{"go":{"adapter":{"from_raw":"pointFromRaw","import":"image","to_raw":"pointToRaw","type":"image.Point"}},"name":"origin","type":{"kind":"int","bits":32,"signed":true}},{"go":{"callback_error":true},"name":"observer","type":{"kind":"int","bits":32,"signed":true}}],"return":{"kind":"void"},"symbol":"zg_translate"}],"ir_version":2,"package":"geometry","prefix":"zg","types":[{"go":{"adapter":{"from_raw":"modeFromRaw","to_raw":"modeToRaw","type":"Mode"}},"kind":"opaque","name":"Canvas"}],"zig_version":"0.16.0"}
    ;

    var from_v1 = try semantic.Semantic.parse(std.testing.allocator, v1);
    defer from_v1.deinit();
    var from_v2 = try semantic.Semantic.parse(std.testing.allocator, v2);
    defer from_v2.deinit();

    const migrated = try from_v1.value.serialize(std.testing.allocator);
    defer std.testing.allocator.free(migrated);
    const current = try from_v2.value.serialize(std.testing.allocator);
    defer std.testing.allocator.free(current);
    try std.testing.expectEqualStrings(current, migrated);

    // The fields are readable through the accessors either way, which is what
    // every consumer of the document actually calls.
    const function = from_v1.value.functions[0];
    try std.testing.expectEqualStrings("Translate", function.goName().?);
    try std.testing.expectEqualStrings("Canvas", function.goOwnerOverride().?);
    try std.testing.expectEqualStrings("time.Duration", function.returnGoAdapter().?.type);
    try std.testing.expectEqualStrings("image.Point", function.params[0].goAdapter().?.type);
    try std.testing.expect(function.params[1].goError());
    try std.testing.expectEqualStrings("Mode", from_v1.value.types[0].goAdapter().?.type);

    // A version-1 document with no Go-specific field at all gains no `go`
    // object: migration must not make a document larger than the generator
    // would write for the same binding.
    const plain =
        \\{"functions":[{"name":"add","params":[],"return":{"kind":"void"},"symbol":"zg_add"}],"ir_version":1,"package":"plain","prefix":"zg","types":[],"zig_version":"0.16.0"}
    ;
    var parsed_plain = try semantic.Semantic.parse(std.testing.allocator, plain);
    defer parsed_plain.deinit();
    const plain_bytes = try parsed_plain.value.serialize(std.testing.allocator);
    defer std.testing.allocator.free(plain_bytes);
    try std.testing.expect(std.mem.indexOf(u8, plain_bytes, "\"go\"") == null);
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
    try std.testing.expectEqual(semantic.current_ir_version, parsed_minimal.value.ir_version);
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
