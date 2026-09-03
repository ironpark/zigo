---
completed_at: "2026-09-03T03:49:12Z"
depends_on:
- "98-atomic-value-scalars#0"
perf_phase: false
status: done
---
> DONE-WHEN: Native writes through the pointer are visible to Go after the call and Go writes before/during the call are visible to native; cancel snapshots unchanged; verification loop green.
> NEXT: none

# Pointer atomics as call-scoped Go sync/atomic parameters

## Planned Work

- Accept `*std.atomic.Value(T)`/`*const` for 32/64-bit integers as borrowed parameters; Go signature uses `sync/atomic` pointer types; reuse the cancel flag's pinning/allocation mechanism on cgo and purego; diagnostics for unsupported widths and retained use; tests, example, docs, CHANGELOG.

## Done When

- Native writes through the pointer are visible to Go after the call and Go writes before/during the call are visible to native; cancel snapshots unchanged; verification loop green.
