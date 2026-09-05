---
description: "Review plan: generalize ownership as a first-class IR concept and evaluate exporting Zig comptime interface patterns as Go interfaces"
plan_status: in-progress
registered_at: "2026-09-05T07:29:55Z"
---
> NEXT: Inventory every ownership path with its lowering fields, emit sites and golden case. ([Phase 0](phases/00-ownership-inventory.md))

# Phases

- [x] [Phase 00: Inventory ownership paths](phases/00-ownership-inventory.md)
- [x] [Phase 01: Ownership design and recommendation](phases/01-ownership-design.md)
- [x] [Phase 02: Comptime interface survey](phases/02-interface-survey.md)
- [x] [Phase 03: Interface design and recommendation](phases/03-interface-design.md)
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

Both reviews are written and linked from `docs/.agent/design/README.md`.

- Ownership (`10-ownership-model.md`): adopt as a lowering-only record.
  `AbiFn.ownership` and `param_ownership` derived from today's semantic
  fields; no `semantic.json` change, no ir_version bump, all goldens
  byte-identical. Automatic `runtime.AddCleanup` needs no work (handles and
  callback tokens already register it; buffers are copy-then-release). The
  arena scope API is deferred until a measurement shows release calls
  above the 10% threshold. Follow-up plan: 4 phases.
- Interfaces (`11-comptime-interfaces.md`): implement the explicit
  `.interfaces` registration over opaque handles only, validated by rendered
  Go signature equality (ZIGO049), emitted as `<pkg>_interfaces_gen.go` with
  compile-time assertions. `anytype` functions and Go generics stay out.
  Minor release (`0.9.0`). Follow-up plan: 4 phases.

Suggested order: ownership record first, then interfaces, since signature
comparison is simpler once ownership is one field on the lowered function.
