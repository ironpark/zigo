//! The generator's plugin contract. A plugin is an ordinary Zig package that
//! compiles against this file alone: it names itself, owns typed function and type options, validates its own declarations, and adds Go code through hooks.
//!
//! Hooks are additive and Go-only. Nothing here reaches the Zig shim, the C
//! header or the raw package, so a plugin cannot move the ABI and works the
//! same on the cgo and purego backends.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const diagnostic = @import("diagnostic");
const naming = @import("naming");

/// Major versions are incompatible; minor versions add capabilities.
pub const ContractVersion = struct { major: u16, minor: u16 };
pub const contract_version: ContractVersion = .{ .major = 1, .minor = 0 };

/// Serialized build configuration; decoded as the registered plugin's Config.
pub const Configuration = struct { name: []const u8, json: []const u8 };

pub fn readConfig(comptime P: Plugin, allocator: std.mem.Allocator, configurations: []const Configuration) !P.Config {
    var json: []const u8 = "{}";
    for (configurations) |entry| {
        if (std.mem.eql(u8, entry.name, P.name)) {
            json = entry.json;
            break;
        }
    }
    return std.json.parseFromSliceLeaky(P.Config, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidPluginConfig,
    };
}

pub const site = @import("plugin/site.zig");

/// Runs before lowering. All allocations and diagnostics belong to the run arena.
pub const ValidateContext = struct {
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    configurations: []const Configuration = &.{},
    diagnostics: *std.ArrayList(diagnostic.Diagnostic),

    pub fn diagnose(self: ValidateContext, issue: diagnostic.Diagnostic) !void {
        try self.diagnostics.append(self.allocator, issue);
    }

    pub fn config(self: ValidateContext, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.configurations);
    }

    pub fn optionsOf(self: ValidateContext, comptime P: Plugin, comptime attachment: enum { function, type }, ext: ?semantic.Extensions) !?(if (attachment == .function) P.FunctionOptions else P.TypeOptions) {
        return readOptions(P, attachment, self.allocator, ext);
    }
};

/// The identifiers a rendering of the public package used. Selectors
/// (`x.Name`) are not identifiers of this package and are skipped. It lives
/// here rather than next to the scanner because `Options` carries it.
pub const Referenced = struct {
    names: std.StringHashMapUnmanaged(void) = .empty,

    pub fn contains(self: *const Referenced, name: []const u8) bool {
        return self.names.contains(name);
    }

    pub fn deinit(self: *Referenced, allocator: std.mem.Allocator) void {
        var keys = self.names.keyIterator();
        while (keys.next()) |key| allocator.free(key.*);
        self.names.deinit(allocator);
    }

    pub fn add(self: *Referenced, allocator: std.mem.Allocator, name: []const u8) !void {
        if (self.names.contains(name)) return;
        const owned = try allocator.dupe(u8, name);
        errdefer allocator.free(owned);
        try self.names.put(allocator, owned, {});
    }
};

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
    /// Which registered plugins run beyond the built-in ones, by name. Null
    /// runs every plugin the generator was built with, which is what a build
    /// wants: listing a plugin module is already the choice. Naming a subset
    /// is how one binary can hold several plugins and a golden case still pin
    /// exactly one.
    plugins: ?[]const []const u8 = null,
    configurations: []const Configuration = &.{},
    /// The generated helpers the public package references, decided by
    /// rendering it (`emit.references.referencedHelpersAlloc`). Null emits every
    /// gated helper, which only the discovery rendering itself relies on
    /// being absent.
    helpers: ?*const Referenced = null,

    /// Whether an added plugin of this name runs. Built-in features are not
    /// asked: they are the generator's own surface, not an opt-in.
    pub fn runsPlugin(self: Options, name: []const u8) bool {
        const selected = self.plugins orelse return true;
        for (selected) |entry| {
            if (std.mem.eql(u8, entry, name)) return true;
        }
        return false;
    }

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

