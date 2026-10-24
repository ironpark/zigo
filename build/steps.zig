//! The build steps `addGoBindings` wires: link input collection, pkg-config
//! resolution, host reflection clones and the publish steps. Zig 0.17 has no
//! custom steps, so the work that needs real paths runs as `zigo-gen`
//! subcommands in the build runner.
const std = @import("std");

pub const volatile_cgo_link_file = "zigo_link_inputs_gen.go";

/// One install directory as a lazy path. Zig 0.17 resolves the install
/// prefix only in the build runner, so everything that has to spell an
/// installed location -- the cgo line, the purego search path, the doctor's
/// library -- receives one of these and lets the generator do the spelling.
pub fn installDirPath(b: *std.Build, dir: std.Build.InstallDir, sub_path: []const u8) std.Build.LazyPath {
    return switch (dir) {
        .prefix => .{ .relative = .{ .base = .install_prefix, .sub_path = sub_path } },
        .lib => .{ .relative = .{ .base = .install_lib, .sub_path = sub_path } },
        .bin => .{ .relative = .{ .base = .install_bin, .sub_path = sub_path } },
        .header => .{ .relative = .{ .base = .install_include, .sub_path = sub_path } },
        .custom => |custom| .{ .relative = .{
            .base = .install_prefix,
            .sub_path = if (sub_path.len == 0) custom else b.pathJoin(&.{ custom, sub_path }),
        } },
    };
}

/// A directory argument the generator sees as an absolute path. Two such
/// paths always share a root, so the relative path between them is the one
/// the committed files are written with.
pub fn addAbsoluteDirectoryArg(run: *std.Build.Step.Run, path: std.Build.LazyPath) void {
    run.addDirectoryArg2(path, .{ .make_absolute = true });
}

/// The link line of one native target.
pub const TargetFlags = struct {
    /// Build constraint spelled before `LDFLAGS`, such as `darwin,arm64`.
    /// Empty writes the unqualified line a single-target tree links with.
    constraint: []const u8,
    /// Where this target's archives install.
    library_dir: std.Build.InstallDir,
    /// `lib<name>.a` file names, the binding archive first.
    archives: []const []const u8,
    /// The install steps that put the static inputs in place.
    archive_installs: []const *std.Build.Step,
};

pub const CgoLinkFlagsOptions = struct {
    /// Destination relative to the package root.
    output_path: []const u8,
    package: []const u8,
    /// The directory the file lives in.
    source_dir: std.Build.LazyPath,
    targets: []const TargetFlags,
    extra_ldflags: []const u8,
    system_ldflags: []const u8,
    link_inputs: *const LinkInputCollector,
};

/// Publishes the cgo directive that names static archive inputs. It lives
/// outside the checked generator tree: the archives exist only after a build,
/// and the directive is only present when a module has such inputs, so a
/// checkout that has not built yet has nothing stale to compare against.
pub fn addCgoLinkFlags(b: *std.Build, generator: *std.Build.Step.Compile, options: CgoLinkFlagsOptions) *std.Build.Step.UpdateSourceFiles {
    const run = b.addRunArtifact(generator);
    run.addArgs(&.{ "cgo-link-flags", "--output" });
    const output = run.addOutputFileArg(volatile_cgo_link_file);
    run.addArgs(&.{ "--package", options.package, "--source-dir" });
    addAbsoluteDirectoryArg(run, options.source_dir);
    for (options.targets) |target| {
        run.addArgs(&.{ "--target", target.constraint, "--library-dir" });
        addAbsoluteDirectoryArg(run, installDirPath(b, target.library_dir, ""));
        for (target.archives) |archive| run.addArgs(&.{ "--archive", archive });
    }
    run.addArgs(&.{ "--extra-ldflags", options.extra_ldflags, "--system-ldflags", options.system_ldflags });
    addSystemLibraryDirArgs(run, options.link_inputs);
    const update = b.addUpdateSourceFiles();
    update.addCopyFileToSource(output, options.output_path);
    return update;
}

