---
completed_at: "2026-09-01T11:32:06Z"
description: "Unify the two generated handle lifecycles: every owned handle gets RWMutex Close-serialization plus the AddCleanup GC safety net, selected per type not per program"
plan_status: done
registered_at: "2026-09-01T11:14:45Z"
---
> NEXT: Unify the two handle lifecycle emission paths into one per-type template. ([Phase 0](phases/00-unify-template.md))

# Phases

- [x] [Phase 00: Unify the handle template per type](phases/00-unify-template.md)
- [x] [Phase 01: Lifecycle tests: race and GC reclamation](phases/01-lifecycle-tests.md)
- [x] [Phase 02: Regenerate all examples and document the lifecycle](phases/02-regen-and-docs.md)

# Shared Verification

- `zig build test` after every phase (emit unit tests and goldens, cgo and
  purego).
- `go test -race` on examples 04 and 10 in phase 1; full fourteen-tree sweep
  (`go test`, `gofmt -l`, `go vet`) in phase 2.
- Grep checks in phase 2: `mu\s+sync.RWMutex` and `cleanup runtime.Cleanup`
  in every owned handle; `callbackHandles` only where the type owns
  callbacks.

# Decisions That Constrain Ordering

Phase 0 changes emission; phase 1 locks the new guarantees in with tests
before the repo-wide sweep; phase 2 regenerates everything and documents the
result.

# Next Implementation Target

Unify the two handle lifecycle emission paths into one per-type template.
