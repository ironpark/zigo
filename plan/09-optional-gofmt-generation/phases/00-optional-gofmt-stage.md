---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Root Zig tests, all example generation/check/ABI steps, and all Go tests pass; build output confirms formatter execution where installed; `git diff --check` is clean.
> NEXT: none

# Optional gofmt stage

## Planned Work

- Add optional `gofmt` discovery and immutable formatted outputs to the build graph, route update/check inputs through them, document behavior, and run regression verification.

## Done When

- Root Zig tests, all example generation/check/ABI steps, and all Go tests pass; build output confirms formatter execution where installed; `git diff --check` is clean.
