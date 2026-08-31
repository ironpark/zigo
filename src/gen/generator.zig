const std = @import("std");
const emit = @import("emit.zig");
const abi = @import("abi");
const errors_lock = @import("errors_lock");
const lower = @import("lower.zig");
const semantic = @import("semantic");
const validate = @import("validate.zig");

pub const Options = struct {
    package: []const u8,
    prefix: []const u8,
    go_module: []const u8,
    cflags_override: ?[]const u8 = null,
    ldflags_override: ?[]const u8 = null,
    system_ldflags: []const u8 = "",
    framework_ldflags: []const u8 = "",
    include_dir: []const u8 = "${SRCDIR}/../../../zig-out/include",
    library_dir: []const u8 = "${SRCDIR}/../../../zig-out/lib",
    raw_package_path: []const u8 = "internal/raw",
    raw_package_name: []const u8 = "raw",
    raw_colocated: bool = false,
    auto_cleanup: bool = false,
    go_package: []const u8 = "",
    errors_lock_bytes: ?[]const u8 = null,
    backend: emit.Options.Backend = .cgo,
    link_mode: emit.Options.LinkMode = .static,
    library_stem: []const u8 = "",
    library_search_paths: []const u8 = "",
    library_env_vars: ?[]const u8 = null,
    library_automatic: bool = false,
    library_exported_api: bool = true,
};

const PreparedFile = struct {
    path: []const u8,
    contents: []const u8,
};

pub fn generate(allocator: std.mem.Allocator, io: std.Io, semantic_bytes: []const u8, output: std.Io.Dir, options: Options) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const scratch_allocator = scratch.allocator();

    var parsed = try semantic.Semantic.parse(scratch_allocator, semantic_bytes);
    defer parsed.deinit();
    try validate.semanticDocument(scratch_allocator, parsed.value);
    var baseline: ?errors_lock.ErrorsLock = if (options.errors_lock_bytes) |bytes| try errors_lock.ErrorsLock.parse(scratch_allocator, bytes) else null;
    defer if (baseline) |*value| value.deinit(scratch_allocator);
    var lock: errors_lock.ErrorsLock = if (options.errors_lock_bytes) |bytes| try errors_lock.ErrorsLock.parse(scratch_allocator, bytes) else .{};
    defer lock.deinit(scratch_allocator);
    var error_names: std.ArrayList([]const u8) = .empty;
    defer error_names.deinit(scratch_allocator);
    for (parsed.value.functions) |function| switch (function.@"return") {
        .error_union => |value| for (value.error_set) |name| {
            var exists = false;
            for (error_names.items) |existing| {
                if (std.mem.eql(u8, existing, name)) exists = true;
            }
            if (!exists) try error_names.append(scratch_allocator, name);
        },
        else => {},
    };
    try lock.assign(scratch_allocator, error_names.items);
    if (baseline) |value| try lock.validateAgainst(value);
    const abi_codes = try scratch_allocator.alloc(abi.ErrorCode, lock.codes.items.len);
    for (lock.codes.items, 0..) |entry, index| abi_codes[index] = .{ .code = entry.code, .name = entry.name };
    std.mem.sort(abi.ErrorCode, abi_codes, {}, struct {
        fn lessThan(_: void, lhs: abi.ErrorCode, rhs: abi.ErrorCode) bool {
            return lhs.code < rhs.code;
        }
    }.lessThan);
    const program = try lower.semanticDocumentForBackend(scratch_allocator, parsed.value, options.package, options.prefix, abi_codes, switch (options.backend) {
        .cgo => .cgo,
        .purego => .purego,
    });
    const emitter_options: emit.Options = .{
        .go_module = options.go_module,
        .cflags_override = options.cflags_override,
        .ldflags_override = options.ldflags_override,
        .system_ldflags = options.system_ldflags,
        .framework_ldflags = options.framework_ldflags,
        .include_dir = options.include_dir,
        .library_dir = options.library_dir,
        .raw_package_path = options.raw_package_path,
        .raw_package_name = options.raw_package_name,
        .raw_colocated = options.raw_colocated,
        .auto_cleanup = options.auto_cleanup,
        .go_package = options.go_package,
        .backend = options.backend,
        .link_mode = options.link_mode,
        .library_stem = options.library_stem,
        .library_search_paths = options.library_search_paths,
        .library_env_vars = options.library_env_vars,
        .library_automatic = options.library_automatic,
        .library_exported_api = options.library_exported_api,
    };
    var prepared: std.ArrayList(PreparedFile) = .empty;
    defer prepared.deinit(scratch_allocator);
    for (emit.all) |emitter| {
        const relative_path = try emitter.pathAlloc(scratch_allocator, program, emitter_options);
        var rendered: std.Io.Writer.Allocating = .init(scratch_allocator);
        defer rendered.deinit();
        try emitter.render(scratch_allocator, &rendered.writer, program, emitter_options);
        const contents = try rendered.toOwnedSlice();
        try prepared.append(scratch_allocator, .{
            .path = relative_path,
            .contents = if (std.mem.endsWith(u8, relative_path, ".go")) blk: {
                const body = std.mem.trimEnd(u8, contents, "\n");
                break :blk try std.fmt.allocPrint(scratch_allocator, "{s}\n", .{body});
            } else contents,
        });
    }
    const serialized_lock = try lock.serialize(scratch_allocator);
    try prepared.append(scratch_allocator, .{ .path = "errors.lock.json", .contents = serialized_lock });

    // Do not mutate the output tree until parsing, validation, lowering, every
    // emitter, and lock serialization have completed successfully. The commit
    // loop deliberately performs no work with the caller-provided allocator.
    for (prepared.items) |file| {
        // A file the emitter had nothing to put in would reach the user as a
        // package clause and no declarations, indistinguishable from a failed
        // generation. Every path here belongs to this run, so an earlier run's
        // copy is removed rather than left for `zigo check` to call obsolete.
        if (declaresNothing(file.path, file.contents)) {
            output.deleteFile(io, file.path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
            continue;
        }
        if (std.fs.path.dirname(file.path)) |directory| try output.createDirPath(io, directory);
        try output.writeFile(io, .{ .sub_path = file.path, .data = file.contents });
    }
}

