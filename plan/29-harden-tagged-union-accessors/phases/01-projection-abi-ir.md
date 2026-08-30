---
completed_at: "2026-08-30T10:53:44Z"
depends_on:
- "29-harden-tagged-union-accessors#0"
perf_phase: false
status: done
---
> DONE-WHEN: Structural lowering tests cover tag/scalar/slice/handle projections and emitters contain no independent symbol derivation.
> NEXT: none

# Projection ABI IR

## Planned Work

- Add explicit projection declarations, parameters, roles, symbols, and status values to ABI IR.
- Lower tagged-union type metadata once and centralize generated-name collision validation.
- Refactor shim, C header, cgo, and public emission to consume lowered projections.

## Done When

- Structural lowering tests cover tag/scalar/slice/handle projections and emitters contain no independent symbol derivation.
