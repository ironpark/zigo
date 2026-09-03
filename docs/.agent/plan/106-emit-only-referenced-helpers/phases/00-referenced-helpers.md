---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `staticcheck -checks U1000 ./...` is clean in every example module and the verification loop passes.
> NEXT: none

# Reference-driven helper emission

## Planned Work

- Add use predicates for SliceView, ToRaw, SliceToRaw, boolToUint8, zigoOptionalPointer, activeCallbackHandleCount (and any other helper staticcheck flags); wire emission; update goldens and unit tests; CHANGELOG.

## Done When

- `staticcheck -checks U1000 ./...` is clean in every example module and the verification loop passes.
