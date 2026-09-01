const std = @import("std");
const build_options = @import("build_options");
const dynamic_library = @import("dynamic_library");

pub const Options = struct {
    pub const Backend = enum { cgo, purego };
    go_executable: []const u8 = "go",
    gofmt_executable: []const u8 = "gofmt",
    native_target: bool = true,
    backend: Backend = .cgo,
    /// Installed shared library validated by the purego backend.
    library_path: ?[]const u8 = null,
    /// `go.mod` of the module that imports the generated purego bindings.
    go_mod_path: ?[]const u8 = null,
};

/// State of a purego deployment. Absent members were not asked about.
pub const Purego = struct {
    platform: []const u8 = host_platform,
    platform_supported: bool = true,
    library: ?Library = null,
    module: ?Module = null,

    pub const Library = struct {
        pub const State = enum { missing, unloadable, loadable };
        path: []const u8,
        state: State,
        message: ?[]const u8 = null,
    };

    pub const Module = struct {
        pub const State = enum { unreadable, missing, pinned, other_version };
        path: []const u8,
        state: State,
        /// Only set when the required version is not the tested one.
        version: ?[]const u8 = null,
    };
};

pub const Probe = struct {
    go_version: ?[]const u8,
    cgo_enabled: ?[]const u8,
    c_compiler: ?[]const u8,
    c_compiler_available: bool,
    gofmt_available: bool,
    native_target: bool,
    purego: Purego = .{},
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
    // `go env CC` can be a whole command line rather than one program: the
    // supported Windows toolchain is `CC="zig cc"`, and a cross build adds
    // `-target <triple>` on top of that. Probe the program, report the whole
    // thing -- the arguments are the part a reader needs to see.
    const cc_command = stdoutIfSucceeded(cc_result);
    const cc_probe_result = if (cc_command) |command| std.process.run(allocator, io, .{
        .argv = &.{ firstWord(command).?, "--version" },
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
    // The parsed version borrows these bytes, so they must outlive `render`.
    const go_mod_bytes = if (options.backend == .purego and options.go_mod_path != null)
        std.Io.Dir.cwd().readFileAlloc(io, options.go_mod_path.?, allocator, .limited(4 * 1024 * 1024)) catch null
    else
        null;
    defer if (go_mod_bytes) |bytes| allocator.free(bytes);
    var library_error_buffer: [256]u8 = undefined;
    return render(writer, .{
        .go_version = stdoutIfSucceeded(go_version_result),
        .cgo_enabled = stdoutIfSucceeded(cgo_result),
        .c_compiler = cc_command,
        .c_compiler_available = cc_probe_result != null,
        .gofmt_available = gofmt_result != null,
        .native_target = options.native_target,
        .purego = if (options.backend == .purego) probePurego(options, go_mod_bytes, &library_error_buffer) else .{},
    }, options.backend);
}

const host_platform = @tagName(@import("builtin").target.os.tag) ++ "/" ++ @tagName(@import("builtin").target.cpu.arch);

fn probePurego(options: Options, go_mod_bytes: ?[]const u8, message_buffer: []u8) Purego {
    return .{
        .platform_supported = build_options.puregoTargetSupported(@import("builtin").target),
        .library = if (options.library_path) |path| probeLibrary(path, message_buffer) else null,
        .module = if (options.go_mod_path) |path| probeModule(path, go_mod_bytes) else null,
    };
}

/// Loads the installed shared library exactly like the generated Go loader does.
fn probeLibrary(path: []const u8, message_buffer: []u8) Purego.Library {
    var library = dynamic_library.Library.open(path) catch |err| return .{
        .path = path,
        .state = if (err == error.FileNotFound) .missing else .unloadable,
        .message = std.fmt.bufPrint(message_buffer, "{t}", .{err}) catch @errorName(err),
    };
    library.close();
    return .{ .path = path, .state = .loadable };
}

/// Reports whether `go.mod` requires the purego version this generator emits for.
fn probeModule(path: []const u8, contents: ?[]const u8) Purego.Module {
    const bytes = contents orelse return .{ .path = path, .state = .unreadable };
    var lines = std.mem.tokenizeAny(u8, bytes, "\r\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        const start = std.mem.indexOf(u8, trimmed, build_options.purego_module) orelse continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        var fields = std.mem.tokenizeAny(u8, trimmed[start + build_options.purego_module.len ..], " \t");
        const version = fields.next() orelse return .{ .path = path, .state = .other_version };
        if (std.mem.eql(u8, version, build_options.purego_version)) return .{ .path = path, .state = .pinned };
        return .{ .path = path, .state = .other_version, .version = version };
    }
    return .{ .path = path, .state = .missing };
}

pub fn render(writer: *std.Io.Writer, probe: Probe, backend: Options.Backend) !bool {
    var healthy = true;
    if (probe.native_target) {
        try writer.writeAll("PASS target: native build\n");
    } else if (backend == .purego) {
        // The reflection pipeline builds for the host, so a purego library
        // cross-compiles. What the host cannot do is load a foreign artifact,
        // so the run-time checks below are skipped rather than failed.
        try writer.writeAll("SKIP target: cross build; the checks below describe this host, and the cross-built artifact has to be validated on the target\n");
    } else {
        healthy = false;
        // The archive itself cross-builds, and `CC="zig cc -target <triple>"`
        // links it -- but that needs GOOS, CGO_ENABLED and a -target-carrying
        // CC on the Go side, none of which this invocation can observe. So the
        // check stays a failure and points at the recipe instead of guessing.
        try writer.writeAll("FAIL target: the cgo backend cannot be validated from a cross build; use the native host target, or follow the cross recipe in docs/getting-started.md and validate on the target\n");
    }

    // Generated handles always register `runtime.AddCleanup`, which landed
    // in Go 1.24.
    const minimum_minor: u32 = 24;
    if (probe.go_version) |version_output| {
        if (parseGoVersion(version_output)) |version| {
            if (version.major > 1 or (version.major == 1 and version.minor >= minimum_minor)) {
                try writer.print("PASS go: {s} (minimum 1.{d})\n", .{ version.token, minimum_minor });
            } else {
                healthy = false;
                try writer.print("FAIL go: {s} is too old; install Go 1.{d} or newer\n", .{ version.token, minimum_minor });
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
        try renderPurego(writer, probe.purego, probe.native_target, &healthy);
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
            try writer.print("FAIL C compiler: {s} is configured by `go env CC` but {s} is not executable\n", .{ compiler, firstWord(compiler) orelse compiler });
        }
    } else {
        healthy = false;
        try writer.writeAll("FAIL C compiler: unable to query `go env CC`; install a native C toolchain\n");
    }

    if (probe.gofmt_available) {
        try writer.writeAll("PASS gofmt: available\n");
    } else {
        // Generation formats through gofmt, so a missing binary is not optional.
        healthy = false;
        try writer.writeAll("FAIL gofmt: unavailable; generated Go is formatted with gofmt, so install the Go distribution or set `.gofmt`\n");
    }

    try writer.writeAll(if (healthy) "doctor: ok\n" else "doctor: failed\n");
    return healthy;
}

fn renderPurego(writer: *std.Io.Writer, purego: Purego, native_target: bool, healthy: *bool) !void {
    if (purego.platform_supported) {
        try writer.print("PASS purego platform: {s} is supported\n", .{purego.platform});
    } else {
        healthy.* = false;
        try writer.print("FAIL purego platform: {s} is unsupported; purego bindings require macOS, Linux, or Windows on amd64/arm64\n", .{purego.platform});
    }

    const module = build_options.purego_module;
    const version = build_options.purego_version;
    if (purego.module) |required| switch (required.state) {
        .unreadable => {
            healthy.* = false;
            try writer.print("FAIL purego module: unable to read {s}; run `zig build go` to create the module\n", .{required.path});
        },
        .missing => {
            healthy.* = false;
            try writer.print("FAIL purego module: {s} does not require {s}; run `go get {s}@{s}`\n", .{ required.path, module, module, version });
        },
        .other_version => try writer.print("WARN purego module: {s} requires {s} {s}; zigo generates and tests against {s}\n", .{ required.path, module, required.version orelse "an unparsed version", version }),
        .pinned => try writer.print("PASS purego module: {s} {s}\n", .{ module, version }),
    };

    if (purego.library == null and !native_target)
        try writer.writeAll("SKIP shared library: a cross-built artifact cannot be loaded on this host\n");
    if (purego.library) |library| switch (library.state) {
        .missing => {
            healthy.* = false;
            try writer.print("FAIL shared library: {s} is missing; run `zig build go-lib` to build and install it\n", .{library.path});
        },
        .unloadable => {
            healthy.* = false;
            try writer.print("FAIL shared library: {s} could not be loaded: {s}\n", .{ library.path, library.message orelse "unknown error" });
        },
        .loadable => try writer.print("PASS shared library: {s} loads at run time\n", .{library.path}),
    };
}

const GoVersion = struct {
    major: u32,
    minor: u32,
    token: []const u8,
};

fn parseGoVersion(output: []const u8) ?GoVersion {
    var words = std.mem.tokenizeAny(u8, output, whitespace);
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

/// The trimmed stdout of a probe that ran and exited zero; null when the
/// probe could not run, failed, or printed nothing.
fn stdoutIfSucceeded(result: ?std.process.RunResult) ?[]const u8 {
    const ran = result orelse return null;
    if (!termSucceeded(ran.term)) return null;
    const trimmed = std.mem.trim(u8, ran.stdout, whitespace);
    return if (trimmed.len == 0) null else trimmed;
}

const whitespace = " \r\n\t";

fn firstWord(output: []const u8) ?[]const u8 {
    var words = std.mem.tokenizeAny(u8, output, whitespace);
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
        .gofmt_available = true,
        .native_target = true,
    }, .cgo));
    try std.testing.expect(std.mem.indexOf(u8, healthy_output.written(), "PASS gofmt") != null);
    try std.testing.expect(std.mem.indexOf(u8, healthy_output.written(), "PASS C compiler: cc\n") != null);
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
    }, .cgo));
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "install Go 1.24 or newer") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "CGO_ENABLED=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "missing-cc is configured") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "the cgo backend cannot be validated from a cross build") != null);

    // A purego cross build is supported: the target line and the run-time
    // library check report SKIP, and neither makes the doctor fail.
    var cross_purego: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer cross_purego.deinit();
    try std.testing.expect(try render(&cross_purego.writer, .{
        .go_version = "go version go1.24.2 linux/amd64",
        .cgo_enabled = null,
        .c_compiler = null,
        .c_compiler_available = false,
        .gofmt_available = true,
        .native_target = false,
        .purego = .{ .module = .{ .path = "go.mod", .state = .pinned } },
    }, .purego));
    try std.testing.expect(std.mem.indexOf(u8, cross_purego.written(), "SKIP target: cross build") != null);
    try std.testing.expect(std.mem.indexOf(u8, cross_purego.written(), "SKIP shared library: a cross-built artifact") != null);
    try std.testing.expect(std.mem.indexOf(u8, cross_purego.written(), "doctor: ok") != null);

    // A missing gofmt is a failure: generation formats through it.
    var unformatted: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer unformatted.deinit();
    try std.testing.expect(!try render(&unformatted.writer, .{
        .go_version = "go version go1.24.2 linux/amd64",
        .cgo_enabled = "1",
        .c_compiler = "cc",
        .c_compiler_available = true,
        .gofmt_available = false,
        .native_target = true,
    }, .cgo));
    try std.testing.expect(std.mem.indexOf(u8, unformatted.written(), "FAIL gofmt") != null);
}

