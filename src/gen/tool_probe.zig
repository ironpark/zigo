//! External tool invocation for doctor. Results own process output; diagnosis
//! and formatting remain in doctor.zig. Commands are argv, never shell text.
const std = @import("std");

pub const State = enum { skipped, unavailable, failed, succeeded };
pub const Result = union(enum) {
    skipped,
    unavailable: anyerror,
    completed: std.process.RunResult,

    pub fn state(self: Result) State {
        return switch (self) {
            .skipped => .skipped,
            .unavailable => .unavailable,
            .completed => |value| if (termSucceeded(value.term)) .succeeded else .failed,
        };
    }

    pub fn ran(self: Result) bool {
        return self == .completed;
    }

    pub fn stdout(self: Result) ?[]const u8 {
        if (self.state() != .succeeded) return null;
        const bytes = std.mem.trim(u8, self.completed.stdout, whitespace);
        return if (bytes.len == 0) null else bytes;
    }

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        if (self.* == .completed) {
            allocator.free(self.completed.stdout);
            allocator.free(self.completed.stderr);
        }
        self.* = .skipped;
    }
};

/// Injectable execution boundary lets tests assert the complete command.
pub const Runner = struct {
    context: ?*anyopaque = null,
    execute: *const fn (?*anyopaque, std.mem.Allocator, std.Io, []const []const u8) anyerror!std.process.RunResult = executeProcess,

    fn probe(self: Runner, allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) Result {
        return .{ .completed = self.execute(self.context, allocator, io, argv) catch |err| return .{ .unavailable = err } };
    }
};

fn executeProcess(_: ?*anyopaque, allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) !std.process.RunResult {
    return std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    });
}

pub const Options = struct {
    go_executable: []const u8 = "go",
    gofmt_executable: []const u8 = "gofmt",
    cgo: bool = true,
};

pub const Toolchain = struct {
    go_version: Result = .skipped,
    cgo: Result = .skipped,
    cc: Result = .skipped,
    compiler: Result = .skipped,
    gofmt: Result = .skipped,

    pub fn deinit(self: *Toolchain, allocator: std.mem.Allocator) void {
        inline for (.{ "go_version", "cgo", "cc", "compiler", "gofmt" }) |field| @field(self, field).deinit(allocator);
    }
};

pub fn collect(allocator: std.mem.Allocator, io: std.Io, options: Options, runner: Runner) !Toolchain {
    var result: Toolchain = .{};
    errdefer result.deinit(allocator);
    result.go_version = runner.probe(allocator, io, &.{ options.go_executable, "version" });
    if (result.go_version.ran() and options.cgo) {
        result.cgo = runner.probe(allocator, io, &.{ options.go_executable, "env", "CGO_ENABLED" });
        result.cc = runner.probe(allocator, io, &.{ options.go_executable, "env", "CC" });
    }
    if (result.cc.stdout()) |command| {
        const args = compilerProbeArgs(allocator, command) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => null,
        };
        if (args) |argv| {
            defer allocator.free(argv);
            result.compiler = runner.probe(allocator, io, argv);
        } else result.compiler = .{ .unavailable = error.InvalidCompilerCommand };
    }
    // gofmt -h may exit nonzero after printing help. Availability deliberately
    // means it ran; this is not the compiler's successful-version policy.
    result.gofmt = runner.probe(allocator, io, &.{ options.gofmt_executable, "-h" });
    return result;
}

const whitespace = " \r\n\t";

const FakeRunner = struct {
    calls: usize = 0,
    cgo: bool = true,
    compiler_state: State = .succeeded,

    fn execute(context: ?*anyopaque, allocator: std.mem.Allocator, _: std.Io, argv: []const []const u8) !std.process.RunResult {
        const self: *FakeRunner = @ptrCast(@alignCast(context.?));
        const step = self.calls;
        self.calls += 1;
        const expected: []const []const u8 = if (!self.cgo and step == 1) &.{ "format-tool", "-h" } else switch (step) {
            0 => &.{ "go-tool", "version" },
            1 => &.{ "go-tool", "env", "CGO_ENABLED" },
            2 => &.{ "go-tool", "env", "CC" },
            3 => &.{ "zig", "cc", "-target", "x86_64-windows-gnu", "--version" },
            4 => &.{ "format-tool", "-h" },
            else => return error.UnexpectedInvocation,
        };
        try std.testing.expectEqual(expected.len, argv.len);
        for (expected, argv) |want, got| try std.testing.expectEqualStrings(want, got);
        if (step == 3 and self.compiler_state == .unavailable) return error.FileNotFound;
        const output = switch (step) {
            0 => "go version go1.26.7 windows/amd64\n",
            1 => "1\n",
            2 => "zig cc -target x86_64-windows-gnu\n",
            else => "",
        };
        const stdout = try allocator.dupe(u8, output);
        errdefer allocator.free(stdout);
        const failed = step == 3 and self.compiler_state == .failed;
        return .{
            .stdout = stdout,
            .stderr = try allocator.dupe(u8, if (failed) "invalid compiler option" else ""),
            .term = .{ .exited = if (failed) 1 else if (std.mem.eql(u8, argv[0], "format-tool")) 2 else 0 },
        };
    }
};

