---
description: Separate tool probes, share backend contract tests and split runtime emitters without ABI changes
plan_status: in-progress
registered_at: "2026-09-05T11:14:16Z"
---
> NEXT: Begin with tool execution and diagnostic separation. ([Phase 0](phases/00-tool-probes.md))

# Phases

- [x] [Phase 00: Tool probes](phases/00-tool-probes.md)
- [x] [Phase 01: Shared runtime contracts](phases/01-shared-contracts.md)
- [x] [Phase 02: Emitter responsibilities](phases/02-emitter-responsibilities.md)
- [ ] [Phase 03: Lowering and handoff](phases/03-lowering-handoff.md)

# Shared Verification

Zig unit and golden tests, cgo/purego tests, go-check and ABI checks, native zig cc doctor and Windows cross compilation.

# Decisions That Constrain Ordering

Tool probes, shared tests, emitters, then layout lowering and final review.

# Next Implementation Target

Begin with tool execution and diagnostic separation.
