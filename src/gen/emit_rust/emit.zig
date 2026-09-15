//! Entry point of the Rust generator: the emitter table the generator runs,
//! and the output file names.
//!
//! A sibling of `src/gen/emit/emit.zig`, not a layer over it. The two meet at
//! exactly four things: the `Emitter` and `Options` records the generator
//! drives them with, `emit.neutral_emitters` -- the Zig shim, its panic source
//! and the C header, which describe the bound library rather than the language
//! binding it -- and the `abi.Program` they both read. Nothing that writes Go
//! is reachable from here.
const std = @import("std");
const abi = @import("abi");
const diagnostic = @import("diagnostic");
const emit = @import("../emit/emit.zig");
const enums = @import("enums.zig");
const buffers = @import("buffers.zig");
const handles = @import("handles.zig");
const plugin = @import("plugin");
const plugin_hooks = @import("plugin_hooks.zig");
const public = @import("public.zig");
const registry = @import("../plugins/registry.zig");
const raw = @import("raw.zig");
const types = @import("types.zig");

pub const Emitter = emit.Emitter;
pub const Options = emit.Options;

/// Every output a Rust binding has. The three neutral entries come first, in
/// their own order, so the shim, panic source and header land in the output
/// manifest exactly where a Go binding puts them -- the two trees describe the
/// same native library, and a diff between them should be about the language,
/// not about file order.
///
/// The crate has no per-package walk, unlike Go: sub-packages are out of the
/// minimal backend's scope, so there is one `src/lib.rs` and the table is flat.
pub const core_emitters = emit.neutral_emitters ++ crate_emitters ++ plugin_emitters;

/// The crate's own files, each framed so the hooks that run inside it know
/// which file they are in. `raw` and `buffer` are the two kinds Go has no
/// counterpart for.
const crate_emitters = [_]Emitter{
    framed(.raw, .{ .pathAlloc = rawPath, .render = raw.renderRaw }),
    framed(.errors, .{ .pathAlloc = errorPath, .render = public.renderErrors, .enabled = errorsEnabled }),
    framed(.handles, .{ .pathAlloc = handlePath, .render = handles.renderHandles, .enabled = handlesEnabled }),
    framed(.buffer, .{ .pathAlloc = bufferPath, .render = buffers.renderBuffers, .enabled = buffersEnabled }),
    framed(.enums, .{ .pathAlloc = enums.path, .render = enums.render, .enabled = enums.enabled }),
    framed(.api, .{ .pathAlloc = libPath, .render = public.renderLib }),
};

/// `source` with the `FileInfo` of the file it writes put in the options, so
/// a `file_begin` or `file_end` node knows where it is.
fn framed(comptime kind: @FieldType(plugin.FileInfo, "kind"), comptime source: Emitter) Emitter {
    return .{
        .enabled = source.enabled,
        .pathAlloc = source.pathAlloc,
        .render = struct {
            fn render(a: std.mem.Allocator, w: *std.Io.Writer, p: abi.Program, o: Options) anyerror!void {
                const path = try source.pathAlloc(a, p, o);
                defer a.free(path);
                var options = o;
                options.file = .{ .path = path, .kind = kind };
                return source.render(a, w, p, options);
            }
        }.render,
    };
}

/// How many modules the registered plugins add, which is the length of the
/// table below.
const plugin_file_count = blk: {
    var count: usize = 0;
    for (registry.plugins) |registered| {
        if (registered.rust) |slot| count += slot.source_files.len;
    }
    // The crate's own plugin module, which is written only when a package
    // boundary produced something; the emitter is always in the table and its
    // `enabled` answers.
    break :blk count + 1;
};

/// One emitter per plugin module, in registration order, and the crate's
/// `zigo_plugins` module last.
const plugin_emitters = blk: {
    var result: [plugin_file_count]Emitter = undefined;
    var slot_index: usize = 0;
    for (registry.plugins, 0..) |registered, index| {
        if (registered.rust) |slot| for (slot.source_files) |file| {
            result[slot_index] = framedPluginModule(index, file);
            slot_index += 1;
        };
    }
    result[slot_index] = package_module_emitter;
    break :blk result;
};

