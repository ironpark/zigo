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
const handles = @import("handles.zig");
const public = @import("public.zig");
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
pub const core_emitters = emit.neutral_emitters ++ [_]Emitter{
    .{ .pathAlloc = rawPath, .render = raw.renderRaw },
    .{ .pathAlloc = errorPath, .render = public.renderErrors, .enabled = errorsEnabled },
    .{ .pathAlloc = handlePath, .render = handles.renderHandles, .enabled = handlesEnabled },
    .{ .pathAlloc = libPath, .render = public.renderLib },
};

fn errorsEnabled(_: std.mem.Allocator, program: abi.Program, _: Options) anyerror!bool {
    return public.hasErrors(program);
}

fn handlesEnabled(_: std.mem.Allocator, program: abi.Program, _: Options) anyerror!bool {
    return handles.hasHandles(program);
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
    for (program.functions) |function| {
        if (types.unsupported(program, function)) |reason|
            try issues.append(allocator, try types.unsupportedDiagnostic(allocator, function, reason));
    }
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(types);
    std.testing.refAllDecls(raw);
    std.testing.refAllDecls(public);
    std.testing.refAllDecls(handles);
}
