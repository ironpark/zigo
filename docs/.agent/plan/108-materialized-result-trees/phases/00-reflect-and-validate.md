---
completed_at: "2026-09-03T06:47:47Z"
perf_phase: false
status: done
---
> DONE-WHEN: A materialized tree with nested structs, strings, slices and optional pointers reflects into semantic.json and every unsupported shape is rejected with a diagnostic naming the field path.
> NEXT: none

# Reflection, semantic model and validation

## Planned Work

- `.repr = .materialized` registration; tree walk with the supported field kinds; cycle and unsupported-kind diagnostics; semantic.json representation; abi-diff classification of tree changes; unit tests through real reflection.

## Done When

- A materialized tree with nested structs, strings, slices and optional pointers reflects into semantic.json and every unsupported shape is rejected with a diagnostic naming the field path.
