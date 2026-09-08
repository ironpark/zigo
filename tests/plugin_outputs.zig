const std = @import("std");
const generator = @import("generator");
const api = @import("plugin");
const outputs = @import("outputs");
const diagnostic = @import("diagnostic");
const fixture = @embedFile("generator_cases/sub_packages/semantic.json");
const enabled = [_]api.Configuration{ .{ .name = "OUTPUTS", .json = "{\"enabled\":true}" }, .{ .name = "CONTRACT", .json = "{\"label\":\"from-build\"}" } };

fn read(allocator: std.mem.Allocator, directory: std.Io.Dir, path: []const u8) ![]u8 {
    return directory.readFileAlloc(std.testing.io, path, allocator, .limited(4 * 1024 * 1024));
}

test "exact artifacts and scoped Go files remain separate across split packages and backends" {
    inline for (.{ .cgo, .purego }) |backend| inline for (.{ "api", "." }) |public_path| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        var baseline = std.testing.tmpDir(.{ .iterate = true });
        defer baseline.cleanup();
        var output = std.testing.tmpDir(.{ .iterate = true });
        defer output.cleanup();
        const options: generator.Options = .{ .package = "packages", .prefix = "zg", .go_module = "example.com/api", .go_package = "api", .go_package_path = public_path, .backend = backend };
        try generator.generate(allocator, std.testing.io, fixture, baseline.dir, options);
        var configured = options;
        configured.configurations = &enabled;
        outputs.document_runs = 0;
        outputs.document_go_runs = 0;
        outputs.package_runs = 0;
        outputs.raw_runs = 0;
        try output.dir.writeFile(std.testing.io, .{ .sub_path = "empty.bin", .data = "old content must be truncated" });
        try generator.generate(allocator, std.testing.io, fixture, output.dir, configured);
        try std.testing.expectEqual(@as(usize, 1), outputs.document_runs);
        try std.testing.expectEqual(@as(usize, 1), outputs.document_go_runs);
        try std.testing.expectEqual(@as(usize, 2), outputs.package_runs);
        try std.testing.expectEqual(@as(usize, 1), outputs.raw_runs);
        const artifacts = .{
            .{ "API_INDEX.md", "# API\r\nFunctions: 3\r\nzigoMust(false)\r\n\r\n" },
            .{ "schema.proto", "syntax = \"proto3\";" },
            .{ "types.d.ts", "export interface API {}\r\n\r\n" },
            .{ "go.mod.fragment", "require example.com/extra v1.0.0\n" },
            .{ "build_tag.go", "//go:build ignore\n\n" },
            .{ "empty.bin", "" },
            .{ "opaque.bin", "a\x00\xff\n\n" },
        };
        inline for (artifacts) |artifact| try std.testing.expectEqualStrings(artifact[1], try read(allocator, output.dir, artifact[0]));
        const base = if (std.mem.eql(u8, public_path, ".")) "" else "api/";
        const directories = [_][]const u8{ base, try std.fmt.allocPrint(allocator, "{s}model/", .{base}) };
        for (directories, 0..) |directory, index| {
            try std.testing.expectEqualStrings(if (index == 0) "package=;functions=2" else "package=model;functions=1", try read(allocator, output.dir, try std.fmt.allocPrint(allocator, "{s}api.md", .{directory})));
            const external = try read(allocator, output.dir, try std.fmt.allocPrint(allocator, "{s}zigo_external_test.go", .{directory}));
            try std.testing.expect(std.mem.indexOf(u8, external, if (index == 0) "package api_test" else "package model_test") != null);
            try std.testing.expect(std.mem.indexOf(u8, external, "ContractFile") == null);
            const example = try read(allocator, output.dir, try std.fmt.allocPrint(allocator, "{s}zigo_internal_test.go", .{directory}));
            try std.testing.expect(std.mem.indexOf(u8, example, "// Output: 42") != null);
            try std.testing.expect(std.mem.indexOf(u8, example, "ContractFile") == null);
            const tagged = try read(allocator, output.dir, try std.fmt.allocPrint(allocator, "{s}zigo_tagged.go", .{directory}));
            try std.testing.expect(std.mem.startsWith(u8, tagged, "//go:build !zigo_output_disabled\n\n// Code generated"));
        }
        const document_go = try read(allocator, output.dir, try std.fmt.allocPrint(allocator, "{s}zigo_document_gen.go", .{base}));
        try std.testing.expect(std.mem.indexOf(u8, document_go, "DocumentFunctionCount = 3") != null);
        try std.testing.expect(std.mem.indexOf(u8, document_go, "ContractFile") == null);
        const raw = try read(allocator, output.dir, "internal/raw/zigo_raw_extra.go");
        try std.testing.expect(std.mem.indexOf(u8, raw, "package raw") != null);
        try std.testing.expect(std.mem.indexOf(u8, raw, "ContractFile") == null);
        // Artifact prose and standalone/test Go files cannot retain production
        // helpers or affect any previously generated file.
        var walker = try baseline.dir.walk(allocator);
        defer walker.deinit();
        while (try walker.next(std.testing.io)) |entry| {
            if (entry.kind != .file) continue;
            try std.testing.expectEqualStrings(try read(allocator, baseline.dir, entry.path), try read(allocator, output.dir, entry.path));
        }
    };
}

