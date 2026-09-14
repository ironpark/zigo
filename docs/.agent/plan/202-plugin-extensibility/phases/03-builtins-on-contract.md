---
depends_on:
- "202-plugin-extensibility#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `grep -rn "goIterator\|goImplements" src` returns nothing.
> NEXT: none

# Built-ins on the public contract

## Planned Work

- Remove `SemanticFn.go.iterator`, `go.implements`, `go.implements_keep_original` and the `goIterator()/goImplements()/goImplementsHidesOriginal()` accessors; provide `plugin.iterator.read(fn)`/`plugin.implements.read(fn)` helpers that decode `ext` and use them in `abi_diff.zig`, `validate/functions.zig`, `validate/names.zig`, `emit/common.zig`, `plugins/must.zig`, and the reflector.
- `abi-diff`: classify via the decoded `ext` values; keep the parse-time migration for v1/v2 documents by mapping old `go.*` fields into `ext` when reading.
- Align `zigo.features.implements` subjects with the generator (`function, handle`) or drop the handle subject if it has no behaviour; make the authoring `features.*` values plain `plugin.Plugin` re-exports of the built-ins so there is one definition.
- Audit remaining privileged reads: any `origin.*` deref or typed IR access in `src/gen/plugins/*` that a third-party plugin cannot perform must go through `Context` or `ext`.
- Docs: state that built-ins use the public contract; CHANGELOG "Plugin API 5.0" table completes.

## Done When

- `grep -rn "goIterator\|goImplements" src` returns nothing.
- `semantic.json` sidecars carry `ext.ITERATOR`/`ext.IMPLEMENTS` only (no `go.iterator`, `go.implements`); v1/v2 documents still parse in tests.
- Goldens and examples byte-identical; `go-abi-check` passes against the new HEAD.
