const std = @import("std");

/// Loads an installed zigo shared library with the platform loader and checks
/// that every requested symbol resolves. Usage:
///
///     zigo-shared-library-smoke <library> [symbol...]
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);
    if (args.len < 2) return error.ExpectedLibraryPath;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), init.io, &stdout_buffer);
    const writer = &stdout.interface;

    var library = std.DynLib.open(args[1]) catch |err| {
        try writer.print("FAIL load: {s}: {t}\n", .{ args[1], err });
        try writer.flush();
        return err;
    };
    defer library.close();
    try writer.print("PASS load: {s}\n", .{args[1]});

    var missing = false;
    for (args[2..]) |symbol| {
        const name = try allocator.dupeZ(u8, symbol);
        defer allocator.free(name);
        if (library.lookup(*const anyopaque, name) == null) {
            missing = true;
            try writer.print("FAIL symbol: {s} is not exported\n", .{symbol});
        } else {
            try writer.print("PASS symbol: {s}\n", .{symbol});
        }
    }
    // A resolvable name that was never generated would mean the loader is
    // matching symbols it should not, so the negative case is checked too.
    if (library.lookup(*const anyopaque, "zg_symbol_that_does_not_exist") != null) {
        missing = true;
        try writer.writeAll("FAIL symbol: an undefined name resolved\n");
    }
    try writer.writeAll(if (missing) "shared-library-smoke: failed\n" else "shared-library-smoke: ok\n");
    try writer.flush();
    if (missing) std.process.exit(1);
}
