const std = @import("std");
const build_options = @import("src/build_options.zig");
const naming = @import("src/gen/naming.zig");
const modules = @import("build/modules.zig");
const steps = @import("build/steps.zig");
const tests = @import("build/tests.zig");

pub const CgoFlags = struct {
    cflags: []const []const u8 = &.{},
    ldflags: []const []const u8 = &.{},
    /// Additional linker flags appended after zigo's default (or overridden)
    /// binding-library flags, on every platform.
    extra_ldflags: []const []const u8 = &.{},
    /// Linker flags for one platform only, each emitted as its own
    /// `#cgo <goos>[,<goarch>] LDFLAGS:` line after the library lines. They
    /// apply whether or not `targets` is set, and survive `ldflags` overrides.
    target_ldflags: []const TargetLdflags = &.{},

    pub const TargetLdflags = struct {
        /// Go's OS name: `darwin`, `linux`, `windows`, ...
        goos: []const u8,
        /// Go's architecture name; null applies the flags to every architecture.
        goarch: ?[]const u8 = null,
        ldflags: []const []const u8,
    };
};

const LinkMode = enum { static, dynamic };
const Backend = enum { cgo, purego };

/// How the Go side reaches the native library. One axis, because the two it
/// replaced could describe combinations that do not exist: purego never links
/// statically, and it never goes through cgo.
pub const Link = enum {
    /// cgo against a static archive.
    cgo_static,
    /// cgo against a shared library.
    cgo_dynamic,
    /// No cgo. Symbols are resolved at run time from a shared library.
    purego,

    fn backend(self: Link) Backend {
        return if (self == .purego) .purego else .cgo;
    }

    fn linkMode(self: Link) LinkMode {
        return if (self == .cgo_static) .static else .dynamic;
    }
};

/// How a generated purego package finds its shared library at run time.
pub const LibraryLoading = build_options.LibraryLoading;

/// The `GOOS`/`GOARCH` pair of a native target.
pub const GoTarget = build_options.GoTarget;

/// Where the generated native artifacts are installed under Zig's prefix.
pub const Install = struct {
    library_dir: std.Build.InstallDir = .lib,
    header_dir: std.Build.InstallDir = .header,
    /// Native library stem, without a leading `lib` or platform extension.
    library_name: ?[]const u8 = null,
    /// Installed C header filename. The generated source header keeps its
    /// canonical `zigo_<name>.h` name.
    header_name: ?[]const u8 = null,
};

pub const Options = struct {
    name: []const u8,
    module: *std.Build.Module,
    bindings: std.Build.LazyPath,
    source_root: ?std.Build.LazyPath = null,
    go_dir: std.Build.LazyPath,
    go_module: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    prefix: []const u8 = "zg",
    link: Link = .cgo_static,
    /// Further platforms the native library is built for, on top of
    /// `target`. The Go tree is generated once and every platform's library
    /// installs under `install.library_dir/<goos>_<goarch>/`. With cgo the
    /// raw package carries a `#cgo <goos>,<goarch> LDFLAGS` line per platform;
    /// with purego the generated loader looks for the library in the running
    /// platform's subdirectory of every search path. The caller's module
    /// graph is rebuilt per platform, so it must not carry prebuilt archives.
    /// Empty keeps the single-target layout.
    targets: []const std.Build.ResolvedTarget = &.{},
    cgo_flags: ?CgoFlags = null,
    abi_base: ?[]const u8 = null,
    /// Slash-separated path of the raw package inside `go_dir`. Setting it to
    /// the public package path colocates the two.
    raw_package: []const u8 = "internal/raw",
    /// `gofmt` used to format generated Go. Defaults to the one on `PATH`.
    gofmt: ?[]const u8 = null,
    /// Public Go package name. Defaults to the snake_case binding name, which
    /// can contain underscores; set it to choose an idiomatic Go name. The C
    /// header and the native library keep the binding name either way.
    go_package: ?[]const u8 = null,
    /// Slash-separated public package path inside `go_dir`. Defaults to
    /// `go_package`; `.` publishes the package at the `go_dir` root.
    go_package_path: ?[]const u8 = null,
    /// Body of the generated `// Package ...` doc. Null falls back to the `//!`
    /// container doc of the bindings file, then to a default sentence.
    go_package_doc: ?[]const u8 = null,
    /// Emit `Must*` companions for public functions whose generated Go
    /// signature returns an error. Disabled by default.
    go_must_variants: bool = false,
    /// Optional source path for the JSON form of `go-coverage`.
    coverage_json: ?[]const u8 = null,
    /// purego-only run-time loading policy. The default requires an explicit
    /// `LoadLibrary` call and consults `ZIGO_LIBRARY_PATH`.
    library_loading: LibraryLoading = .{},
    /// Native library and C header install directories and filenames.
    install: Install = .{},
};

const ResolvedRawPackage = struct {
    path: []const u8,
    name: []const u8,
    colocated: bool,
};

