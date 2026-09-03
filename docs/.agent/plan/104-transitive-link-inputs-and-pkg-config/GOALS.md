# GOALS

## Problem and the end result from the user's point of view

Two build-integration defects reported from a gostty-style project whose target module imports packages (`pkg/libav` declaring `linkSystemLibrary("avformat")`, `pkg/vector` declaring `linkFramework("Accelerate")`).

A. `staticLibraryInputs` (`build.zig`) walks `import_table` recursively for `.other_step` / `.static_path` archives, but `systemLibraryFlags`, `pkgConfigLibraries`, `frameworkFlags` and the `lib_paths` `-L` flags look only at the target module. `zig build go` succeeds and `go build` later fails with `ld: library not found`. End result: every `-l`, `-L`, `-framework`/`-weak_framework` and `#cgo pkg-config:` entry declared anywhere in the import graph reaches the generated cgo block, deduplicated, in a deterministic order.

B. Zig's `linkSystemLibrary("avformat")` with pkg-config tries both `avformat` and `libavformat`; zigo copies the original name to `#cgo pkg-config:` and cgo has no such fallback, so the Zig build passes and only the Go build breaks. End result: for `.force` pkg-config libraries zigo asks pkg-config at build time which spelling resolves (original first, then `lib` prefix) and emits that spelling; when neither resolves the `go` step fails with a diagnostic naming the library and the module that declared it.

## Measurable goals

- One collector (same shape as `StaticInputCollector`) gathers system libraries, pkg-config names, frameworks and lib paths across the module graph; a library reached through two imports appears once.
- A `build.zig` unit test or a generator-case-level test proves an import-declared system library and framework reach the cgo flags.
- pkg-config resolution runs through `std.process.Child` with `pkg-config --exists`; a missing `pkg-config` binary keeps today's behavior (emit the original name) with a warning, not a failure.
- Docs `configuration.md` link section updated; CHANGELOG `## [Unreleased]` `### Fixed` (transitive) and `### Changed` (pkg-config resolution).

## Supported scope and non-goals

In scope: `build.zig` link collection, the `--pkg-config-libs` and system-library flag plumbing into `src/gen/emit.zig`, docs, tests. Non-goals: purego backend (it has no link step), Windows library naming.

## Reference source / commit / license

Current main; `build.zig` `staticLibraryInputs` / `StaticInputCollector` (the recursive precedent), `systemLibraryFlags`, `pkgConfigLibraries`, `frameworkFlags`; `src/gen/emit.zig` cgo preamble emission.

## Completion criteria for the whole plan

Both phases done; verification loop green; tree clean.