test "doctor reports a multi-word CC in full" {
    // `CC="zig cc"` is the supported Windows toolchain: the probe runs `zig`,
    // but a report that printed only `zig` would hide which driver is in use.
    var probe: Probe = .{
        .go_version = "go version go1.26.0 windows/amd64",
        .cgo_enabled = "1",
        .c_compiler = "zig cc",
        .c_compiler_available = true,
        .gofmt_available = true,
        .native_target = true,
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expect(try render(&output.writer, probe, .cgo));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "PASS C compiler: zig cc\n") != null);

    probe.c_compiler_available = false;
    var missing: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer missing.deinit();
    try std.testing.expect(!try render(&missing.writer, probe, .cgo));
    // The blamed program is the one that was probed, not the whole line.
    try std.testing.expect(std.mem.indexOf(u8, missing.written(), "zig cc is configured by `go env CC` but zig is not executable") != null);
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
    }, .purego));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "no C compiler required") != null);
}

test "purego doctor reports artifact, module, and platform problems" {
    const environment: Probe = .{
        .go_version = "go version go1.24.2 linux/amd64",
        .cgo_enabled = null,
        .c_compiler = null,
        .c_compiler_available = false,
        .gofmt_available = true,
        .native_target = true,
    };

    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var probe = environment;
    probe.purego = .{
        .platform = "freebsd/x86_64",
        .platform_supported = false,
        .library = .{ .path = "zig-out/lib/libscalar_zigo.so", .state = .missing },
        .module = .{ .path = "go/go.mod", .state = .missing },
    };
    try std.testing.expect(!try render(&output.writer, probe, .purego));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "FAIL purego platform: freebsd/x86_64 is unsupported") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "run `go get github.com/ebitengine/purego@v0.10.2`") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "libscalar_zigo.so is missing; run `zig build go-lib`") != null);

    var unloadable: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer unloadable.deinit();
    probe = environment;
    probe.purego = .{
        .platform = "linux/x86_64",
        .library = .{ .path = "zig-out/lib/libscalar_zigo.so", .state = .unloadable, .message = "FileBusy" },
        .module = .{ .path = "go/go.mod", .state = .other_version, .version = "v0.9.0" },
    };
    try std.testing.expect(!try render(&unloadable.writer, probe, .purego));
    try std.testing.expect(std.mem.indexOf(u8, unloadable.written(), "could not be loaded: FileBusy") != null);
    try std.testing.expect(std.mem.indexOf(u8, unloadable.written(), "WARN purego module") != null);

    var healthy: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer healthy.deinit();
    probe = environment;
    probe.purego = .{
        .platform = "macos/aarch64",
        .library = .{ .path = "zig-out/lib/libscalar_zigo.dylib", .state = .loadable },
        .module = .{ .path = "go/go.mod", .state = .pinned },
    };
    try std.testing.expect(try render(&healthy.writer, probe, .purego));
    try std.testing.expect(std.mem.indexOf(u8, healthy.written(), "PASS purego module: github.com/ebitengine/purego v0.10.2") != null);
    try std.testing.expect(std.mem.indexOf(u8, healthy.written(), "loads at run time") != null);
    try std.testing.expect(std.mem.indexOf(u8, healthy.written(), "doctor: ok") != null);

    // Nothing to validate means nothing to report.
    var bare: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer bare.deinit();
    try std.testing.expect(try render(&bare.writer, environment, .purego));
    try std.testing.expect(std.mem.indexOf(u8, bare.written(), "shared library") == null);
    try std.testing.expect(std.mem.indexOf(u8, bare.written(), "purego module") == null);
}

