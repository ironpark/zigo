const std = @import("std");

pub const Backend = enum { cgo, purego };
/// Only the distinction the generator acts on: Windows constrains the purego
/// callback ABI in ways the other systems do not.
pub const LinkMode = enum { static, dynamic };

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
    header_name: []const u8 = "",
    cflags: []const u8 = "",
    ldflags: []const u8 = "",
    extra_ldflags: []const u8 = "",
    ldflags_external: bool = false,
    system_ldflags: []const u8 = "",
    pkg_config_libs: []const u8 = "",
    framework_ldflags: []const u8 = "",
    raw_package_path: []const u8 = "internal/raw",
    raw_package_name: []const u8 = "raw",
    raw_colocated: bool = false,
    go_package: []const u8 = "",
    go_package_path: []const u8 = "",
    go_package_doc: []const u8 = "",
    go_must_variants: bool = false,
    errors_lock_path: ?[]const u8 = null,
    backend: Backend = .cgo,
    link_mode: LinkMode = .static,
    library_stem: []const u8 = "",
    /// Colon-separated candidate locations, in the order they are tried.
    library_search_paths: []const u8 = "",
    /// Comma-separated environment variable names. `null` selects the defaults.
    library_env_vars: ?[]const u8 = null,
    library_automatic: bool = false,
    library_exported_api: bool = true,
    /// Generated Go is formatted through `gofmt`, so generation runs it over
    /// its own output rather than leaving the caller to enumerate the files.
    gofmt_executable: []const u8 = "gofmt",
};

pub const Check = struct {
    generated_path: []const u8,
    source_path: []const u8,
    /// Single generated files that live outside the Go directory, such as
    /// `zigo/semantic.json`, paired with the committed copy they must match.
    files: []const FilePair = &.{},
};

pub const FilePair = struct {
    generated_path: []const u8,
    source_path: []const u8,
};

pub const AbiDiff = struct {
    base_path: []const u8,
    current_path: []const u8,
    json: bool = false,
    fail_on_breaking: bool = false,
    base_backend: Backend = .cgo,
    current_backend: Backend = .cgo,
};

pub const Report = struct {
    semantic_path: []const u8,
    go_module: []const u8 = "",
    raw_package_path: []const u8 = "internal/raw",
    raw_colocated: bool = false,
    backend: Backend = .cgo,
    go_package: []const u8 = "",
    go_package_path: []const u8 = "",
    library_search_paths: []const u8 = "",
    library_env_vars: ?[]const u8 = null,
    library_automatic: bool = false,
    library_exported_api: bool = true,
};

pub const Doctor = struct {
    go_executable: []const u8 = "go",
    gofmt_executable: []const u8 = "gofmt",
    native_target: bool = true,
    backend: Backend = .cgo,
    library_path: ?[]const u8 = null,
    go_mod_path: ?[]const u8 = null,
};

pub const Command = union(enum) {
    generate: Generate,
    check: Check,
    abi_diff: AbiDiff,
    report: Report,
    doctor: Doctor,
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
        \\  generate  --semantic <file> --output <dir> --package <name> [--gofmt <path>] [options]
        \\            [--go-package <name>] [--go-package-path <path>] [--go-must-variants]
        \\  check     --generated <dir> --source <dir> [--file <generated> <source>]...
        \\  abi-diff  --base <file> --current <file> [--base-backend cgo|purego] [--current-backend cgo|purego] [--json] [--fail-on breaking]
        \\  report    --semantic <file> [--go-module <path>] [options]
        \\            [--go-package <name>] [--go-package-path <path>]
        \\            [--library-search-paths <a:b>] [--library-env-vars <A,B>]
        \\            [--library-automatic] [--library-internal-api]
        \\  doctor    [--go <path>] [--gofmt <path>] [--target native|cross]
        \\            [--backend cgo|purego] [--library <path>] [--go-mod <path>]
        \\
    );
}

fn isHelpFlag(argument: []const u8) bool {
    return std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h");
}

