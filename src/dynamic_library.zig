//! Shared-library loading for zigo's own tooling, on every platform zigo
//! supports.
//!
//! `std.DynLib` cannot be referenced at all when compiling for Windows with
//! Zig 0.16: its `InnerType` switch has no Windows arm, so it falls through to
//! a struct whose `open` is `@compileError("unsupported platform")` and which
//! declares no `close`, which breaks `DynLib.close` as well. Naming the type
//! is enough to fail the build, so the doctor's loadability probe and the
//! smoke loader cannot use it directly now that Windows is a supported purego
//! target.
//!
//! Windows therefore goes straight to kernel32, which is what `std.DynLib`
//! would do and what the generated Go loader already does through `syscall`.
//! POSIX keeps delegating to `std.DynLib`, so its behaviour is unchanged.

const std = @import("std");
const builtin = @import("builtin");

const windows = std.os.windows;
const is_windows = builtin.target.os.tag == .windows;

/// `FileNotFound` is the one member callers branch on: it separates a library
/// that was never installed from one that exists but will not load.
pub const Error = std.DynLib.Error || error{
    BadPathName,
    NameTooLong,
    AccessDenied,
    InvalidExeFormat,
    LoadFailed,
};

pub const Library = struct {
    handle: if (is_windows) windows.HMODULE else std.DynLib,

    /// Trusts the file. A malicious library can execute arbitrary code.
    pub fn open(path: []const u8) Error!Library {
        if (!is_windows) return .{ .handle = try std.DynLib.open(path) };
        // A stack buffer keeps the probe allocation-free, as the POSIX arm is.
        var wide_path: [4096]u16 = undefined;
        const length = try windows.wtf8ToWtf16Le(wide_path[0 .. wide_path.len - 1], path);
        wide_path[length] = 0;
        const handle = LoadLibraryW(wide_path[0..length :0].ptr) orelse return switch (windows.GetLastError()) {
            .FILE_NOT_FOUND, .PATH_NOT_FOUND, .MOD_NOT_FOUND => error.FileNotFound,
            .ACCESS_DENIED => error.AccessDenied,
            .BAD_EXE_FORMAT => error.InvalidExeFormat,
            else => error.LoadFailed,
        };
        return .{ .handle = handle };
    }

    pub fn close(self: *Library) void {
        if (is_windows) _ = FreeLibrary(self.handle) else self.handle.close();
    }

    /// Null when the library does not export `name`.
    pub fn lookup(self: *Library, name: [:0]const u8) ?*const anyopaque {
        if (!is_windows) return self.handle.lookup(*const anyopaque, name);
        return GetProcAddress(self.handle, name.ptr);
    }
};

// `std.os.windows` declares no loader entry points in 0.16, so they are named
// here. `callconv(.winapi)` is the same convention std uses for kernel32.
extern "kernel32" fn LoadLibraryW(lpLibFileName: [*:0]const u16) callconv(.winapi) ?windows.HMODULE;
extern "kernel32" fn FreeLibrary(hLibModule: windows.HMODULE) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetProcAddress(hModule: windows.HMODULE, lpProcName: [*:0]const u8) callconv(.winapi) ?*const anyopaque;

test "an absent path is reported as missing rather than unloadable" {
    // This is the distinction the doctor branches on: a library that was never
    // installed asks for `zig build go-lib`, anything else is a real failure.
    try std.testing.expectError(error.FileNotFound, Library.open("/definitely/absent/zigo-library-probe"));
}
