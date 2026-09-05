---
depends_on:
- "119-handle-lifecycle-refactor#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Shared contracts pass, cgo race tests pass, Windows cross compilation and generation/ABI checks pass; changes committed without push.
> NEXT: none

# Lifecycle contracts

## Planned Work

- Share concurrent call versus Close tests across callback/tagged-union cgo and purego backends; document boundaries and verify integration.

## Done When

- Shared contracts pass, cgo race tests pass, Windows cross compilation and generation/ABI checks pass; changes committed without push.