/// A plugin Rust emitter wrapped in its module frame: the plugin writes
/// items, and the generated marker and the `use` block derived from that body
/// are added here. A plugin therefore never spells a `use` block, and a body
/// that came out empty leaves the file at its prelude, which the generator
/// drops.
fn framedPluginModule(comptime plugin_index: usize, comptime file: plugin.RustSourceFile) Emitter {
    return .{
        .owner = registry.plugins[plugin_index].name,
        .helper_scan = false,
        .enabled = struct {
            fn enabled(allocator: std.mem.Allocator, program: abi.Program, options: Options) anyerror!bool {
                if (!plugin_hooks.runs(plugin_index, options)) return false;
                return plugin_hooks.sourceFileEnabled(allocator, program, options, file);
            }
        }.enabled,
        .pathAlloc = struct {
            fn path(allocator: std.mem.Allocator, _: abi.Program, _: Options) anyerror![]u8 {
                return std.fmt.allocPrint(allocator, "src/{s}.rs", .{file.module});
            }
        }.path,
        .render = struct {
            fn render(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) anyerror!void {
                if (!plugin_hooks.runs(plugin_index, options)) return;
                var file_options = options;
                file_options.file = .{
                    .path = "src/" ++ file.module ++ ".rs",
                    .owner = registry.plugins[plugin_index].name,
                    .kind = .plugin,
                    .rust_source_file = file,
                };
                var body: std.Io.Writer.Allocating = .init(allocator);
                defer body.deinit();
                try file.render(plugin_hooks.context(allocator, program, file_options), &body.writer);
                if (body.written().len == 0) return;
                try writer.writeAll("// Code generated by zigo. DO NOT EDIT.\n\n");
                const declared = if (file.imports) |reader|
                    try reader(plugin_hooks.context(allocator, program, file_options))
                else
                    plugin_hooks.rustSlot(registry.plugins[plugin_index]).imports;
                try plugin_hooks.writeUses(writer, declared, body.written());
                try writer.writeAll(body.written());
            }
        }.render,
    };
}

/// The crate's own plugin module: everything the package boundaries wrote,
/// under the `use` block the registered plugins declared.
const package_module_emitter: Emitter = .{
    .owner = "plugins",
    .helper_scan = false,
    .enabled = struct {
        fn enabled(allocator: std.mem.Allocator, program: abi.Program, options: Options) anyerror!bool {
            const body = try plugin_hooks.packageBodyAlloc(allocator, program, options);
            defer allocator.free(body);
            return body.len != 0;
        }
    }.enabled,
    .pathAlloc = struct {
        fn path(allocator: std.mem.Allocator, _: abi.Program, _: Options) anyerror![]u8 {
            return allocator.dupe(u8, plugin_hooks.package_module_path);
        }
    }.path,
    .render = struct {
        fn render(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: Options) anyerror!void {
            const body = try plugin_hooks.packageBodyAlloc(allocator, program, options);
            defer allocator.free(body);
            if (body.len == 0) return;
            try writer.writeAll("// Code generated by zigo. DO NOT EDIT.\n\n");
            try plugin_hooks.writeUses(writer, plugin_hooks.declaredUses(), body);
            try writer.writeAll(body);
        }
    }.render,
};

/// The plugin analyses and claim rules, run with the crate's context.
pub const analyze = plugin_hooks.analyze;

fn errorsEnabled(_: std.mem.Allocator, program: abi.Program, _: Options) anyerror!bool {
    return public.hasErrors(program);
}

fn handlesEnabled(_: std.mem.Allocator, program: abi.Program, _: Options) anyerror!bool {
    return handles.hasHandles(program);
}

fn buffersEnabled(_: std.mem.Allocator, program: abi.Program, _: Options) anyerror!bool {
    return buffers.hasBuffers(program);
}

// The crate layout is fixed rather than derived from an option. Go's raw and
// public package paths are options because a Go module puts packages where the
// user's import paths say; a Cargo crate's sources are `src/` by convention
// that nothing overrides, so deriving these would only add a way to produce a
// crate `cargo` cannot build.
fn rawPath(allocator: std.mem.Allocator, _: abi.Program, _: Options) ![]u8 {
    return allocator.dupe(u8, "src/raw.rs");
}

fn errorPath(allocator: std.mem.Allocator, _: abi.Program, _: Options) ![]u8 {
    return allocator.dupe(u8, "src/error.rs");
}

fn handlePath(allocator: std.mem.Allocator, _: abi.Program, _: Options) ![]u8 {
    return allocator.dupe(u8, "src/handle.rs");
}

fn bufferPath(allocator: std.mem.Allocator, _: abi.Program, _: Options) ![]u8 {
    return allocator.dupe(u8, "src/buffer.rs");
}

fn libPath(allocator: std.mem.Allocator, _: abi.Program, _: Options) ![]u8 {
    return allocator.dupe(u8, "src/lib.rs");
}

/// Every declaration the minimal Rust backend cannot render, as diagnostics.
///
/// The generator reports these and stops. Skipping them silently would hand
/// the user a crate that compiles and is missing half the binding, which is
/// worse than a refusal naming the declaration: the whole point of the
/// minimal scope is that its edges are visible.
pub fn unsupportedIssues(
    allocator: std.mem.Allocator,
    program: abi.Program,
    issues: *std.ArrayList(diagnostic.Diagnostic),
) !void {
    try enums.unsupportedIssues(allocator, program, issues);
    for (program.functions) |function| {
        if (types.unsupported(program, function)) |reason|
            try issues.append(allocator, try types.unsupportedDiagnostic(allocator, function, reason));
    }
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(plugin_hooks);
    std.testing.refAllDecls(types);
    std.testing.refAllDecls(raw);
    std.testing.refAllDecls(public);
    std.testing.refAllDecls(handles);
    std.testing.refAllDecls(buffers);
    std.testing.refAllDecls(enums);
}
