const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);
    if (args.len != 2) return error.ExpectedLibraryPath;

    var library = try std.DynLib.open(args[1]);
    defer library.close();
    const add = library.lookup(*const fn (i32, i32) callconv(.c) i32, "zg_add") orelse
        return error.MissingAddSymbol;
    if (library.lookup(*const fn () callconv(.c) void, "zg_symbol_that_does_not_exist") != null)
        return error.UnexpectedSymbol;
    if (add(19, 23) != 42) return error.UnexpectedResult;
}