pub const GoBindings = struct {
    update: *std.Build.Step.UpdateSourceFiles,
    check: *std.Build.Step.Run,
    abi_check: ?*std.Build.Step.Run,
    report: *std.Build.Step.Run,
    doctor: *std.Build.Step.Run,
    coverage: *std.Build.Step.Run,
    /// The native library for `Options.target`. See `native_libraries` for
    /// the others when `Options.targets` is set.
    lib: *std.Build.Step.Compile,
    /// Installs the native binding library for `Options.target`.
    install_library: *std.Build.Step.InstallArtifact,
    /// Target-specific basename of the native binding library.
    library_filename: []const u8,
    /// Full path `install_library` writes the native binding library to.
    /// Use this rather than joining a directory with `library_filename`.
    library_path: []const u8,
    /// One entry per platform, `Options.target` first. A single-target
    /// binding set has exactly one.
    native_libraries: []const NativeLibrary,
    semantic_json: std.Build.LazyPath,
    /// Build-time-resolved names used by the generated `#cgo pkg-config:` line.
    resolved_pkg_config: ?std.Build.LazyPath,

    pub const NativeLibrary = struct {
        target: std.Build.ResolvedTarget,
        /// Go's name for the platform; null when Go has no cgo toolchain for
        /// it, which only a single-target build can be.
        go_target: ?GoTarget,
        lib: *std.Build.Step.Compile,
        install_library: *std.Build.Step.InstallArtifact,
        /// Full path `install_library` writes the library to.
        library_path: []const u8,
    };

    pub const StandardStepOptions = struct {
        /// Prefixes conventional step names for projects with multiple binding sets.
        /// For example, `.name_prefix = "admin"` registers `admin-go` and
        /// `admin-go-check` instead of `go` and `go-check`.
        name_prefix: ?[]const u8 = null,
        /// Installs the native binding library as part of the default install
        /// step. Disable this when the caller manages installation separately.
        install_library_by_default: bool = true,
    };

    pub const StandardSteps = struct {
        update: *std.Build.Step,
        check: *std.Build.Step,
        abi_check: ?*std.Build.Step,
        report: *std.Build.Step,
        doctor: *std.Build.Step,
        coverage: *std.Build.Step,
        library: *std.Build.Step,
        /// Aggregate validation step: staleness, toolchain, native library and,
        /// when `abi_base` is set, the ABI comparison.
        verify: *std.Build.Step,
    };

    /// Registers conventional user-facing build steps for this binding set.
    pub fn addStandardSteps(self: GoBindings, b: *std.Build, options: StandardStepOptions) StandardSteps {
        if (options.name_prefix) |prefix| {
            if (prefix.len == 0) @panic("Go binding step name_prefix must not be empty");
        }
        const update = b.step(standardStepName(b, options.name_prefix, "go"), "Generate and build Go bindings");
        update.dependOn(&self.update.step);
        const check = b.step(standardStepName(b, options.name_prefix, "go-check"), "Fail if generated Go bindings are stale");
        check.dependOn(&self.check.step);
        const report = b.step(standardStepName(b, options.name_prefix, "go-report"), "Explain the effective Go binding contract");
        report.dependOn(&self.report.step);
        const doctor = b.step(standardStepName(b, options.name_prefix, "go-doctor"), "Check Go binding toolchain prerequisites");
        doctor.dependOn(&self.doctor.step);
        const coverage = b.step(standardStepName(b, options.name_prefix, "go-coverage"), "Report public Zig API binding coverage");
        coverage.dependOn(&self.coverage.step);
        const library = b.step(standardStepName(b, options.name_prefix, "go-lib"), "Build and install the native Go binding library");
        for (self.native_libraries) |native| {
            library.dependOn(&native.install_library.step);
            if (options.install_library_by_default) {
                b.getInstallStep().dependOn(&native.install_library.step);
            }
        }
        const abi_check = if (self.abi_check) |run| step: {
            const value = b.step(standardStepName(b, options.name_prefix, "abi-check"), "Fail on a breaking Go binding ABI change");
            value.dependOn(&run.step);
            break :step value;
        } else null;
        const verify = b.step(standardStepName(b, options.name_prefix, "go-verify"), "Validate generated bindings, toolchain, and the native library");
        verify.dependOn(check);
        verify.dependOn(library);
        verify.dependOn(doctor);
        if (abi_check) |value| verify.dependOn(value);
        return .{ .update = update, .check = check, .abi_check = abi_check, .report = report, .doctor = doctor, .coverage = coverage, .library = library, .verify = verify };
    }
};

fn standardStepName(b: *std.Build, prefix: ?[]const u8, suffix: []const u8) []const u8 {
    return if (prefix) |value| b.fmt("{s}-{s}", .{ value, suffix }) else suffix;
}

const ResolvedInstall = struct {
    library_dir: std.Build.InstallDir,
    header_dir: std.Build.InstallDir,
    library_stem: []const u8,
    generated_header_name: []const u8,
    header_name: []const u8,
    cgo_library_dir: []const u8,
    cgo_header_dir: []const u8,
    purego_default_search_paths: []const []const u8,
};

const ExplicitHeaderInstall = struct {
    path: []const u8,
    backend: Backend,
};

var explicit_header_installs: std.ArrayList(ExplicitHeaderInstall) = .empty;

