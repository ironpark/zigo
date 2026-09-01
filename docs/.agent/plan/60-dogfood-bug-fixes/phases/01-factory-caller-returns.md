---
completed_at: "2026-09-01T20:39:22Z"
perf_phase: false
status: done
---
> DONE-WHEN: New fixture compiles and its test passes on both backends; the unsupported-payload
> NEXT: none

# Non-constructor caller returns become owned handles

## Planned Work

- Make explicit `.returns = .caller` with an opaque-pointer payload (direct or
  error-union) take the same owned-handle emission path as named constructors,
  regardless of function name: Go returns `*X` built via `newX(...)`, including
  callback-handle plumbing when the function takes callbacks.
- Add a ZIGO diagnostic for `.returns = .caller` payloads that cannot be wrapped
  (non-opaque payload), instead of emitting broken Go.
- Extend a fixture or example with a non-constructor-named factory (e.g. `clone` or
  `openChild`) exercising the path on cgo and purego; update goldens via the case
  runner + `zig build snapshot --update-snapshots`.

## Done When

- New fixture compiles and its test passes on both backends; the unsupported-payload
  case produces the new diagnostic; `zig build test` green; committed.
