---
depends_on:
- "52-split-generated-files#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Example 10 emits `tagged_union_union_value_gen.go` and
> NEXT: none

# Per-union files

## Planned Work

- Route each union's projections, snapshot, and variant emission into
  `<pkg>_union_<union>_gen.go`, one file per union, removing
  `<pkg>_type_gen.go` entirely.
- Add deterministic union file-name derivation to `naming.zig` (normalize,
  then numeric suffix on residual collision), with unit tests covering
  reserved-suffix-like union names (e.g. a union named `type`) and two
  unions normalizing identically.
- Update goldens; verify the concatenated per-package content is
  declaration-identical to the pre-split output.

## Done When

- Example 10 emits `tagged_union_union_value_gen.go` and
  `tagged_union_union_signal_gen.go`, no file over ~450 lines, and no
  `tagged_union_type_gen.go`; naming unit tests pass.
- `zig build test` passes; example 10 tests pass under cgo and purego.