test "purego module probe reads the required version from go.mod" {
    try std.testing.expectEqual(Purego.Module.State.unreadable, probeModule("go.mod", null).state);
    try std.testing.expectEqual(Purego.Module.State.missing, probeModule("go.mod", "module example.com/app\n\ngo 1.23\n").state);
    const pinned = probeModule("go.mod", "module example.com/app\n\ngo 1.23\n\nrequire github.com/ebitengine/purego v0.10.2\n");
    try std.testing.expectEqual(Purego.Module.State.pinned, pinned.state);
    const block = probeModule("go.mod", "require (\n\tgithub.com/ebitengine/purego v0.9.0 // indirect\n)\n");
    try std.testing.expectEqual(Purego.Module.State.other_version, block.state);
    try std.testing.expectEqualStrings("v0.9.0", block.version.?);
    try std.testing.expectEqual(Purego.Module.State.missing, probeModule("go.mod", "// github.com/ebitengine/purego v0.10.2\n").state);
}

test "shared library probe distinguishes a missing file from a loadable one" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqual(Purego.Library.State.missing, probeLibrary("./definitely-missing-zigo-library.so", &buffer).state);
}

test "Go version parser accepts development and future major versions" {
    const development = parseGoVersion("go version go1.26rc1 linux/amd64").?;
    try std.testing.expectEqual(@as(u32, 1), development.major);
    try std.testing.expectEqual(@as(u32, 26), development.minor);
    const future = parseGoVersion("go version go2.0 darwin/arm64").?;
    try std.testing.expectEqual(@as(u32, 2), future.major);
}
