//! Entry point of the Go generator: the emitter tables the generator runs,
//! the output file names, and the tests that render whole files.
const target_types = @import("target_types.zig");
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");
const common = @import("common.zig");
const docs = @import("docs.zig");
const header = @import("header.zig");
pub const interfaces = @import("interfaces.zig");
const public = @import("public.zig");
const public_runtime = @import("public_runtime.zig");
const public_types = @import("public_types.zig");
const purego = @import("purego.zig");
const raw = @import("raw.zig");
const shim = @import("shim.zig");
pub const references = @import("references.zig");

pub const Options = struct {
    pub const Backend = enum { cgo, purego };
    pub const LinkMode = enum { static, dynamic };
    /// One Go platform the cgo raw package links a native library for.
    pub const CgoTarget = struct { goos: []const u8, goarch: []const u8 };
    /// Extra link flags for one platform: a `#cgo <constraint> LDFLAGS:` line
    /// of its own, so a flag one platform needs never reaches the others.
    pub const TargetLdflags = struct {
        /// `goos` or `goos,goarch`, spelled as cgo's build constraint.
        constraint: []const u8,
        flags: []const u8,
    };
    go_module: []const u8,
    cflags_override: ?[]const u8 = null,
    ldflags_override: ?[]const u8 = null,
    extra_ldflags: []const u8 = "",
    /// The build integration emits the complete LDFLAGS line into a volatile
    /// Go file when it contains machine-local static archive paths.
    ldflags_external: bool = false,
    system_ldflags: []const u8 = "",
    framework_ldflags: []const u8 = "",
    /// Space-separated pkg-config package names. They become a `#cgo
    /// pkg-config:` line rather than `-l` flags, so cgo asks pkg-config for the
    /// compile and link flags of each one.
    pkg_config_libs: []const u8 = "",
    include_dir: []const u8 = "${SRCDIR}/../../../zig-out/include",
    library_dir: []const u8 = "${SRCDIR}/../../../zig-out/lib",
    /// Installed header filename. Empty derives `zigo_<package>.h`.
    header_name: []const u8 = "",
    raw_package_path: []const u8 = "internal/raw",
    raw_package_name: []const u8 = "raw",
    raw_colocated: bool = false,
    /// Emit and use the backend-neutral runtime shared by split public packages.
    /// Kept off for legacy single-package documents so their output stays byte-identical.
    shared_lifecycle: bool = false,
    lifecycle_package_path: []const u8 = "internal/lifecycle",
    backend: Backend = .cgo,
    link_mode: Options.LinkMode = .static,
    /// Go platforms the cgo raw package links for. Empty keeps one unqualified
    /// `#cgo LDFLAGS` line naming `library_dir` directly. Otherwise every entry
    /// gets its own `#cgo <goos>,<goarch> LDFLAGS` line naming the library in
    /// `library_dir/<goos>_<goarch>/`, so one generated tree builds for each
    /// listed platform. Ignored by purego, which resolves the library at run time.
    cgo_targets: []const CgoTarget = &.{},
    /// Appended per-platform lines, written after the library link lines.
    target_ldflags: []const TargetLdflags = &.{},
    library_stem: []const u8 = "",
    /// Public Go package name. Empty derives it from the binding name.
    go_package: []const u8 = "",
    /// Public package path below the module root. Empty defaults to the public
    /// package name; `.` publishes at the module root.
    go_package_path: []const u8 = "",
    /// Body of the generated `// Package ...` doc. Empty falls back to the
    /// `//!` container doc of the bindings file, then to a default sentence.
    go_package_doc: []const u8 = "",
    /// Emit checked-call convenience wrappers that panic on error.
    go_must_variants: bool = false,
    /// Null renders the legacy single package; empty selects the default package
    /// of a split document; a value selects that named sub-package.
    active_package: ?[]const u8 = null,
    default_package_path: []const u8 = "",
    /// Colon-separated purego candidate locations, in the order they are tried.
    library_search_paths: []const u8 = "",
    /// Comma-separated environment variable names. `null` selects the defaults.
    library_env_vars: ?[]const u8 = null,
    library_automatic: bool = false,
    library_exported_api: bool = true,
    /// Every search-path directory holds the library under a
    /// `<goos>_<goarch>` subdirectory, the layout `targets` installs, so the
    /// loader joins the running platform's name before the file name.
    library_platform_dirs: bool = false,
    /// The generated helpers the public package references, decided by
    /// rendering it (`references.referencedHelpersAlloc`). Null emits every
    /// gated helper, which only the discovery rendering itself relies on
    /// being absent.
    helpers: ?*const references.Referenced = null,

    /// Whether a gated helper of this name is written.
    pub fn emitsHelper(self: Options, name: []const u8) bool {
        const set = self.helpers orelse return true;
        return set.contains(name);
    }

    /// `emitsHelper` for a name spelled from a type name, such as
    /// `zigo<Type>ToRaw`. A name too long to spell is treated as referenced.
    pub fn emitsHelperFmt(self: Options, comptime format: []const u8, args: anytype) bool {
        var buffer: [256]u8 = undefined;
        const name = std.fmt.bufPrint(&buffer, format, args) catch return true;
        return self.emitsHelper(name);
    }
};

pub const Emitter = struct {
    pathAlloc: *const fn (std.mem.Allocator, abi.Program, Options) anyerror![]u8,
    render: *const fn (std.mem.Allocator, *std.Io.Writer, abi.Program, Options) anyerror!void,
};

pub const core_emitters = [_]Emitter{
    .{ .pathAlloc = shimPath, .render = shim.renderShim },
    .{ .pathAlloc = panicSourcePath, .render = shim.renderPanicSource },
    .{ .pathAlloc = headerPath, .render = header.renderHeader },
    .{ .pathAlloc = rawPath, .render = raw.renderRaw },
    .{ .pathAlloc = rawLoadPosixPath, .render = purego.renderRawLoadPosix },
    .{ .pathAlloc = rawLoadWindowsPath, .render = purego.renderRawLoadWindows },
    .{ .pathAlloc = lifecyclePath, .render = renderLifecycle },
};

pub const public_emitters = [_]Emitter{
    .{ .pathAlloc = publicPath, .render = public.renderPublic },
    .{ .pathAlloc = publicEnumsPath, .render = public.renderPublicEnumsFile },
    .{ .pathAlloc = publicStructsPath, .render = public.renderPublicStructsFile },
    .{ .pathAlloc = publicHandlesPath, .render = public.renderPublicHandlesFile },
    .{ .pathAlloc = publicRuntimePath, .render = public.renderPublicRuntimeFile },
    .{ .pathAlloc = publicErrorsPath, .render = public_runtime.renderPublicErrors },
    .{ .pathAlloc = interfaces.interfacesPath, .render = interfaces.renderInterfacesFile },
};

fn lifecyclePath(allocator: std.mem.Allocator, _: abi.Program, options: Options) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/lifecycle_gen.go", .{options.lifecycle_package_path});
}