/// One generated file: where it goes and what goes in it. Plugin files render
/// through the same public-file path as the built-in ones, so their imports
/// are derived from the body they wrote.
pub const Emitter = struct {
    /// Diagnostic label, filled with the plugin name by the generator.
    owner: []const u8 = "generator",
    pathAlloc: *const fn (std.mem.Allocator, abi.Program, Options) anyerror![]u8,
    render: *const fn (std.mem.Allocator, *std.Io.Writer, abi.Program, Options) anyerror!void,
};

/// Module-relative path for a file in the currently rendered public package.
/// Call from Emitter.pathAlloc; the caller owns the returned allocation.
pub fn publicFilePathAlloc(allocator: std.mem.Allocator, program: abi.Program, options: Options, filename: []const u8) ![]u8 {
    const directory = if (options.go_package_path.len != 0)
        try allocator.dupe(u8, options.go_package_path)
    else if (options.go_package.len != 0)
        try allocator.dupe(u8, options.go_package)
    else
        try naming.snakeAlloc(allocator, program.package);
    defer allocator.free(directory);
    if (std.mem.eql(u8, directory, ".")) return allocator.dupe(u8, filename);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory, filename });
}

const publicFilePathAllocImpl = publicFilePathAlloc;

pub const ResultOptions = struct {
    /// Drop only the public trailing error; optional presence flags remain.
    omit_error: bool = false,
};

/// A non-standard Go import a hook may write. It is added to a file only when
/// the rendered body actually spells the qualifier, the same rule the built-in
/// imports follow.
pub const Import = struct {
    /// The name the body writes before the dot.
    qualifier: []const u8,
    /// The Go import path.
    path: []const u8,
};

/// The public-package writers a hook needs but cannot reimplement: they answer
/// for package qualification and for the exact spelling a generated signature
/// has. Passed as a table so a plugin compiled as its own module reaches them
/// without importing generator internals.
pub const Writers = struct {
    /// The type name as this package spells it, qualified when the type lives
    /// in another generated package.
    writeTypeName: *const fn (Context, *std.Io.Writer, []const u8) anyerror!void,
    /// The Go spelling of a semantic type node.
    writeGoType: *const fn (Context, *std.Io.Writer, semantic.TypeNode) anyerror!void,
    /// The receiver name a method of this type is written with.
    receiverNameAlloc: *const fn (Context, std.mem.Allocator, []const u8) anyerror![]u8,
    /// The parameter list and result of a public function, parentheses
    /// included, exactly as the method being hooked spells them.
    writeSignature: *const fn (Context, *std.Io.Writer, abi.AbiFn) anyerror!void,
    writeParameters: *const fn (Context, *std.Io.Writer, abi.AbiFn) anyerror!void,
    writeResultType: *const fn (Context, *std.Io.Writer, abi.AbiFn, ResultOptions) anyerror!usize,
    writeCallArguments: *const fn (Context, *std.Io.Writer, abi.AbiFn) anyerror!void,
};

/// What a `method_hook` is adjacent to: the method the generator just wrote.
/// The names are the ones the method itself used, so a wrapper that calls it
/// can never spell the call differently.
pub const Method = struct {
    /// The exported Go method name.
    go_name: []const u8,
    /// The Go receiver type, absent for a free function.
    receiver: ?[]const u8 = null,
    /// The receiver variable name, absent for a free function.
    receiver_name: ?[]const u8 = null,
    /// The Go parameter names, indexed by semantic parameter.
    param_names: [][]u8,
    /// The handle type a constructor hands back, when it is one.
    owned_type: ?[]const u8 = null,
    /// Whether the method's Go signature carries an `error`.
    needs_check: bool = false,
};