fn isKnownCommand(argument: []const u8) bool {
    return std.mem.eql(u8, argument, "generate") or std.mem.eql(u8, argument, "check") or std.mem.eql(u8, argument, "abi-diff") or std.mem.eql(u8, argument, "report") or std.mem.eql(u8, argument, "doctor");
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
    if (std.mem.eql(u8, args[0], "report")) return .{ .report = try parseReport(args[1..]) };
    if (std.mem.eql(u8, args[0], "doctor")) return .{ .doctor = try parseDoctor(args[1..]) };
    return error.UnknownCommand;
}

/// The `--library-*` run-time loading policy, shared by `generate` and `report`.
const LibraryLoadingArgs = struct {
    search_paths: ?[]const u8 = null,
    env_vars: ?[]const u8 = null,
    automatic: bool = false,
    exported_api: bool = true,

    /// Consumes one loading-policy flag. Returns false for any other flag.
    fn parseFlag(self: *LibraryLoadingArgs, flag: []const u8, args: []const []const u8, index: *usize) ParseError!bool {
        if (std.mem.eql(u8, flag, "--library-search-paths")) {
            try set(&self.search_paths, try takeValue(args, index));
        } else if (std.mem.eql(u8, flag, "--library-env-vars")) {
            if (self.env_vars != null) return error.DuplicateArgument;
            self.env_vars = try takeValue(args, index);
        } else if (std.mem.eql(u8, flag, "--library-automatic")) {
            if (self.automatic) return error.DuplicateArgument;
            self.automatic = true;
        } else if (std.mem.eql(u8, flag, "--library-internal-api")) {
            if (!self.exported_api) return error.DuplicateArgument;
            self.exported_api = false;
        } else return false;
        return true;
    }
};

