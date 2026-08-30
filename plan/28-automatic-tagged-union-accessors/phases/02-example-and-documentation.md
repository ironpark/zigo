---
depends_on:
- "28-automatic-tagged-union-accessors#1"
perf_phase: false
status: planned
---
> DONE-WHEN: Example Zig tests, generation/stale checks, Go tests, ABI checks, and the full root test graph pass.
> NEXT: none

# End-to-end example and documentation

## Planned Work

- Add a focused example with owned and borrowed tagged-union handles and multiple payload forms.
- Commit generated semantic/Go artifacts and Go behavior tests.
- Document declaration syntax, lifetime rules, supported payloads, diagnostics, and ABI compatibility behavior; wire the example into CI.

## Done When

- Example Zig tests, generation/stale checks, Go tests, ABI checks, and the full root test graph pass.
