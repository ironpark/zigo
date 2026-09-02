---
completed_at: "2026-09-02T23:42:22Z"
perf_phase: false
status: done
---
> DONE-WHEN: A boxed value `init(gpa, Options)` binds as `NewTerminal(cols, rows, ...)` on both backends; verification loop green.
> NEXT: none

# Flatten struct parameters

## Planned Work

- Schema, reflection with default-value check and diagnostic, IR, validation, lowering, emit (cgo/purego), generator case, example test constructing through a flattened options struct, docs, CHANGELOG.

## Done When

- A boxed value `init(gpa, Options)` binds as `NewTerminal(cols, rows, ...)` on both backends; verification loop green.
