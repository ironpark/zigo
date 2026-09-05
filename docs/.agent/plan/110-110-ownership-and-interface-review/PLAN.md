---
depends_on:
- go-generator-restructure
description: "Review plan: generalize ownership as a first-class IR concept and evaluate exporting Zig comptime interface patterns as Go interfaces"
plan_status: in-progress
registered_at: "2026-09-05T07:29:55Z"
---
> NEXT: Inventory every ownership path with its lowering fields, emit sites and golden case. ([Phase 0](phases/00-ownership-inventory.md))

# Phases

- [ ] [Phase 00: Inventory ownership paths](phases/00-ownership-inventory.md)
- [ ] [Phase 01: Ownership design and recommendation](phases/01-ownership-design.md)
- [ ] [Phase 02: Comptime interface survey](phases/02-interface-survey.md)
- [ ] [Phase 03: Interface design and recommendation](phases/03-interface-design.md)
- [ ] [Phase 04: Index and hand-off](phases/04-index-and-handoff.md)

# Shared Verification

- Design documents only: verify each cited symbol and golden case exists
  (`grep` the cited names in `src/` and `tests/generator_cases`).
- `zig build test` stays green (no code changes expected; run once at the end
  to prove the tree is untouched).

# Decisions That Constrain Ordering

Phases 0 and 2 are independent surveys and can run in parallel. Phase 1
follows 0, phase 3 follows 2. Phase 4 closes. Ownership first if serialised:
its answer affects how interface methods that return native memory would be
described.

# Next Implementation Target

Inventory every ownership path with its lowering fields, emit sites and golden case.
