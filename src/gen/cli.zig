const std = @import("std");

pub const ParseError = error{
    DuplicateArgument,
    InvalidValue,
    MissingRequiredArgument,
    MissingValue,
    UnknownArgument,
    UnknownCommand,
};

pub const Generate = struct {
    semantic_path: []const u8,
    output_path: []const u8,
    package: []const u8,
    prefix: []const u8 = "zg",
    go_module: []const u8,
    include_dir: []const u8 = "${SRCDIR}/../../../zig-out/include",
    library_dir: []const u8 = "${SRCDIR}/../../../zig-out/lib",
    cflags: []const u8 = "",
    ldflags: []const u8 = "",
    system_ldflags: []const u8 = "",
    framework_ldflags: []const u8 = "",
    raw_package_path: []const u8 = "internal/raw",
    raw_package_name: []const u8 = "raw",
    raw_colocated: bool = false,
    auto_cleanup: bool = false,
    errors_lock_path: ?[]const u8 = null,
};

pub const Check = struct {
    generated_path: []const u8,
    source_path: []const u8,
};

pub const AbiDiff = struct {
    base_path: []const u8,
    current_path: []const u8,
    json: bool = false,
    fail_on_breaking: bool = false,
};

pub const Command = union(enum) {
    generate: Generate,
    check: Check,
    abi_diff: AbiDiff,
};

pub fn isHelp(args: []const []const u8) bool {
    if (args.len == 1) return std.mem.eql(u8, args[0], "help") or isHelpFlag(args[0]);
    return args.len == 2 and isKnownCommand(args[0]) and isHelpFlag(args[1]);
}

pub fn writeUsage(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll(
        \\usage: zigo-gen <command> [options]
        \\
        \\commands:
        \\  generate  --semantic <file> --output <dir> --package <name> [options]
        \\  check     --generated <dir> --source <dir>
        \\  abi-diff  --base <file> --current <file> [--json] [--fail-on breaking]
        \\
    );
}

fn isHelpFlag(argument: []const u8) bool {
    return std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h");
}

fn isKnownCommand(argument: []const u8) bool {
    return std.mem.eql(u8, argument, "generate") or std.mem.eql(u8, argument, "check") or std.mem.eql(u8, argument, "abi-diff");
}

pub fn writeParseError(writer: *std.Io.Writer, err: ParseError) std.Io.Writer.Error!void {
    const message = switch (err) {
        error.DuplicateArgument => "an argument was provided more than once",
        error.InvalidValue => "an argument has an unsupported value",
        error.MissingRequiredArgument => "a required argument is missing",
        error.MissingValue => "an argument is missing its value",
        error.UnknownArgument => "an unknown argument was provided",
        error.UnknownCommand => "the command is missing or unknown",
    };
    try writer.print("error: {s}\n\n", .{message});
    try writeUsage(writer);
}

pub fn parse(args: []const []const u8) ParseError!Command {
    if (args.len == 0) return error.UnknownCommand;
    if (std.mem.eql(u8, args[0], "generate")) return .{ .generate = try parseGenerate(args[1..]) };
    if (std.mem.eql(u8, args[0], "check")) return .{ .check = try parseCheck(args[1..]) };
    if (std.mem.eql(u8, args[0], "abi-diff")) return .{ .abi_diff = try parseAbiDiff(args[1..]) };
    return error.UnknownCommand;
}