test "tool collection preserves commands and distinguishes process outcomes" {
    for ([_]State{ .succeeded, .failed, .unavailable }) |state| {
        var fake: FakeRunner = .{ .compiler_state = state };
        var result = try collect(std.testing.allocator, std.testing.io, .{ .go_executable = "go-tool", .gofmt_executable = "format-tool" }, .{ .context = &fake, .execute = FakeRunner.execute });
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 5), fake.calls);
        try std.testing.expectEqual(state, result.compiler.state());
        try std.testing.expectEqualStrings("1", result.cgo.stdout().?);
        try std.testing.expect(result.gofmt.ran());
        try std.testing.expectEqual(State.failed, result.gofmt.state());
        if (state == .failed) {
            try std.testing.expectEqualStrings("invalid compiler option", result.compiler.completed.stderr);
            try std.testing.expectEqual(@as(u8, 1), result.compiler.completed.term.exited);
        }
        if (state == .unavailable) try std.testing.expectEqual(error.FileNotFound, result.compiler.unavailable);
    }
}

test "purego collection does not invoke compiler probes" {
    var fake: FakeRunner = .{ .cgo = false };
    var result = try collect(std.testing.allocator, std.testing.io, .{ .go_executable = "go-tool", .gofmt_executable = "format-tool", .cgo = false }, .{ .context = &fake, .execute = FakeRunner.execute });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), fake.calls);
    try std.testing.expectEqual(State.skipped, result.compiler.state());
    try std.testing.expectEqual(State.skipped, result.cc.state());
}
/// Follow Go's CC field conventions: leading single/double quotes group an
/// argument, with no unescaping. In particular Windows backslashes survive.
/// The returned argument strings borrow command; only the slice is owned.
fn compilerProbeArgs(allocator: std.mem.Allocator, command: []const u8) ![]const []const u8 {
    var args: std.ArrayList([]const u8) = .empty;
    errdefer args.deinit(allocator);
    var remaining = command;
    while (true) {
        remaining = std.mem.trimStart(u8, remaining, whitespace);
        if (remaining.len == 0) break;
        if (remaining[0] == '\'' or remaining[0] == '"') {
            const quote = remaining[0];
            remaining = remaining[1..];
            const end = std.mem.indexOfScalar(u8, remaining, quote) orelse return error.InvalidCompilerCommand;
            try args.append(allocator, remaining[0..end]);
            remaining = remaining[end + 1 ..];
        } else {
            const end = std.mem.indexOfAny(u8, remaining, whitespace) orelse remaining.len;
            try args.append(allocator, remaining[0..end]);
            remaining = remaining[end..];
        }
    }
    if (args.items.len == 0 or args.items[0].len == 0) return error.InvalidCompilerCommand;
    try args.append(allocator, "--version");
    return args.toOwnedSlice(allocator);
}

fn termSucceeded(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

test "compiler probe requires a successful exit" {
    try std.testing.expect(termSucceeded(.{ .exited = 0 }));
    try std.testing.expect(!termSucceeded(.{ .exited = 1 }));
}

test "compiler probe preserves drivers options and quoted Windows paths" {
    const cases = [_]struct { command: []const u8, expected: []const []const u8 }{
        .{ .command = "cc", .expected = &.{ "cc", "--version" } },
        .{ .command = "zig cc", .expected = &.{ "zig", "cc", "--version" } },
        .{ .command = "zig cc -target x86_64-windows-gnu", .expected = &.{ "zig", "cc", "-target", "x86_64-windows-gnu", "--version" } },
        .{ .command = "\"D:\\Program Files\\Zig\\zig.exe\" cc", .expected = &.{ "D:\\Program Files\\Zig\\zig.exe", "cc", "--version" } },
        .{ .command = "ccache '/opt/zig tools/zig' cc", .expected = &.{ "ccache", "/opt/zig tools/zig", "cc", "--version" } },
        .{ .command = " \tzig\r\ncc \t", .expected = &.{ "zig", "cc", "--version" } },
    };
    for (cases) |case| {
        const args = try compilerProbeArgs(std.testing.allocator, case.command);
        defer std.testing.allocator.free(args);
        try std.testing.expectEqual(case.expected.len, args.len);
        for (case.expected, args) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
    }
    for ([_][]const u8{ "", " \t", "''", "\"zig cc", "zig 'cc" }) |invalid| {
        try std.testing.expectError(error.InvalidCompilerCommand, compilerProbeArgs(std.testing.allocator, invalid));
    }
}