/// True for a Go file that got no further than its own prelude. Every emitter
/// writes the marker and the `package` clause before deciding it has nothing to
/// declare, so this is the shape that decision leaves behind.
fn declaresNothing(path: []const u8, contents: []const u8) bool {
    if (!std.mem.endsWith(u8, path, ".go")) return false;
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, contents, "\n"), '\n');
    if (!std.mem.startsWith(u8, lines.first(), "// Code generated by zigo.")) return false;
    const package_line = lines.next() orelse return false;
    if (!std.mem.startsWith(u8, package_line, "package ")) return false;
    return lines.next() == null;
}

test "bool is lowered to uint8 at the ABI boundary" {
    const fixture =
        \\{"functions":[{"name":"negate","params":[{"name":"p0","type":{"kind":"bool"}}],"return":{"kind":"bool"},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{ .package = "scalar", .prefix = "zg", .go_module = "example.com/zigo/scalar" });
    const header = try temporary.dir.readFileAlloc(std.testing.io, "zigo_scalar.h", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(header);
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "uint8_t zg_negate(uint8_t p0)"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "scalar/scalar_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "func boolToUint8") == null);
    const helpers = try temporary.dir.readFileAlloc(std.testing.io, "scalar/scalar_helpers_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(helpers);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        helpers,
        1,
        "func boolToUint8(value bool) uint8 {\n" ++
            "\tif value {\n" ++
            "\t\treturn 1\n" ++
            "\t}\n" ++
            "\treturn 0\n" ++
            "}\n",
    ));
}

test "public Go filename uses the normalized package name" {
    const fixture =
        \\{"functions":[],"package":"HTTPClient","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "HTTPClient",
        .prefix = "zg",
        .go_module = "example.com/http-client",
    });
    try temporary.dir.access(std.testing.io, "http_client/http_client_gen.go", .{});
    try temporary.dir.access(std.testing.io, "internal/raw/raw_gen.go", .{});
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "http_client/generated.go", .{}));
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "internal/raw/cgo.go", .{}));
    // This binding declares no type, no error, and no helper, so the three
    // files that would hold them are not written at all.
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "http_client/http_client_type_gen.go", .{}));
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "http_client/http_client_errors_gen.go", .{}));
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "http_client/http_client_helpers_gen.go", .{}));
}

test "raw Go package can use a custom relative path" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"p0","type":{"bits":32,"kind":"int","signed":true}},{"name":"p1","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/zigo/scalar",
        .raw_package_path = "support/ffi",
        .raw_package_name = "ffi",
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "support/ffi/ffi_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "package ffi"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "scalar/scalar_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "import raw \"example.com/zigo/scalar/support/ffi\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "return raw.Add(p0, p1)"));
}

test "raw Go bindings can be colocated without public name collisions" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"p0","type":{"bits":32,"kind":"int","signed":true}},{"name":"p1","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/zigo/scalar",
        .raw_package_path = "scalar",
        .raw_package_name = "scalar",
        .raw_colocated = true,
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "scalar/scalar_cgo_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "package scalar"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func zigoRawAdd("));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func zigoRawLastErrorMessage()"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "scalar/scalar_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "import ") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "return zigoRawAdd(p0, p1)"));
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "scalar/scalar_helpers_gen.go", .{}));
}

