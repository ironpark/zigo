---
completed_at: "2026-08-30T11:15:31Z"
description: Harden generated tagged-union projections across lifetime safety, ABI modeling, panic/closed-handle behavior, diff classification, and adversarial tests.
plan_status: done
registered_at: "2026-08-30T10:42:00Z"
---
> NEXT: Harden accessor lifetime and payload-width validation before restructuring the ABI model. ([Phase 0](phases/00-initial-work.md))

# Phases

- [x] [Phase 00: Lifetime and payload validation](phases/00-initial-work.md)
- [x] [Phase 01: Projection ABI IR](phases/01-projection-abi-ir.md)
- [x] [Phase 02: Lifecycle and panic boundary](phases/02-lifecycle-panic-boundary.md)
- [x] [Phase 03: ABI classification and adversarial matrix](phases/03-abi-and-adversarial-tests.md)

# Shared Verification

Use filtered Zig tests per phase, then `zig build check test --summary all`. Regenerate and check example 10, run its Go tests including lifecycle cases, run all example Zig/stale checks and all Go tests, and finish with ABI checks against committed baselines.

# Decisions That Constrain Ordering

Close immediate correctness gaps first. Establish one lowered projection model before changing boundary status handling. Refine ABI compatibility only after the final projection contract is stable.

# Next Implementation Target

Harden accessor lifetime and payload-width validation before restructuring the ABI model.