/// Copies the generated tree into the package's source directory and removes
/// the generated files a previous run left behind; see `src/gen/publish.zig`.
/// It writes into the source tree, so it runs every time.
pub fn addPublishGenerated(
    b: *std.Build,
    generator: *std.Build.Step.Compile,
    generated: std.Build.LazyPath,
    source_dir: std.Build.LazyPath,
) *std.Build.Step.Run {
    const run = b.addRunArtifact(generator);
    run.setName("publish generated bindings");
    run.has_side_effects = true;
    run.addArgs(&.{ "publish", "--generated" });
    run.addDirectoryArg(generated);
    run.addArg("--source");
    run.addDirectoryArg(source_dir);
    return run;
}

pub const StaticLinkInputs = struct {
    paths: []const std.Build.LazyPath,
    /// The `<name>` each archive installs as, `lib<name>.a`.
    names: []const []const u8,

    pub const empty: StaticLinkInputs = .{ .paths = &.{}, .names = &.{} };
};

pub const HostReflectionClones = RetargetClones;

/// Clones made while retargeting one module graph. One map per target keeps
/// a module shared by two imports as one clone for that target.
pub const RetargetClones = struct {
    modules: std.AutoHashMapUnmanaged(*std.Build.Module, *std.Build.Module) = .empty,
    libraries: std.AutoHashMapUnmanaged(*std.Build.Step.Compile, *std.Build.Step.Compile) = .empty,
};

/// What a retargeted module graph keeps of the original's native inputs.
pub const RetargetPolicy = enum {
    /// Reflection on the build host. Static library steps are rebuilt because
    /// their headers and libc/libc++ settings can be required to compile the
    /// caller's C/C++ sources; target archives (`.static_path`), dynamic
    /// libraries, assembly and resource files are left out because reflection
    /// never calls them.
    host_reflection,
    /// A native library for another listed target. Every input is rebuilt for
    /// that target. A prebuilt archive cannot be, so it is a configure error.
    native,
};

/// The caller's module rebuilt for the host so reflection can run it. Imports
/// are cloned the same way; system libraries, C sources, include paths and
/// macros carry over. See `RetargetPolicy.host_reflection`.
pub fn hostReflectionModule(
    b: *std.Build,
    module: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
    clones: *RetargetClones,
) *std.Build.Module {
    return retargetModule(b, module, b.graph.host, optimize, clones, .host_reflection);
}