test "cgo flag overrides and observed link flags are emitted" {
    const fixture =
        \\{"functions":[],"package":"flags","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
        .cflags_override = "-I/opt/flags/include",
        .ldflags_override = "-L/opt/flags/lib -lflags_zigo",
        .system_ldflags = "-lz",
        .framework_ldflags = "-framework CoreFoundation",
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "#cgo CFLAGS: -I/opt/flags/include") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "#cgo LDFLAGS: -L/opt/flags/lib -lflags_zigo -lz") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "#cgo darwin LDFLAGS: -framework CoreFoundation") != null);
}

test "static cgo links its archive by path and dynamic cgo keeps the search path" {
    const fixture =
        \\{"functions":[],"package":"flags","prefix":"zg","zig_version":"0.16.0"}
    ;
    var static_output = std.testing.tmpDir(.{ .iterate = true });
    defer static_output.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, static_output.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
        .library_stem = "flags_zigo",
        .system_ldflags = "-lz",
    });
    const static_raw = try static_output.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(static_raw);
    // A dynamic artifact of the same name in the install directory must not be
    // able to satisfy this link.
    try std.testing.expect(std.mem.containsAtLeast(u8, static_raw, 1, "#cgo LDFLAGS: ${SRCDIR}/../../../zig-out/lib/libflags_zigo.a -lz"));

    var dynamic_output = std.testing.tmpDir(.{ .iterate = true });
    defer dynamic_output.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, dynamic_output.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
        .library_stem = "flags_zigo",
        .link_mode = .dynamic,
    });
    const dynamic_raw = try dynamic_output.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(dynamic_raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, dynamic_raw, 1, "#cgo LDFLAGS: -L${SRCDIR}/../../../zig-out/lib -lflags_zigo"));

    // Without an explicit stem the package name still derives the artifact.
    var default_output = std.testing.tmpDir(.{ .iterate = true });
    defer default_output.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, default_output.dir, .{
        .package = "flags",
        .prefix = "zg",
        .go_module = "example.com/flags",
    });
    const default_raw = try default_output.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(default_raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, default_raw, 1, "${SRCDIR}/../../../zig-out/lib/libflags_zigo.a"));
}

test "errors enums and slices share one lowered ABI" {
    const fixture =
        \\{
        \\  "functions": [
        \\    {"name":"divide","params":[{"name":"p0","type":{"bits":64,"kind":"float"}},{"name":"p1","type":{"bits":64,"kind":"float"}}],"return":{"error_set":["DivideByZero"],"kind":"error_union","payload":{"bits":64,"kind":"float"}},"symbol":"ignored"},
        \\    {"name":"sum","params":[{"name":"p0","type":{"const":true,"element":{"bits":64,"kind":"float"},"kind":"slice"}}],"return":{"bits":64,"kind":"float"},"symbol":"ignored"},
        \\    {"name":"fill","params":[{"direction":"out","name":"p0","type":{"const":false,"element":{"bits":64,"kind":"float"},"kind":"slice"}}],"return":{"kind":"void"},"symbol":"ignored"},
        \\    {"name":"normalizeFormat","params":[{"name":"p0","type":{"kind":"enum","ref":"Format"}}],"return":{"kind":"enum","ref":"Format"},"symbol":"ignored"}
        \\  ],
        \\  "package":"features",
        \\  "prefix":"zg",
        \\  "types":[{"fields":[{"name":"pcm","value":0},{"name":"flac","value":1}],"kind":"enum","name":"Format","tag_type":{"bits":32,"kind":"int","signed":false}}],
        \\  "zig_version":"0.16.0"
        \\}
    ;
    const lock =
        \\{"ir_version":1,"next_code":2,"codes":{"DivideByZero":1},"reserved":{"0":"OK","-1":"Unknown","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle"}}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "features",
        .prefix = "zg",
        .go_module = "example.com/features",
        .errors_lock_bytes = lock,
    });
    const header = try temporary.dir.readFileAlloc(std.testing.io, "zigo_features.h", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(header);
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "int32_t zg_divide(double p0, double p1, double * out_result)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "const double * p0_ptr, size_t p0_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "size_t * p0_written"));
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "#define ZG_FORMAT_FLAC 1"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "features/features_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "ErrDivideByZero") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "type Format") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Sum(p0 []float64) float64"));
    try std.testing.expect(std.mem.indexOf(u8, public, "func boolToUint8") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "activeCallbackHandles") == null);
    const public_types = try temporary.dir.readFileAlloc(std.testing.io, "features/features_type_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public_types);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type Format"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "func (value Format) String() string"));
    const public_errors = try temporary.dir.readFileAlloc(std.testing.io, "features/features_errors_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public_errors);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "ErrDivideByZero"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "func errorForCode(operation string, code int32) error"));
    // The error file also converts an unrecognized code, so its imports are a block.
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "\t\"strconv\"\n\n\t\"example.com/features/internal/raw\""));
    const shim = try temporary.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(shim);
    try std.testing.expect(std.mem.containsAtLeast(u8, shim, 1, "p0_ptr: [*c]f64, p0_len: usize, p0_written: *usize"));
    try std.testing.expect(std.mem.containsAtLeast(u8, shim, 1, "p0_written.* = p0_len"));
}

