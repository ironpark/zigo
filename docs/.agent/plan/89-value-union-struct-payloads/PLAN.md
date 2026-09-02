---
description: widen by-value tagged unions to C-representable struct payloads, omitted variants, and value returns
plan_status: in-progress
registered_at: "2026-09-02T22:15:54Z"
---
> NEXT: Accept struct payloads and omitted variants in by-value unions. ([Phase 0](phases/00-struct-payloads.md))

# Phases

- [ ] [Phase 00: Struct payloads and omitted variants](phases/00-struct-payloads.md)
- [ ] [Phase 01: Value union returns](phases/01-value-returns.md)

# Shared Verification

Standard loop (see plan 87-field-accessors VERIFICATION).

# Decisions That Constrain Ordering

Phase 0 then 1.

# Next Implementation Target

Accept struct payloads and omitted variants in by-value unions.
