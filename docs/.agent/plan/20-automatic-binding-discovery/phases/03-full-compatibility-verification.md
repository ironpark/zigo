---
completed_at: "2026-08-30T05:57:59Z"
depends_on:
- "20-automatic-binding-discovery#2"
perf_phase: false
status: done
---
> DONE-WHEN: All repository checks pass and the worktree contains only the committed implementation and plan status updates.
> NEXT: none

# Full compatibility verification

## Planned Work

- Run the root unit, snapshot, formatting, native/cross-target compile, and all example Go/generation checks.
- Fix regressions without widening discovery semantics.

## Done When

- All repository checks pass and the worktree contains only the committed implementation and plan status updates.