fn resolveInstall(
    b: *std.Build,
    options: Install,
    artifact_package: []const u8,
    backend: Backend,
    raw_source_dir: []const u8,
    public_source_dir: []const u8,
) ResolvedInstall {
    const default_library_stem = b.fmt("{s}_zigo", .{artifact_package});
    const library_stem = options.library_name orelse default_library_stem;
    validateInstallFilename("install.library_name", library_stem);

    const generated_header_name = b.fmt("zigo_{s}.h", .{artifact_package});
    // A purego binding set declares decorated entry points, so its default
    // header must not overwrite the cgo header in a shared prefix.
    const default_header_name = if (backend == .purego)
        b.fmt("zigo_{s}_purego.h", .{artifact_package})
    else
        generated_header_name;
    const header_name = options.header_name orelse default_header_name;
    validateInstallFilename("install.header_name", header_name);
    if (options.header_name != null)
        registerExplicitHeader(b, options.header_dir, header_name, backend);

    const library_path = b.getInstallPath(options.library_dir, "");
    const header_path = b.getInstallPath(options.header_dir, "");
    const default_search_paths: []const []const u8 = if (backend == .purego and options.library_dir != .lib)
        b.allocator.dupe([]const u8, &.{relativeInstallPath(b, public_source_dir, library_path)}) catch @panic("OOM")
    else
        &.{};
    return .{
        .library_dir = options.library_dir,
        .header_dir = options.header_dir,
        .library_stem = library_stem,
        .generated_header_name = generated_header_name,
        .header_name = header_name,
        .cgo_library_dir = cgoRelativePath(b, raw_source_dir, library_path),
        .cgo_header_dir = cgoRelativePath(b, raw_source_dir, header_path),
        .purego_default_search_paths = default_search_paths,
    };
}

/// cgo build constraints are lowercase words, so a typo like `Linux` would
/// silently select nothing.
fn validateGoPlatformWord(option: []const u8, value: []const u8) void {
    if (value.len == 0) std.debug.panic("{s} must not be empty", .{option});
    for (value) |byte| {
        if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte))
            std.debug.panic("{s} must be a lowercase Go platform name, got '{s}'", .{ option, value });
    }
}

fn validateInstallFilename(option: []const u8, value: []const u8) void {
    if (value.len == 0 or !std.mem.eql(u8, std.fs.path.basename(value), value) or
        std.mem.eql(u8, value, ".") or std.mem.eql(u8, value, ".."))
    {
        std.debug.panic("{s} must be a non-empty filename without directory components", .{option});
    }
}

fn registerExplicitHeader(b: *std.Build, dir: std.Build.InstallDir, name: []const u8, backend: Backend) void {
    const path = b.getInstallPath(dir, name);
    for (explicit_header_installs.items) |installed| {
        if (installed.backend != backend and std.mem.eql(u8, installed.path, path)) {
            std.debug.panic("cgo and purego install.header_name both resolve to '{s}'; choose distinct header names", .{path});
        }
    }
    explicit_header_installs.append(std.heap.page_allocator, .{
        .path = std.heap.page_allocator.dupe(u8, path) catch @panic("OOM"),
        .backend = backend,
    }) catch @panic("OOM");
}

