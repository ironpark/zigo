---
completed_at: "2026-09-03T05:35:58Z"
description: convert slices of narrow integers such as []const u21 in the shim instead of rejecting them with ZIGO018
plan_status: done
registered_at: "2026-09-03T03:27:39Z"
---
> NEXT: Convert narrow integer slice elements in the shim. ([Phase 0](phases/00-narrow-slices.md))

# Phases

- [x] [Phase 00: Narrow integer slice elements](phases/00-narrow-slices.md)

# Shared Verification

Standard loop (see plan 100-packed-struct-values VERIFICATION).

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Convert narrow integer slice elements in the shim.