/// Backend-neutral state shared by every public package in a split binding.
/// Native loading and callback-token ownership deliberately remain in raw/native.
fn renderLifecycle(_: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) !void {
    if (!options.shared_lifecycle) return;
    try writer.writeAll(
        "// Code generated by zigo. DO NOT EDIT.\n\n" ++
            "// Package lifecycle contains the runtime state shared by generated public packages.\n" ++
            "package lifecycle\n\n" ++
            "import (\n\t\"errors\"\n\t\"fmt\"\n\t\"strconv\"\n\t\"unsafe\"\n)\n\n" ++
            "var (\n" ++
            "\tErrInvalidHandle = errors.New(\"zigo: nil or closed handle\")\n" ++
            "\tErrHandleInUse = errors.New(\"zigo: handle has open children\")\n" ++
            "\tErrNativePanic = errors.New(\"zigo: native panic\")\n" ++
            "\tErrNativeStatus = errors.New(\"zigo: unrecognized native status\")\n" ++
            "\tErrCallbackPanic = errors.New(\"zigo: callback panic\")\n" ++
            "\tErrCallbackFailed = errors.New(\"zigo: callback failed\")\n" ++
            "\tErrOutOfRange = errors.New(\"zigo: argument out of range\")\n" ++
            "\tErrNilStream = errors.New(\"zigo: nil stream argument\")\n" ++
            ")\n\n" ++
            "type Handle interface {\n" ++
            "\tZigoAcquire(operation string) (unsafe.Pointer, error)\n" ++
            "\tZigoRelease()\n" ++
            "\tZigoPoison(cause *NativePanicError)\n" ++
            "}\n\n",
    );
    if (common.programHasChildConstructors(program)) try writer.writeAll(
        "type ChildHandle interface {\n" ++
            "\tHandle\n" ++
            "\tZigoAcquireChild(operation string) (unsafe.Pointer, ChildHandle, error)\n" ++
            "\tZigoDropChild()\n" ++
            "}\n\n",
    );
    try writer.writeAll(
        "func CheckedPointer(operation string, value Handle) (unsafe.Pointer, error) { return value.ZigoAcquire(operation) }\n" ++
            "func OptionalPointer(operation string, absent bool, value Handle) (unsafe.Pointer, error) {\n" ++
            "\tif absent { return nil, nil }\n\treturn CheckedPointer(operation, value)\n}\n" ++
            "func PoisonAfterPanic(err error, handles ...Handle) error {\n" ++
            "\tif cause, ok := err.(*NativePanicError); ok { for _, handle := range handles { handle.ZigoPoison(cause) } }\n" ++
            "\treturn err\n}\n\n" ++
            "func Release(handle Handle) { handle.ZigoRelease() }\n\n" ++
            "type HandleError struct { Operation string }\n" ++
            "func (err *HandleError) Error() string { return \"zigo: \" + err.Operation + \": nil or closed handle\" }\n" ++
            "func (err *HandleError) Unwrap() error { return ErrInvalidHandle }\n\n" ++
            "type HandleInUseError struct { Operation string; Children int }\n" ++
            "func (err *HandleInUseError) Error() string { return \"zigo: \" + err.Operation + \": handle has open children: \" + strconv.Itoa(err.Children) }\n" ++
            "func (err *HandleInUseError) Unwrap() error { return ErrHandleInUse }\n\n" ++
            "type NativePanicError struct { Operation, Message string }\n" ++
            "func (err *NativePanicError) Error() string { if err.Message == \"\" { return \"zigo: \" + err.Operation + \": native panic\" }; return \"zigo: \" + err.Operation + \": native panic: \" + err.Message }\n" ++
            "func (err *NativePanicError) Unwrap() error { return ErrNativePanic }\n" ++
            "func (err *NativePanicError) Poisoned(operation string) error { message := \"handle unusable after a native panic in \" + err.Operation; if err.Message != \"\" { message += \": \" + err.Message }; return &NativePanicError{Operation: operation, Message: message} }\n\n" ++
            "type RangeError struct { Operation, Parameter, Type string }\n" ++
            "func (err *RangeError) Error() string { return \"zigo: \" + err.Operation + \": argument \" + err.Parameter + \" is out of range for \" + err.Type }\n" ++
            "func (err *RangeError) Unwrap() error { return ErrOutOfRange }\n\n" ++
            "type StreamError struct { Operation, Parameter string; Err error }\n" ++
            "func (err *StreamError) Error() string { return \"zigo: \" + err.Operation + \": stream \" + err.Parameter + \": \" + err.Err.Error() }\n" ++
            "func (err *StreamError) Unwrap() error { return err.Err }\n\n" ++
            "type CallbackError struct { Operation, Callback string; Err error }\n" ++
            "func (err *CallbackError) Error() string { return \"zigo: \" + err.Operation + \": callback \" + err.Callback + \": \" + err.Err.Error() }\n" ++
            "func (err *CallbackError) Is(target error) bool { return target == ErrCallbackFailed }\n" ++
            "func (err *CallbackError) Unwrap() error { return err.Err }\n\n" ++
            "type StatusError struct { Operation string; Status uint8 }\n" ++
            "func (err *StatusError) Error() string { return \"zigo: \" + err.Operation + \": unrecognized native status\" }\n" ++
            "func (err *StatusError) Unwrap() error { return ErrNativeStatus }\n\n" ++
            "type CallbackPanicError struct { Operation string; Value any; Stack []byte }\n" ++
            "func (err *CallbackPanicError) Error() string { return \"zigo: \" + err.Operation + \": callback panic: \" + fmt.Sprint(err.Value) }\n" ++
            "func (err *CallbackPanicError) Is(target error) bool { return target == ErrCallbackPanic }\n" ++
            "func (err *CallbackPanicError) Unwrap() error { if cause, ok := err.Value.(error); ok { return cause }; return nil }\n\n" ++
            "type Error struct { Code int32; Name, Operation string }\n" ++
            "func (err *Error) Error() string { if err.Operation == \"\" { return err.Name }; return \"zigo: \" + err.Operation + \": \" + err.Name }\n" ++
            "func (err *Error) Is(target error) bool { other, ok := target.(*Error); return ok && err.Code == other.Code }\n",
    );
}

fn shimPath(allocator: std.mem.Allocator, _: abi.Program, _: Options) ![]u8 {
    return allocator.dupe(u8, "shim.zig");
}

fn panicSourcePath(allocator: std.mem.Allocator, _: abi.Program, _: Options) ![]u8 {
    return allocator.dupe(u8, "panic.c");
}

fn headerPath(allocator: std.mem.Allocator, program: abi.Program, _: Options) ![]u8 {
    const package = try naming.snakeAlloc(allocator, program.package);
    defer allocator.free(package);
    return std.fmt.allocPrint(allocator, "zigo_{s}.h", .{package});
}

fn rawPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    if (options.raw_colocated) {
        const package = try common.publicPackageAlloc(allocator, program, options);
        defer allocator.free(package);
        const filename = try std.fmt.allocPrint(allocator, "{s}_{s}_gen.go", .{ package, @tagName(options.backend) });
        defer allocator.free(filename);
        return publicFilePathAlloc(allocator, program, options, filename);
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}_gen.go", .{ options.raw_package_path, options.raw_package_name });
}

/// One naming rule for the concern-scoped companions of the raw package, so a
/// colocated raw package keeps its `<package>_<backend>_...` prefix and a
/// separate one keeps its `<raw package name>_...` prefix.
fn rawConcernPathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options, concern: []const u8) ![]u8 {
    if (options.raw_colocated) {
        const package = try common.publicPackageAlloc(allocator, program, options);
        defer allocator.free(package);
        const filename = try std.fmt.allocPrint(allocator, "{s}_{s}_{s}_gen.go", .{ package, @tagName(options.backend), concern });
        defer allocator.free(filename);
        return publicFilePathAlloc(allocator, program, options, filename);
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}_{s}_gen.go", .{ options.raw_package_path, options.raw_package_name, concern });
}

fn rawLoadPosixPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return rawConcernPathAlloc(allocator, program, options, "load_posix");
}