fn resolvedLibraryLoading(loading: LibraryLoading, install: ResolvedInstall) LibraryLoading {
    if (loading.search_paths.len != 0 or install.purego_default_search_paths.len == 0) return loading;
    var resolved = loading;
    resolved.search_paths = install.purego_default_search_paths;
    return resolved;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = b.option([]const []const u8, "test-filter", "Run only tests or generator cases matching a filter") orelse &.{};
    const zigo = b.addModule("zigo", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generator_modules = modules.createGeneratorModules(b, b.path("src"), target, optimize);
    const generator = modules.addGeneratorWithModules(b, b.path("src/main.zig"), target, optimize, generator_modules);
    b.installArtifact(generator);

    tests.addRepositorySteps(b, target, optimize, test_filters, zigo, generator_modules, generator);
}

/// Adds the Go-binding pipeline to a consuming build graph.
pub fn addGoBindings(b: *std.Build, options: Options) GoBindings {
    const backend = options.link.backend();
    const link_mode = options.link.linkMode();
    if (backend == .purego) {
        if (!build_options.puregoTargetSupported(options.target.result))
            @panic("`.link = .purego` supports macOS, Linux and Windows on amd64/arm64 only");
    }
    const artifact_package = naming.snakeAlloc(b.allocator, options.name) catch @panic("OOM");
    const go_package = if (options.go_package) |value| blk: {
        naming.validateGoPackageName(value) catch
            @panic("go_package must be a valid Go package identifier");
        break :blk value;
    } else artifact_package;
    const go_package_path = resolveGoPackagePath(options.go_package_path orelse go_package);
    const raw_package = resolveRawPackage(b, options.raw_package, go_package_path, go_package);
    const raw_source_dir = options.go_dir.path(b, raw_package.path).getPath(b);
    const public_source_dir = options.go_dir.path(b, go_package_path).getPath(b);
    const install = resolveInstall(b, options.install, artifact_package, backend, raw_source_dir, public_source_dir);
    const library_loading = resolvedLibraryLoading(options.library_loading, install);
    build_options.validateLibraryLoading(library_loading, backend == .purego) catch |err| switch (err) {
        error.UnsupportedBackend => @panic("library_loading is only supported by .link = .purego"),
        error.EmptySearchPath => @panic("library_loading.search_paths entries must not be empty"),
        error.InvalidSearchPath => @panic("library_loading.search_paths entries must not contain quotes, backslashes or control characters"),
        error.InvalidEnvironmentName => @panic("library_loading.env_vars entries must be ASCII letters, digits and underscores, and must not start with a digit"),
    };
    const native_targets = resolveNativeTargets(b, options, backend, install);
    const zigo_dependency = b.dependencyFromBuildZig(@This(), .{});
    const generator = modules.addGenerator(b, zigo_dependency.path("src/main.zig"), b.graph.host, .Debug);
    // Reflection runs the bindings module as an executable on the host, so the
    // whole reflection pipeline builds for `b.graph.host` even when the library
    // targets another platform. The generated Go tree is platform-independent;
    // reflected layouts are pinned by the shim's comptime ABI guards, which fail
    // the target compile if a C-variable type diverges.
    const naming_module = b.createModule(.{
        .root_source_file = zigo_dependency.path("src/gen/naming.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const semantic_module = b.createModule(.{
        .root_source_file = zigo_dependency.path("src/gen/ir/semantic.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .imports = &.{.{ .name = "naming", .module = naming_module }},
    });
    // The reflected module is the caller's, retargeted to the host. Its
    // Static link inputs were built for `options.target`, and a host executable
    // cannot link a foreign archive. Rebuild library steps for the host so
    // their headers and libc/libc++ settings remain available; prebuilt target
    // archives are still left out. See `hostReflectionModule`.
    var reflection_clones: steps.HostReflectionClones = .{};
    const reflected_module = steps.hostReflectionModule(b, options.module, options.optimize, &reflection_clones);
    const bindings_module = b.createModule(.{
        .root_source_file = options.bindings,
        .target = b.graph.host,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "zigo", .module = zigo_dependency.module("zigo") },
            .{ .name = options.name, .module = reflected_module },
        },
    });
    const reflector = b.addExecutable(.{
        .name = "zigo-reflect",
        .root_module = b.createModule(.{
            .root_source_file = zigo_dependency.path("src/reflect/main.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
            .imports = &.{
                .{ .name = "bindings", .module = bindings_module },
                .{ .name = "naming", .module = naming_module },
                .{ .name = "semantic", .module = semantic_module },
            },
        }),
    });
    const semantic_run = b.addRunArtifact(reflector);
    semantic_run.addArgs(&.{ options.name, options.prefix });
    semantic_run.addFileArg(options.bindings);
    // An absent source root is an absent argument, not an empty one.
    if (options.source_root) |source_root| semantic_run.addFileArg(source_root);
    const semantic_json = semantic_run.captureStdOut(.{ .basename = "semantic.json", .trim_whitespace = .none });
    // Successful fallback warnings stay captured so Zig does not label a
    // successful command as failed. On a non-zero exit, Step.Run reports the
    // captured enrichment diagnostics with the actual failure.
    _ = semantic_run.captureStdErr(.{ .basename = "warnings.txt", .trim_whitespace = .none });

    const coverage = b.addRunArtifact(reflector);
    coverage.has_side_effects = true;
    coverage.addArgs(&.{ "coverage", options.name, options.prefix });
    coverage.addFileArg(options.bindings);
    if (options.source_root) |source_root| coverage.addFileArg(source_root);
    if (options.coverage_json) |destination| {
        const coverage_json_run = b.addRunArtifact(reflector);
        coverage_json_run.addArgs(&.{ "coverage-json", options.name, options.prefix });
        coverage_json_run.addFileArg(options.bindings);
        if (options.source_root) |source_root| coverage_json_run.addFileArg(source_root);
        const coverage_json = coverage_json_run.captureStdOut(.{ .basename = "coverage.json", .trim_whitespace = .none });
        const publish_coverage = b.addUpdateSourceFiles();
        publish_coverage.addCopyFileToSource(coverage_json, destination);
        coverage.step.dependOn(&publish_coverage.step);
    }

    const generate = b.addRunArtifact(generator);
    generate.addArgs(&.{ "generate", "--semantic" });
    generate.addFileArg(semantic_json);
    generate.addArg("--output");
    const generated_dir = generate.addOutputDirectoryArg("bindings");
    // Generation formats its own Go, so the set of generated files never has to
    // be spelled out here.
    if (options.gofmt) |gofmt| generate.addArgs(&.{ "--gofmt", gofmt });
    const cflags_override = if (options.cgo_flags) |flags| steps.joinFlags(b, flags.cflags) else "";
    const ldflags_override = if (options.cgo_flags) |flags| steps.joinFlags(b, flags.ldflags) else "";
    const extra_ldflags = if (options.cgo_flags) |flags| steps.joinFlags(b, flags.extra_ldflags) else "";
    var link_inputs: steps.LinkInputCollector = .{};
    link_inputs.collect(b, options.module);
    const system_ldflags = steps.systemLibraryFlags(b, &link_inputs);
    const static_link_inputs = if (backend == .cgo and link_mode == .static and ldflags_override.len == 0)
        link_inputs.staticLibraryInputs()
    else
        steps.StaticLinkInputs.empty;
    const framework_ldflags = steps.frameworkFlags(b, &link_inputs);
    const pkg_config_resolution = if (backend == .cgo)
        steps.ResolvePkgConfigLibraries.create(b, artifact_package, link_inputs.system_libraries.items)
    else
        null;
    generate.addArgs(&.{
        "--package",           options.name,
        "--prefix",            options.prefix,
        "--go-module",         options.go_module,
        "--include-dir",       install.cgo_header_dir,
        "--library-dir",       install.cgo_library_dir,
        "--header-name",       install.header_name,
        "--cflags",            cflags_override,
        "--ldflags",           ldflags_override,
        "--extra-ldflags",     extra_ldflags,
        "--system-ldflags",    system_ldflags,
        "--framework-ldflags", framework_ldflags,
        "--raw-package-path",  raw_package.path,
        "--raw-package-name",  raw_package.name,
        "--backend",           @tagName(backend),
        "--library-stem",      install.library_stem,
        "--link-mode",         @tagName(link_mode),
        "--go-package",        go_package,
        "--go-package-path",   go_package_path,
        "--go-package-doc",    options.go_package_doc orelse "",
    });
    if (pkg_config_resolution) |resolution| {
        generate.addArg("--pkg-config-libs-file");
        generate.addFileArg(resolution.output());
        // Report zigo's module-specific diagnostic before Zig independently
        // attempts to resolve the same forced library for reflection.
        semantic_run.step.dependOn(&resolution.step);
    }
    if (static_link_inputs.paths.len != 0) generate.addArg("--ldflags-external");
    if (options.targets.len != 0 and backend == .cgo) {
        for (native_targets) |native| generate.addArgs(&.{ "--cgo-target", b.fmt("{s}/{s}", .{ native.go_target.?.goos, native.go_target.?.goarch }) });
    }
    // purego finds the library at run time, so the per-platform layout is a
    // loader policy rather than a link line.
    const library_platform_dirs = options.targets.len != 0 and backend == .purego;
    if (library_platform_dirs) generate.addArg("--library-platform-dirs");
    if (options.cgo_flags) |flags| {
        for (flags.target_ldflags) |entry| {
            validateGoPlatformWord("cgo_flags.target_ldflags goos", entry.goos);
            if (entry.goarch) |goarch| validateGoPlatformWord("cgo_flags.target_ldflags goarch", goarch);
            if (entry.ldflags.len == 0) @panic("cgo_flags.target_ldflags entries must list at least one flag");
            const constraint = if (entry.goarch) |goarch| b.fmt("{s},{s}", .{ entry.goos, goarch }) else entry.goos;
            generate.addArgs(&.{ "--target-ldflags", b.fmt("{s}={s}", .{ constraint, steps.joinFlags(b, entry.ldflags) }) });
        }
    }
    if (options.go_must_variants) generate.addArg("--go-must-variants");
    if (backend == .purego) addLibraryLoadingArgs(b, generate, library_loading);
    if (raw_package.colocated) generate.addArg("--raw-colocated");
    const errors_lock_path = "zigo/errors.lock.json";
    const has_errors_lock = blk: {
        b.build_root.handle.access(b.graph.io, errors_lock_path, .{}) catch |err| switch (err) {
            error.FileNotFound => break :blk false,
            else => @panic("unable to inspect errors.lock.json"),
        };
        break :blk true;
    };
    if (has_errors_lock) {
        generate.addArg("--errors-lock");
        generate.addFileArg(b.path(errors_lock_path));
    }

    const check = b.addRunArtifact(generator);
    check.addArgs(&.{ "check", "--generated" });
    check.addDirectoryArg(generated_dir);
    check.addArg("--source");
    check.addDirectoryArg(options.go_dir);
    // The sidecar files the update step copies outside the Go directory are
    // part of the committed output too, so a stale one fails the check here
    // rather than in CI's post-generation diff.
    check.addArg("--file");
    check.addFileArg(semantic_json);
    check.addArg(b.pathFromRoot("zigo/semantic.json"));
    check.addArg("--file");
    check.addFileArg(generated_dir.path(b, "errors.lock.json"));
    check.addArg(b.pathFromRoot(errors_lock_path));
    const report = b.addRunArtifact(generator);
    report.addArgs(&.{ "report", "--semantic" });
    report.addFileArg(semantic_json);
    report.addArgs(&.{ "--go-module", options.go_module, "--raw-package-path", raw_package.path, "--go-package", go_package, "--go-package-path", go_package_path });
    report.addArgs(&.{ "--backend", @tagName(backend) });
    if (backend == .purego) addLibraryLoadingArgs(b, report, library_loading);
    if (library_platform_dirs) report.addArg("--library-platform-dirs");
    if (raw_package.colocated) report.addArg("--raw-colocated");
    const doctor = b.addRunArtifact(generator);
    doctor.has_side_effects = true;
    // One platform the host can run is enough for the checks that load or
    // link the artifact; every other platform still cross-builds.
    const any_native_target = for (native_targets) |native| {
        if (isRunnableOnHost(native.resolved.result, b.graph.host.result)) break true;
    } else false;
    doctor.addArgs(&.{ "doctor", "--target", if (any_native_target) "native" else "cross" });
    doctor.addArgs(&.{ "--backend", @tagName(backend) });
    // Report the same gofmt the update step will format with.
    if (options.gofmt) |gofmt| doctor.addArgs(&.{ "--gofmt", gofmt });
    const abi_check: ?*std.Build.Step.Run = if (options.abi_base) |abi_base| check: {
        const baseline = b.addSystemCommand(&.{ "git", "show" });
        // The ref can move without changing argv, so this read must not reuse a
        // build-cache entry from an older commit.
        baseline.has_side_effects = true;
        baseline.setCwd(b.path("."));
        baseline.addArg(b.fmt("{s}:./zigo/semantic.json", .{abi_base}));
        const baseline_semantic = baseline.captureStdOut(.{ .basename = "semantic-base.json", .trim_whitespace = .none });
        const run = b.addRunArtifact(generator);
        run.addArgs(&.{ "abi-diff", "--base" });
        run.addFileArg(baseline_semantic);
        run.addArg("--current");
        run.addFileArg(semantic_json);
        run.addArgs(&.{ "--base-backend", @tagName(backend), "--current-backend", @tagName(backend) });
        run.addArgs(&.{ "--fail-on", "breaking" });
        break :check run;
    } else null;

    var native_libraries: std.ArrayList(GoBindings.NativeLibrary) = .empty;
    var target_link_flags: std.ArrayList(steps.PublishCgoLinkFlags.TargetFlags) = .empty;
    for (native_targets) |native| {
        const shim_module = b.createModule(.{
            .root_source_file = generated_dir.path(b, "shim.zig"),
            .target = native.resolved,
            .optimize = options.optimize,
            .imports = &.{.{ .name = "zigo_target", .module = native.module }},
        });
        const lib = b.addLibrary(.{
            .name = install.library_stem,
            .linkage = switch (link_mode) {
                .static => .static,
                .dynamic => .dynamic,
            },
            .root_module = shim_module,
        });
        lib.root_module.addCSourceFile(.{ .file = generated_dir.path(b, "panic.c"), .flags = &.{"-fno-sanitize=undefined"} });
        lib.root_module.linkSystemLibrary("c", .{});
        // Zig names a Windows static archive `<name>.lib`, but the generated cgo
        // `#cgo LDFLAGS` line spells the archive `lib<name>.a` on every host so the
        // emitted block stays identical across targets. `zig cc` links a `.a`
        // archive on Windows just as happily, so rename the install instead of
        // teaching the generator a per-OS filename.
        const static_windows_archive = link_mode == .static and
            native.resolved.result.os.tag == .windows;
        const install_lib = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = native.library_dir },
            // A Windows cgo dynamic link consumes the import library, so it must
            // follow the DLL into the configured search directory as well.
            .implib_dir = if (link_mode == .dynamic and native.resolved.result.os.tag == .windows)
                .{ .override = native.library_dir }
            else
                .disabled,
            .dest_sub_path = if (static_windows_archive)
                b.fmt("lib{s}.a", .{install.library_stem})
            else
                null,
        });
        native_libraries.append(b.allocator, .{
            .target = native.resolved,
            .go_target = native.go_target,
            .lib = lib,
            .install_library = install_lib,
            .library_path = installedLibraryPath(b, install_lib),
        }) catch @panic("OOM");

        if (static_link_inputs.paths.len == 0) continue;
        // Every static input is installed beside the binding archive under the
        // same `lib<name>.a` spelling, so the cgo line names install-relative
        // paths on every host: cgo rejects a bare `.lib`, and a Windows absolute
        // path with backslashes never survives its flag check. A retargeted
        // module graph carries its own rebuilt inputs, collected here per target.
        var native_inputs: steps.LinkInputCollector = .{};
        native_inputs.collect(b, native.module);
        const inputs = native_inputs.staticLibraryInputs();
        var archives: std.ArrayList([]const u8) = .empty;
        var installs: std.ArrayList(*std.Build.Step) = .empty;
        for (inputs.paths, inputs.names) |path, name| {
            if (std.mem.eql(u8, name, install.library_stem)) @panic(b.fmt("static link input '{s}' collides with the binding library name", .{name}));
            const file_name = b.fmt("lib{s}.a", .{name});
            const install_archive = b.addInstallFileWithDir(path, native.library_dir, file_name);
            installs.append(b.allocator, &install_archive.step) catch @panic("OOM");
            archives.append(b.allocator, b.fmt("{s}/{s}", .{ native.cgo_library_dir, file_name })) catch @panic("OOM");
        }
        target_link_flags.append(b.allocator, .{
            .constraint = native.constraint,
            .binding_archive = b.fmt("{s}/lib{s}.a", .{ native.cgo_library_dir, install.library_stem }),
            .static_archives = archives.items,
            .archive_installs = installs.items,
        }) catch @panic("OOM");
    }
    const primary = native_libraries.items[0];
    const install_header = b.addInstallFileWithDir(
        generated_dir.path(b, install.generated_header_name),
        install.header_dir,
        install.header_name,
    );
    const volatile_link_flags = if (static_link_inputs.paths.len != 0)
        steps.PublishCgoLinkFlags.create(b, .{
            .output_path = sourcePath(b, options.go_dir, b.pathJoin(&.{ raw_package.path, steps.volatile_cgo_link_file })),
            .package = raw_package.name,
            .targets = target_link_flags.items,
            .extra_ldflags = extra_ldflags,
            .system_ldflags = system_ldflags,
        })
    else
        null;
    const publish = steps.PublishGeneratedGo.create(b, generated_dir, sourcePath(b, options.go_dir, "."));
    const update = b.addUpdateSourceFiles();
    update.step.dependOn(&publish.step);
    update.addCopyFileToSource(generated_dir.path(b, "errors.lock.json"), errors_lock_path);
    update.addCopyFileToSource(semantic_json, "zigo/semantic.json");
    const go_mod_path = sourcePath(b, options.go_dir, "go.mod");
    b.build_root.handle.access(b.graph.io, go_mod_path, .{}) catch |err| switch (err) {
        error.FileNotFound => update.addBytesToSource(b.fmt("module {s}\n\ngo {s}\n{s}", .{
            options.go_module,
            "1.24",
            if (backend == .purego) b.fmt("\nrequire {s} {s}\n", .{ build_options.purego_module, build_options.purego_version }) else "",
        }), go_mod_path),
        else => @panic("unable to inspect go.mod"),
    };
    if (backend == .purego) {
        const go_mod = b.build_root.handle.readFileAlloc(b.graph.io, go_mod_path, b.allocator, .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => @panic("unable to read go.mod for purego dependency validation"),
        };
        if (go_mod) |contents| {
            if (std.mem.indexOf(u8, contents, build_options.purego_module) == null)
                std.debug.panic("purego backend requires {0s} {1s}; run `go get {0s}@{1s}`", .{ build_options.purego_module, build_options.purego_version });
        }
    }
    if (backend == .purego) {
        // The purego doctor validates the deployed artifact, so it must run
        // against a freshly installed library and the module that loads it.
        // A cross-built artifact cannot be loaded here, so it is not offered:
        // the doctor reports that check as skipped rather than failing it.
        // With several targets, the one the host can run is the one checked.
        const loadable = for (native_libraries.items) |native| {
            if (isRunnableOnHost(native.target.result, b.graph.host.result)) break native;
        } else null;
        doctor.step.dependOn(&(if (loadable) |native| native.install_library else primary.install_library).step);
        if (loadable) |native| doctor.addArgs(&.{ "--library", native.library_path });
        doctor.addArgs(&.{ "--go-mod", b.pathFromRoot(go_mod_path) });
    }
    update.step.dependOn(&install_header.step);
    for (native_libraries.items) |native| {
        update.step.dependOn(&native.install_library.step);
        // The archive is useless to cgo without the header beside it, so every
        // step that installs a library (`go-lib`, the default `install`)
        // installs the header as well.
        native.install_library.step.dependOn(&install_header.step);
        // Every platform's shim has to compile for the tree to be valid.
        check.step.dependOn(&native.lib.step);
        if (abi_check) |run| run.step.dependOn(&native.lib.step);
    }
    if (volatile_link_flags) |flags| {
        update.step.dependOn(&flags.step);
        check.step.dependOn(&flags.step);
        for (native_libraries.items, flags.config.targets) |native, target_flags| {
            native.install_library.step.dependOn(&flags.step);
            for (target_flags.archive_installs) |archive_install| native.install_library.step.dependOn(archive_install);
        }
    }

    return .{
        .update = update,
        .check = check,
        .abi_check = abi_check,
        .report = report,
        .doctor = doctor,
        .coverage = coverage,
        .lib = primary.lib,
        .install_library = primary.install_library,
        .library_filename = primary.install_library.dest_sub_path,
        .library_path = primary.library_path,
        .native_libraries = native_libraries.items,
        .semantic_json = semantic_json,
        .resolved_pkg_config = if (pkg_config_resolution) |resolution| resolution.output() else null,
    };
}