/// The module graph rooted at `module`, rebuilt for `target`.
pub fn retargetModule(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    clones: *RetargetClones,
    policy: RetargetPolicy,
) *std.Build.Module {
    if (clones.modules.get(module)) |clone| return clone;
    const clone = switch (policy) {
        .host_reflection => b.createModule(.{
            .root_source_file = module.root_source_file,
            .target = target,
            .optimize = module.optimize orelse optimize,
            .link_libc = module.link_libc,
            .link_libcpp = module.link_libcpp,
            .single_threaded = module.single_threaded,
            .sanitize_c = module.sanitize_c,
            .no_builtin = module.no_builtin,
        }),
        // A native clone is the caller's own library for another platform, so
        // every code generation setting follows it.
        .native => b.createModule(.{
            .root_source_file = module.root_source_file,
            .target = target,
            .optimize = module.optimize orelse optimize,
            .link_libc = module.link_libc,
            .link_libcpp = module.link_libcpp,
            .single_threaded = module.single_threaded,
            .strip = module.strip,
            .unwind_tables = module.unwind_tables,
            .dwarf_format = module.dwarf_format,
            .code_model = module.code_model,
            .stack_protector = module.stack_protector,
            .stack_check = module.stack_check,
            .sanitize_c = module.sanitize_c,
            .sanitize_thread = module.sanitize_thread,
            .fuzz = module.fuzz,
            .valgrind = module.valgrind,
            .pic = module.pic,
            .red_zone = module.red_zone,
            .omit_frame_pointer = module.omit_frame_pointer,
            .error_tracing = module.error_tracing,
            .no_builtin = module.no_builtin,
        }),
    };
    clones.modules.put(b.allocator, module, clone) catch @panic("OOM");
    for (module.import_table.keys(), module.import_table.values()) |name, import| {
        clone.addImport(name, retargetModule(b, import, target, optimize, clones, policy));
    }
    clone.c_macros.appendSlice(b.allocator, module.c_macros.items) catch @panic("OOM");
    clone.include_dirs.appendSlice(b.allocator, module.include_dirs.items) catch @panic("OOM");
    clone.lib_paths.appendSlice(b.allocator, module.lib_paths.items) catch @panic("OOM");
    if (target.result.os.tag.isDarwin()) {
        for (module.frameworks.keys(), module.frameworks.values()) |name, framework| {
            clone.frameworks.put(b.allocator, name, framework) catch @panic("OOM");
        }
    }
    for (module.link_objects.items) |object| switch (object) {
        .system_lib, .c_source_file, .c_source_files => clone.link_objects.append(b.allocator, object) catch @panic("OOM"),
        .other_step => |compile| switch (policy) {
            .host_reflection => if (compile.isStaticLibrary()) {
                clone.linkLibrary(retargetLibrary(b, compile, target, optimize, clones, policy));
            },
            .native => if (compile.isStaticLibrary() or compile.isDynamicLibrary()) {
                clone.linkLibrary(retargetLibrary(b, compile, target, optimize, clones, policy));
            } else if (compile.kind == .obj) {
                clone.addObject(retargetLibrary(b, compile, target, optimize, clones, policy));
            } else {
                std.debug.panic("targets: cannot rebuild linked artifact '{s}' ({s}) for another target", .{ compile.name, @tagName(compile.kind) });
            },
        },
        .static_path => |path| switch (policy) {
            .host_reflection => {},
            .native => std.debug.panic(
                "targets: prebuilt archive '{s}' cannot be rebuilt for another target; link it as a Compile step, or call addGoBindings once per target",
                .{path.getDisplayName()},
            ),
        },
        .assembly_file, .win32_resource_file => switch (policy) {
            .host_reflection => {},
            .native => clone.link_objects.append(b.allocator, object) catch @panic("OOM"),
        },
    };
    return clone;
}

/// A library or object step rebuilt for `target`, with the same installed
/// headers. A host reflection clone is always a static archive and carries a
/// distinct name; a native clone keeps the original's kind and name so its
/// install spelling (`lib<name>.a`) does not change across targets.
fn retargetLibrary(
    b: *std.Build,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    clones: *RetargetClones,
    policy: RetargetPolicy,
) *std.Build.Step.Compile {
    if (clones.libraries.get(library)) |clone| return clone;
    const root_module = retargetModule(b, library.root_module, target, optimize, clones, policy);
    const clone = switch (policy) {
        .host_reflection => b.addLibrary(.{
            .name = b.fmt("{s}_reflection_host", .{library.name}),
            .linkage = .static,
            .root_module = root_module,
        }),
        .native => if (library.kind == .obj)
            b.addObject(.{ .name = library.name, .root_module = root_module })
        else
            b.addLibrary(.{
                .name = library.name,
                .linkage = if (library.isDynamicLibrary()) .dynamic else .static,
                .root_module = root_module,
            }),
    };
    clones.libraries.put(b.allocator, library, clone) catch @panic("OOM");
    for (library.installed_headers.items) |installation| switch (installation) {
        .file => |file| clone.installHeader(file.source, file.dest_rel_path),
        .directory => |directory| clone.installHeadersDirectory(
            directory.source,
            directory.dest_rel_path,
            directory.options,
        ),
    };
    return clone;
}

