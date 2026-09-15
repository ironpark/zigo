# SCOPE

`src/plugin.zig`, `src/plugin/gobuild.zig`, new `src/plugin/rustbuild.zig`, `src/gen/emit/plugin_hooks.zig`,
`src/gen/emit_rust/*`, `src/gen/emit/shim.zig`, `header.zig`, `raw.zig`, `purego.zig`, `src/gen/emit_rust/raw.zig`,
`src/gen/abi_diff.zig`, `src/gen/ir/abi.zig`, `src/gen/generator.zig`, `src/main.zig`, `build.zig` (shim module
wiring), `src/gen/plugins/*`, `plugins/*`, `examples/13-rust-quick-start`, one Go example, `docs/plugins/*`, tests.

# CONTEXT

## Current implementation and bottlenecks

- `Plugin` (`src/plugin.zig`) has `visit`, `claims`, `source_files`, `artifacts`, `imports`, and `output_targets: []const []const u8 = &.{"go"}`. `Context.builder()` returns the Go builder from `src/plugin/gobuild.zig`. `Writers` renders Go only (comment at `src/plugin.zig:~428`).
- `src/gen/emit_rust/emit.zig` is a sibling of the Go emitter sharing only `Emitter`, `Options`, `neutral_emitters` (shim, panic source, C header) and `abi.Program`. It never imports `plugin` or `plugin_hooks`.
- `targets.Target` (`src/gen/targets.zig`) carries naming rules per language; `targets.go` and `targets.rust` exist.
- Shim: `src/gen/emit/shim.zig` `renderShim` writes the whole Zig C ABI from `abi.Program.functions[]` (`AbiFn{ symbol, params, ret, errors, origin }`). Header: `header.zig` `renderHeader`. Go raw: `raw.zig` `renderRaw` (cgo) and `purego.zig` (symbol lookup table). Rust raw: `emit_rust/raw.zig`. `abi_diff.zig` classifies changes from `semantic.json` plus the ABI tables.
- `build.zig` compiles the shim as a Zig module whose root imports the bound library; plugin modules are compiled from paths (`PluginModule.root_source_file`) against the generator's contract modules only.

## Target structure and invariants

- `Plugin.go: ?GoRender` and `Plugin.rust: ?RustRender`, each `{ visit, claims, source_files, imports }`; the presence of a slot replaces `output_targets`. A plugin with neither renders nothing but may still transform, validate, analyze, or contribute natively.
- `Context.builder()` is target-specific: `GoContext.builder()` returns `gobuild.Builder`, `RustContext.builder()` returns `rustbuild.Builder`. Shared parts (`optionsOf`, `facts`, `site`, `program`) live on a common base.
- `Plugin.native: ?Native = { sources: []const NativeSource, symbols: fn(NativeContext) []const NativeSymbol }`. A `NativeSymbol` is a C signature spelled with `abi.AbiScalar` params and return, plus the Zig function path inside the plugin's source that implements it. Lowering appends them to `abi.Program.functions` with `origin` marked as plugin-owned, so every downstream emitter and `abi-diff` see them without special cases.
- Plugin-owned symbols are namespaced `<prefix>_<PLUGIN>_<name>` and never collide with binding symbols.
