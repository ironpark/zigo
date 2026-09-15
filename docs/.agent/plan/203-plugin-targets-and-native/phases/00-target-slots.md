---
completed_at: "2026-09-15T01:23:56Z"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -rn "output_targets" src plugins docs tests` returns nothing.
> NEXT: none

# Per-target render slots and Rust builder

## Planned Work

- Replace `Plugin.visit/claims/source_files/imports/output_targets` with `go: ?GoRender` and `rust: ?RustRender` slots of identical shape (`visit`, `claims`, `source_files`, `imports`), typed per language; keep `artifacts` target-neutral.
- Add `src/plugin/rustbuild.zig`: a Rust AST builder (items: fn, impl block, trait impl, struct, enum, const, use; statements: let, expression, return, if/else, match with arms, for, block; expressions: path, call, method call, literals, references, closures, macro call (`format!`, `vec!`), raw escape hatch) rendering `rustfmt`-stable output. Generator-backed nodes (type names, signatures) go through a `RustWriters` table implemented in `src/gen/emit_rust/`.
- Split `Context` into a shared base plus `GoContext`/`RustContext` (each with its own `builder()` and writers). `Node` stays shared.
- Add Rust visitor dispatch: `src/gen/emit_rust/plugin_hooks.zig` walking the same node order as the Go one and flushing at the equivalent insertion points (after each `impl` method, after each type, at file begin/end, and a `src/zigo_plugins.rs` module for package-level output that `lib.rs` re-exports when non-empty).
- Port every shipped and built-in plugin and test fixture to the `go` slot; built-ins whose behaviour is Go-only stay Go-only.
- Contract 6.0; update `tests/plugin_contract.zig`, `docs/plugins/api-reference.md` (slots, RustContext, Rust builder), CHANGELOG "Plugin API 6.0" table.

## Done When

- `grep -rn "output_targets" src plugins docs tests` returns nothing.
- A test plugin with only a `rust` slot renders into example 13's crate and `cargo test` passes; Go goldens and examples byte-identical.