/// One platform the native library is built for.
const NativeTarget = struct {
    resolved: std.Build.ResolvedTarget,
    /// Go's name for the platform. Always set in multi-target mode.
    go_target: ?GoTarget,
    /// `<goos>,<goarch>` for the `#cgo` constraint; empty in single-target mode.
    constraint: []const u8,
    /// Where this target's library and static inputs install.
    library_dir: std.Build.InstallDir,
    /// The same directory spelled for the generated cgo line.
    cgo_library_dir: []const u8,
    /// The caller's module graph, rebuilt for this target when it is not the
    /// one the caller built it for.
    module: *std.Build.Module,
};

/// `Options.target` first, then `Options.targets`. Without extra targets the
/// single entry keeps the caller's module and the flat install layout, so
/// existing trees stay byte-identical. With them, every entry (including the
/// first) gets a `<goos>_<goarch>` subdirectory and a qualified cgo line.
fn resolveNativeTargets(b: *std.Build, options: Options, backend: Backend, install: ResolvedInstall) []const NativeTarget {
    if (options.targets.len == 0) {
        const single = b.allocator.alloc(NativeTarget, 1) catch @panic("OOM");
        single[0] = .{
            .resolved = options.target,
            .go_target = build_options.goTarget(options.target.result),
            .constraint = "",
            .library_dir = install.library_dir,
            .cgo_library_dir = install.cgo_library_dir,
            .module = options.module,
        };
        return single;
    }
    var list: std.ArrayList(NativeTarget) = .empty;
    for (0..options.targets.len + 1) |index| {
        const resolved = if (index == 0) options.target else options.targets[index - 1];
        const go = build_options.goTarget(resolved.result) orelse std.debug.panic(
            "targets: '{s}' has no Go platform name, so a Go binding cannot be built for it",
            .{resolved.result.zigTriple(b.allocator) catch @panic("OOM")},
        );
        if (backend == .purego and !build_options.puregoTargetSupported(resolved.result))
            std.debug.panic("targets: '{s}' is not a purego platform; `.link = .purego` supports macOS, Linux and Windows on amd64/arm64 only", .{resolved.result.zigTriple(b.allocator) catch @panic("OOM")});
        for (list.items) |existing| {
            if (existing.go_target.?.eql(go)) std.debug.panic("targets lists {s}/{s} more than once (`target` counts as the first entry)", .{ go.goos, go.goarch });
        }
        const subdirectory = b.fmt("{s}_{s}", .{ go.goos, go.goarch });
        var clones: steps.RetargetClones = .{};
        list.append(b.allocator, .{
            .resolved = resolved,
            .go_target = go,
            .constraint = b.fmt("{s},{s}", .{ go.goos, go.goarch }),
            .library_dir = installSubdirectory(b, install.library_dir, subdirectory),
            .cgo_library_dir = b.fmt("{s}/{s}", .{ install.cgo_library_dir, subdirectory }),
            .module = if (index == 0)
                options.module
            else
                steps.retargetModule(b, options.module, resolved, options.optimize, &clones, .native),
        }) catch @panic("OOM");
    }
    return list.items;
}

