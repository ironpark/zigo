---
description: Isolate ownership lowering and handle emission, and share lifecycle race contracts without ABI changes
plan_status: in-progress
registered_at: "2026-09-05T11:27:17Z"
---
> NEXT: Start with ownership lowering. ([Phase 0](phases/00-ownership-lowering.md))

# Phases

- [x] [Phase 00: Ownership lowering](phases/00-ownership-lowering.md)
- [x] [Phase 01: Handle emitter](phases/01-handle-emitter.md)
- [ ] [Phase 02: Lifecycle contracts](phases/02-lifecycle-contracts.md)

# Shared Verification

Full Zig/golden tests, example generation and ABI checks, cgo/purego tests, race detector and Windows compile checks.

# Decisions That Constrain Ordering

Ownership, emitter, shared contracts and integration.

# Next Implementation Target

Start with ownership lowering.
