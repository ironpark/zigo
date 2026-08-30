---
depends_on:
- "21-typed-go-callbacks#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Every repository verification passes and planr reports all phases done.
> NEXT: none

# Full compatibility verification

## Planned Work

- Run root tests, formatting, native and Windows compile checks.
- Run stale-generation, ABI, and Go tests for all examples.
- Confirm the worktree and completed plan are clean and committed.

## Done When

- Every repository verification passes and planr reports all phases done.
