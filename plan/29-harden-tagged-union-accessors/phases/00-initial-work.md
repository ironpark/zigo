---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Focused and full Zig tests pass, proving unsupported payloads fail before emission and generated cleanup-enabled accessors preserve liveness.
> NEXT: none

# Lifetime and payload validation

## Planned Work

- Add accessor `runtime.KeepAlive` coverage for owned and borrowed wrappers under auto cleanup.
- Restrict scalar and numeric-slice payload widths to types that every Zig/C/cgo/Go emitter represents.
- Add focused validation/emitter tests for invalid widths and cleanup output.

## Done When

- Focused and full Zig tests pass, proving unsupported payloads fail before emission and generated cleanup-enabled accessors preserve liveness.
