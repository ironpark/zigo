---
description: "Make the purego callback-invoke hot path lock-free: sync.Map registry matching cgo.Handle semantics, plus drop the redundant sync.Once in Close"
plan_status: in-progress
registered_at: "2026-09-01T11:56:49Z"
---
> NEXT: Replace the purego callback registry's global mutex with a sync.Map lookup. ([Phase 0](phases/00-lockfree-registry.md))

# Phases

- [x] [Phase 00: Lock-free registry lookup](phases/00-lockfree-registry.md)
- [ ] [Phase 01: Drop the redundant Close once and regenerate](phases/01-drop-close-once.md)

# Shared Verification

- `zig build test` after every phase (emit unit tests, cgo and purego
  goldens).
- Callback-example purego suites after phase 0 (with `ZIGO_TEST_LIBRARY`
  where needed); full fourteen-tree sweep plus `-race` cgo runs after
  phase 1.
- Grep checks: no `callbackRegistryMu` and no `sync.Once` in any
  regenerated `*_gen.go`; the invariant comment present in purego raw
  output.

# Decisions That Constrain Ordering

Phase 0 is the substantive concurrency change and lands with its own tests;
phase 1 is the small template cleanup and the repo-wide regeneration sweep.

# Next Implementation Target

Replace the purego callback registry's global mutex with a sync.Map lookup.
