---
completed_at: "2026-09-03T04:47:40Z"
perf_phase: false
status: done
---
> DONE-WHEN: A registered packed struct crosses in every listed position on both backends with Go tests; goldens unchanged elsewhere.
> NEXT: none

# Packed struct values

## Planned Work

- Registration, validation, lowering as backing scalar, mirror emission for standalone registrations, conversions at every scalar position, abi-diff rules, tests, example, docs, CHANGELOG.

## Done When

- A registered packed struct crosses in every listed position on both backends with Go tests; goldens unchanged elsewhere.