/// `dir/<name>` as an install directory. Every install directory resolves to a
/// path under the prefix, which is what `.custom` is relative to.
fn installSubdirectory(b: *std.Build, dir: std.Build.InstallDir, name: []const u8) std.Build.InstallDir {
    const base = relativeInstallPath(b, b.install_prefix, b.getInstallPath(dir, ""));
    if (std.mem.startsWith(u8, base, ".."))
        std.debug.panic("targets requires install.library_dir to live inside the install prefix, but it resolves to '{s}'", .{b.getInstallPath(dir, "")});
    return .{ .custom = if (base.len == 0 or std.mem.eql(u8, base, ".")) b.dupe(name) else b.fmt("{s}/{s}", .{ base, name }) };
}

/// Passes the run-time loading policy as delimited lists, matching the
/// generator's `--library-*` arguments.
fn addLibraryLoadingArgs(b: *std.Build, run: *std.Build.Step.Run, loading: LibraryLoading) void {
    if (loading.search_paths.len != 0)
        run.addArgs(&.{ "--library-search-paths", joinWith(b, loading.search_paths, ":") });
    if (loading.env_vars) |names| run.addArgs(&.{ "--library-env-vars", joinWith(b, names, ",") });
    if (loading.loader.isAutomatic()) run.addArg("--library-automatic");
    if (!loading.loader.exportsApi()) run.addArg("--library-internal-api");
}

