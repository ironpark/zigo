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

const customization_json = @embedFile("plugin_transform/semantic.json");

test "external semantic customization rewrites IR, conversions, names and preserves native call order" {
    inline for (.{ .cgo, .purego }) |backend| {
        var output = std.testing.tmpDir(.{ .iterate = true });
        defer output.cleanup();
        @import("observer").runs = 0;
        @import("observer").policies = 0;
        contract.transform_runs = 0;
        contract.validation_runs = 0;
        contract.analysis_runs = 0;
        try generator.generate(std.testing.allocator, std.testing.io, customization_json, output.dir, .{
            .package = "custom",
            .prefix = "zg",
            .go_module = "example.com/custom",
            .backend = backend,
            .configurations = &.{.{ .name = "CONTRACT", .json = "{\"customize\":true}" }},
        });
        try std.testing.expectEqual(@as(usize, 1), @import("observer").runs);
        try std.testing.expectEqual(@as(usize, 1), @import("observer").policies);
        try std.testing.expectEqual(@as(usize, 1), contract.transform_runs);
        try std.testing.expectEqual(@as(usize, 1), contract.validation_runs);
        try std.testing.expectEqual(@as(usize, 1), contract.analysis_runs);
        var walker = try output.dir.walk(std.testing.allocator);
        defer walker.deinit();
        var public_seen = false;
        var native_seen = false;
        var type_seen = false;
        while (try walker.next(std.testing.io)) |entry| {
            if (entry.kind != .file) continue;
            const contents = try output.dir.readFileAlloc(std.testing.io, entry.path, std.testing.allocator, .limited(4 * 1024 * 1024));
            defer std.testing.allocator.free(contents);
            try std.testing.expect(std.mem.indexOf(u8, contents, "zg_hidden") == null);
            if (std.mem.indexOf(u8, contents, "func HTTPCombine(") != null) {
                public_seen = true;
                try std.testing.expect(std.mem.indexOf(u8, contents, "func HTTPCombine(right time.Time, left time.Time) time.Time") != null);
                try std.testing.expect(std.mem.indexOf(u8, contents, "func HTTPDerived(left time.Time, right time.Time) time.Time") != null);
                try std.testing.expect(std.mem.indexOf(u8, contents, "unixTimeToRaw(right)") != null);
                try std.testing.expect(std.mem.indexOf(u8, contents, "unixTimeFromRaw(") != null);
                try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, contents, "\"time\""));
            }
            if (std.mem.indexOf(u8, contents, "target.combine(") != null) {
                native_seen = true;
                // Both wrappers call the same original declaration, in native order.
                try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, contents, "target.combine(left, right)"));
                try std.testing.expect(std.mem.indexOf(u8, contents, "target.derived(") == null);
                try std.testing.expect(std.mem.indexOf(u8, contents, "target.state(@enumFromInt(value))") != null);
            }
            if (std.mem.indexOf(u8, contents, "type HTTPState ") != null) type_seen = true;
        }
        try std.testing.expect(public_seen and native_seen and type_seen);
    }
}

test "invalid transformed output fails before validation callbacks and leaves output untouched" {
    const diagnostic = @import("diagnostic");
    const cases = .{
        .{ "{\"customize\":true,\"invalid_order\":true}", "ZIGO060" },
        .{ "{\"customize\":true,\"invalid_adapter\":true}", "ZIGO052" },
        .{ "{\"customize\":true,\"invalid_name\":true}", "ZIGO021" },
        .{ "{\"customize\":true,\"collision\":true}", "ZIGO024" },
    };
    inline for (cases) |case| {
        var output = std.testing.tmpDir(.{ .iterate = true });
        defer output.cleanup();
        try output.dir.writeFile(std.testing.io, .{ .sub_path = "sentinel", .data = "keep" });
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
        contract.validation_runs = 0;
        contract.analysis_runs = 0;
        try std.testing.expectError(error.InvalidSemantic, generator.generate(arena.allocator(), std.testing.io, customization_json, output.dir, .{
            .package = "custom",
            .prefix = "zg",
            .go_module = "example.com/custom",
            .diagnostics = &issues,
            .configurations = &.{.{ .name = "CONTRACT", .json = case[0] }},
        }));
        try std.testing.expectEqual(@as(usize, 0), contract.validation_runs);
        try std.testing.expectEqual(@as(usize, 0), contract.analysis_runs);
        try std.testing.expectEqualStrings(case[1], issues.items[0].code);
        var iterator = output.dir.iterate();
        var files: usize = 0;
        while (try iterator.next(std.testing.io)) |entry| {
            files += 1;
            try std.testing.expectEqualStrings("sentinel", entry.name);
        }
        try std.testing.expectEqual(@as(usize, 1), files);
    }
}