fn rawLoadWindowsPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return rawConcernPathAlloc(allocator, program, options, "load_windows");
}

fn publicPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    const package = try common.publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    const filename = try std.fmt.allocPrint(allocator, "{s}_gen.go", .{package});
    defer allocator.free(filename);
    return publicFilePathAlloc(allocator, program, options, filename);
}

fn publicEnumsPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return publicConcernPathAlloc(allocator, program, options, "enums");
}

fn publicStructsPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return publicConcernPathAlloc(allocator, program, options, "structs");
}

fn publicHandlesPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return publicConcernPathAlloc(allocator, program, options, "handles");
}

fn publicRuntimePath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return publicConcernPathAlloc(allocator, program, options, "runtime");
}

/// One file per tagged union, named from the union itself so the file set
/// grows with the bindings instead of one file growing with them.
fn publicUnionPathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options, stem: []const u8) ![]u8 {
    const concern = try std.fmt.allocPrint(allocator, "union_{s}", .{stem});
    defer allocator.free(concern);
    return publicConcernPathAlloc(allocator, program, options, concern);
}

/// One naming rule for every concern-scoped file in the public package, so a
/// new concern cannot drift from `<package>_<concern>_gen.go`.
pub fn publicConcernPathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options, concern: []const u8) ![]u8 {
    const package = try common.publicPackageAlloc(allocator, program, options);
    defer allocator.free(package);
    const filename = try std.fmt.allocPrint(allocator, "{s}_{s}_gen.go", .{ package, concern });
    defer allocator.free(filename);
    return publicFilePathAlloc(allocator, program, options, filename);
}

fn publicErrorsPath(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]u8 {
    return publicConcernPathAlloc(allocator, program, options, "errors");
}

fn publicFilePathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options, filename: []const u8) ![]u8 {
    const path = try common.publicPackagePathAlloc(allocator, program, options);
    defer allocator.free(path);
    if (std.mem.eql(u8, path, ".")) return allocator.dupe(u8, filename);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, filename });
}

/// One generated file, produced outside the fixed emitter table because how
/// many there are depends on the bindings.
pub const File = struct {
    path: []u8,
    contents: []u8,
};

/// The per-union files: each tagged union's projections, snapshot, and sealed
/// variant hierarchy, in the order the union was declared.
pub fn unionFilesAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options) ![]File {
    const variants = try public_types.unionVariantNamesAlloc(allocator, program);
    defer public_types.freeUnionVariantNames(allocator, variants);

    var files: std.ArrayList(File) = .empty;
    errdefer {
        for (files.items) |file| {
            allocator.free(file.path);
            allocator.free(file.contents);
        }
        files.deinit(allocator);
    }
    var stems: std.ArrayList([]u8) = .empty;
    defer {
        for (stems.items) |stem| allocator.free(stem);
        stems.deinit(allocator);
    }
    for (variants) |entry| {
        if (!packageMatches(entry.owner.package, options.active_package)) continue;
        const stem = try naming.unionFileStemAlloc(allocator, entry.owner.name, @ptrCast(stems.items));
        try stems.append(allocator, stem);
        const path = try publicUnionPathAlloc(allocator, program, options, stem);
        errdefer allocator.free(path);
        var rendered: std.Io.Writer.Allocating = .init(allocator);
        defer rendered.deinit();
        try public_types.renderUnionFile(allocator, &rendered.writer, program, options, entry);
        try files.append(allocator, .{ .path = path, .contents = try rendered.toOwnedSlice() });
    }
    return files.toOwnedSlice(allocator);
}

pub fn packageMatches(package: ?[]const u8, active: ?[]const u8) bool {
    const selected = active orelse return true;
    return if (package) |name| std.mem.eql(u8, name, selected) else selected.len == 0;
}

/// The per-union files concatenated, so a test can assert over the whole
/// tagged-union surface the way it did when one file held it.
pub fn renderUnionFilesForTest(program: abi.Program) ![]u8 {
    var referenced = try references.referencedHelpersAlloc(std.testing.allocator, program, .{ .go_module = "example.com/test" });
    defer referenced.deinit(std.testing.allocator);
    const files = try unionFilesAlloc(std.testing.allocator, program, .{ .go_module = "example.com/test", .helpers = &referenced });
    defer {
        for (files) |file| {
            std.testing.allocator.free(file.path);
            std.testing.allocator.free(file.contents);
        }
        std.testing.allocator.free(files);
    }
    var joined: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer joined.deinit();
    for (files) |file| try joined.writer.writeAll(file.contents);
    return joined.toOwnedSlice();
}

pub fn renderForTest(render: *const fn (std.mem.Allocator, *std.Io.Writer, abi.Program, Options) anyerror!void, program: abi.Program) ![]u8 {
    var referenced = try references.referencedHelpersAlloc(std.testing.allocator, program, .{ .go_module = "example.com/variant" });
    defer referenced.deinit(std.testing.allocator);
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    errdefer output.deinit();
    try render(std.testing.allocator, &output.writer, program, .{ .go_module = "example.com/variant", .helpers = &referenced });
    return output.toOwnedSlice();
}

test "snapshot-backed unions build their variants from one native call" {
    const document: semantic.Semantic = .{
        .package = "signal",
        .prefix = "zg",
        .types = &.{
            .{
                .access = .snapshot,
                .fields = &.{
                    .{ .name = "idle", .type = .{ .void = {} }, .value = 0 },
                    .{ .name = "ticks", .type = .{ .int = .{ .bits = 32, .signed = false } }, .value = 1 },
                    .{ .name = "level", .type = .{ .float = .{ .bits = 64 } }, .value = 2 },
                    .{ .name = "mode", .type = .{ .@"enum" = .{ .ref = "Mode" } }, .value = 3 },
                    .{ .name = "active", .type = .{ .bool = {} }, .value = 4 },
                },
                .kind = .tagged_union,
                .name = "Signal",
                .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
            },
            .{
                .fields = &.{
                    .{ .name = "idle", .value = 0 },
                    .{ .name = "ticks", .value = 1 },
                    .{ .name = "level", .value = 2 },
                    .{ .name = "mode", .value = 3 },
                    .{ .name = "active", .value = 4 },
                },
                .kind = .@"enum",
                .name = "SignalTag",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
            .{
                .fields = &.{ .{ .name = "idle", .value = 0 }, .{ .name = "active", .value = 1 } },
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocument(arena.allocator(), document, "signal", "zg", &.{});

    const public_types_text = try renderUnionFilesForTest(program);
    defer std.testing.allocator.free(public_types_text);

    const builder = std.mem.indexOf(u8, public_types_text, "func zigoSignalVariant(receiver zigoHandle) (SignalVariant, error) {").?;
    const builder_end = std.mem.indexOfPos(u8, public_types_text, builder, "\n}\n").?;
    const body = public_types_text[builder..builder_end];
    // The whole variant costs one native call: the snapshot read. Not one
    // projection per variant, and not a tag read on top of it.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "zigoSignalSnapshot(receiver)"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "zigoSignalTag(receiver)"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "zigoSignalAs"));
    try std.testing.expect(std.mem.indexOf(u8, body, "return SignalIdle{}, nil") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "return SignalLevel{Value: data.level}, nil") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "return SignalMode{Value: data.mode}, nil") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "return SignalActive{Value: data.active}, nil") != null);
    // The projection surface stays: the fast path is additive.
    try std.testing.expect(std.mem.indexOf(u8, public_types_text, "func (s *Signal) AsTicks() (uint32, bool, error)") != null);
    // Nothing hands out a borrowed Signal, so the Ref surface is not generated.
    try std.testing.expect(std.mem.indexOf(u8, public_types_text, "SignalRef") == null);
}

test "a colocated internal loader keeps the loader out of the exported names" {
    const origin: semantic.SemanticFn = .{
        .name = "ping",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "zg_ping",
    };
    const program: abi.Program = .{
        .backend = .purego,
        .callback_convention = .function_pointer_userdata_v2,
        .functions = &.{.{ .symbol = "zg_ping", .params = &.{}, .ret = .void, .origin = &origin }},
        .package = "hub",
        .prefix = "zg",
    };
    const options: Options = .{
        .go_module = "example.com/hub",
        .backend = .purego,
        .raw_colocated = true,
        .library_exported_api = false,
        .library_automatic = true,
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try raw.renderRaw(std.testing.allocator, &output.writer, program, options);
    const raw_text = output.written();

    // The raw package is the public package here, so the loader can only be
    // kept internal by not exporting its names.
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func zigoRawLoadLibrary(") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func zigoRawLibraryLoaded(") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "var zigoRawDefaultLibraryName = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func LoadLibrary(") == null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func LibraryLoaded(") == null);
    // The error type is not part of the loader API; callers still inspect it.
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "type LibraryError struct") != null);

    var exported: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer exported.deinit();
    var exported_options = options;
    exported_options.raw_colocated = false;
    exported_options.library_exported_api = true;
    try raw.renderRaw(std.testing.allocator, &exported.writer, program, exported_options);
    try std.testing.expect(std.mem.indexOf(u8, exported.written(), "func LoadLibrary(") != null);
}

