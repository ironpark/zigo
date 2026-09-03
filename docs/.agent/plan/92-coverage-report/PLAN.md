---
completed_at: "2026-09-03T00:12:11Z"
description: add a go-coverage build step listing unbound public declarations with a reason
plan_status: done
registered_at: "2026-09-02T22:15:54Z"
---
> NEXT: Implement the coverage walk and `go-coverage` step. ([Phase 0](phases/00-coverage-mode.md))

# Phases

- [x] [Phase 00: Coverage mode](phases/00-coverage-mode.md)

# Shared Verification

Standard loop (see plan 87-field-accessors VERIFICATION) plus running `go-coverage` on every example.

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Implement the coverage walk and `go-coverage` step.
