---
completed_at: "2026-09-03T06:27:03Z"
perf_phase: false
status: done
---
> DONE-WHEN: `staticcheck -checks U1000 ./...` is clean in every example module and the verification loop passes.
> NEXT: none

# Reference-driven helper emission

## Planned Work

- Add use predicates for SliceView, ToRaw, SliceToRaw, boolToUint8, zigoOptionalPointer, activeCallbackHandleCount (and any other helper staticcheck flags); wire emission; update goldens and unit tests; CHANGELOG.

## Done When

- `staticcheck -checks U1000 ./...` is clean in every example module and the verification loop passes.
