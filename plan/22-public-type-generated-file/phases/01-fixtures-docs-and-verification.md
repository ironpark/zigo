---
depends_on:
- "22-public-type-generated-file#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Repository-wide verification passes, the plan is complete, and the worktree is clean and committed.
> NEXT: none

# Fixtures, documentation, and verification

## Planned Work

- Regenerate golden fixtures and all examples.
- Update generated-file architecture and configuration documentation.
- Run root native/Windows checks plus every example's stale, ABI, Zig, and Go tests where available.

## Done When

- Repository-wide verification passes, the plan is complete, and the worktree is clean and committed.
