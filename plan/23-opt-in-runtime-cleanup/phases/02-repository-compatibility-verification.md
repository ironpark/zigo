---
depends_on:
- "23-opt-in-runtime-cleanup#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Default Go 1.23 examples and the Go 1.24 cleanup example all pass repository-wide verification.
> NEXT: none

# Repository compatibility verification

## Planned Work

- Regenerate affected fixtures and examples.
- Run root native and Windows checks, formatting, all example stale/ABI checks, all Go tests, and available example Zig tests.
- Confirm plan completion and a clean committed worktree.

## Done When

- Default Go 1.23 examples and the Go 1.24 cleanup example all pass repository-wide verification.
