//! The emitter's options: everything the Go tree is rendered with. The
//! plugin contract sees only the `PluginOptions` view `view()` cuts from it,
//! so the link flags, library paths and the helper gate's bookkeeping stay the
//! emitter's own.
const std = @import("std");
const plugin = @import("plugin");
const targets = @import("targets");
const references = @import("references.zig");

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
    /// The output language this run generates for. The generator resolves it
    /// once and every context reads the one value. The emitters in this
    /// directory do not read it: they are Go's, which is what a plugin's `go`
    /// render slot records.
    target: targets.Target = targets.default,
    // The `go_*` fields below describe the Go module system specifically -- a
    // module path, a package name, a package directory, a package doc. A
    // second target does not want them renamed; it wants its own fields
    // beside them, because a crate name is different data rather than a
    // different spelling.
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
    link_mode: LinkMode = .static,
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
    /// Which added plugins run beyond the built-in ones, by name. Null runs
    /// every plugin the generator was built with, which is what a build
    /// wants: listing a plugin module is already the choice. Naming a subset
    /// is how one binary can hold several plugins and a golden case still pin
    /// exactly one. Not part of the plugin contract: a plugin never asks
    /// which of its neighbours run.
    plugins: ?[]const []const u8 = null,
    configurations: []const plugin.Configuration = &.{},
    /// The generated helpers the public package references, decided by
    /// rendering it (`references.referencedHelpersAlloc`). Null emits every
    /// gated helper, which only the discovery rendering itself relies on
    /// being absent.
    helpers: ?*const references.Referenced = null,
    file: ?plugin.FileInfo = null,
    /// What the plugins' `analyze` recorded; rendering reads it through the
    /// context's read-only view.
    facts: *const plugin.Facts = &.{},

    /// The part of these options a plugin may see.
    pub fn view(self: Options) plugin.PluginOptions {
        return .{
            .target = self.target,
            .go_module = self.go_module,
            .go_package = self.go_package,
            .go_package_path = self.go_package_path,
            .raw_package_path = self.raw_package_path,
            .raw_colocated = self.raw_colocated,
            .active_package = self.active_package,
            .configurations = self.configurations,
            .helpers = if (self.helpers) |set| set.helperSet() else null,
            .file = self.file,
        };
    }

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

test "the plugin view carries the helper gate and the package selection" {
    var referenced: references.Referenced = .{};
    defer referenced.deinit(std.testing.allocator);
    try referenced.add(std.testing.allocator, "zigoMust");
    const options: Options = .{ .go_module = "example.com/m", .active_package = "inner", .helpers = &referenced, .plugins = &.{"X"} };
    const view = options.view();
    try std.testing.expectEqualStrings("inner", view.active_package.?);
    try std.testing.expect(view.emitsHelper("zigoMust"));
    try std.testing.expect(!view.emitsHelper("zigoMustMatch"));
    try std.testing.expect((Options{ .go_module = "" }).view().emitsHelper("anything"));
    try std.testing.expect(options.runsPlugin("X") and !options.runsPlugin("Y"));
}
