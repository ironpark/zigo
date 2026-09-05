---
depends_on:
- "118-boundary-refactor#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Both backends execute the same tests including race checks where supported.
> NEXT: none

# Shared runtime contracts

## Planned Work

- Extract reader contract tests into a shared test module consumed by cgo and purego; keep thin backend adapters.

## Done When

- Both backends execute the same tests including race checks where supported.
