---
depends_on:
- "29-harden-tagged-union-accessors#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Runtime/process tests show wrong variants preserve outputs and closed/nil handles do not abort; emitter tests show Zig panics map to a distinct projection status.
> NEXT: none

# Lifecycle and panic boundary

## Planned Work

- Route projections through the panic containment layer with distinct mismatch, invalid-handle, success, and panic status.
- Prevent nil/closed public wrappers from reaching Zig and define stable Go behavior.
- Document caller synchronization requirements and test out-parameter preservation.

## Done When

- Runtime/process tests show wrong variants preserve outputs and closed/nil handles do not abort; emitter tests show Zig panics map to a distinct projection status.