test "a cgo target list qualifies one link line per platform" {
    const origin: semantic.SemanticFn = .{
        .name = "ping",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "zg_ping",
    };
    const program: abi.Program = .{
        .functions = &.{.{ .symbol = "zg_ping", .params = &.{}, .ret = .void, .origin = &origin }},
        .package = "hub",
        .prefix = "zg",
    };
    const targets: []const Options.CgoTarget = &.{
        .{ .goos = "darwin", .goarch = "arm64" },
        .{ .goos = "linux", .goarch = "amd64" },
    };

    var static_output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer static_output.deinit();
    try raw.renderRaw(std.testing.allocator, &static_output.writer, program, .{
        .go_module = "example.com/hub",
        .library_dir = "${SRCDIR}/lib",
        .cgo_targets = targets,
        .system_ldflags = "-lz",
    });
    const static_text = static_output.written();
    try std.testing.expect(std.mem.indexOf(u8, static_text, "\n#cgo darwin,arm64 LDFLAGS: ${SRCDIR}/lib/darwin_arm64/libhub_zigo.a -lz\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, static_text, "\n#cgo linux,amd64 LDFLAGS: ${SRCDIR}/lib/linux_amd64/libhub_zigo.a -lz\n") != null);
    // The unqualified line is what a single-target tree links with; it must
    // not also appear here or every platform would link two archives.
    try std.testing.expect(std.mem.indexOf(u8, static_text, "\n#cgo LDFLAGS:") == null);

    var dynamic_output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer dynamic_output.deinit();
    try raw.renderRaw(std.testing.allocator, &dynamic_output.writer, program, .{
        .go_module = "example.com/hub",
        .library_dir = "${SRCDIR}/lib",
        .cgo_targets = targets,
        .link_mode = .dynamic,
    });
    try std.testing.expect(std.mem.indexOf(u8, dynamic_output.written(), "\n#cgo linux,amd64 LDFLAGS: -L${SRCDIR}/lib/linux_amd64 -lhub_zigo\n") != null);

    // An explicit override owns the whole line, target list or not.
    var override_output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer override_output.deinit();
    try raw.renderRaw(std.testing.allocator, &override_output.writer, program, .{
        .go_module = "example.com/hub",
        .cgo_targets = targets,
        .ldflags_override = "-L/opt/hub -lhub",
    });
    try std.testing.expect(std.mem.indexOf(u8, override_output.written(), "\n#cgo LDFLAGS: -L/opt/hub -lhub\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, override_output.written(), "darwin,arm64") == null);

    // Platform additions are separate lines, and they outlive an external
    // archive line because they never name the archive.
    var platform_output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer platform_output.deinit();
    try raw.renderRaw(std.testing.allocator, &platform_output.writer, program, .{
        .go_module = "example.com/hub",
        .ldflags_external = true,
        .target_ldflags = &.{ .{ .constraint = "linux", .flags = "-ldl" }, .{ .constraint = "darwin,arm64", .flags = "-framework Metal" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, platform_output.written(), "\n#cgo LDFLAGS:") == null);
    try std.testing.expect(std.mem.indexOf(u8, platform_output.written(), "\n#cgo linux LDFLAGS: -ldl\n#cgo darwin,arm64 LDFLAGS: -framework Metal\n") != null);
}

test "every entry point the loader resolves is annotated for the COFF export table" {
    const origin: semantic.SemanticFn = .{
        .name = "ping",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "zg_ping",
    };
    const program: abi.Program = .{
        .backend = .purego,
        .callback_convention = .function_pointer_userdata_v2,
        .functions = &.{.{ .symbol = "zg_ping", .params = &.{}, .ret = .void, .origin = &origin }},
        .package = "unit",
        .prefix = "zg",
    };
    const options: Options = .{ .go_module = "example.com/unit", .backend = .purego };

    inline for (.{ shim.renderPanicSource, header.renderHeader }) |render| {
        var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer output.deinit();
        try render(std.testing.allocator, &output.writer, program, options);
        const text = output.written();
        try std.testing.expect(std.mem.indexOf(u8, text, "#define ZIGO_EXPORT __declspec(dllexport)") != null);
        // The public wrapper is what the generated loader looks up by name;
        // the `_impl` half is internal to the artifact and must stay unexported
        // so the DLL publishes exactly the documented surface.
        try std.testing.expect(std.mem.indexOf(u8, text, "ZIGO_EXPORT void zg_ping(") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "ZIGO_EXPORT const char *zg_last_error_message(void)") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "ZIGO_EXPORT void zg_ping_impl(") == null);
    }
}

test "the runtime symbols carry the binding prefix so two bindings can share a binary" {
    const origin: semantic.SemanticFn = .{
        .name = "ping",
        .params = &.{},
        .@"return" = .{ .void = {} },
        .symbol = "custom_ping",
    };
    const program: abi.Program = .{
        .backend = .cgo,
        .callback_convention = .function_pointer_userdata_v2,
        .functions = &.{.{ .symbol = "custom_ping", .params = &.{}, .ret = .void, .origin = &origin }},
        .package = "unit",
        .prefix = "custom",
    };
    const options: Options = .{ .go_module = "example.com/unit", .backend = .cgo };

    inline for (.{ shim.renderShim, shim.renderPanicSource, header.renderHeader, raw.renderRaw }) |render| {
        var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer output.deinit();
        try render(std.testing.allocator, &output.writer, program, options);
        const text = output.written();
        try std.testing.expect(std.mem.indexOf(u8, text, "zg_panic_bridge") == null);
        try std.testing.expect(std.mem.indexOf(u8, text, "zg_last_error_message") == null);
    }
    var panic_source: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer panic_source.deinit();
    try shim.renderPanicSource(std.testing.allocator, &panic_source.writer, program, options);
    try std.testing.expect(std.mem.indexOf(u8, panic_source.written(), "void custom_panic_bridge(") != null);
    try std.testing.expect(std.mem.indexOf(u8, panic_source.written(), "ZIGO_EXPORT const char *custom_last_error_message(void)") != null);
}

test "a package doc comes from the option, the container doc, then a default" {
    const program: abi.Program = .{ .functions = &.{}, .package = "queue", .prefix = "zg" };
    var documented = program;
    documented.doc = "Queues events natively.\n\nThe second paragraph is kept.";
    const cases = [_]struct { program: abi.Program, options: Options, expected: []const u8 }{
        // Nothing to go on: a plain statement of what the package is.
        .{
            .program = program,
            .options = .{ .go_module = "example.com/queue" },
            .expected = "// Package queue provides Go bindings generated by zigo.\n",
        },
        // The `//!` container doc, capitalized, so it becomes its own
        // paragraph after the plain first sentence.
        .{
            .program = documented,
            .options = .{ .go_module = "example.com/queue" },
            .expected = "// Package queue provides Go bindings generated by zigo.\n//\n// Queues events natively.\n//\n// The second paragraph is kept.\n",
        },
        // The option wins, and a body already written as this package's doc is
        // emitted as written.
        .{
            .program = documented,
            .options = .{ .go_module = "example.com/queue", .go_package_doc = "Package queue holds events until Go asks for them." },
            .expected = "// Package queue holds events until Go asks for them.\n",
        },
    };
    for (cases) |case| {
        var rendered: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer rendered.deinit();
        try docs.writePublicPackageDoc(&rendered.writer, "queue", case.program, case.options);
        try std.testing.expectEqualStrings(case.expected, rendered.written());
    }
}

test "a doc that opens with the declaration's own name is not repeated" {
    const cases = [_]struct {
        go_name: []const u8,
        zig_name: []const u8,
        doc: []const u8,
        expected: []const u8,
    }{
        // The reported shape: the Zig doc opens with the Zig spelling.
        .{
            .go_name = "AlgorithmID",
            .zig_name = "algorithmId",
            .doc = "algorithmId names the negotiated algorithm.",
            .expected = "\n// AlgorithmID names the negotiated algorithm.\n",
        },
        // The Go spelling counts too, and so does any other casing of either.
        .{
            .go_name = "Clone",
            .zig_name = "clone",
            .doc = "Clone copies the queue.",
            .expected = "\n// Clone copies the queue.\n",
        },
        .{
            .go_name = "AlgorithmID",
            .zig_name = "algorithmId",
            .doc = "ALGORITHMID names the negotiated algorithm.",
            .expected = "\n// AlgorithmID names the negotiated algorithm.\n",
        },
        // A capitalized sentence is joined with a colon rather than being
        // lowercased into the identifier, so the summary keeps its words.
        .{
            .go_name = "Echo",
            .zig_name = "echo",
            .doc = "Echoes UTF-8 text without changing its bytes.",
            .expected = "\n// Echo: Echoes UTF-8 text without changing its bytes.\n",
        },
        // The reported breakage: a noun phrase must never be spliced.
        .{
            .go_name = "SelectionSilent",
            .zig_name = "selectionSilent",
            .doc = "The selection flag bits shared by the setters below.",
            .expected = "\n// SelectionSilent: The selection flag bits shared by the setters below.\n",
        },
        // A lowercase verb was written to continue from a name, so it splices.
        .{
            .go_name = "Len",
            .zig_name = "len",
            .doc = "reports how many events are queued.",
            .expected = "\n// Len reports how many events are queued.\n",
        },
        // A name that only prefixes the first word is not the first word.
        .{
            .go_name = "Clone",
            .zig_name = "clone",
            .doc = "clones the queue.",
            .expected = "\n// Clone clones the queue.\n",
        },
        // Only the first line is rewritten; the rest is copied verbatim.
        .{
            .go_name = "Clone",
            .zig_name = "clone",
            .doc = "clone copies the queue.\nThe caller owns the copy.",
            .expected = "\n// Clone copies the queue.\n// The caller owns the copy.\n",
        },
        // A doc that is nothing but the name leaves the prefix alone.
        .{
            .go_name = "Clone",
            .zig_name = "clone",
            .doc = "clone",
            .expected = "\n// Clone\n",
        },
    };
    for (cases) |case| {
        var rendered: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer rendered.deinit();
        try docs.writeGoDoc(&rendered.writer, case.go_name, case.zig_name, case.doc);
        try std.testing.expectEqualStrings(case.expected, rendered.written());
    }
}

test "a scalar-only struct slice crosses as a cast while a bool-bearing one is copied" {
    var point: semantic.TypeNode = .{ .value_struct = .{ .ref = "Point" } };
    var flagged: semantic.TypeNode = .{ .value_struct = .{ .ref = "Flagged" } };
    const count: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    const document: semantic.Semantic = .{
        .package = "shapes",
        .prefix = "zg",
        .functions = &.{
            .{
                .name = "fillPoints",
                .params = &.{.{
                    .direction = .out,
                    .name = "output",
                    .type = .{ .slice = .{ .@"const" = false, .element = &point } },
                    .written = .@"return",
                }},
                .@"return" = count,
                .symbol = "zg_fill_points",
            },
            .{
                .name = "fillFlagged",
                .params = &.{.{
                    .direction = .out,
                    .name = "output",
                    .type = .{ .slice = .{ .@"const" = false, .element = &flagged } },
                    .written = .@"return",
                }},
                .@"return" = count,
                .symbol = "zg_fill_flagged",
            },
        },
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "x", .type = .{ .int = .{ .bits = 16, .signed = true } } },
                    .{ .name = "y", .type = .{ .int = .{ .bits = 16, .signed = true } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Point",
            },
            .{
                .fields = &.{
                    .{ .name = "ready", .type = .{ .bool = {} } },
                    .{ .name = "count", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Flagged",
            },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocument(arena.allocator(), document, "shapes", "zg", &.{});

    // A `.return` slice reports its count through the return value, so no
    // `_written` parameter reaches the header or the shim.
    const header_text = try renderForTest(header.renderHeader, program);
    defer std.testing.allocator.free(header_text);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "ZIGO_EXPORT size_t zg_fill_points(zg_point * output_ptr, size_t output_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "output_written") == null);
    const shim_text = try renderForTest(shim.renderShim, program);
    defer std.testing.allocator.free(shim_text);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "output_written") == null);

    const raw_text = try renderForTest(raw.renderRaw, program);
    defer std.testing.allocator.free(raw_text);
    // The scalar-only element points the C call at the caller's own slice and
    // has nothing to read back afterwards.
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "outputPtr := (*C.zg_point)(zigoSlicePtr(output))") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "outputValues[i].x") == null);
    // The bool-bearing element keeps its buffer, but an output parameter is
    // never converted on the way in.
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "outputValues = make([]C.zg_flagged, len(output))") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "coutput.ready = ") == null);
    // `.return` carries the count in the call's own result, so the raw layer
    // reads that rather than an `_written` out parameter it no longer has.
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "for i := 0; i < int(result) && i < len(output); i++ {") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "outputWritten") == null);

    const public_text = try renderForTest(public.renderPublic, program);
    defer std.testing.allocator.free(public_text);
    // Neither direction copies for the castable element; the copied one only
    // takes back as many elements as the shim reported written.
    try std.testing.expect(std.mem.indexOf(u8, public_text, "outputRaw = unsafe.Slice((*raw.PointData)(unsafe.Pointer(&output[0])), len(output))") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "zigoPointSliceToRaw(output)") == null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "zigoPointSliceCopyFromRaw(") == null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "outputRaw := make([]raw.FlaggedData, len(output))") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "zigoFlaggedSliceCopyFromRaw(output, outputRaw, int(result))") != null);
}