/// Static libraries that Zig records as inputs are not folded into another
/// static archive. cgo must therefore name each input again when it links the
/// final Go executable.
///
/// Inputs are gathered from the module and everything it imports, in
/// dependency-first order: a library attached to an imported module (ghostty
/// hangs simdutf and highway on `ghostty-vt`, and the binding imports that)
/// is just as much a link input as one attached to the module itself.
const SystemLibraryInput = struct {
    library: std.Build.Module.SystemLib,
    module: *std.Build.Module,
};

const FrameworkInput = struct {
    name: []const u8,
    options: std.Build.Module.LinkFrameworkOptions,
};

/// All native inputs carried by a module graph, in dependency-first order.
/// Each emitted spelling is retained only at its first occurrence so diamond
/// imports and repeated declarations cannot duplicate a cgo directive.
pub const LinkInputCollector = struct {
    seen_modules: std.AutoHashMapUnmanaged(*std.Build.Module, void) = .empty,
    static_paths: std.ArrayList(std.Build.LazyPath) = .empty,
    static_names: std.ArrayList([]const u8) = .empty,
    static_compiles: std.ArrayList(*std.Build.Step.Compile) = .empty,
    library_paths: std.ArrayList(std.Build.LazyPath) = .empty,
    system_libraries: std.ArrayList(SystemLibraryInput) = .empty,
    frameworks: std.ArrayList(FrameworkInput) = .empty,

    pub fn collect(self: *LinkInputCollector, b: *std.Build, module: *std.Build.Module) void {
        if (self.seen_modules.contains(module)) return;
        self.seen_modules.put(b.allocator, module, {}) catch @panic("OOM");
        for (module.import_table.values()) |import| self.collect(b, import);

        for (module.lib_paths.items) |path| {
            for (self.library_paths.items) |existing| {
                if (lazyPathEql(existing, path)) break;
            } else {
                self.library_paths.append(b.allocator, path) catch @panic("OOM");
            }
        }

        for (module.frameworks.keys(), module.frameworks.values()) |name, options| {
            for (self.frameworks.items) |existing| {
                if (std.mem.eql(u8, existing.name, name)) break;
            } else {
                self.frameworks.append(b.allocator, .{ .name = name, .options = options }) catch @panic("OOM");
            }
        }

        for (module.link_objects.items) |object| {
            switch (object) {
                .system_lib => |library| {
                    for (self.system_libraries.items) |existing| {
                        if (std.mem.eql(u8, existing.library.name, library.name)) break;
                    } else {
                        self.system_libraries.append(b.allocator, .{ .library = library, .module = module }) catch @panic("OOM");
                    }
                    continue;
                },
                else => {},
            }
            const path: std.Build.LazyPath, const name: []const u8 = switch (object) {
                .other_step => |compile| blk: {
                    if (!compile.isStaticLibrary()) continue;
                    // One library reached through two imports is one input.
                    if (std.mem.indexOfScalar(*std.Build.Step.Compile, self.static_compiles.items, compile) != null) continue;
                    self.static_compiles.append(b.allocator, compile) catch @panic("OOM");
                    break :blk .{ compile.getEmittedBin(), compile.name };
                },
                .static_path => |candidate| .{ candidate, archiveStem(std.fs.path.basename(candidate.getDisplayName())) },
                else => continue,
            };
            const display = path.getDisplayName();
            for (self.static_names.items, self.static_paths.items) |existing_name, existing_path| {
                if (!std.mem.eql(u8, existing_name, name)) continue;
                if (std.mem.eql(u8, existing_path.getDisplayName(), display)) break;
                @panic(b.fmt("two static link inputs would both install as lib{s}.a", .{name}));
            } else {
                self.static_paths.append(b.allocator, path) catch @panic("OOM");
                self.static_names.append(b.allocator, name) catch @panic("OOM");
            }
        }
    }

    pub fn staticLibraryInputs(self: *const LinkInputCollector) StaticLinkInputs {
        return .{ .paths = self.static_paths.items, .names = self.static_names.items };
    }
};

