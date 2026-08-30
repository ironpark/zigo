---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Root Zig tests pass, the colocated example passes generation/check/ABI and Go tests, no `_raw_gen.go` colocated references remain, and `git diff --check` is clean.
> NEXT: none

# Rename colocated cgo output

## Planned Work

- Change both generated-path implementations, update regression expectations and documentation, rename the committed example artifact, and verify Zig and Go builds.

## Done When

- Root Zig tests pass, the colocated example passes generation/check/ABI and Go tests, no `_raw_gen.go` colocated references remain, and `git diff --check` is clean.