test "a returned struct slice is reinterpreted for a castable element and copied otherwise" {
    var point: semantic.TypeNode = .{ .value_struct = .{ .ref = "Point" } };
    var flagged: semantic.TypeNode = .{ .value_struct = .{ .ref = "Flagged" } };
    var point_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &point } };
    const document: semantic.Semantic = .{
        .package = "shapes",
        .prefix = "zg",
        .functions = &.{
            .{
                .name = "points",
                .params = &.{},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &point } },
                .symbol = "zg_points",
            },
            .{
                .name = "flaggedAll",
                .params = &.{},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &flagged } },
                .symbol = "zg_flagged_all",
            },
            .{
                .name = "pointsChecked",
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &point_slice } },
                .symbol = "zg_points_checked",
            },
            .{
                // An `.out` parameter forces the return into a named result, so
                // the reinterpretation has to hold on that path too.
                .name = "collect",
                .params = &.{.{
                    .direction = .out,
                    .name = "output",
                    .type = .{ .slice = .{ .@"const" = false, .element = &flagged } },
                    .written = .all,
                }},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &point } },
                .symbol = "zg_collect",
            },
        },
        .types = &.{
            .{
                .fields = &.{
                    .{ .name = "x", .type = .{ .int = .{ .bits = 16, .signed = true } } },
                    .{ .name = "y", .type = .{ .int = .{ .bits = 16, .signed = true } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Point",
            },
            .{
                .fields = &.{
                    .{ .name = "ready", .type = .{ .bool = {} } },
                    .{ .name = "count", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Flagged",
            },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocument(arena.allocator(), document, "shapes", "zg", &.{.{ .code = 1, .name = "Invalid" }});

    const public_text = try renderForTest(public.renderPublic, program);
    defer std.testing.allocator.free(public_text);
    // The raw layer already copied into a Go allocation, so the public layer
    // hands that same memory back under the public element type.
    try std.testing.expect(std.mem.indexOf(u8, public_text, "return zigoPointSliceView(raw.Points())") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "return zigoPointSliceView(result), nil") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "return zigoPointSliceView(result)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "zigoPointSliceFromRaw(") == null);
    // A bool-bearing element cannot be reinterpreted and keeps the copy.
    try std.testing.expect(std.mem.indexOf(u8, public_text, "return zigoFlaggedSliceFromRaw(raw.FlaggedAll())") != null);

    const structs = try renderForTest(public.renderPublicStructsFile, program);
    defer std.testing.allocator.free(structs);
    // The copying helper would be dead code for a castable element, so only
    // the view is emitted for it and only the copy for the other.
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoPointSliceFromRaw(") == null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoPointSliceToRaw(") == null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoPointSliceCopyFromRaw(") == null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoPointSliceView(values []raw.PointData) []Point {") != null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "return unsafe.Slice((*Point)(unsafe.Pointer(&values[0])), len(values))") != null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoFlaggedSliceFromRaw(values []raw.FlaggedData) []Flagged {") != null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoFlaggedSliceView(") == null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoPointToRaw(") == null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoFlaggedToRaw(") == null);

    const runtime = try renderForTest(public.renderPublicRuntimeFile, program);
    defer std.testing.allocator.free(runtime);
    // Merely reading back a bool-bearing struct does not reference the
    // bool-to-ABI conversion helper.
    try std.testing.expect(std.mem.indexOf(u8, runtime, "func boolToUint8(") == null);
}

test "public helpers are emitted only for matching parameter references" {
    var flagged: semantic.TypeNode = .{ .value_struct = .{ .ref = "Flagged" } };
    const document: semantic.Semantic = .{
        .package = "helpers",
        .prefix = "zg",
        .functions = &.{
            .{
                .name = "accept",
                .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Flagged" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_accept",
            },
            .{
                .name = "acceptMany",
                .params = &.{.{ .name = "values", .type = .{ .slice = .{ .@"const" = true, .element = &flagged } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_accept_many",
            },
            .{
                .name = "merge",
                .params = &.{.{ .name = "other", .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = true, .ref = "Handle" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_merge",
            },
        },
        .types = &.{
            .{
                .fields = &.{.{ .name = "ready", .type = .{ .bool = {} } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Flagged",
            },
            .{
                .fields = &.{.{ .name = "value", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Unused",
            },
            .{ .kind = .@"opaque", .name = "Handle" },
        },
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocument(arena.allocator(), document, "helpers", "zg", &.{});

    const structs = try renderForTest(public.renderPublicStructsFile, program);
    defer std.testing.allocator.free(structs);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoFlaggedToRaw(") != null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoFlaggedSliceToRaw(") != null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoUnusedToRaw(") == null);
    try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoUnusedSliceView(") == null);

    const runtime = try renderForTest(public.renderPublicRuntimeFile, program);
    defer std.testing.allocator.free(runtime);
    try std.testing.expect(std.mem.indexOf(u8, runtime, "func boolToUint8(") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime, "func zigoOptionalPointer(") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime, "func activeCallbackHandleCount(") == null);
}

test "a stream parameter becomes a shim adapter and a fixed callback ABI" {
    var count: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    var nothing: semantic.TypeNode = .{ .void = {} };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{
                .name = "dump",
                .params = &.{.{ .name = "w", .type = .{ .io_stream = .{ .direction = .writer } } }},
                .receiver = "Document",
                .@"return" = .{ .error_union = .{ .error_set = &.{"WriteFailed"}, .payload = &nothing } },
                .symbol = "zg_document_dump",
            },
            .{
                .name = "load",
                .params = &.{.{ .buffer = 8192, .name = "r", .type = .{ .io_stream = .{ .direction = .reader } } }},
                .receiver = "Document",
                .@"return" = .{ .error_union = .{ .error_set = &.{"ReadFailed"}, .payload = &count } },
                .symbol = "zg_document_load",
            },
            .{
                .name = "banner",
                .params = &.{.{ .buffer = 1024 * 1024, .name = "out", .type = .{ .io_stream = .{ .direction = .writer } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_banner",
            },
        },
        .package = "stream",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Document" }},
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocument(arena.allocator(), document, "stream", "zg", &.{
        .{ .code = 1, .name = "WriteFailed" },
        .{ .code = 2, .name = "ReadFailed" },
    });
    try std.testing.expect(common.programUsesCallbackDiagnostics(program));
    const handles_text = try renderForTest(public.renderPublicHandlesFile, program);
    defer std.testing.allocator.free(handles_text);
    try std.testing.expect(std.mem.indexOf(u8, handles_text, "zigoOptionalPointer") == null);

    const shim_text = try renderForTest(shim.renderShim, program);
    defer std.testing.allocator.free(shim_text);
    // One trampoline per direction, bound by name, and one copy of the
    // adapters however many parameters use them.
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "extern fn zg_zigo_stream_write(ptr: [*]const u8, len: usize, userdata: usize) callconv(.c) i32;") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "extern fn zg_zigo_stream_read(ptr: [*]u8, cap: usize, userdata: usize) callconv(.c) i32;") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, shim_text, "const ZigoWriterAdapter = struct {"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, shim_text, "const ZigoReaderAdapter = struct {"));

    // A default-sized buffer is a stack array; the megabyte one is not.
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "    var w_stream_buffer: [65536]u8 = undefined;") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "    var r_stream_buffer: [8192]u8 = undefined;") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "const out_stream_buffer = std.heap.c_allocator.alloc(u8, 1048576) catch @panic(") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "defer std.heap.c_allocator.free(out_stream_buffer);") != null);

    try std.testing.expect(std.mem.indexOf(u8, shim_text, "var w_stream: ZigoWriterAdapter = .init(&w_stream_buffer, &zg_zigo_stream_write, w_userdata);") != null);
    // Whatever the target function left buffered still has to reach Go.
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "defer w_stream.interface.flush() catch {};") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "target.Document.dump(self, &w_stream.interface)") != null);
    // The byte-slice fast path: a non-NULL `r_data` is read with `fixed` and
    // the trampoline is never called.
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "var r_stream_fixed: std.Io.Reader = if (r_data != null) .fixed(r_data[0..r_data_len]) else undefined;") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "target.Document.load(self, r_stream_interface)") != null);

    const header_text = try renderForTest(header.renderHeader, program);
    defer std.testing.allocator.free(header_text);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "int32_t zg_document_dump(zg_document * self, size_t w_userdata);") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "int32_t zg_document_load(zg_document * self, const uint8_t * r_data, size_t r_data_len, size_t r_userdata, size_t * out_result);") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_text, "void zg_banner(size_t out_userdata);") != null);
    const raw_text = try renderForTest(raw.renderRaw, program);
    defer std.testing.allocator.free(raw_text);
    // Two fixed trampolines, bound by the names the shim declared.
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "//export zg_zigo_stream_write") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "//export zg_zigo_stream_read") != null);
    // A short write is a failure the Go side names, not a silent truncation.
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "\tif err == nil && n != int(p1) {\n\t\terr = io.ErrShortWrite\n\t}") != null);
    // Only io.EOF ends the stream; any other error is reported.
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "\tif err == io.EOF {\n\t\treturn C.int32_t(0)\n\t}") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "readStream(state.Reader,") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "\t\t\tresult = C.int32_t(-3)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func TakeStreamError(handle cgo.Handle) (error, bool)") != null);
    // Only a reader carries the byte-slice fast path, and a present-but-empty
    // slice still crosses as a non-NULL pointer.
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func DocumentLoad(self unsafe.Pointer, rHandle uintptr, rData []byte) (uint, int32) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "func DocumentDump(self unsafe.Pointer, wHandle uintptr) int32 {") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "rDataPtr = (*C.uint8_t)(unsafe.Pointer(&zigoEmptyStreamData))") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw_text, "C.zg_document_load((*C.zg_document)(self), rDataPtr, C.size_t(len(rData)), C.size_t(rHandle), &outResult)") != null);

    const public_text = try renderForTest(public.renderPublic, program);
    defer std.testing.allocator.free(public_text);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "func (d *Document) Dump(w io.Writer) error {") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "func (d *Document) Load(r io.Reader) (uint, error) {") != null);
    // An infallible Zig function still returns an error in Go: a nil stream
    // and a failing one both have to reach the caller.
    try std.testing.expect(std.mem.indexOf(u8, public_text, "func Banner(out io.Writer) error {") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "\tif w == nil {\n\t\treturn &StreamError{Operation: \"Document.Dump\", Parameter: \"w\", Err: ErrNilStream}\n\t}") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "\twHandle := newZigoWriterHandle(w)\n\tdefer deleteCallbackHandle(wHandle)") != null);
    // The stream's own error is taken before the native status is judged.
    // A reader is offered to the fast path; a writer has none to be offered.
    try std.testing.expect(std.mem.indexOf(u8, public_text, "\trData := zigoReaderBytes(r)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "zigoReaderBytes(w)") == null);

    const runtime_body = try renderForTest(public.renderPublicRuntimeBody, program);
    defer std.testing.allocator.free(runtime_body);
    // `zigoBytes()` outranks `Bytes()`, so a caller can opt a type in even
    // when it already has a `Bytes()` that means something else.
    const zigo_bytes = std.mem.indexOf(u8, runtime_body, "case interface{ zigoBytes() []byte }:").?;
    const bytes = std.mem.indexOf(u8, runtime_body, "case interface{ Bytes() []byte }:").?;
    try std.testing.expect(zigo_bytes < bytes);
    const rethrow = std.mem.indexOf(u8, public_text, "zigoRethrowCallbackPanic(\"Document.Dump\"").?;
    const stream_error = std.mem.indexOf(u8, public_text, "zigoStreamError(\"Document.Dump\", \"w\", wHandle)").?;
    const status = std.mem.indexOf(u8, public_text, "errorForCode(\"Document.Dump\"").?;
    try std.testing.expect(rethrow < stream_error and stream_error < status);
}

test "materialized decoders and output reuse are emitted for both raw backends" {
    var node: semantic.TypeNode = .{ .materialized = .{ .ref = "Node" } };
    const node_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &node } };
    const count: semantic.TypeNode = .{ .int = .{ .bits = 64, .signed = false, .is_usize = true } };
    const fill_params = [_]semantic.Parameter{.{ .direction = .out, .name = "output", .type = node_slice, .written = .@"return" }};
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const bytes: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &byte } };
    const release_params = [_]semantic.Parameter{.{ .name = "buffer", .type = bytes }};
    const functions = [_]semantic.SemanticFn{
        .{ .name = "snapshot", .ownership = .caller, .params = &.{}, .release = "release", .@"return" = node, .symbol = "zg_snapshot" },
        .{ .name = "fill", .ownership = .caller, .params = &fill_params, .release = "release", .@"return" = count, .symbol = "zg_fill" },
        .{ .name = "release", .params = &release_params, .@"return" = .{ .void = {} }, .symbol = "zg_release" },
    };
    const fields = [_]semantic.TypeField{.{ .name = "value", .type = .{ .int = .{ .bits = 32, .signed = true } } }};
    const types = [_]semantic.TypeDecl{
        .{ .fields = &fields, .kind = .materialized, .materialized_version = 1, .name = "Node", .zig_path = "Node" },
        .{ .fields = &fields, .kind = .materialized, .materialized_version = 1, .name = "Unused", .zig_path = "Unused" },
    };
    const document: semantic.Semantic = .{
        .allocator = "std.heap.c_allocator",
        .functions = &functions,
        .package = "tree",
        .prefix = "zg",
        .types = &types,
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    inline for (.{ abi.Program.Backend.cgo, abi.Program.Backend.purego }) |backend| {
        const program = try @import("lower").semanticDocumentForBackend(arena.allocator(), document, "tree", "zg", &.{}, backend);
        const public_text = try renderForTest(public.renderPublic, program);
        defer std.testing.allocator.free(public_text);
        try std.testing.expect(std.mem.indexOf(u8, public_text, "return zigoDecodeNodeBuffer(") != null);
        try std.testing.expect(std.mem.indexOf(u8, public_text, "zigoBuffer, result := ") != null);
        try std.testing.expect(std.mem.indexOf(u8, public_text, "copy(output, zigoDecoded)") != null);
        const structs = try renderForTest(public.renderPublicStructsFile, program);
        defer std.testing.allocator.free(structs);
        try std.testing.expect(std.mem.indexOf(u8, structs, "type Node struct") != null);
        try std.testing.expect(std.mem.indexOf(u8, structs, "type Unused struct") == null);
        try std.testing.expect(std.mem.indexOf(u8, structs, "func zigoDecodeNodeSliceBuffer") != null);
        const raw_text = try renderForTest(raw.renderRaw, program);
        defer std.testing.allocator.free(raw_text);
        try std.testing.expect(std.mem.indexOf(u8, raw_text, "func Fill(output int) ([]byte, uint)") != null);
    }
}

