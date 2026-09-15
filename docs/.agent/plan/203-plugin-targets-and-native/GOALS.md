# GOALS

## Problem and the end result from the user's point of view

After plan 202 (contract 5.0) a plugin can visit any IR node and render Go through a builder, but
only Go: `output_targets` gates the run while the builder and visitor are Go-shaped and the Rust
emitter never calls a plugin. Plugins also cannot touch the native side, so a feature that needs a
helper exported from Zig cannot be a plugin. A plugin author should be able to (a) render for Go
and Rust through per-target slots with a builder per language, and (b) ship Zig source that the
shim compiles and C symbols that the header, raw packages, purego loader and `abi-diff` all pick
up automatically.

## Measurable goals

- A shipped plugin renders both Go and Rust from one `Plugin` value; example 13 (Rust) shows its output.
- A shipped plugin contributes a Zig source file and an exported C symbol that appears in the C header, the Go raw package (cgo and purego), the Rust raw module, and `abi-diff` output.
- Contract bumped to 6.0; generated Go and Rust byte-identical for bindings that use no new feature.

## Supported scope and non-goals

In scope: `src/plugin.zig` render slots, a Rust builder, Rust emitter visitor dispatch, native contribution
plumbing through shim/header/raw/purego/abi-diff, one Rust-capable shipped plugin, one native-capable shipped
plugin, docs, tests, examples.
Out of scope: shared facts between plugins, distribution helpers, typed option references.

## Reference source / commit / license

Baseline: tag 0.27.0 (commit 633852f2). MIT.

## Completion criteria for the whole plan

All four phases done; `docs/plugins/*` describe contract 6.0; CHANGELOG `Unreleased / Changed (breaking)` has a "Plugin API 6.0" table.
