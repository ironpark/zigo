---
completed_at: "2026-09-02T23:42:22Z"
description: flatten selected fields of a struct parameter into scalar arguments so value init with an options struct binds without a facade
plan_status: done
registered_at: "2026-09-02T22:15:54Z"
---
> NEXT: Implement `.flatten` on struct parameters. ([Phase 0](phases/00-flatten-params.md))

# Phases

- [x] [Phase 00: Flatten struct parameters](phases/00-flatten-params.md)

# Shared Verification

Standard loop (see plan 87-field-accessors VERIFICATION).

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Implement `.flatten` on struct parameters.