test "callbacks use role-specific public types and typed handle helpers" {
    const fixture =
        \\{
        \\  "functions":[
        \\    {"name":"subscribe","params":[{"name":"handler","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"zg_subscribe"},
        \\    {"name":"install","namespace":"Registry","params":[{"name":"handler","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":64,"kind":"int","signed":false},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"zg_registry_install"},
        \\    {"name":"replace","namespace":"Registry","params":[{"name":"handler","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":8,"kind":"int","signed":false},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"zg_registry_replace"}
        \\  ],
        \\  "package":"callbacks","prefix":"zg","zig_version":"0.16.0"
        \\}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "callbacks",
        .prefix = "zg",
        .go_module = "example.com/callbacks",
    });
    const public = try temporary.dir.readFileAlloc(std.testing.io, "callbacks/callbacks_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "type SubscribeHandlerCallback") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Subscribe(handler SubscribeHandlerCallback)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "defer deleteCallbackHandle(handlerHandle)"));
    const public_types = try temporary.dir.readFileAlloc(std.testing.io, "callbacks/callbacks_type_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public_types);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type SubscribeHandlerCallback func(int32) int32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type RegistryInstallHandler func(uint64) int32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type RegistryReplaceHandler func(uint8) int32"));
    const helpers = try temporary.dir.readFileAlloc(std.testing.io, "callbacks/callbacks_helpers_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(helpers);
    try std.testing.expect(std.mem.containsAtLeast(u8, helpers, 1, "func newSubscribeHandlerCallbackHandle(value SubscribeHandlerCallback) zigoCallbackHandle"));
    try std.testing.expect(std.mem.containsAtLeast(u8, helpers, 1, "stored := (func(int32) int32)(value)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, helpers, 1, "stored := (func(uint64) int32)(value)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, helpers, 1, "stored := (func(uint8) int32)(value)"));
    try std.testing.expect(std.mem.indexOf(u8, helpers, "value any") == null);
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, ".Value().(func(int32) int32)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, ".Value().(func(uint64) int32)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, ".Value().(func(uint8) int32)"));
}

test "opt-in cleanup isolates state stops explicitly and keeps owners alive" {
    const fixture =
        \\{
        \\  "constructors":[{"deinit":"deinit","init":"create","type":"Context"}],
        \\  "functions":[
        \\    {"name":"create","namespace":"Context","ownership":"caller","params":[{"name":"callback","retention":"retained","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"error_set":["OutOfMemory"],"kind":"error_union","payload":{"const":false,"kind":"opaque_ptr","nullable":false,"ref":"Context"}},"symbol":"zg_context_create"},
        \\    {"name":"touch","params":[],"receiver":"Context","return":{"kind":"void"},"symbol":"zg_context_touch"},
        \\    {"name":"use","params":[{"name":"context","type":{"const":false,"kind":"opaque_ptr","nullable":false,"ref":"Context"}}],"return":{"kind":"void"},"symbol":"zg_use"},
        \\    {"name":"deinit","params":[],"receiver":"Context","return":{"kind":"void"},"symbol":"zg_context_deinit"}
        \\  ],
        \\  "package":"opaque","prefix":"zg","types":[{"kind":"opaque","name":"Context","zig_path":"root.Context"}],"zig_version":"0.16.0"
        \\}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "opaque",
        .prefix = "zg",
        .go_module = "example.com/opaque",
        .raw_package_path = "opaque",
        .raw_package_name = "opaque",
        .raw_colocated = true,
        .auto_cleanup = true,
    });
    const shim = try temporary.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(shim);
    try std.testing.expect(std.mem.containsAtLeast(u8, shim, 1, "target.Context.create("));
    try std.testing.expect(std.mem.containsAtLeast(u8, shim, 1, "target.Context.deinit(self)"));
    const public = try temporary.dir.readFileAlloc(std.testing.io, "opaque/opaque_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "import \"runtime\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func NewContext(callback ContextCallback) (*Context, error)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "zigoRawContextCreate("));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "return newContext(result, []zigoCallbackHandle{callbackHandle}), nil"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "defer runtime.KeepAlive(c)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "defer runtime.KeepAlive(context)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "ptr, err := zigoCheckedPointer(\"Context.Touch receiver\", c)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "contextPtr, err := zigoCheckedPointer(\"Use parameter context\", context)"));
    try std.testing.expect(std.mem.indexOf(u8, public, "c.ptr") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "context.ptr") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "type Context struct") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "zigoRawLastErrorMessage()") == null);
    const public_types = try temporary.dir.readFileAlloc(std.testing.io, "opaque/opaque_type_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(public_types);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type Context struct"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "type ContextRef struct"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "cleanup         runtime.Cleanup"));
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        public_types,
        1,
        "type contextCleanupState struct {\n" ++
            "\tptr             unsafe.Pointer\n" ++
            "\tcallbackHandles []zigoCallbackHandle\n" ++
            "}\n",
    ));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "callbackHandles []zigoCallbackHandle"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "runtime.AddCleanup(value, cleanupContext, state)"));
    try std.testing.expect(std.mem.indexOf(u8, public_types, "runtime.AddCleanup(value, cleanupContext, value)") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "func cleanupContext(state contextCleanupState)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "zigoRawContextDeinit(state.ptr)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "deleteCallbackHandle(handle)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "c.once.Do"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "c.cleanup.Stop()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_types, 1, "runtime.KeepAlive(c)"));
    const public_errors = try temporary.dir.readFileAlloc(std.testing.io, "opaque/opaque_errors_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(public_errors);
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "zigoRawLastErrorMessage()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "\t\"errors\"\n\t\"strconv\"\n"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public_errors, 1, "type HandleError struct"));
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "opaque/opaque_cgo_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func zigoRawContextCreate("));
}