fn parseGenerate(args: []const []const u8) ParseError!Generate {
    var semantic_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var package: ?[]const u8 = null;
    var prefix: ?[]const u8 = null;
    var go_module: ?[]const u8 = null;
    var include_dir: ?[]const u8 = null;
    var library_dir: ?[]const u8 = null;
    var header_name: ?[]const u8 = null;
    var cflags: ?[]const u8 = null;
    var ldflags: ?[]const u8 = null;
    var extra_ldflags: ?[]const u8 = null;
    var ldflags_external = false;
    var system_ldflags: ?[]const u8 = null;
    var pkg_config_libs: ?[]const u8 = null;
    var framework_ldflags: ?[]const u8 = null;
    var raw_package_path: ?[]const u8 = null;
    var raw_package_name: ?[]const u8 = null;
    var go_package: ?[]const u8 = null;
    var go_package_path: ?[]const u8 = null;
    var go_package_doc: ?[]const u8 = null;
    var errors_lock_path: ?[]const u8 = null;
    var gofmt_executable: ?[]const u8 = null;
    var raw_colocated = false;
    var raw_colocated_seen = false;
    var go_must_variants = false;
    var backend: ?Backend = null;
    var link_mode: ?LinkMode = null;
    var library_stem: ?[]const u8 = null;
    var loading: LibraryLoadingArgs = .{};

    var index: usize = 0;
    while (index < args.len) {
        const flag = args[index];
        index += 1;
        if (std.mem.eql(u8, flag, "--raw-colocated")) {
            if (raw_colocated_seen) return error.DuplicateArgument;
            raw_colocated_seen = true;
            raw_colocated = true;
        } else if (std.mem.eql(u8, flag, "--go-must-variants")) {
            if (go_must_variants) return error.DuplicateArgument;
            go_must_variants = true;
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
        } else if (std.mem.eql(u8, flag, "--header-name")) {
            try set(&header_name, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--cflags")) {
            try set(&cflags, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--ldflags")) {
            try set(&ldflags, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--extra-ldflags")) {
            try set(&extra_ldflags, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--ldflags-external")) {
            if (ldflags_external) return error.DuplicateArgument;
            ldflags_external = true;
        } else if (std.mem.eql(u8, flag, "--system-ldflags")) {
            try set(&system_ldflags, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--pkg-config-libs")) {
            try set(&pkg_config_libs, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--framework-ldflags")) {
            try set(&framework_ldflags, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--raw-package-path")) {
            try set(&raw_package_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--go-package")) {
            try set(&go_package, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--go-package-path")) {
            try set(&go_package_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--go-package-doc")) {
            try set(&go_package_doc, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--raw-package-name")) {
            try set(&raw_package_name, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--errors-lock")) {
            try set(&errors_lock_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--backend")) {
            if (backend != null) return error.DuplicateArgument;
            backend = parseBackend(try takeValue(args, &index)) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, flag, "--link-mode")) {
            if (link_mode != null) return error.DuplicateArgument;
            link_mode = parseLinkMode(try takeValue(args, &index)) orelse return error.InvalidValue;
        } else if (try loading.parseFlag(flag, args, &index)) {
            // handled by the shared loading-policy parser
        } else if (std.mem.eql(u8, flag, "--library-stem")) {
            try set(&library_stem, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--gofmt")) {
            try set(&gofmt_executable, try takeValue(args, &index));
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
        .header_name = header_name orelse "",
        .cflags = cflags orelse "",
        .ldflags = ldflags orelse "",
        .extra_ldflags = extra_ldflags orelse "",
        .ldflags_external = ldflags_external,
        .system_ldflags = system_ldflags orelse "",
        .pkg_config_libs = pkg_config_libs orelse "",
        .framework_ldflags = framework_ldflags orelse "",
        .raw_package_path = raw_package_path orelse "internal/raw",
        .raw_package_name = raw_package_name orelse "raw",
        .go_package = go_package orelse "",
        .go_package_path = go_package_path orelse go_package orelse "",
        .go_package_doc = go_package_doc orelse "",
        .go_must_variants = go_must_variants,
        .raw_colocated = raw_colocated,
        .errors_lock_path = errors_lock_path,
        .backend = backend orelse .cgo,
        .link_mode = link_mode orelse .static,
        .library_stem = library_stem orelse "",
        .library_search_paths = loading.search_paths orelse "",
        .library_env_vars = loading.env_vars,
        .library_automatic = loading.automatic,
        .library_exported_api = loading.exported_api,
        .gofmt_executable = gofmt_executable orelse "gofmt",
    };
}

fn parseCheck(args: []const []const u8) ParseError!Check {
    var generated_path: ?[]const u8 = null;
    var source_path: ?[]const u8 = null;
    var files: std.ArrayList(FilePair) = .empty;
    var index: usize = 0;
    while (index < args.len) {
        const flag = args[index];
        index += 1;
        if (std.mem.eql(u8, flag, "--generated")) {
            try set(&generated_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--source")) {
            try set(&source_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--file")) {
            const generated = try takeValue(args, &index);
            const source = try takeValue(args, &index);
            files.append(std.heap.page_allocator, .{ .generated_path = generated, .source_path = source }) catch @panic("OOM");
        } else {
            return error.UnknownArgument;
        }
    }
    return .{
        .generated_path = generated_path orelse return error.MissingRequiredArgument,
        .source_path = source_path orelse return error.MissingRequiredArgument,
        .files = files.items,
    };
}

fn parseAbiDiff(args: []const []const u8) ParseError!AbiDiff {
    var base_path: ?[]const u8 = null;
    var current_path: ?[]const u8 = null;
    var json = false;
    var json_seen = false;
    var fail_on_breaking = false;
    var fail_on_seen = false;
    var base_backend: ?Backend = null;
    var current_backend: ?Backend = null;
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
        } else if (std.mem.eql(u8, flag, "--base-backend")) {
            if (base_backend != null) return error.DuplicateArgument;
            base_backend = parseBackend(try takeValue(args, &index)) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, flag, "--current-backend")) {
            if (current_backend != null) return error.DuplicateArgument;
            current_backend = parseBackend(try takeValue(args, &index)) orelse return error.InvalidValue;
        } else {
            return error.UnknownArgument;
        }
    }
    return .{
        .base_path = base_path orelse return error.MissingRequiredArgument,
        .current_path = current_path orelse return error.MissingRequiredArgument,
        .json = json,
        .fail_on_breaking = fail_on_breaking,
        .base_backend = base_backend orelse .cgo,
        .current_backend = current_backend orelse .cgo,
    };
}

fn parseReport(args: []const []const u8) ParseError!Report {
    var semantic_path: ?[]const u8 = null;
    var go_module: ?[]const u8 = null;
    var raw_package_path: ?[]const u8 = null;
    var raw_colocated = false;
    var raw_colocated_seen = false;
    var backend: ?Backend = null;
    var go_package: ?[]const u8 = null;
    var go_package_path: ?[]const u8 = null;
    var loading: LibraryLoadingArgs = .{};
    var index: usize = 0;
    while (index < args.len) {
        const flag = args[index];
        index += 1;
        if (try loading.parseFlag(flag, args, &index)) {
            // handled by the shared loading-policy parser
        } else if (std.mem.eql(u8, flag, "--semantic")) {
            try set(&semantic_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--go-module")) {
            try set(&go_module, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--raw-package-path")) {
            try set(&raw_package_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--go-package")) {
            try set(&go_package, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--go-package-path")) {
            try set(&go_package_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--raw-colocated")) {
            if (raw_colocated_seen) return error.DuplicateArgument;
            raw_colocated_seen = true;
            raw_colocated = true;
        } else if (std.mem.eql(u8, flag, "--backend")) {
            if (backend != null) return error.DuplicateArgument;
            backend = parseBackend(try takeValue(args, &index)) orelse return error.InvalidValue;
        } else {
            return error.UnknownArgument;
        }
    }
    return .{
        .semantic_path = semantic_path orelse return error.MissingRequiredArgument,
        .go_module = go_module orelse "",
        .raw_package_path = raw_package_path orelse "internal/raw",
        .raw_colocated = raw_colocated,
        .backend = backend orelse .cgo,
        .go_package = go_package orelse "",
        .go_package_path = go_package_path orelse go_package orelse "",
        .library_search_paths = loading.search_paths orelse "",
        .library_env_vars = loading.env_vars,
        .library_automatic = loading.automatic,
        .library_exported_api = loading.exported_api,
    };
}

fn parseDoctor(args: []const []const u8) ParseError!Doctor {
    var go_executable: ?[]const u8 = null;
    var gofmt_executable: ?[]const u8 = null;
    var native_target = true;
    var target_seen = false;
    var backend: ?Backend = null;
    var library_path: ?[]const u8 = null;
    var go_mod_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < args.len) {
        const flag = args[index];
        index += 1;
        if (std.mem.eql(u8, flag, "--go")) {
            try set(&go_executable, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--library")) {
            try set(&library_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--go-mod")) {
            try set(&go_mod_path, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--gofmt")) {
            try set(&gofmt_executable, try takeValue(args, &index));
        } else if (std.mem.eql(u8, flag, "--target")) {
            if (target_seen) return error.DuplicateArgument;
            target_seen = true;
            const value = try takeValue(args, &index);
            if (std.mem.eql(u8, value, "native")) {
                native_target = true;
            } else if (std.mem.eql(u8, value, "cross")) {
                native_target = false;
            } else {
                return error.InvalidValue;
            }
        } else if (std.mem.eql(u8, flag, "--backend")) {
            if (backend != null) return error.DuplicateArgument;
            backend = parseBackend(try takeValue(args, &index)) orelse return error.InvalidValue;
        } else {
            return error.UnknownArgument;
        }
    }
    return .{
        .go_executable = go_executable orelse "go",
        .gofmt_executable = gofmt_executable orelse "gofmt",
        .native_target = native_target,
        .backend = backend orelse .cgo,
        .library_path = library_path,
        .go_mod_path = go_mod_path,
    };
}

fn parseLinkMode(value: []const u8) ?LinkMode {
    if (std.mem.eql(u8, value, "static")) return .static;
    if (std.mem.eql(u8, value, "dynamic")) return .dynamic;
    return null;
}

fn parseBackend(value: []const u8) ?Backend {
    if (std.mem.eql(u8, value, "cgo")) return .cgo;
    if (std.mem.eql(u8, value, "purego")) return .purego;
    return null;
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
        "--go-package",
        "scalarapi",
        "--go-package-path",
        ".",
        "--include-dir",
        "include",
        "--library-dir",
        "lib",
        "--header-name",
        "flags_native.h",
        "--cflags",
        "-Icustom",
        "--ldflags",
        "-Lcustom",
        "--extra-ldflags",
        "-Wl,--as-needed",
        "--system-ldflags",
        "-lz",
        "--framework-ldflags",
        "-framework CoreFoundation",
        "--raw-package-path",
        "scalar",
        "--raw-package-name",
        "scalar",
        "--raw-colocated",
        "--errors-lock",
        "errors.lock.json",
        "--go-must-variants",
    });
    const options = command.generate;
    try std.testing.expectEqualStrings("semantic.json", options.semantic_path);
    try std.testing.expectEqualStrings("scalar", options.package);
    try std.testing.expectEqualStrings("example.com/scalar", options.go_module);
    try std.testing.expectEqualStrings("scalarapi", options.go_package);
    try std.testing.expectEqualStrings(".", options.go_package_path);
    try std.testing.expectEqualStrings("-Icustom", options.cflags);
    try std.testing.expectEqualStrings("flags_native.h", options.header_name);
    try std.testing.expectEqualStrings("-Wl,--as-needed", options.extra_ldflags);
    try std.testing.expectEqualStrings("scalar", options.raw_package_path);
    try std.testing.expect(options.raw_colocated);
    try std.testing.expectEqualStrings("errors.lock.json", options.errors_lock_path.?);
    try std.testing.expect(options.go_must_variants);

    const dynamic_generate = (try parse(&.{ "generate", "--semantic", "s.json", "--output", "out", "--package", "scalar", "--link-mode", "dynamic", "--library-stem", "scalar_zigo" })).generate;
    try std.testing.expectEqual(LinkMode.dynamic, dynamic_generate.link_mode);
    try std.testing.expectEqualStrings("scalar_zigo", dynamic_generate.library_stem);
    try std.testing.expectError(error.InvalidValue, parse(&.{ "generate", "--semantic", "s.json", "--output", "out", "--package", "scalar", "--link-mode", "shared" }));

    const loading = (try parse(&.{ "generate", "--semantic", "s.json", "--output", "out", "--package", "scalar", "--library-search-paths", "${EXECUTABLE_DIR}:/opt/app/lib", "--library-env-vars", "ZIGO_SCALAR_LIBRARY_PATH,ZIGO_LIBRARY_PATH", "--library-automatic", "--library-internal-api" })).generate;
    try std.testing.expectEqualStrings("${EXECUTABLE_DIR}:/opt/app/lib", loading.library_search_paths);
    try std.testing.expectEqualStrings("ZIGO_SCALAR_LIBRARY_PATH,ZIGO_LIBRARY_PATH", loading.library_env_vars.?);
    try std.testing.expect(loading.library_automatic);
    try std.testing.expect(!loading.library_exported_api);
    try std.testing.expectError(error.DuplicateArgument, parse(&.{ "generate", "--semantic", "s.json", "--output", "out", "--package", "scalar", "--library-automatic", "--library-automatic" }));

    // The same policy flags configure the report so it can explain the contract.
    const loading_report = (try parse(&.{ "report", "--semantic", "s.json", "--backend", "purego", "--library-env-vars", "" })).report;
    try std.testing.expectEqualStrings("", loading_report.library_env_vars.?);
    try std.testing.expect(loading_report.library_exported_api);
}

test "generate command retains defaults" {
    const command = try parse(&.{ "generate", "--semantic", "semantic.json", "--output", "out", "--package", "scalar" });
    const options = command.generate;
    try std.testing.expectEqualStrings("zg", options.prefix);
    try std.testing.expectEqualStrings("scalar", options.go_module);
    try std.testing.expectEqualStrings("internal/raw", options.raw_package_path);
    try std.testing.expectEqualStrings("", options.go_package_path);
    try std.testing.expect(!options.raw_colocated);
    try std.testing.expect(options.errors_lock_path == null);
    try std.testing.expect(!options.go_must_variants);

    const named = (try parse(&.{ "generate", "--semantic", "semantic.json", "--output", "out", "--package", "scalar", "--go-package", "scalarapi" })).generate;
    try std.testing.expectEqualStrings("scalarapi", named.go_package_path);
}

test "check and abi-diff commands parse named arguments" {
    const check = (try parse(&.{ "check", "--generated", "expected", "--source", "go", "--file", "out/semantic.json", "zigo/semantic.json" })).check;
    try std.testing.expectEqualStrings("expected", check.generated_path);
    try std.testing.expectEqualStrings("go", check.source_path);
    try std.testing.expectEqual(@as(usize, 1), check.files.len);
    try std.testing.expectEqualStrings("out/semantic.json", check.files[0].generated_path);
    try std.testing.expectEqualStrings("zigo/semantic.json", check.files[0].source_path);

    const diff = (try parse(&.{ "abi-diff", "--base", "old.json", "--current", "new.json", "--base-backend", "cgo", "--current-backend", "purego", "--json", "--fail-on", "breaking" })).abi_diff;
    try std.testing.expect(diff.json);
    try std.testing.expect(diff.fail_on_breaking);
    try std.testing.expectEqual(Backend.cgo, diff.base_backend);
    try std.testing.expectEqual(Backend.purego, diff.current_backend);
}

test "report and doctor commands parse effective configuration" {
    const report = (try parse(&.{ "report", "--semantic", "semantic.json", "--go-module", "example.com/api", "--raw-package-path", "bridge/raw", "--go-package", "api", "--go-package-path", ".", "--raw-colocated" })).report;
    try std.testing.expectEqualStrings("semantic.json", report.semantic_path);
    try std.testing.expectEqualStrings("example.com/api", report.go_module);
    try std.testing.expectEqualStrings(".", report.go_package_path);
    try std.testing.expect(report.raw_colocated);

    const doctor = (try parse(&.{ "doctor", "--go", "/tools/go", "--gofmt", "/tools/gofmt", "--target", "cross" })).doctor;
    try std.testing.expectEqualStrings("/tools/go", doctor.go_executable);
    try std.testing.expect(!doctor.native_target);
    try std.testing.expect(doctor.library_path == null);

    const purego_doctor = (try parse(&.{ "doctor", "--backend", "purego", "--library", "zig-out/lib/libscalar_zigo.so", "--go-mod", "go/go.mod" })).doctor;
    try std.testing.expectEqual(Backend.purego, purego_doctor.backend);
    try std.testing.expectEqualStrings("zig-out/lib/libscalar_zigo.so", purego_doctor.library_path.?);
    try std.testing.expectEqualStrings("go/go.mod", purego_doctor.go_mod_path.?);
    try std.testing.expectError(error.DuplicateArgument, parse(&.{ "doctor", "--library", "one", "--library", "two" }));
}

test "parser rejects incomplete unknown and duplicate arguments" {
    try std.testing.expectError(error.UnknownCommand, parse(&.{"--check"}));
    try std.testing.expectError(error.MissingRequiredArgument, parse(&.{ "generate", "--semantic", "semantic.json" }));
    try std.testing.expectError(error.MissingValue, parse(&.{ "check", "--generated" }));
    try std.testing.expectError(error.MissingValue, parse(&.{ "check", "--generated", "a", "--source", "b", "--file", "only" }));
    try std.testing.expectError(error.UnknownArgument, parse(&.{ "check", "--wat", "value" }));
    try std.testing.expectError(error.UnknownArgument, parse(&.{ "generate", "--semantic", "s.json", "--output", "out", "--package", "scalar", "--auto-cleanup" }));
    try std.testing.expectError(error.DuplicateArgument, parse(&.{ "check", "--generated", "one", "--generated", "two", "--source", "go" }));
    try std.testing.expectError(error.DuplicateArgument, parse(&.{ "generate", "--semantic", "semantic.json", "--output", "out", "--package", "scalar", "--raw-colocated", "--raw-colocated" }));
    try std.testing.expectError(error.DuplicateArgument, parse(&.{ "generate", "--semantic", "semantic.json", "--output", "out", "--package", "scalar", "--go-must-variants", "--go-must-variants" }));
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
