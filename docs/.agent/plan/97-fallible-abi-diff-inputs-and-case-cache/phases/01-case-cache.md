---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Editing a case's `semantic.json` or expected file reruns its step on the next `zig build test`; full loop green.
> NEXT: none

# generator case cache correctness

## Planned Work

- Reproduce the stale cache, fix the input declaration in `addGeneratorCases`, verify a change under a case directory reruns the step, update `docs/development.md` if needed.

## Done When

- Editing a case's `semantic.json` or expected file reruns its step on the next `zig build test`; full loop green.
