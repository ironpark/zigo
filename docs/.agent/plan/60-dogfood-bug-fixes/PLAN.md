---
description: "Fix four dogfooding bugs: non-constructor caller returns, prune walking .zig-cache, optional pointer params, doubled doc comments"
plan_status: in-progress
registered_at: "2026-09-01T20:29:12Z"
---
> NEXT: Skip `.zig-cache`/`zig-out` in the prune and check walks with a regression test. ([Phase 0](phases/00-prune-skip-caches.md))

# Phases

- [x] [Phase 00: Prune and check skip build caches](phases/00-prune-skip-caches.md)
- [x] [Phase 01: Non-constructor caller returns become owned handles](phases/01-factory-caller-returns.md)
- [x] [Phase 02: Optional opaque-pointer parameters](phases/02-optional-pointer-params.md)
- [ ] [Phase 03: Doc comment de-duplication](phases/03-doc-comment-dedup.md)

# Shared Verification

- `zig build test` after every phase.
- Golden updates only through the case runner + `zig build snapshot
  --update-snapshots` (never hand-edit or gofmt goldens).
- Phase 0: targeted prune regression test.
- Phases 1-2: fixture tests on both cgo and purego backends; cross-check windows
  targets still build (`zig build check` cross steps in CI).
- CI green on all jobs before marking the plan done.

# Decisions That Constrain Ordering

Phase 0 first (field data loss, smallest). Phases 1, 2, 3 are independent of each
other and of phase 0; suggested order 1 → 2 → 3 by severity, but any order is valid.

# Next Implementation Target

Skip `.zig-cache`/`zig-out` in the prune and check walks with a regression test.
