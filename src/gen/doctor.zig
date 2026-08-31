const std = @import("std");

pub const Options = struct {
    pub const Backend = enum { cgo, purego };
    go_executable: []const u8 = "go",
    gofmt_executable: []const u8 = "gofmt",
    native_target: bool = true,
    auto_cleanup: bool = false,
    backend: Backend = .cgo,
    /// Installed shared library validated by the purego backend.
    library_path: ?[]const u8 = null,
    /// `go.mod` of the module that imports the generated purego bindings.
    go_mod_path: ?[]const u8 = null,
};

/// Version of purego this generator emits and tests against.
pub const purego_version = "v0.10.2";
pub const purego_module = "github.com/ebitengine/purego";

pub const LibraryState = enum { unchecked, missing, unloadable, loadable };
pub const ModuleState = enum { unchecked, unreadable, missing, pinned, other_version };

pub const Probe = struct {
    go_version: ?[]const u8,
    cgo_enabled: ?[]const u8,
    c_compiler: ?[]const u8,
    c_compiler_available: bool,
    gofmt_available: bool,
    native_target: bool,
    platform_supported: bool = true,
    platform_name: []const u8 = "",
    library_path: ?[]const u8 = null,
    library_state: LibraryState = .unchecked,
    library_error: ?[]const u8 = null,
    go_mod_path: ?[]const u8 = null,
    module_state: ModuleState = .unchecked,
    module_version: ?[]const u8 = null,
};

