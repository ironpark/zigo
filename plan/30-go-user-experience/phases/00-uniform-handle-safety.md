---
perf_phase: false
status: in-progress
---
> DONE-WHEN: No generated public call passes an opaque `.ptr` directly to raw code.
> NEXT: none

# Uniform Handle Safety and Checked Projections

## Planned Work

- Emit pointer validation for every opaque owner and borrowed reference, then route ordinary receivers and opaque parameters through it before raw calls.
- Add exported typed lifecycle/native projection errors with `errors.Is` support.
- Generate `TryTag` and `TryAs*` checked methods; retain `Tag` and `As*` as compatible convenience methods that panic with typed errors.
- Add emitter and executable Go tests for nil, closed, parent-invalid, mismatch, native panic, and valid-call behavior.

## Done When

- No generated public call passes an opaque `.ptr` directly to raw code.
- Checked projection tests distinguish mismatch, invalid handle, and native panic without string matching, existing projection APIs still work, and focused Zig plus Go tests pass.