test "parameter reordering composes and preserves injected arguments around a receiver" {
    const semantic = @import("semantic");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var issues: std.ArrayList(@import("diagnostic").Diagnostic) = .empty;
    const doc: semantic.Semantic = .{ .package = "custom", .prefix = "zg", .zig_version = "0.16.0" };
    const context: plugin.TransformContext = .{ .allocator = allocator, .document = doc, .diagnostics = &issues };
    const original: semantic.SemanticFn = .{
        .name = "combine",
        .receiver = "State",
        .receiver_kind = .value,
        .receiver_at = 1,
        .symbol = "zg_state_combine",
        .params = &.{ .{ .name = "allocator", .injected = .allocator, .type = .{ .void = {} } }, .{ .name = "value", .type = .{ .int = .{ .bits = 64, .signed = false } } } },
        .@"return" = .{ .int = .{ .bits = 64, .signed = false } },
    };
    const reversed = try context.reorderParameters(original, &.{ 1, 0 });
    const restored = try context.reorderParameters(reversed, &.{ 1, 0 });
    try std.testing.expectEqual(@as(?usize, 0), restored.params[0].native_index);
    try std.testing.expectEqual(@as(?usize, 1), restored.params[1].native_index);
    try std.testing.expectError(error.InvalidParameterOrder, context.reorderParameters(original, &.{ 0, 0 }));
    try std.testing.expectError(error.InvalidParameterOrder, context.reorderParameters(original, &.{0}));
    try std.testing.expectError(error.InvalidParameterOrder, context.reorderParameters(original, &.{ 0, 2 }));
    var document = doc;
    document.allocator = "std.heap.page_allocator";
    document.functions = &.{original};
    document.types = &.{.{ .name = "State", .kind = .@"enum", .tag_type = .{ .int = .{ .bits = 8, .signed = false } }, .fields = &.{.{ .name = "ready", .value = 0 }} }};
    inline for (.{ .cgo, .purego }) |backend| {
        var output = std.testing.tmpDir(.{ .iterate = true });
        defer output.cleanup();
        try generator.generate(allocator, std.testing.io, try document.serialize(allocator), output.dir, .{
            .package = "custom",
            .prefix = "zg",
            .go_module = "example.com/custom",
            .backend = backend,
            .configurations = &.{.{ .name = "CONTRACT", .json = "{\"customize\":true}" }},
        });
        var walker = try output.dir.walk(allocator);
        defer walker.deinit();
        var seen = false;
        while (try walker.next(std.testing.io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".zig")) continue;
            const text = try output.dir.readFileAlloc(std.testing.io, entry.path, allocator, .limited(4 * 1024 * 1024));
            if (std.mem.indexOf(u8, text, "target.State.combine(")) |_| {
                seen = true;
                try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "target.State.combine(std.heap.page_allocator, @enumFromInt(self), value)"));
                try std.testing.expect(std.mem.indexOf(u8, text, "target.HTTPState") == null);
            }
        }
        try std.testing.expect(seen);
    }
}

test "plugin preflight rejects disabled dependencies and malformed config before transforms" {
    inline for (.{ false, true }) |malformed| {
        var output = std.testing.tmpDir(.{});
        defer output.cleanup();
        contract.transform_runs = 0;
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var issues: std.ArrayList(@import("diagnostic").Diagnostic) = .empty;
        try std.testing.expectError(if (malformed) error.InvalidSemantic else error.DisabledPluginDependency, generator.generate(arena.allocator(), std.testing.io, customization_json, output.dir, .{
            .package = "custom",
            .prefix = "zg",
            .go_module = "example.com/custom",
            .diagnostics = &issues,
            .plugins = if (malformed) null else &.{"OBSERVER"},
            .configurations = if (malformed) &.{.{ .name = "CONTRACT", .json = "{\"customize\":123}" }} else &.{},
        }));
        try std.testing.expectEqual(@as(usize, 0), contract.transform_runs);
        if (malformed) try std.testing.expectEqualStrings("CONTRACT001", issues.items[0].code);
    }
}

test {
    _ = @import("plugin_outputs.zig");
}
