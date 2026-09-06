---
completed_at: "2026-09-06T06:22:23Z"
depends_on:
- "133-materialized-v2-and-enum-covers#0"
perf_phase: true
status: done
---
> DONE-WHEN: Generated Go has no `C.GoBytes`/`copy` for materialized buffers and the
> NEXT: none

# Decode from the native buffer

## Planned Work

- Raw cgo/purego materialized returns expose the native view and defer
  release to the public wrapper, which decodes then releases.
- `Fill` decodes into the caller's slice directly.

## Done When

- Generated Go has no `C.GoBytes`/`copy` for materialized buffers and the
  example benchmark is not slower.