/// What a hook is given besides its writer: the lowered program, the emitter
/// options in force, the writers table, and -- for `method_hook` -- the method
/// the hook is being written after.
pub const Context = struct {
    allocator: std.mem.Allocator,
    program: abi.Program,
    options: Options,
    writers: *const Writers,
    /// Set for `method_hook`, null for `type_hook` and for `validate`.
    method: ?Method = null,

    pub fn config(self: Context, comptime P: Plugin) !P.Config {
        return readConfig(P, self.allocator, self.options.configurations);
    }

    pub fn writeTypeName(self: Context, writer: *std.Io.Writer, name: []const u8) !void {
        return self.writers.writeTypeName(self, writer, name);
    }

    pub fn writeGoType(self: Context, writer: *std.Io.Writer, node: semantic.TypeNode) !void {
        return self.writers.writeGoType(self, writer, node);
    }

    pub fn receiverNameAlloc(self: Context, allocator: std.mem.Allocator, type_name: []const u8) ![]u8 {
        return self.writers.receiverNameAlloc(self, allocator, type_name);
    }

    pub fn writeSignature(self: Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        return self.writers.writeSignature(self, writer, function);
    }

    /// Public parameter list including parentheses. Requires method context.
    pub fn writeParameters(self: Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        const write = self.writers.writeParameters;
        return write(self, writer, function);
    }

    /// Public results including their leading space and any tuple parentheses.
    /// Returns the number of emitted results, allowing wrappers to choose a
    /// forwarding helper without parsing Go source. Zero results write nothing.
    pub fn writeResultType(self: Context, writer: *std.Io.Writer, function: abi.AbiFn, options: ResultOptions) !usize {
        const write = self.writers.writeResultType;
        return write(self, writer, function, options);
    }

    /// Arguments in public parameter order, without parentheses.
    pub fn writeCallArguments(self: Context, writer: *std.Io.Writer, function: abi.AbiFn) !void {
        const write = self.writers.writeCallArguments;
        return write(self, writer, function);
    }

    pub fn publicFilePathAlloc(self: Context, filename: []const u8) ![]u8 {
        return publicFilePathAllocImpl(self.allocator, self.program, self.options, filename);
    }

    /// `P`'s options on the function being written, or null when the
    /// declaration did not extend `P`.
    pub fn functionOptions(self: Context, comptime P: anytype, function: semantic.SemanticFn) !?P.FunctionOptions {
        return readOptions(P, .function, self.allocator, function.ext);
    }

    /// `P`'s options on a type declaration, or null when it did not extend `P`.
    pub fn typeOptions(self: Context, comptime P: anytype, declaration: semantic.TypeDecl) !?P.TypeOptions {
        return readOptions(P, .type, self.allocator, declaration.ext);
    }
};

/// The diagnostic code a plugin reports unreadable options under: its name
/// followed by `001`. Plugin codes never borrow the `ZIGO` prefix, so a
/// diagnostic always says which plugin objected.
pub fn optionsCode(comptime P: anytype) []const u8 {
    return P.name ++ "001";
}

/// `P`'s options on a declaration, or null when the declaration did not
/// extend `P`. The result is allocated from `allocator` and never freed
/// individually: the generator backs it with the arena that owns the run.
pub fn readOptions(comptime P: anytype, comptime attachment: enum { function, type }, allocator: std.mem.Allocator, ext: ?semantic.Extensions) !?(if (attachment == .function) P.FunctionOptions else P.TypeOptions) {
    const attached = (ext orelse return null).get(P.name) orelse return null;
    return std.json.parseFromValueLeaky(if (attachment == .function) P.FunctionOptions else P.TypeOptions, allocator, attached, .{}) catch return error.InvalidPluginOptions;
}

/// A generator plugin. Every field but `name` is optional, so a plugin that
/// only adds a method next to an existing one is four lines long.
pub const Target = enum { function, handle, value, enumeration, tagged_union };

pub fn typeTarget(kind: semantic.TypeKind) ?Target {
    return switch (kind) {
        .@"opaque" => .handle,
        .value_struct => .value,
        .@"enum" => .enumeration,
        .tagged_union => .tagged_union,
        .callback, .materialized, .error_set => null,
    };
}