fn joinWith(b: *std.Build, values: []const []const u8, separator: []const u8) []const u8 {
    return std.mem.join(b.allocator, separator, values) catch @panic("OOM");
}

/// Where the install step actually puts the native library.
///
/// Read both the configured directory and target-specific filename back from
/// the install step so `GoBindings` and `go-doctor` cannot drift from it.
fn installedLibraryPath(b: *std.Build, install: *std.Build.Step.InstallArtifact) []const u8 {
    // `dest_dir` is only null when installation was disabled, which zigo never does.
    return b.getInstallPath(install.dest_dir.?, install.dest_sub_path);
}

fn isRunnableOnHost(target: std.Target, host: std.Target) bool {
    return target.cpu.arch == host.cpu.arch and target.os.tag == host.os.tag and target.abi == host.abi;
}

fn resolveGoPackagePath(path: []const u8) []const u8 {
    if (std.mem.eql(u8, path, ".")) return path;
    build_options.validateRawPackagePath(path) catch |err| switch (err) {
        error.InvalidPath => @panic("go_package_path must be '.' or a non-empty relative slash-separated path"),
        error.InvalidComponent => @panic("go_package_path must not contain empty, '.' or '..' components"),
        error.InvalidCharacter => @panic("go_package_path components may contain only ASCII letters, digits, '_', '-' and '.'"),
    };
    return path;
}

