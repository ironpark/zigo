---
description: Audit canonical Zig type implementations, semantic ownership, declaration forms, public paths, visibility, and physical/file placement without changing source.
plan_status: in-progress
registered_at: "2026-08-30T01:37:48Z"
---
> NEXT: Inventory and assess every production Zig type without changing implementation code. ([Phase 0](phases/00-inventory-and-assess.md))

# Phases

- [ ] [Phase 00: Inventory and assess production types](phases/00-inventory-and-assess.md)

# Shared Verification

Compare the assessment count and locations to `ziglyzer --types src` plus the root-level `build.zig` inventory; inspect explicit-root reports; run `zig build test --summary all`; run `git diff --check`; confirm no production Zig source changed.

# Decisions That Constrain Ordering

This is a single audit phase because inventory, path tracing, and assessment must remain consistent as one evidence set.

# Next Implementation Target

Inventory and assess every production Zig type without changing implementation code.
