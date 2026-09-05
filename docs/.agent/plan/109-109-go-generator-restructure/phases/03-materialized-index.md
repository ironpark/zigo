---
depends_on:
- "109-109-go-generator-restructure#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `emit/materialized.zig` has no by-name layout scan.
> NEXT: none

# Materialized layouts by index

## Planned Work

- `AbiFn.MaterializedReturn/MaterializedOut` gain `layout: usize` set by
  `lowerMaterializedLayouts`; `Program.materializedLayout(index)` replaces the
  name lookup and `unreachable` in emit.
- `abi.materializedReturn/materializedOut` keep returning the root name for
  validate; lowering fills the index after layouts exist.

## Done When

- `emit/materialized.zig` has no by-name layout scan.
- Goldens unchanged; `zig build test` green.
