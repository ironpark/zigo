---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Focused and full generator tests pass and generated opt-in Go source compiles with Go 1.24+.
> NEXT: none

# Option and safe emission

## Planned Work

- Add build, CLI, generator, and emitter option propagation with a disabled default.
- Emit isolated cleanup state, `runtime.Cleanup`, constructor attachment, `Stop`, shared release logic, and `runtime.KeepAlive` for managed owners.
- Add generator tests proving default compatibility, opt-in placement, no wrapper capture, callback release state, and opaque-argument liveness.

## Done When

- Focused and full generator tests pass and generated opt-in Go source compiles with Go 1.24+.
