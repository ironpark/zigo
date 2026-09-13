---
completed_at: "2026-09-13T20:52:07Z"
depends_on:
- "201-api-consistency-refactor#3"
perf_phase: false
status: done
---
> DONE-WHEN: `tests/plugin_contract.zig` and `zig build test` pass; examples 10 and 11 (which use shipped plugins) verify.
> NEXT: none

# Plugin API surface

## Planned Work

- Single option access: keep `Context.optionsOf(P, attachment)` on all contexts with `comptime P: Plugin`; remove `functionOptions/typeOptions` and make `readOptions` private.
- Split `plugin.Options` into an emitter-private struct and a small `PluginOptions` view (package paths, output target, facts, helpers); move `Referenced` out of `src/plugin.zig`.
- One `Facts` access path (`AnalyzeContext.facts` and a `Context.facts()` accessor); remove `Options.facts`.
- Add `typeSite` helper in `src/plugin/site.zig` so type-attached diagnostics stop hardcoding `semantic.json`.
- Add `Writers` helpers for method skeletons and Go identifier derivation so shipped plugins stop calling `naming.pascalAlloc` and hand-formatting statement syntax; update `plugins/json`, `plugins/enumkit`, `plugins/satisfies`.
- Make built-in plugins (`iterator`, `implements`) read their options through `ext` like third-party plugins.
- Bump `contract_version` major to 4; update `docs/plugins/*`.

## Done When

- `tests/plugin_contract.zig` and `zig build test` pass; examples 10 and 11 (which use shipped plugins) verify.
- `grep -rn "pascalAlloc\|options.facts" plugins src/gen/plugins` returns nothing.
