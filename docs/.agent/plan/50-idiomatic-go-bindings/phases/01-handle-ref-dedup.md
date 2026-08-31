---
completed_at: "2026-08-31T19:50:36Z"
depends_on:
- "50-idiomatic-go-bindings#0"
perf_phase: false
status: done
---
> DONE-WHEN: Example 10's regenerated tagged-union type file is at least 30% smaller than
> NEXT: none

# Deduplicate handle/ref method bodies

## Planned Work

- Emit one unexported implementation function per projection/operation that
  accepts the `zigoHandle` interface plus the operation label; emit handle and
  ref methods as one-line delegations to it.
- Hoist repeated operation-label strings into the shared implementation so the
  literal appears once per operation.

## Done When

- Example 10's regenerated tagged-union type file is at least 30% smaller than
  before this plan and contains each projection body exactly once.
- `zig build test` and all regenerated example test suites pass.
