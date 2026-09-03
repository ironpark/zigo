---
description: append concrete fix suggestions to naming diagnostics and record callback reentrancy and thread contracts in Go docs
plan_status: in-progress
registered_at: "2026-09-02T22:15:54Z"
---
> NEXT: Add `note` lines to naming diagnostics. ([Phase 0](phases/00-diagnostic-notes.md))

# Phases

- [x] [Phase 00: Diagnostic notes](phases/00-diagnostic-notes.md)
- [ ] [Phase 01: Callback contract metadata](phases/01-callback-contract.md)

# Shared Verification

Standard loop (see plan 87-field-accessors VERIFICATION).

# Decisions That Constrain Ordering

Phases are independent; do 0 then 1.

# Next Implementation Target

Add `note` lines to naming diagnostics.