test "narrow integer slices use promoted ABI elements and shim buffers" {
    var narrow: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    const input_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &narrow } };
    const output_slice: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &narrow } };
    const input_params = [_]semantic.Parameter{.{ .name = "values", .type = input_slice }};
    const output_params = [_]semantic.Parameter{.{ .direction = .out, .name = "output", .type = output_slice }};
    const release_params = [_]semantic.Parameter{.{ .name = "values", .type = input_slice }};
    const functions = [_]semantic.SemanticFn{
        .{ .name = "sum", .params = &input_params, .@"return" = .{ .int = .{ .bits = 32, .signed = false } }, .symbol = "zg_sum" },
        .{ .name = "fill", .params = &output_params, .@"return" = .{ .void = {} }, .symbol = "zg_fill" },
        .{ .name = "take", .ownership = .caller, .params = &.{}, .release = "free", .@"return" = input_slice, .symbol = "zg_take" },
        .{ .name = "free", .params = &release_params, .@"return" = .{ .void = {} }, .symbol = "zg_free" },
    };
    const document: semantic.Semantic = .{
        .allocator = "std.heap.c_allocator",
        .functions = &functions,
        .package = "narrow_slice",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocument(arena.allocator(), document, "narrow_slice", "zg", &.{});

    const shim_text = try renderForTest(shim.renderShim, program);
    defer std.testing.allocator.free(shim_text);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "export fn zg_sum_impl(values_ptr: [*c]const u32, values_len: usize) u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "const zigo_values_slice = std.heap.c_allocator.alloc(u21, values_len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "target.sum(zigo_values_slice)") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "const zigo_output_slice = std.heap.c_allocator.alloc(u21, output_len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "output_ptr[zigo_i] = @intCast(zigo_value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "const zigo_result_ptr: [*]u32 = @ptrCast(@constCast(result.ptr));") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "target.free(if (values_len == 0) &.{} else @as([*]const u21, @ptrCast(values_ptr))[0..values_len])") != null);

    const public_text = try renderForTest(public.renderPublic, program);
    defer std.testing.allocator.free(public_text);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "func Sum(values []uint32) (uint32, error)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "for _, zigoValue := range values") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "func Fill(output []uint32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, public_text, "func Take() []uint32") != null);
}