fn parseGenerate(args: []const []const u8) ParseError!Generate {
    var semantic_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var package: ?[]const u8 = null;
    var prefix: ?[]const u8 = null;
    var go_module: ?[]const u8 = null;
    var include_dir: ?[]const u8 = null;
    var library_dir: ?[]const u8 = null;
    var cflags: ?[]const u8 = null;
    var ldflags: ?[]const u8 = null;
    var system_ldflags: ?[]const u8 = null;
    var framework_ldflags: ?[]const u8 = null;
    var raw_package_path: ?[]const u8 = null;
    var raw_package_name: ?[]const u8 = null;
    var errors_lock_path: ?[]const u8 = null;
    var raw_colocated = false;
    var raw_colocated_seen = false;
    var auto_cleanup = false;
    var auto_cleanup_seen = false;

    var index: usize = 0;
    while (index < args.len) {
        const flag = args[index];
        index += 1;
        if (std.mem.eql(u8, flag, "--raw-colocated")) {
            if (raw_colocated_seen) return error.DuplicateArgument;
            raw_colocated_seen = true;
            raw_colocated = true;
        } else if (std.mem.eql(u8, flag, "--auto-cleanup")) {
            if (auto_cleanup_seen) return error.DuplicateArgument;
            auto_cleanup_seen = true;
            auto_cleanup = true;
        } else if (std.mem.eql(u8, flag, "--semantic")) {
            try set(&semantic_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--output")) {
            try set(&output_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--package")) {
            try set(&package, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--prefix")) {
            try set(&prefix, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--go-module")) {
            try set(&go_module, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--include-dir")) {
            try set(&include_dir, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--library-dir")) {
            try set(&library_dir, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--cflags")) {
            try set(&cflags, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--ldflags")) {
            try set(&ldflags, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--system-ldflags")) {
            try set(&system_ldflags, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--framework-ldflags")) {
            try set(&framework_ldflags, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--raw-package-path")) {
            try set(&raw_package_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--raw-package-name")) {
            try set(&raw_package_name, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--errors-lock")) {
            try set(&errors_lock_path, try takeValue(args, &index));
        } else {
            return error.UnknownArgument;
        }
    }

    const resolved_package = package orelse return error.MissingRequiredArgument;
    return .{
        .semantic_path = semantic_path orelse return error.MissingRequiredArgument,
        .output_path = output_path orelse return error.MissingRequiredArgument,
        .package = resolved_package,
        .prefix = prefix orelse "zg",
        .go_module = go_module orelse resolved_package,
        .include_dir = include_dir orelse "${SRCDIR}/../../../zig-out/include",
        .library_dir = library_dir orelse "${SRCDIR}/../../../zig-out/lib",
        .cflags = cflags orelse "",
        .ldflags = ldflags orelse "",
        .system_ldflags = system_ldflags orelse "",
        .framework_ldflags = framework_ldflags orelse "",
        .raw_package_path = raw_package_path orelse "internal/raw",
        .raw_package_name = raw_package_name orelse "raw",
        .raw_colocated = raw_colocated,
        .auto_cleanup = auto_cleanup,
        .errors_lock_path = errors_lock_path,
    };
}

fn parseCheck(args: []const []const u8) ParseError!Check {
    var generated_path: ?[]const u8 = null;
    var source_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < args.len) {
        const flag = args[index];
        index += 1;
        if (std.mem.eql(u8, flag, "--generated")) {
            try set(&generated_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--source")) {
            try set(&source_path, try takeValue(args, &index));
        } else {
            return error.UnknownArgument;
        }
    }
    return .{
        .generated_path = generated_path orelse return error.MissingRequiredArgument,
        .source_path = source_path orelse return error.MissingRequiredArgument,
    };
}

fn parseAbiDiff(args: []const []const u8) ParseError!AbiDiff {
    var base_path: ?[]const u8 = null;
    var current_path: ?[]const u8 = null;
    var json = false;
    var json_seen = false;
    var fail_on_breaking = false;
    var fail_on_seen = false;
    var index: usize = 0;
    while (index < args.len) {
        const flag = args[index];
        index += 1;
        if (std.mem.eql(u8, flag, "--base")) {
            try set(&base_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--current")) {
            try set(&current_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--json")) {
            if (json_seen) return error.DuplicateArgument;
            json_seen = true;
            json = true;
        } else if (std.mem.eql(u8, flag, "--fail-on")) {
            if (fail_on_seen) return error.DuplicateArgument;
            fail_on_seen = true;
            if (!std.mem.eql(u8, try takeValue(args, &index), "breaking")) return error.InvalidValue;
            fail_on_breaking = true;
        } else {
            return error.UnknownArgument;
        }
    }
    return .{
        .base_path = base_path orelse return error.MissingRequiredArgument,
        .current_path = current_path orelse return error.MissingRequiredArgument,
        .json = json,
        .fail_on_breaking = fail_on_breaking,
    };
}

fn takeValue(args: []const []const u8, index: *usize) ParseError![]const u8 {
    if (index.* >= args.len) return error.MissingValue;
    const value = args[index.*];
    index.* += 1;
    return value;
}

fn set(slot: *?[]const u8, value: []const u8) ParseError!void {
    if (slot.* != null) return error.DuplicateArgument;
    slot.* = value;
}

test "generate command parses named arguments" {
    const command = try parse(&.{
        "generate",
        "--semantic",
        "semantic.json",
        "--output",
        "out",
        "--package",
        "scalar",
        "--prefix",
        "zs",
        "--go-module",
        "example.com/scalar",
        "--include-dir",
        "include",
        "--library-dir",
        "lib",
        "--cflags",
        "-Icustom",
        "--ldflags",
        "-Lcustom",
        "--system-ldflags",
        "-lz",
        "--framework-ldflags",
        "-framework CoreFoundation",
        "--raw-package-path",
        "scalar",
        "--raw-package-name",
        "scalar",
        "--raw-colocated",
        "--auto-cleanup",
        "--errors-lock",
        "errors.lock.json",
    });
    const options = command.generate;
    try std.testing.expectEqualStrings("semantic.json", options.semantic_path);
    try std.testing.expectEqualStrings("scalar", options.package);
    try std.testing.expectEqualStrings("example.com/scalar", options.go_module);
    try std.testing.expectEqualStrings("-Icustom", options.cflags);
    try std.testing.expectEqualStrings("scalar", options.raw_package_path);
    try std.testing.expect(options.raw_colocated);
    try std.testing.expect(options.auto_cleanup);
    try std.testing.expectEqualStrings("errors.lock.json", options.errors_lock_path.?);
}

test "generate command retains defaults" {
    const command = try parse(&.{ "generate", "--semantic", "semantic.json", "--output", "out", "--package", "scalar" });
    const options = command.generate;
    try std.testing.expectEqualStrings("zg", options.prefix);
    try std.testing.expectEqualStrings("scalar", options.go_module);
    try std.testing.expectEqualStrings("internal/raw", options.raw_package_path);
    try std.testing.expect(!options.raw_colocated);
    try std.testing.expect(!options.auto_cleanup);
    try std.testing.expect(options.errors_lock_path == null);
}

test "check and abi-diff commands parse named arguments" {
    const check = (try parse(&.{ "check", "--generated", "expected", "--source", "go" })).check;
    try std.testing.expectEqualStrings("expected", check.generated_path);
    try std.testing.expectEqualStrings("go", check.source_path);

    const diff = (try parse(&.{ "abi-diff", "--base", "old.json", "--current", "new.json", "--json", "--fail-on", "breaking" })).abi_diff;
    try std.testing.expect(diff.json);
    try std.testing.expect(diff.fail_on_breaking);
}

test "parser rejects incomplete unknown and duplicate arguments" {
    try std.testing.expectError(error.UnknownCommand, parse(&.{"--check"}));
    try std.testing.expectError(error.MissingRequiredArgument, parse(&.{ "generate", "--semantic", "semantic.json" }));
    try std.testing.expectError(error.MissingValue, parse(&.{ "check", "--generated" }));
    try std.testing.expectError(error.UnknownArgument, parse(&.{ "check", "--wat", "value" }));
    try std.testing.expectError(error.DuplicateArgument, parse(&.{ "check", "--generated", "one", "--generated", "two", "--source", "go" }));
    try std.testing.expectError(error.DuplicateArgument, parse(&.{ "generate", "--semantic", "semantic.json", "--output", "out", "--package", "scalar", "--auto-cleanup", "--auto-cleanup" }));
    try std.testing.expectError(error.InvalidValue, parse(&.{ "abi-diff", "--base", "old", "--current", "new", "--fail-on", "all" }));
}

test "help and parse errors render actionable usage" {
    try std.testing.expect(isHelp(&.{"--help"}));
    try std.testing.expect(isHelp(&.{ "generate", "--help" }));
    var rendered: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer rendered.deinit();
    try writeParseError(&rendered.writer, error.MissingRequiredArgument);
    try std.testing.expect(std.mem.indexOf(u8, rendered.written(), "required argument is missing") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered.written(), "generate  --semantic") != null);
}
