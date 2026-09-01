---
completed_at: "2026-09-01T11:43:54Z"
description: "Close the last lifecycle gap: union projections and Ref methods take the handle read lock via a zigoLocker accessor on the zigoHandle interface"
plan_status: done
registered_at: "2026-09-01T11:35:48Z"
---
> NEXT: Add the zigoLocker accessor and lock the shared projection implementations. ([Phase 0](phases/00-locker-accessor.md))

# Phases

- [x] [Phase 00: Locker accessor and locked projection prologues](phases/00-locker-accessor.md)
- [x] [Phase 01: Race coverage and documentation](phases/01-race-tests-and-docs.md)

# Shared Verification

- `zig build test` after every phase (emit unit tests, goldens for cgo and
  purego).
- `go test -race` on example 10 in both phases; full fourteen-tree sweep in
  phase 1.
- Grep checks: every `func zigo<Union>...(receiver zigoHandle` body
  acquires the locker before `zigoCheckedPointer`; `docs/limitations.md`
  no longer mentions unlocked projections.

# Decisions That Constrain Ordering

Phase 0 lands the mechanism behind the guarantee; phase 1 proves it under
the race detector, sweeps the repo, and retires the documented limitation.

# Next Implementation Target

Add the zigoLocker accessor and lock the shared projection implementations.