test "shared lifecycle is opt-in and contains cross-package identities" {
    // An empty program, not `undefined`: the lifecycle renderer reads the
    // function list to decide whether child-handle support is needed.
    const program: abi.Program = .{ .functions = &.{}, .package = "unit", .prefix = "zg" };
    var disabled: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer disabled.deinit();
    try renderLifecycle(std.testing.allocator, &disabled.writer, program, .{ .go_module = "example.com/unit" });
    try std.testing.expectEqual(@as(usize, 0), disabled.written().len);

    var enabled: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer enabled.deinit();
    try renderLifecycle(std.testing.allocator, &enabled.writer, program, .{ .go_module = "example.com/unit", .shared_lifecycle = true });
    const source = enabled.written();
    try std.testing.expect(std.mem.indexOf(u8, source, "package lifecycle") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "type Handle interface") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "func PoisonAfterPanic") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "type CallbackError struct") != null);
}

test "dependency-module types registered under another name resolve through the root at comptime" {
    const fields = [_]semantic.TypeField{.{ .name = "value", .type = .{ .int = .{ .bits = 32, .signed = true } } }};
    const types = [_]semantic.TypeDecl{
        .{ .fields = &fields, .kind = .materialized, .materialized_version = 1, .name = "Probe", .zig_path = "probe.Nested.ProbeReader" },
        .{ .fields = &fields, .kind = .materialized, .materialized_version = 1, .name = "Leaf", .zig_path = "probe.Leaf" },
    };
    const probe: semantic.TypeNode = .{ .materialized = .{ .ref = "Probe" } };
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    const bytes: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &byte } };
    const release_params = [_]semantic.Parameter{.{ .name = "buffer", .type = bytes }};
    const functions = [_]semantic.SemanticFn{
        .{ .name = "snapshot", .ownership = .caller, .params = &.{}, .release = "release", .@"return" = probe, .symbol = "zg_snapshot" },
        .{ .name = "release", .params = &release_params, .@"return" = .{ .void = {} }, .symbol = "zg_release" },
    };
    const document: semantic.Semantic = .{
        .allocator = "std.heap.c_allocator",
        .functions = &functions,
        .package = "probe",
        .prefix = "zg",
        .types = &types,
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try @import("lower").semanticDocumentForBackend(arena.allocator(), document, "probe", "zg", &.{}, .cgo);
    const probe_spelling = try target_types.targetTypeSpellingAlloc(std.testing.allocator, program, "Probe");
    defer std.testing.allocator.free(probe_spelling);
    try std.testing.expectEqualStrings("zigoTargetType(&.{ \"Nested.ProbeReader\", \"ProbeReader\", \"Probe\" })", probe_spelling);
    const leaf_spelling = try target_types.targetTypeSpellingAlloc(std.testing.allocator, program, "Leaf");
    defer std.testing.allocator.free(leaf_spelling);
    try std.testing.expectEqualStrings("target.Leaf", leaf_spelling);
    const shim_text = try renderForTest(shim.renderShim, program);
    defer std.testing.allocator.free(shim_text);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "fn zigoTargetType(comptime candidates") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "value: zigoTargetType(&.{ \"Nested.ProbeReader\", \"ProbeReader\", \"Probe\" })) !u64") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim_text, "target.Probe") == null);
}

