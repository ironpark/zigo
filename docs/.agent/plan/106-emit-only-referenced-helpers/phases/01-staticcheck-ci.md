---
completed_at: "2026-09-03T06:29:07Z"
depends_on:
- "106-emit-only-referenced-helpers#0"
perf_phase: false
status: done
---
> DONE-WHEN: CI runs staticcheck on all example modules and passes.
> NEXT: none

# staticcheck in CI

## Planned Work

- Install `staticcheck` in the CI test job and run `-checks U1000` over every example go.mod (cgo and purego); document the check in `docs/contributing` or the README development section.

## Done When

- CI runs staticcheck on all example modules and passes.
