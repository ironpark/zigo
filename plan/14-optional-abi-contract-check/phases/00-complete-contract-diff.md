---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Every newly covered contract change produces `hasBreaking() == true`, unchanged documents remain empty, and focused/full Zig tests pass.
> NEXT: none

# Complete semantic contract comparison

## Planned Work

- Compare IR version, package, prefix, exported function symbols, and constructor mappings in addition to the existing signature and ownership rules.
- Define deterministic breaking report subjects and details for each new comparison.
- Add focused positive and negative tests, including allocation-failure coverage of the expanded report.

## Done When

- Every newly covered contract change produces `hasBreaking() == true`, unchanged documents remain empty, and focused/full Zig tests pass.
