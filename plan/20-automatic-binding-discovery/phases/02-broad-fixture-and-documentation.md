---
depends_on:
- "20-automatic-binding-discovery#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Telemetry-hub exposes the same intended API with a substantially smaller declaration and its Zig/Go/generation/ABI checks pass.
> NEXT: none

# Broad fixture and documentation

## Planned Work

- Convert telemetry-hub to automatic discovery while retaining only exceptional metadata.
- Update generated golden files if semantic output intentionally changes.
- Document discovery policy, override precedence, exclusions, limitations, and legacy explicit mode.

## Done When

- Telemetry-hub exposes the same intended API with a substantially smaller declaration and its Zig/Go/generation/ABI checks pass.