pub const Plugin = struct {
    min_contract: ContractVersion = contract_version,
    Config: type = struct {},
    /// Ordering only: absent plugins in after are ignored.
    after: []const []const u8 = &.{},
    /// Required registered and enabled plugins; also run before this plugin.
    requires: []const []const u8 = &.{},
    /// The plugin's identity: the `ext` key its options travel under, the
    /// prefix of its diagnostic codes, and the suffix of the files it writes.
    /// Spelled in upper case, since the diagnostic codes are.
    name: []const u8,
    /// The declaration options this plugin reads, as a `std.json`-serializable
    /// struct. A plugin that takes none leaves it at the empty struct.
    FunctionOptions: type = struct {},
    TypeOptions: type = struct {},
    targets: []const Target = &.{ .function, .handle, .value, .enumeration, .tagged_union },
    /// Runs after core and option validation; report any number of diagnostics.
    validate: ?*const fn (ValidateContext) anyerror!void = null,
    /// Written after each public method, into the file that owns it.
    method_hook: ?*const fn (Context, *std.Io.Writer, abi.AbiFn) anyerror!void = null,
    /// Written after each handle, value struct and enum, into the file that
    /// owns it.
    type_hook: ?*const fn (Context, *std.Io.Writer, semantic.TypeDecl) anyerror!void = null,
    /// Whole public files this plugin adds. A file whose body comes out empty
    /// is dropped, so an emitter that has nothing to say costs nothing.
    files: []const Emitter = &.{},

    /// Non-standard imports the hooks may write, added where they are used.
    imports: []const Import = &.{},

    pub fn supports(comptime self: Plugin, target: ?Target) bool {
        const requested = target orelse return false;
        inline for (self.targets) |candidate| if (candidate == requested) return true;
        return false;
    }
};

/// Stable topological order. Registration errors are compile-time errors.
pub fn ordered(comptime entries: []const Plugin) [entries.len]Plugin {
    comptime {
        @setEvalBranchQuota(100000);
        for (entries, 0..) |entry, i| {
            if (entry.min_contract.major != contract_version.major or entry.min_contract.minor > contract_version.minor)
                @compileError("incompatible plugin contract: " ++ entry.name);
            for (entries[0..i]) |previous| if (std.mem.eql(u8, previous.name, entry.name))
                @compileError("duplicate plugin: " ++ entry.name);
            for (entry.requires) |name| {
                var found = false;
                for (entries) |candidate| {
                    if (std.mem.eql(u8, candidate.name, name)) found = true;
                }
                if (!found) @compileError("missing plugin dependency: " ++ entry.name ++ " requires " ++ name);
            }
        }
        var result: [entries.len]Plugin = undefined;
        var used = [_]bool{false} ** entries.len;
        for (0..entries.len) |slot| {
            var found = false;
            for (entries, 0..) |entry, index| {
                if (used[index]) continue;
                var ready = true;
                for (entry.after ++ entry.requires) |dependency| {
                    for (entries, 0..) |candidate, dependency_index| {
                        if (std.mem.eql(u8, candidate.name, dependency) and !used[dependency_index]) ready = false;
                    }
                }
                if (!ready) continue;
                result[slot] = entry;
                used[index] = true;
                found = true;
                break;
            }
            if (!found) @compileError("cycle in plugin ordering");
        }
        return result;
    }
}

test "plugin ordering is stable and respects dependencies" {
    const entries = ordered(&.{ .{ .name = "C", .requires = &.{"B"} }, .{ .name = "A" }, .{ .name = "B", .after = &.{ "A", "ABSENT" } } });
    try std.testing.expectEqualStrings("A", entries[0].name);
    try std.testing.expectEqualStrings("B", entries[1].name);
    try std.testing.expectEqualStrings("C", entries[2].name);
}

test "plugin config decodes defaults and rejects unknown fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const p: Plugin = .{ .name = "CONFIG", .Config = struct { enabled: bool = false } };
    try std.testing.expect(!(try readConfig(p, arena.allocator(), &.{})).enabled);
    try std.testing.expect((try readConfig(p, arena.allocator(), &.{.{ .name = "CONFIG", .json = "{\"enabled\":true}" }})).enabled);
    try std.testing.expectError(error.InvalidPluginConfig, readConfig(p, arena.allocator(), &.{.{ .name = "CONFIG", .json = "{\"typo\":true}" }}));
}