/// `libfoo.a`, `foo.lib` and `foo.a` all install as `libfoo.a`.
fn archiveStem(file_name: []const u8) []const u8 {
    const stem = std.fs.path.stem(file_name);
    if (std.mem.startsWith(u8, stem, "lib") and stem.len > 3) return stem[3..];
    return stem;
}

/// `-l` flags for the system libraries cgo has to name directly. Only
/// `.force` libraries move to the pkg-config line: `.yes` means "try
/// pkg-config, otherwise `-lfoo`", and a `#cgo pkg-config:` entry has no such
/// fallback. The module's search paths become `-L` flags in the generator,
/// which is the first place they are real paths; see `addSystemLibraryDirArgs`.
pub fn systemLibraryFlags(b: *std.Build, inputs: *const LinkInputCollector) []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    for (inputs.system_libraries.items) |input| {
        if (input.library.use_pkg_config == .force) continue;
        flags.append(b.allocator, b.fmt("-l{s}", .{input.library.name})) catch @panic("OOM");
    }
    return joinFlags(b, flags.items);
}

/// A `--system-library-dir` for every search path on the module graph, in
/// collection order. The generator puts each one as `-L` ahead of the
/// `--system-ldflags` libraries.
pub fn addSystemLibraryDirArgs(run: *std.Build.Step.Run, inputs: *const LinkInputCollector) void {
    for (inputs.library_paths.items) |path| {
        run.addArg("--system-library-dir");
        addAbsoluteDirectoryArg(run, path);
    }
}

/// Whether two lazy paths name the same location, as far as the configure
/// phase can tell without resolving them.
fn lazyPathEql(a: std.Build.LazyPath, b: std.Build.LazyPath) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .src_path => |left| left.owner == b.src_path.owner and std.mem.eql(u8, left.sub_path, b.src_path.sub_path),
        .generated => |left| left.index == b.generated.index and left.up == b.generated.up and std.mem.eql(u8, left.sub_path, b.generated.sub_path),
        .cwd_relative => |left| std.mem.eql(u8, left, b.cwd_relative),
        .dependency => |left| left.dependency == b.dependency.dependency and std.mem.eql(u8, left.sub_path, b.dependency.sub_path),
        .relative => |left| left.eql(b.relative),
    };
}

pub fn frameworkFlags(b: *std.Build, inputs: *const LinkInputCollector) []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    for (inputs.frameworks.items) |framework| {
        flags.append(b.allocator, if (framework.options.weak) "-weak_framework" else "-framework") catch @panic("OOM");
        flags.append(b.allocator, framework.name) catch @panic("OOM");
    }
    return joinFlags(b, flags.items);
}

/// The `#cgo pkg-config:` names for every library a module forces through
/// pkg-config, resolved by `zigo-gen pkg-config` in the build runner, or null
/// when no module forces one. It runs every time: what pkg-config answers
/// depends on the machine, not on anything the build cache sees.
pub fn addResolvePkgConfig(
    b: *std.Build,
    generator: *std.Build.Step.Compile,
    artifact_package: []const u8,
    system_libraries: []const SystemLibraryInput,
) ?*std.Build.Step.Run {
    var any = false;
    for (system_libraries) |input| any = any or input.library.use_pkg_config == .force;
    if (!any) return null;
    const run = b.addRunArtifact(generator);
    run.setName(b.fmt("resolve pkg-config libraries for {s}", .{artifact_package}));
    run.has_side_effects = true;
    run.addArg("pkg-config");
    for (system_libraries) |input| {
        if (input.library.use_pkg_config != .force) continue;
        run.addArgs(&.{ "--library", input.library.name, moduleDisplayName(input.module) });
    }
    return run;
}

fn moduleDisplayName(module: *std.Build.Module) []const u8 {
    return if (module.root_source_file) |root| root.getDisplayName() else "<module without a source root>";
}

pub fn joinFlags(b: *std.Build, flags: []const []const u8) []const u8 {
    return std.mem.join(b.allocator, " ", flags) catch @panic("OOM");
}
