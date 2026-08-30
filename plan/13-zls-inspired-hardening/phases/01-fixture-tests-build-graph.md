---
depends_on:
- "13-zls-inspired-hardening#0"
perf_phase: false
status: planned
---
> DONE-WHEN: A new generator behavior case can be added without embedding a large expected source string in Zig code.
> NEXT: none

# Introduce fixture tests and canonical module wiring

## Planned Work

- Move representative generator semantic inputs and expected output trees into discoverable case directories.
- Add a generator case runner with deterministic traversal and an optional `-Dtest-filter` build option.
- Refactor `build.zig` so production and test artifacts consume one canonical generator module bundle.
- Add a compile-only `check` step for fast graph validation.

## Done When

- A new generator behavior case can be added without embedding a large expected source string in Zig code.
- `zig build test -Dtest-filter=<case>` runs a selected case, `zig build check` succeeds, and the full suite passes.
