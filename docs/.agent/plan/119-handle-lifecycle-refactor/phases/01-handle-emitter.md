---
depends_on:
- "119-handle-lifecycle-refactor#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Root tests and affected cgo/purego generation checks pass with no generated changes.
> NEXT: none

# Handle emitter

## Planned Work

- Extract handle types and lifecycle runtime generation from public_types into a dedicated emitter with unchanged call sites.

## Done When

- Root tests and affected cgo/purego generation checks pass with no generated changes.