test "ZIGO003 validation failure leaves the output tree untouched" {
    const fixture =
        \\{"functions":[{"name":"configure","params":[{"name":"config","type":{"kind":"value_struct","ref":"Config"}}],"return":{"kind":"void"},"symbol":"zg_configure"}],"package":"bad","prefix":"zg","types":[{"kind":"value_struct","name":"Config"}],"zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    const existing = [_]struct { path: []const u8, content: []const u8 }{
        .{ .path = "shim.zig", .content = "old shim" },
        .{ .path = "zigo_bad.h", .content = "old header" },
        .{ .path = "internal/raw/raw_gen.go", .content = "old raw" },
        .{ .path = "bad/bad_gen.go", .content = "old public" },
        .{ .path = "bad/bad_type_gen.go", .content = "old public types" },
        .{ .path = "bad/bad_errors_gen.go", .content = "old public errors" },
        .{ .path = "bad/bad_helpers_gen.go", .content = "old public helpers" },
        .{ .path = "errors.lock.json", .content = "old lock" },
    };
    for (existing) |file| {
        if (std.fs.path.dirname(file.path)) |directory| try temporary.dir.createDirPath(std.testing.io, directory);
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = file.path, .data = file.content });
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidSemantic, generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "bad",
        .prefix = "zg",
        .go_module = "example.com/bad",
    }));
    for (existing) |file| {
        const actual = try temporary.dir.readFileAlloc(std.testing.io, file.path, std.testing.allocator, .limited(64));
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(file.content, actual);
    }
}

test "ZIGO010 validation failure leaves the output tree untouched" {
    const fixture =
        \\{"functions":[{"name":"normalize","params":[],"return":{"kind":"enum","ref":"MissingMode"},"symbol":"zg_normalize"}],"package":"bad","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "shim.zig", .data = "old shim" });
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidSemantic, generate(arena.allocator(), std.testing.io, fixture, temporary.dir, .{
        .package = "bad",
        .prefix = "zg",
        .go_module = "example.com/bad",
    }));
    const actual = try temporary.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("old shim", actual);
}

fn expectAllocationFailureLeavesOutputUntouched(allocator: std.mem.Allocator) !void {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"left","type":{"bits":32,"kind":"int","signed":true}},{"name":"right","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"zg_add"}],"package":"atomic","prefix":"zg","zig_version":"0.16.0"}
    ;
    // `rewritten` is false for a file this binding has nothing to declare in:
    // a successful run removes the earlier copy instead of overwriting it.
    const existing = [_]struct { path: []const u8, content: []const u8, rewritten: bool = true }{
        .{ .path = "shim.zig", .content = "old shim" },
        .{ .path = "zigo_atomic.h", .content = "old header" },
        .{ .path = "internal/raw/raw_gen.go", .content = "old raw" },
        .{ .path = "atomic/atomic_gen.go", .content = "old public" },
        .{ .path = "atomic/atomic_type_gen.go", .content = "old public types", .rewritten = false },
        .{ .path = "atomic/atomic_errors_gen.go", .content = "old public errors", .rewritten = false },
        .{ .path = "atomic/atomic_helpers_gen.go", .content = "old public helpers", .rewritten = false },
        .{ .path = "errors.lock.json", .content = "old lock" },
    };
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    for (existing) |file| {
        if (std.fs.path.dirname(file.path)) |directory| try temporary.dir.createDirPath(std.testing.io, directory);
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = file.path, .data = file.content });
    }

    generate(allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "atomic",
        .prefix = "zg",
        .go_module = "example.com/atomic",
    }) catch |err| {
        if (err != error.OutOfMemory) return err;
        for (existing) |file| {
            const actual = try temporary.dir.readFileAlloc(std.testing.io, file.path, std.testing.allocator, .limited(64));
            defer std.testing.allocator.free(actual);
            try std.testing.expectEqualStrings(file.content, actual);
        }
        return err;
    };

    for (existing) |file| {
        if (!file.rewritten) {
            try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, file.path, .{}));
            continue;
        }
        const actual = try temporary.dir.readFileAlloc(std.testing.io, file.path, std.testing.allocator, .limited(64 * 1024));
        defer std.testing.allocator.free(actual);
        try std.testing.expect(!std.mem.eql(u8, file.content, actual));
    }
}

