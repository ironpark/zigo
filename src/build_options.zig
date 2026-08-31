const std = @import("std");

/// purego release the generator emits bindings for and validates against.
pub const purego_module = "github.com/ebitengine/purego";
pub const purego_version = "v0.10.2";

/// Native platforms the purego backend supports. `build.zig` applies it to the
/// requested target; `doctor` applies it to the host it runs on.
pub fn puregoTargetSupported(target: std.Target) bool {
    return (target.os.tag == .macos or target.os.tag == .linux) and
        (target.cpu.arch == .x86_64 or target.cpu.arch == .aarch64);
}

/// How a generated purego package finds its shared library at run time.
pub const LibraryLoading = struct {
    /// Locations tried in order after the environment variables. An entry that
    /// already names a library file is used as is; anything else is treated as
    /// a directory and joined with the platform library name. `${EXECUTABLE_DIR}`
    /// expands to the directory of the running executable.
    search_paths: []const []const u8 = &.{},
    /// Environment variables consulted before the search paths. `null` uses the
    /// package-specific name followed by the shared `ZIGO_LIBRARY_PATH`.
    env_vars: ?[]const []const u8 = null,
    /// Load on the first binding call instead of requiring an explicit call.
    automatic: bool = false,
    /// Generate the exported `LoadLibrary`/`LibraryLoaded` API.
    exported_api: bool = true,
};

pub const LibraryLoadingError = error{
    UnsupportedBackend,
    UnreachableLoader,
    EmptySearchPath,
    InvalidSearchPath,
    InvalidEnvironmentName,
};

/// Rejects policies that cannot produce a usable package. `purego` reports
/// whether the binding set selected the purego backend.
pub fn validateLibraryLoading(loading: LibraryLoading, purego: bool) LibraryLoadingError!void {
    if (!purego and !isDefaultLibraryLoading(loading)) return error.UnsupportedBackend;
    // Without an exported loader nothing could ever load the library.
    if (!loading.exported_api and !loading.automatic) return error.UnreachableLoader;
    for (loading.search_paths) |path| {
        if (path.len == 0) return error.EmptySearchPath;
        // ':' separates the entries when the policy reaches the generator.
        for (path) |character| if (std.ascii.isControl(character) or character == '"' or
            character == '\\' or character == ':')
            return error.InvalidSearchPath;
    }
    if (loading.env_vars) |names| for (names) |name| {
        if (name.len == 0 or std.ascii.isDigit(name[0])) return error.InvalidEnvironmentName;
        for (name) |character| if (!(std.ascii.isAlphanumeric(character) or character == '_'))
            return error.InvalidEnvironmentName;
    };
}

pub fn isDefaultLibraryLoading(loading: LibraryLoading) bool {
    return loading.search_paths.len == 0 and loading.env_vars == null and
        !loading.automatic and loading.exported_api;
}

pub const RawPackageError = error{
    InvalidPath,
    InvalidComponent,
    InvalidCharacter,
};

pub fn validateRawPackagePath(path: []const u8) RawPackageError!void {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, '\\') != null)
        return error.InvalidPath;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, ".."))
            return error.InvalidComponent;
        for (component) |character| {
            if (!(std.ascii.isAlphanumeric(character) or character == '_' or character == '-' or character == '.'))
                return error.InvalidCharacter;
        }
    }
}

test "raw package paths accept portable relative components" {
    for ([_][]const u8{ "internal/raw", "bridge/cgo", "vendor-ffi/v1.2" }) |path|
        try validateRawPackagePath(path);
}

test "raw package paths reject unsafe forms and components" {
    const cases = [_]struct { path: []const u8, expected: RawPackageError }{
        .{ .path = "", .expected = error.InvalidPath },
        .{ .path = "/absolute", .expected = error.InvalidPath },
        .{ .path = "internal\\raw", .expected = error.InvalidPath },
        .{ .path = "internal//raw", .expected = error.InvalidComponent },
        .{ .path = "./raw", .expected = error.InvalidComponent },
        .{ .path = "../raw", .expected = error.InvalidComponent },
        .{ .path = "internal/raw!", .expected = error.InvalidCharacter },
    };
    for (cases) |case| try std.testing.expectError(case.expected, validateRawPackagePath(case.path));
}

test "purego target support covers the documented desktop matrix" {
    var target = @import("builtin").target;
    for ([_]std.Target.Os.Tag{ .macos, .linux }) |os| {
        for ([_]std.Target.Cpu.Arch{ .aarch64, .x86_64 }) |arch| {
            target.os.tag = os;
            target.cpu.arch = arch;
            try std.testing.expect(puregoTargetSupported(target));
        }
    }
    target.os.tag = .windows;
    try std.testing.expect(!puregoTargetSupported(target));
    target.os.tag = .linux;
    target.cpu.arch = .riscv64;
    try std.testing.expect(!puregoTargetSupported(target));
}

test "library loading policies reject unusable combinations" {
    try validateLibraryLoading(.{}, false);
    try validateLibraryLoading(.{ .search_paths = &.{ "${EXECUTABLE_DIR}", "/opt/app/lib" }, .automatic = true }, true);
    try validateLibraryLoading(.{ .automatic = true, .exported_api = false }, true);
    try std.testing.expectError(error.UnsupportedBackend, validateLibraryLoading(.{ .automatic = true }, false));
    try std.testing.expectError(error.UnreachableLoader, validateLibraryLoading(.{ .exported_api = false }, true));
    try std.testing.expectError(error.EmptySearchPath, validateLibraryLoading(.{ .search_paths = &.{""} }, true));
    try std.testing.expectError(error.InvalidSearchPath, validateLibraryLoading(.{ .search_paths = &.{"lib\"dir"} }, true));
    try std.testing.expectError(error.InvalidSearchPath, validateLibraryLoading(.{ .search_paths = &.{"/opt/a:/opt/b"} }, true));
    try std.testing.expectError(error.InvalidEnvironmentName, validateLibraryLoading(.{ .env_vars = &.{"9BAD"} }, true));
    try std.testing.expectError(error.InvalidEnvironmentName, validateLibraryLoading(.{ .env_vars = &.{"BAD-NAME"} }, true));
}
