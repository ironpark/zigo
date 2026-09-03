---
completed_at: "2026-09-03T02:03:35Z"
depends_on:
- "96-abi-classification-in-lowering#1"
perf_phase: false
status: done
---
> DONE-WHEN: `abi_diff.zig` no longer re-models lowering; all abi-diff tests unchanged and green.
> NEXT: none

# abi-diff over lowered programs

## Planned Work

- Lower both documents for the requested backends and compare lowered functions/handles/structs for C-shape equality; keep semantic comparison for names, packages, docs, and anything lowering drops; remove the hand-modelled ignore rules from `typeEqual`; keep every existing abi-diff test result identical and add a test proving a lowering-invisible change (for example a sentinel annotation) stays compatible through the new path.

## Done When

- `abi_diff.zig` no longer re-models lowering; all abi-diff tests unchanged and green.