test "allocation failures before commit leave the output tree untouched" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expectAllocationFailureLeavesOutputUntouched, .{});
}

test "invalid errors lock leaves the output tree untouched" {
    const fixture =
        \\{"functions":[],"package":"locked","prefix":"zg","zig_version":"0.16.0"}
    ;
    const invalid_lock =
        \\{"codes":{},"ir_version":1,"next_code":1,"reserved":{"-1":"Changed","-2":"PanicCaught","-3":"CallbackPanic","-4":"InvalidHandle","0":"OK"}}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "errors.lock.json", .data = "old output" });

    try std.testing.expectError(error.ReservedMappingChanged, generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "locked",
        .prefix = "zg",
        .go_module = "example.com/locked",
        .errors_lock_bytes = invalid_lock,
    }));
    const actual = try temporary.dir.readFileAlloc(std.testing.io, "errors.lock.json", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("old output", actual);
}

test "generated errors lock produces an identical second generation" {
    const fixture =
        \\{"functions":[{"name":"run","params":[],"return":{"error_set":["Zulu","Alpha"],"kind":"error_union","payload":{"kind":"void"}},"symbol":"zg_run"}],"package":"repeatable","prefix":"zg","zig_version":"0.16.0"}
    ;
    var first = std.testing.tmpDir(.{ .iterate = true });
    defer first.cleanup();
    var second = std.testing.tmpDir(.{ .iterate = true });
    defer second.cleanup();

    try generate(std.testing.allocator, std.testing.io, fixture, first.dir, .{
        .package = "repeatable",
        .prefix = "zg",
        .go_module = "example.com/repeatable",
    });
    const lock = try first.dir.readFileAlloc(std.testing.io, "errors.lock.json", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(lock);
    try generate(std.testing.allocator, std.testing.io, fixture, second.dir, .{
        .package = "repeatable",
        .prefix = "zg",
        .go_module = "example.com/repeatable",
        .errors_lock_bytes = lock,
    });

    const paths = [_][]const u8{
        "errors.lock.json",
        "repeatable/repeatable_gen.go",
        "repeatable/repeatable_errors_gen.go",
        "internal/raw/raw_gen.go",
        "panic.c",
        "shim.zig",
        "zigo_repeatable.h",
    };
    for (paths) |path| {
        const first_bytes = try first.dir.readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(64 * 1024));
        defer std.testing.allocator.free(first_bytes);
        const second_bytes = try second.dir.readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(64 * 1024));
        defer std.testing.allocator.free(second_bytes);
        try std.testing.expectEqualStrings(first_bytes, second_bytes);
    }
}

test "the public package name can be overridden without moving the artifacts" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"a","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"event_queue","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "event_queue",
        .prefix = "zg",
        .go_module = "example.com/eq",
        .go_package = "eventqueue",
    });
    const public = try temporary.dir.readFileAlloc(std.testing.io, "eventqueue/eventqueue_gen.go", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.startsWith(u8, public, "// Code generated by zigo. DO NOT EDIT.\npackage eventqueue\n"));
    // The C header keeps the binding name, so the native artifacts do not move.
    const header = try temporary.dir.readFileAlloc(std.testing.io, "zigo_event_queue.h", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(header);
    try std.testing.expect(std.mem.containsAtLeast(u8, header, 1, "zg_add"));
}