pub fn run(allocator: std.mem.Allocator, io: std.Io, writer: *std.Io.Writer, options: Options) !bool {
    const go_version_result = std.process.run(allocator, io, .{
        .argv = &.{ options.go_executable, "version" },
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch null;
    defer if (go_version_result) |result| {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    };
    const cgo_result = if (go_version_result != null and options.backend == .cgo) std.process.run(allocator, io, .{
        .argv = &.{ options.go_executable, "env", "CGO_ENABLED" },
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch null else null;
    defer if (cgo_result) |result| {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    };
    const cc_result = if (go_version_result != null and options.backend == .cgo) std.process.run(allocator, io, .{
        .argv = &.{ options.go_executable, "env", "CC" },
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch null else null;
    defer if (cc_result) |result| {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    };
    const cc_name = if (cc_result) |result| if (termSucceeded(result.term)) firstWord(result.stdout) else null else null;
    const cc_probe_result = if (cc_name) |name| std.process.run(allocator, io, .{
        .argv = &.{ name, "--version" },
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch null else null;
    defer if (cc_probe_result) |result| {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    };
    const gofmt_result = std.process.run(allocator, io, .{
        .argv = &.{ options.gofmt_executable, "-h" },
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch null;
    defer if (gofmt_result) |result| {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    };
    var library_error_buffer: [256]u8 = undefined;
    const library = if (options.backend == .purego) probeLibrary(options.library_path, &library_error_buffer) else Library{};
    const go_mod_bytes = if (options.backend == .purego and options.go_mod_path != null)
        std.Io.Dir.cwd().readFileAlloc(io, options.go_mod_path.?, allocator, .limited(4 * 1024 * 1024)) catch null
    else
        null;
    defer if (go_mod_bytes) |bytes| allocator.free(bytes);
    const module = if (options.backend == .purego and options.go_mod_path != null)
        probeModule(go_mod_bytes)
    else
        Module{};
    return render(writer, .{
        .go_version = if (go_version_result) |result| if (termSucceeded(result.term)) std.mem.trim(u8, result.stdout, " \r\n\t") else null else null,
        .cgo_enabled = if (cgo_result) |result| if (termSucceeded(result.term)) std.mem.trim(u8, result.stdout, " \r\n\t") else null else null,
        .c_compiler = cc_name,
        .c_compiler_available = cc_probe_result != null,
        .gofmt_available = gofmt_result != null,
        .native_target = options.native_target,
        .platform_supported = hostPlatformSupported(),
        .platform_name = host_platform_name,
        .library_path = options.library_path,
        .library_state = library.state,
        .library_error = library.message,
        .go_mod_path = options.go_mod_path,
        .module_state = module.state,
        .module_version = module.version,
    }, options.auto_cleanup, options.backend);
}

const Library = struct {
    state: LibraryState = .unchecked,
    message: ?[]const u8 = null,
};

const Module = struct {
    state: ModuleState = .unchecked,
    version: ?[]const u8 = null,
};

/// purego supports macOS and Linux on amd64/arm64 in this backend.
pub fn hostPlatformSupported() bool {
    const host = @import("builtin").target;
    return (host.os.tag == .macos or host.os.tag == .linux) and
        (host.cpu.arch == .x86_64 or host.cpu.arch == .aarch64);
}

const host_platform_name = @tagName(@import("builtin").target.os.tag) ++ "/" ++ @tagName(@import("builtin").target.cpu.arch);

/// Loads the installed shared library exactly like the generated Go loader does.
fn probeLibrary(path: ?[]const u8, message_buffer: []u8) Library {
    const value = path orelse return .{};
    var library = std.DynLib.open(value) catch |err| return .{
        .state = if (err == error.FileNotFound) .missing else .unloadable,
        .message = std.fmt.bufPrint(message_buffer, "{t}", .{err}) catch @errorName(err),
    };
    library.close();
    return .{ .state = .loadable };
}

/// Reports whether `go.mod` requires the purego version this generator emits for.
fn probeModule(contents: ?[]const u8) Module {
    const bytes = contents orelse return .{ .state = .unreadable };
    var lines = std.mem.tokenizeAny(u8, bytes, "\r\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        const start = std.mem.indexOf(u8, trimmed, purego_module) orelse continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        var fields = std.mem.tokenizeAny(u8, trimmed[start + purego_module.len ..], " \t");
        const version = fields.next() orelse return .{ .state = .other_version };
        if (std.mem.eql(u8, version, purego_version)) return .{ .state = .pinned, .version = version };
        return .{ .state = .other_version, .version = version };
    }
    return .{ .state = .missing };
}

pub fn render(writer: *std.Io.Writer, probe: Probe, auto_cleanup: bool, backend: Options.Backend) !bool {
    var healthy = true;
    if (probe.native_target) {
        try writer.writeAll("PASS target: native build\n");
    } else {
        healthy = false;
        try writer.writeAll("FAIL target: cross compilation is not supported; use the native host target\n");
    }

    const minimum_minor: u32 = if (auto_cleanup) 24 else 23;
    if (probe.go_version) |version_output| {
        if (parseGoVersion(version_output)) |version| {
            if (version.major > 1 or (version.major == 1 and version.minor >= minimum_minor)) {
                try writer.print("PASS go: {s} (minimum 1.{d})\n", .{ version.token, minimum_minor });
            } else {
                healthy = false;
                try writer.print("FAIL go: {s} is too old; install Go 1.{d} or newer{s}\n", .{ version.token, minimum_minor, if (auto_cleanup) " for auto_cleanup" else "" });
            }
        } else {
            healthy = false;
            try writer.print("FAIL go: could not parse `go version` output: {s}\n", .{version_output});
        }
    } else {
        healthy = false;
        try writer.print("FAIL go: executable unavailable; install Go 1.{d} or newer and add it to PATH\n", .{minimum_minor});
    }

    if (backend == .purego) {
        try writer.writeAll("PASS purego: no C compiler required at Go build time\n");
        try renderPurego(writer, probe, &healthy);
    } else if (probe.cgo_enabled) |enabled| {
        if (std.mem.eql(u8, enabled, "1")) {
            try writer.writeAll("PASS cgo: enabled\n");
        } else {
            healthy = false;
            try writer.writeAll("FAIL cgo: disabled; set CGO_ENABLED=1 and install a native C toolchain\n");
        }
    } else {
        healthy = false;
        try writer.writeAll("FAIL cgo: unable to query `go env CGO_ENABLED`\n");
    }

    if (backend == .purego) {
        // Runtime loading uses the prebuilt native library.
    } else if (probe.c_compiler) |compiler| {
        if (probe.c_compiler_available) {
            try writer.print("PASS C compiler: {s}\n", .{compiler});
        } else {
            healthy = false;
            try writer.print("FAIL C compiler: {s} is configured by `go env CC` but is not executable\n", .{compiler});
        }
    } else {
        healthy = false;
        try writer.writeAll("FAIL C compiler: unable to query `go env CC`; install a native C toolchain\n");
    }

    if (probe.gofmt_available)
        try writer.writeAll("PASS gofmt: available\n")
    else
        try writer.writeAll("WARN gofmt: unavailable; generation remains supported but install gofmt for standard formatting\n");

    try writer.writeAll(if (healthy) "doctor: ok\n" else "doctor: failed\n");
    return healthy;
}

fn renderPurego(writer: *std.Io.Writer, probe: Probe, healthy: *bool) !void {
    if (probe.platform_supported) {
        try writer.print("PASS purego platform: {s} is supported\n", .{probe.platform_name});
    } else {
        healthy.* = false;
        try writer.print("FAIL purego platform: {s} is unsupported; purego bindings require macOS or Linux on amd64/arm64\n", .{probe.platform_name});
    }

    switch (probe.module_state) {
        .unchecked => {},
        .unreadable => {
            healthy.* = false;
            try writer.print("FAIL purego module: unable to read {s}; run `zig build go` to create the module\n", .{probe.go_mod_path orelse "go.mod"});
        },
        .missing => {
            healthy.* = false;
            try writer.print("FAIL purego module: {s} does not require {s}; run `go get {s}@{s}`\n", .{ probe.go_mod_path orelse "go.mod", purego_module, purego_module, purego_version });
        },
        .other_version => try writer.print("WARN purego module: {s} requires {s} {s}; zigo generates and tests against {s}\n", .{ probe.go_mod_path orelse "go.mod", purego_module, probe.module_version orelse "an unparsed version", purego_version }),
        .pinned => try writer.print("PASS purego module: {s} {s}\n", .{ purego_module, purego_version }),
    }

    switch (probe.library_state) {
        .unchecked => {},
        .missing => {
            healthy.* = false;
            try writer.print("FAIL shared library: {s} is missing; run `zig build go-lib` to build and install it\n", .{probe.library_path orelse ""});
        },
        .unloadable => {
            healthy.* = false;
            try writer.print("FAIL shared library: {s} could not be loaded: {s}\n", .{ probe.library_path orelse "", probe.library_error orelse "unknown error" });
        },
        .loadable => try writer.print("PASS shared library: {s} loads at run time\n", .{probe.library_path orelse ""}),
    }
}

const GoVersion = struct {
    major: u32,
    minor: u32,
    token: []const u8,
};

fn parseGoVersion(output: []const u8) ?GoVersion {
    var words = std.mem.tokenizeAny(u8, output, " \r\n\t");
    while (words.next()) |word| {
        if (word.len < 4 or !std.mem.startsWith(u8, word, "go")) continue;
        const body = word[2..];
        const dot = std.mem.indexOfScalar(u8, body, '.') orelse continue;
        const major = std.fmt.parseUnsigned(u32, body[0..dot], 10) catch continue;
        var minor_end = dot + 1;
        while (minor_end < body.len and std.ascii.isDigit(body[minor_end])) : (minor_end += 1) {}
        if (minor_end == dot + 1) continue;
        const minor = std.fmt.parseUnsigned(u32, body[dot + 1 .. minor_end], 10) catch continue;
        return .{ .major = major, .minor = minor, .token = word };
    }
    return null;
}

fn firstWord(output: []const u8) ?[]const u8 {
    var words = std.mem.tokenizeAny(u8, output, " \r\n\t");
    return words.next();
}

fn termSucceeded(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

test "doctor distinguishes required failures from optional gofmt" {
    var healthy_output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer healthy_output.deinit();
    try std.testing.expect(try render(&healthy_output.writer, .{
        .go_version = "go version go1.24.2 linux/amd64",
        .cgo_enabled = "1",
        .c_compiler = "cc",
        .c_compiler_available = true,
        .gofmt_available = false,
        .native_target = true,
    }, true, .cgo));
    try std.testing.expect(std.mem.indexOf(u8, healthy_output.written(), "WARN gofmt") != null);
    try std.testing.expect(std.mem.indexOf(u8, healthy_output.written(), "doctor: ok") != null);

    var failed_output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer failed_output.deinit();
    try std.testing.expect(!try render(&failed_output.writer, .{
        .go_version = "go version go1.23.9 darwin/arm64",
        .cgo_enabled = "0",
        .c_compiler = "missing-cc",
        .c_compiler_available = false,
        .gofmt_available = true,
        .native_target = false,
    }, true, .cgo));
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "install Go 1.24 or newer for auto_cleanup") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "CGO_ENABLED=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "missing-cc is configured") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "cross compilation is not supported") != null);
}

test "purego doctor does not require cgo or a C compiler" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expect(try render(&output.writer, .{
        .go_version = "go version go1.24.2 linux/amd64",
        .cgo_enabled = null,
        .c_compiler = null,
        .c_compiler_available = false,
        .gofmt_available = true,
        .native_target = true,
    }, false, .purego));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "no C compiler required") != null);
}

test "purego doctor reports artifact, module, and platform problems" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expect(!try render(&output.writer, .{
        .go_version = "go version go1.24.2 linux/amd64",
        .cgo_enabled = null,
        .c_compiler = null,
        .c_compiler_available = false,
        .gofmt_available = true,
        .native_target = true,
        .platform_supported = false,
        .platform_name = "windows/x86_64",
        .library_path = "zig-out/lib/libscalar_zigo.so",
        .library_state = .missing,
        .go_mod_path = "go/go.mod",
        .module_state = .missing,
    }, false, .purego));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "FAIL purego platform: windows/x86_64 is unsupported") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "run `go get github.com/ebitengine/purego@v0.10.2`") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "libscalar_zigo.so is missing; run `zig build go-lib`") != null);

    var unloadable: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer unloadable.deinit();
    try std.testing.expect(!try render(&unloadable.writer, .{
        .go_version = "go version go1.24.2 linux/amd64",
        .cgo_enabled = null,
        .c_compiler = null,
        .c_compiler_available = false,
        .gofmt_available = true,
        .native_target = true,
        .platform_name = "linux/x86_64",
        .library_path = "zig-out/lib/libscalar_zigo.so",
        .library_state = .unloadable,
        .library_error = "FileBusy",
        .go_mod_path = "go/go.mod",
        .module_state = .other_version,
        .module_version = "v0.9.0",
    }, false, .purego));
    try std.testing.expect(std.mem.indexOf(u8, unloadable.written(), "could not be loaded: FileBusy") != null);
    try std.testing.expect(std.mem.indexOf(u8, unloadable.written(), "WARN purego module") != null);

    var healthy: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer healthy.deinit();
    try std.testing.expect(try render(&healthy.writer, .{
        .go_version = "go version go1.24.2 darwin/arm64",
        .cgo_enabled = null,
        .c_compiler = null,
        .c_compiler_available = false,
        .gofmt_available = true,
        .native_target = true,
        .platform_name = "macos/aarch64",
        .library_path = "zig-out/lib/libscalar_zigo.dylib",
        .library_state = .loadable,
        .go_mod_path = "go/go.mod",
        .module_state = .pinned,
        .module_version = purego_version,
    }, false, .purego));
    try std.testing.expect(std.mem.indexOf(u8, healthy.written(), "PASS purego module: github.com/ebitengine/purego v0.10.2") != null);
    try std.testing.expect(std.mem.indexOf(u8, healthy.written(), "loads at run time") != null);
    try std.testing.expect(std.mem.indexOf(u8, healthy.written(), "doctor: ok") != null);
}

test "purego module probe reads the required version from go.mod" {
    try std.testing.expectEqual(ModuleState.unreadable, probeModule(null).state);
    try std.testing.expectEqual(ModuleState.missing, probeModule("module example.com/app\n\ngo 1.23\n").state);
    const pinned = probeModule("module example.com/app\n\ngo 1.23\n\nrequire github.com/ebitengine/purego v0.10.2\n");
    try std.testing.expectEqual(ModuleState.pinned, pinned.state);
    const block = probeModule("require (\n\tgithub.com/ebitengine/purego v0.9.0 // indirect\n)\n");
    try std.testing.expectEqual(ModuleState.other_version, block.state);
    try std.testing.expectEqualStrings("v0.9.0", block.version.?);
    try std.testing.expectEqual(ModuleState.missing, probeModule("// github.com/ebitengine/purego v0.10.2\n").state);
}

test "shared library probe distinguishes a missing file from a loadable one" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqual(LibraryState.unchecked, probeLibrary(null, &buffer).state);
    try std.testing.expectEqual(LibraryState.missing, probeLibrary("./definitely-missing-zigo-library.so", &buffer).state);
}

test "Go version parser accepts development and future major versions" {
    const development = parseGoVersion("go version go1.26rc1 linux/amd64").?;
    try std.testing.expectEqual(@as(u32, 1), development.major);
    try std.testing.expectEqual(@as(u32, 26), development.minor);
    const future = parseGoVersion("go version go2.0 darwin/arm64").?;
    try std.testing.expectEqual(@as(u32, 2), future.major);
}
