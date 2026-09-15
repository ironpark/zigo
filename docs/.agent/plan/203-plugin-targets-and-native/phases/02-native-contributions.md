---
depends_on:
- "203-plugin-targets-and-native#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: The TEST plugin's symbol appears in the C header, `raw_gen.go` (cgo and purego), and `src/raw.rs` goldens, and `abi-diff` lists it when added.
> NEXT: none

# Native contributions

## Planned Work

- Contract: `Plugin.native: ?Native` with `sources: []const NativeSource { path: []const u8 (relative to the plugin root), module_name }` and `symbols: *const fn (NativeContext) anyerror![]const NativeSymbol`. `NativeSymbol { name, params: []const abi.AbiParam, ret: abi.AbiScalar, implementation: []const u8 (Zig path inside the source), doc }`. `NativeContext` exposes the semantic program and the plugin's config/facts.
- Build wiring: `build.zig` passes each plugin's native sources to the shim module as named imports (`PluginModule` already has the root path; derive sources relative to it); the generated shim adds `comptime { _ = @import("<module>"); }` plus one exported wrapper per `NativeSymbol` that calls `implementation`, so plugin Zig code needs no `export` of its own.
- Lowering: append plugin symbols to `abi.Program.functions` with a synthetic `origin` flagged `owner = .{ .plugin = NAME }`; symbol spelling `<prefix>_<plugin-lower>_<name>`. Header, Go raw (cgo), purego lookup table, Rust raw, and `abi-diff` consume them through the existing loops; add a `plugin_symbols` section to `semantic.json` so `abi-diff --base` on old sidecars still works.
- Public side: plugin symbols are not auto-wrapped in the public package; the plugin's `go`/`rust` `visit` renders the wrapper using a new builder node `Expr.rawCall(symbol, args)` that spells the raw-package call for the resolved backend (cgo vs purego) and language.
- Diagnostics: duplicate symbol name across plugins, invalid C signature, and a native source that fails to compile all report with the plugin's name prefix.
- TEST plugin gains a native symbol; generator golden and shim compile test; `tests/plugin_contract.zig` updated; docs `api-reference.md` (Native section) and `authoring.md`.

## Done When

- The TEST plugin's symbol appears in the C header, `raw_gen.go` (cgo and purego), and `src/raw.rs` goldens, and `abi-diff` lists it when added.
- Goldens and examples for bindings without native plugins byte-identical.
