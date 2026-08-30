const std = @import("std");

pub const Options = struct {
    go_executable: []const u8 = "go",
    gofmt_executable: []const u8 = "gofmt",
    native_target: bool = true,
    auto_cleanup: bool = false,
};

pub const Probe = struct {
    go_version: ?[]const u8,
    cgo_enabled: ?[]const u8,
    c_compiler: ?[]const u8,
    c_compiler_available: bool,
    gofmt_available: bool,
    native_target: bool,
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
    const cgo_result = if (go_version_result != null) std.process.run(allocator, io, .{
        .argv = &.{ options.go_executable, "env", "CGO_ENABLED" },
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch null else null;
    defer if (cgo_result) |result| {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    };
    const cc_result = if (go_version_result != null) std.process.run(allocator, io, .{
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
    return render(writer, .{
        .go_version = if (go_version_result) |result| if (termSucceeded(result.term)) std.mem.trim(u8, result.stdout, " \r\n\t") else null else null,
        .cgo_enabled = if (cgo_result) |result| if (termSucceeded(result.term)) std.mem.trim(u8, result.stdout, " \r\n\t") else null else null,
        .c_compiler = cc_name,
        .c_compiler_available = cc_probe_result != null,
        .gofmt_available = gofmt_result != null,
        .native_target = options.native_target,
    }, options.auto_cleanup);
}

pub fn render(writer: *std.Io.Writer, probe: Probe, auto_cleanup: bool) !bool {
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

    if (probe.cgo_enabled) |enabled| {
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

    if (probe.c_compiler) |compiler| {
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
    }, true));
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
    }, true));
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "install Go 1.24 or newer for auto_cleanup") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "CGO_ENABLED=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "missing-cc is configured") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed_output.written(), "cross compilation is not supported") != null);
}

test "Go version parser accepts development and future major versions" {
    const development = parseGoVersion("go version go1.26rc1 linux/amd64").?;
    try std.testing.expectEqual(@as(u32, 1), development.major);
    try std.testing.expectEqual(@as(u32, 26), development.minor);
    const future = parseGoVersion("go version go2.0 darwin/arm64").?;
    try std.testing.expectEqual(@as(u32, 2), future.major);
}