test "target type spelling follows registered ancestors across modules" {
    const types = [_]semantic.TypeDecl{
        .{ .kind = .@"opaque", .name = "Terminal", .zig_path = "terminal.Terminal" },
        .{ .kind = .value_struct, .name = "Options", .zig_path = "terminal.Terminal.Options" },
        .{ .kind = .@"opaque", .name = "Cursor", .zig_path = "terminal.Terminal.Screen.Cursor" },
        .{ .kind = .value_struct, .name = "Point", .zig_path = "root.geometry.Point" },
        .{ .kind = .@"opaque", .name = "Orphan", .zig_path = "other.Deep.Orphan" },
        .{ .kind = .@"opaque", .name = "FloatBuffer", .zig_path = "root.Buffer(f32)" },
    };
    const program: abi.Program = .{ .functions = &.{}, .package = "unit", .prefix = "zg", .types = &types };
    const expectations = [_][2][]const u8{
        .{ "Terminal", "target.Terminal" },
        .{ "Options", "target.Terminal.Options" },
        .{ "Cursor", "target.Terminal.Screen.Cursor" },
        .{ "Point", "target.geometry.Point" },
        .{ "Orphan", "target.Orphan" },
        .{ "FloatBuffer", "target.FloatBuffer" },
    };
    for (expectations) |pair| {
        const spelling = try target_types.targetTypeSpellingAlloc(std.testing.allocator, program, pair[0]);
        defer std.testing.allocator.free(spelling);
        try std.testing.expectEqualStrings(pair[1], spelling);
    }
}

test {
    _ = references;
    _ = shim;
    _ = @import("materialized.zig");
    _ = header;
    _ = common;
    _ = raw;
    _ = purego;
    _ = @import("callbacks.zig");
    _ = public;
    _ = @import("must.zig");
    _ = public_types;
    _ = public_runtime;
    _ = interfaces;
    _ = @import("public_writers.zig");
    _ = docs;
}