test "artifact failure and every kind of output collision leave the tree untouched" {
    const cases = .{
        .{ "{\"enabled\":true,\"artifact_path\":\"../escape.md\"}", error.InvalidOutputPath },
        .{ "{\"enabled\":true,\"artifact_path\":\"./shim.zig\"}", error.InvalidOutputPath },
        .{ "{\"enabled\":true,\"artifact_path\":\"schema.proto\"}", error.InvalidOutputPath },
        .{ "{\"enabled\":true,\"artifact_path\":\"SHIM.ZIG\"}", error.InvalidOutputPath },
        .{ "{\"enabled\":true,\"go_path\":\"internal/raw/wrong.go\"}", error.InvalidOutputPath },
        .{ "{\"enabled\":true,\"go_path\":\"packages/wrong.md\"}", error.InvalidOutputPath },
        .{ "{\"enabled\":true,\"go_path\":\"packages/wrong_test.go\"}", error.InvalidOutputPath },
        .{ "{\"enabled\":true,\"fail\":true}", error.ArtifactFailed },
    };
    inline for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var output = std.testing.tmpDir(.{ .iterate = true });
        defer output.cleanup();
        try output.dir.writeFile(std.testing.io, .{ .sub_path = "sentinel", .data = "keep" });
        var issues: std.ArrayList(diagnostic.Diagnostic) = .empty;
        try std.testing.expectError(case[1], generator.generate(arena.allocator(), std.testing.io, fixture, output.dir, .{
            .package = "packages",
            .prefix = "zg",
            .go_module = "example.com/api",
            .diagnostics = &issues,
            .configurations = &.{.{ .name = "OUTPUTS", .json = case[0] }},
        }));
        if (case[1] == error.InvalidOutputPath) try std.testing.expectEqualStrings("ZIGO059", issues.items[0].code);
        var iterator = output.dir.iterate();
        const first = (try iterator.next(std.testing.io)).?;
        try std.testing.expectEqualStrings("sentinel", first.name);
        try std.testing.expectEqualStrings("keep", try read(arena.allocator(), output.dir, "sentinel"));
        try std.testing.expect((try iterator.next(std.testing.io)) == null);
    }
}

test "disabled output providers never evaluate paths or touch existing artifacts" {
    inline for (.{ false, true }) |registry_disabled| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var output = std.testing.tmpDir(.{});
        defer output.cleanup();
        try output.dir.writeFile(std.testing.io, .{ .sub_path = "API_INDEX.md", .data = "user-owned" });
        outputs.path_runs = 0;
        outputs.document_runs = 0;
        try generator.generate(arena.allocator(), std.testing.io, fixture, output.dir, .{
            .package = "packages",
            .prefix = "zg",
            .go_module = "example.com/api",
            .plugins = if (registry_disabled) &.{} else null,
            .configurations = &.{.{ .name = "OUTPUTS", .json = if (registry_disabled) "{\"enabled\":true,\"artifact_path\":\"../invalid\"}" else "{\"enabled\":false,\"artifact_path\":\"../invalid\"}" }},
        });
        try std.testing.expectEqual(@as(usize, 0), outputs.path_runs);
        try std.testing.expectEqual(@as(usize, 0), outputs.document_runs);
        try std.testing.expectEqualStrings("user-owned", try read(arena.allocator(), output.dir, "API_INDEX.md"));
    }
}

test "raw files follow raw directory and package overrides including colocation" {
    inline for (.{ false, true }) |colocated| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var output = std.testing.tmpDir(.{});
        defer output.cleanup();
        try generator.generate(arena.allocator(), std.testing.io, "{\"package\":\"api\",\"prefix\":\"zg\",\"zig_version\":\"0.16.0\"}", output.dir, .{
            .package = "api",
            .prefix = "zg",
            .go_module = "example.com/api",
            .go_package = "api",
            .go_package_path = if (colocated) "." else "api",
            .raw_colocated = colocated,
            .raw_package_path = if (colocated) "." else "internal/native",
            .raw_package_name = if (colocated) "api" else "native",
            .configurations = &enabled,
        });
        const bytes = try read(arena.allocator(), output.dir, if (colocated) "zigo_raw_extra.go" else "internal/native/zigo_raw_extra.go");
        try std.testing.expect(std.mem.indexOf(u8, bytes, if (colocated) "package api" else "package native") != null);
        try std.testing.expect(std.mem.indexOf(u8, bytes, "ContractFile") == null);
    }
}
