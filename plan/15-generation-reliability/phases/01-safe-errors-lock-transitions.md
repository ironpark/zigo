---
depends_on:
- "15-generation-reliability#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Every unsafe lock state or transition is rejected without output mutation,
> NEXT: none

# Safe errors.lock state transitions

## Planned Work

- Validate the supported lock version, exact reserved mapping, code bounds and
  uniqueness, and append-only transition invariants; add malformed and transition
  tests plus actionable generator behavior.

## Done When

- Every unsafe lock state or transition is rejected without output mutation,
  valid addition/deletion histories preserve codes, and focused/full tests pass.