/// Colocation is not a separate option: naming the public package path as the
/// raw package path is what colocates them.
fn resolveRawPackage(b: *std.Build, path: []const u8, go_package_path: []const u8, go_package: []const u8) ResolvedRawPackage {
    if (std.mem.eql(u8, path, go_package_path)) return .{ .path = go_package_path, .name = go_package, .colocated = true };
    if (std.mem.eql(u8, path, "."))
        @panic("raw_package may be '.' only when go_package_path is also '.' (colocated)");
    build_options.validateRawPackagePath(path) catch |err| switch (err) {
        error.InvalidPath => @panic("raw_package must be a non-empty relative slash-separated path"),
        error.InvalidComponent => @panic("raw_package must not contain empty, '.' or '..' components"),
        error.InvalidCharacter => @panic("raw_package components may contain only ASCII letters, digits, '_', '-' and '.'"),
    };
    const name = naming.snakeAlloc(b.allocator, std.fs.path.basename(path)) catch @panic("OOM");
    naming.validateGoPackageName(name) catch
        @panic("raw_package basename must normalize to a valid Go package name");
    return .{ .path = path, .name = name, .colocated = false };
}

fn sourcePath(b: *std.Build, directory: std.Build.LazyPath, child: []const u8) []const u8 {
    return switch (directory) {
        .src_path => |source| b.pathJoin(&.{ source.sub_path, child }),
        else => @panic("go_dir must be a source path"),
    };
}

fn cgoRelativePath(b: *std.Build, from: []const u8, to: []const u8) []const u8 {
    const relative = relativeInstallPath(b, from, to);
    return b.fmt("${{SRCDIR}}/{s}", .{relative});
}

fn relativeInstallPath(b: *std.Build, from: []const u8, to: []const u8) []const u8 {
    const relative = std.fs.path.relative(b.allocator, "", null, from, to) catch @panic("OOM");
    // `std.fs.path.relative` answers in the host separator, but this string is
    // baked into generated Go. Go tooling expects forward slashes on every
    // host, and the committed bytes must not depend on where generation ran.
    std.mem.replaceScalar(u8, relative, std.fs.path.sep_windows, std.fs.path.sep_posix);
    return relative;
}
