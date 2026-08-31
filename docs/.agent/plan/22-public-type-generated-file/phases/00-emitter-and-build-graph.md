---
completed_at: "2026-08-30T06:58:22Z"
perf_phase: false
status: done
---
> DONE-WHEN: Focused and full generator tests prove types appear only in the type file and every generated-file workflow includes it.
> NEXT: none

# Emitter and build graph

## Planned Work

- Add the type-file emitter and move public type rendering out of the callable wrapper renderer.
- Add `<package>_type_gen.go` to build formatting, update, and stale-check inputs.
- Extend generator tests for content placement, empty-file form, repeatability, and atomic output coverage.

## Done When

- Focused and full generator tests prove types appear only in the type file and every generated-file workflow includes it.
