---
perf_phase: false
status: in-progress
---
> DONE-WHEN: API counts meet the target; Zig tests, `go-check`, post-commit `abi-check`, Go
> NEXT: none

# Broad telemetry API example

## Planned Work

- Implement, bind, generate, inspect, and comprehensively test the 40+ operation
  telemetry hub; document its surface, register it in CI, and validate regeneration
  plus repository compatibility.

## Done When

- API counts meet the target; Zig tests, `go-check`, post-commit `abi-check`, Go
  tests, all example checks, root tests, Windows compile, formatting, diff checks,
  and clean regeneration pass.
