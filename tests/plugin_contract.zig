const std = @import("std");
const generator = @import("generator");
const contract = @import("contract");
const plugin = @import("plugin");

const Fixture = struct { json: []const u8, package: []const u8, type_marker: []const u8 = "" };

test "external plugin validates and analyzes once, renders every public scope, and preserves ABI" {
    const fixtures = [_]Fixture{
        .{ .json = @embedFile("generator_cases/callback_bool/semantic.json"), .package = "callbacks", .type_marker = "ContractType callback" },
        .{ .json = @embedFile("generator_cases/materialized/semantic.json"), .package = "tree", .type_marker = "ContractType materialized Root" },
        .{ .json = @embedFile("generator_cases/sub_packages/semantic.json"), .package = "packages" },
        .{ .json = "{\"package\":\"errors\",\"prefix\":\"zg\",\"zig_version\":\"0.16.0\",\"types\":[{\"kind\":\"error_set\",\"name\":\"Failures\"}]}", .package = "errors", .type_marker = "ContractType error_set Failures" },
    };
    for (fixtures) |fixture| inline for (.{ .cgo, .purego }) |backend| {
        var baseline = std.testing.tmpDir(.{ .iterate = true });
        defer baseline.cleanup();
        var output = std.testing.tmpDir(.{ .iterate = true });
        defer output.cleanup();
        const options: generator.Options = .{ .package = fixture.package, .prefix = "zg", .go_module = "example.com/contract", .backend = backend };
        var disabled = options;
        disabled.plugins = &.{};
        try generator.generate(std.testing.allocator, std.testing.io, fixture.json, baseline.dir, disabled);
        contract.validation_runs = 0;
        contract.analysis_runs = 0;
        contract.package_renders = 0;
        try generator.generate(std.testing.allocator, std.testing.io, fixture.json, output.dir, options);
        try std.testing.expectEqual(@as(usize, 1), contract.validation_runs);
        try std.testing.expectEqual(@as(usize, 1), contract.analysis_runs);
        try std.testing.expect(contract.package_renders > 1);
        var walker = try output.dir.walk(std.testing.allocator);
        defer walker.deinit();
        var saw_type = fixture.type_marker.len == 0;
        var package_files: usize = 0;
        while (try walker.next(std.testing.io)) |entry| {
            if (entry.kind != .file) continue;
            const text = try output.dir.readFileAlloc(std.testing.io, entry.path, std.testing.allocator, .limited(4 * 1024 * 1024));
            defer std.testing.allocator.free(text);
            const core = !std.mem.endsWith(u8, entry.path, ".go") or std.mem.startsWith(u8, entry.path, "internal/");
            if (core) {
                const previous = try baseline.dir.readFileAlloc(std.testing.io, entry.path, std.testing.allocator, .limited(4 * 1024 * 1024));
                defer std.testing.allocator.free(previous);
                try std.testing.expectEqualStrings(previous, text);
                try std.testing.expect(std.mem.indexOf(u8, text, "ContractFile") == null);
            } else {
                try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "ContractFile begin"));
                try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "ContractFile end"));
                try std.testing.expect(std.mem.indexOf(u8, text, "\"fmt\"") != null);
                if (std.mem.endsWith(u8, entry.path, "zigo_plugins_gen.go")) {
                    package_files += 1;
                    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "const ContractConfig = \"from-build\""));
                }
                if (std.mem.indexOf(u8, text, fixture.type_marker) != null) saw_type = true;
            }
        }
        try std.testing.expect(saw_type);
        try std.testing.expectEqual(@as(usize, if (std.mem.eql(u8, fixture.package, "packages")) 2 else 1), package_files);
    };
}

test "plugin configuration overrides compiled defaults by registered name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const entries = try plugin.configurationsAlloc(arena.allocator(), &.{.{ .name = "CONTRACT", .json = "{\"label\":\"from-build\"}" }}, "{\"CONTRACT\":{\"label\":\"override\"}}");
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqualStrings("override", (try plugin.readConfig(contract.plugin, arena.allocator(), entries)).label);
}