test "Go parameter names escape keywords, generated locals and duplicates" {
    const fixture =
        \\{"functions":[{"name":"pick","params":[{"name":"type","type":{"bits":32,"kind":"int","signed":true}},{"name":"range","type":{"bits":32,"kind":"int","signed":true}},{"name":"code","type":{"bits":32,"kind":"int","signed":true}},{"name":"result","type":{"bits":32,"kind":"int","signed":true}},{"name":"source_len","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"error_set":["Failed"],"kind":"error_union","payload":{"bits":32,"kind":"int","signed":true}},"symbol":"ignored"}],"package":"kw","prefix":"zg","zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, temporary.dir, .{
        .package = "kw",
        .prefix = "zg",
        .go_module = "example.com/kw",
    });
    const public = try temporary.dir.readFileAlloc(std.testing.io, "kw/kw_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(public);
    // Keywords and the locals the generated bodies declare would not compile.
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Pick(type_ int32, range_ int32, code_ int32, result_ int32, sourceLen uint) (int32, error)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "result, code := raw.Pick(type_, range_, code_, result_, sourceLen)"));
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func Pick(type_ int32, range_ int32, code_ int32, result_ int32, sourceLen uint)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "code := int32(C.zg_pick("));
}

test "purego loading policy shapes the generated candidate order" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"a","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var default_output = std.testing.tmpDir(.{ .iterate = true });
    defer default_output.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, default_output.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
    });
    const default_raw = try default_output.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(default_raw);
    // The package-specific name keeps two zigo packages in one process apart.
    try std.testing.expect(std.mem.containsAtLeast(u8, default_raw, 1, "var libraryEnvVars = []string{\"ZIGO_SCALAR_LIBRARY_PATH\", \"ZIGO_LIBRARY_PATH\"}"));
    try std.testing.expect(std.mem.indexOf(u8, default_raw, "librarySearchPaths") == null);
    try std.testing.expect(std.mem.indexOf(u8, default_raw, "path/filepath") == null);

    var configured = std.testing.tmpDir(.{ .iterate = true });
    defer configured.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, configured.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
        .library_search_paths = "${EXECUTABLE_DIR}/../lib:/opt/app/lib",
        .library_env_vars = "APP_LIBRARY",
    });
    const configured_raw = try configured.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(configured_raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "var libraryEnvVars = []string{\"APP_LIBRARY\"}"));
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "var librarySearchPaths = []string{\"${EXECUTABLE_DIR}/../lib\", \"/opt/app/lib\"}"));
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "os.Executable()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "\"path/filepath\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, configured_raw, 1, "\"strings\""));

    // An empty environment list removes the lookup and its import.
    var bare = std.testing.tmpDir(.{ .iterate = true });
    defer bare.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, bare.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
        .library_env_vars = "",
    });
    const bare_raw = try bare.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(bare_raw);
    try std.testing.expect(std.mem.indexOf(u8, bare_raw, "libraryEnvVars") == null);
    try std.testing.expect(std.mem.indexOf(u8, bare_raw, "\t\"os\"\n") == null);
}

test "automatic loading and loader visibility shape the generated packages" {
    const fixture =
        \\{"functions":[{"name":"add","params":[{"name":"a","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"}],"package":"scalar","prefix":"zg","zig_version":"0.16.0"}
    ;
    var automatic = std.testing.tmpDir(.{ .iterate = true });
    defer automatic.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, automatic.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
        .library_search_paths = "/opt/app/lib",
        .library_automatic = true,
        .library_exported_api = false,
    });
    const raw = try automatic.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(raw);
    // The first binding call attempts the candidates exactly once.
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "func ensureLoaded() {"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "if loadedBindings.Load() != nil || automaticLoadAttempted { return }"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "panic(automaticLoadError)"));
    const public = try automatic.dir.readFileAlloc(std.testing.io, "scalar/scalar_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(public);
    try std.testing.expect(std.mem.indexOf(u8, public, "LoadLibrary") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "LibraryLoaded") == null);
    try std.testing.expect(std.mem.indexOf(u8, public, "DefaultLibraryName") == null);
    // The bound API is unchanged by the policy.
    try std.testing.expect(std.mem.containsAtLeast(u8, public, 1, "func Add("));

    var explicit = std.testing.tmpDir(.{ .iterate = true });
    defer explicit.cleanup();
    try generate(std.testing.allocator, std.testing.io, fixture, explicit.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
    });
    const explicit_raw = try explicit.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(explicit_raw);
    try std.testing.expect(std.mem.indexOf(u8, explicit_raw, "ensureLoaded") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, explicit_raw, 1, "call LoadLibrary first"));
    const explicit_public = try explicit.dir.readFileAlloc(std.testing.io, "scalar/scalar_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(explicit_public);
    try std.testing.expect(std.mem.containsAtLeast(u8, explicit_public, 1, "func LoadLibrary(path string) error"));
}

test "purego generation emits an atomic retryable loader and explicit callback ABI" {
    const scalar_fixture =
        \\{"functions":[{"name":"add","params":[{"name":"a","type":{"bits":32,"kind":"int","signed":true}},{"name":"b","type":{"bits":32,"kind":"int","signed":true}}],"return":{"bits":32,"kind":"int","signed":true},"symbol":"ignored"},{"name":"accept","params":[{"name":"value","type":{"const":true,"kind":"opaque_ptr","nullable":true,"ref":"Handle"}}],"return":{"kind":"void"},"symbol":"ignored"}],"package":"scalar","prefix":"zg","types":[{"kind":"opaque","name":"Handle"}],"zig_version":"0.16.0"}
    ;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try generate(std.testing.allocator, std.testing.io, scalar_fixture, temporary.dir, .{
        .package = "scalar",
        .prefix = "zg",
        .go_module = "example.com/scalar",
        .backend = .purego,
        .library_stem = "scalar_zigo",
    });
    const raw = try temporary.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "import \"C\"") == null);
    // A uintptr round-trip is what `go vet` reports as a possible stale pointer.
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "lastError func() unsafe.Pointer"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "unsafe.Add(p, length)"));
    try std.testing.expect(std.mem.indexOf(u8, raw, "unsafe.Pointer(p") == null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "runtime/cgo") == null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "github.com/ebitengine/purego") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "type LibraryError struct") != null);
    // The committed loader must be identical on every supported host, so the
    // platform basename is selected at run time instead of at generation time.
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "map[string]string{\"darwin\": \"libscalar_zigo.dylib\", \"linux\": \"libscalar_zigo.so\"}[runtime.GOOS]"));
    try std.testing.expect(std.mem.indexOf(u8, raw, "loadedBindings.Store(&next)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "purego.Dlclose(handle)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "different library is already loaded") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "fnAdd func(int32, int32) int32") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "func Accept(value unsafe.Pointer)") != null);

    const callback_fixture =
        \\{"functions":[{"name":"install","params":[{"name":"callback","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"ignored"},{"name":"apply","params":[{"name":"callback","type":{"c_callconv":true,"has_userdata":true,"kind":"callback","params":[{"bits":32,"kind":"int","signed":true},{"bits":64,"is_usize":true,"kind":"int","signed":false}],"return":{"bits":32,"kind":"int","signed":true}}},{"name":"userdata","type":{"bits":64,"is_usize":true,"kind":"int","signed":false}}],"return":{"kind":"void"},"symbol":"ignored"},{"name":"process","params":[],"return":{"error_set":["Failed"],"kind":"error_union","payload":{"bits":64,"is_usize":true,"kind":"int","signed":false}},"symbol":"ignored"}],"package":"callbacks","prefix":"zg","zig_version":"0.16.0"}
    ;
    var rejected = std.testing.tmpDir(.{ .iterate = true });
    defer rejected.cleanup();
    try generate(std.testing.allocator, std.testing.io, callback_fixture, rejected.dir, .{
        .package = "callbacks",
        .prefix = "zg",
        .go_module = "example.com/callbacks",
        .backend = .purego,
    });
    const callback_header = try rejected.dir.readFileAlloc(std.testing.io, "zigo_callbacks.h", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(callback_header);
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_header, 1, "void zg_install_purego_v1(int32_t (*callback)(int32_t, size_t), size_t userdata)"));
    const callback_shim = try rejected.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(callback_shim);
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_shim, 1, "callback: *const fn (i32, usize) callconv(.c) i32, userdata: usize"));
    try std.testing.expect(std.mem.indexOf(u8, callback_shim, "extern fn zg_install_go_callback_callback") == null);
    const callback_raw = try rejected.dir.readFileAlloc(std.testing.io, "internal/raw/raw_gen.go", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(callback_raw);
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_raw, 1, "var callbackPointers [1]uintptr"));
    try std.testing.expect(std.mem.indexOf(u8, callback_raw, "CallbackPointer1") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_raw, 1, "var outResult uintptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, callback_raw, 1, "return uint(outResult), code"));

    var legacy = std.testing.tmpDir(.{ .iterate = true });
    defer legacy.cleanup();
    try generate(std.testing.allocator, std.testing.io, callback_fixture, legacy.dir, .{
        .package = "callbacks",
        .prefix = "zg",
        .go_module = "example.com/callbacks",
        .backend = .cgo,
    });
    const legacy_header = try legacy.dir.readFileAlloc(std.testing.io, "zigo_callbacks.h", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(legacy_header);
    try std.testing.expect(std.mem.containsAtLeast(u8, legacy_header, 1, "void zg_install(size_t userdata)"));
    try std.testing.expect(std.mem.indexOf(u8, legacy_header, "zg_install_purego_v1") == null);
    const legacy_shim = try legacy.dir.readFileAlloc(std.testing.io, "shim.zig", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(legacy_shim);
    try std.testing.expect(std.mem.containsAtLeast(u8, legacy_shim, 1, "extern fn zg_install_go_callback_callback"));
}
