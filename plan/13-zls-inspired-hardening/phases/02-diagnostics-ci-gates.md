---
depends_on:
- "13-zls-inspired-hardening#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: A deliberately changed expected fixture reports the changed content and path without an uncaptured failed-command banner.
> NEXT: none

# Improve failure diagnostics and CI gates

## Planned Work

- Render compact line-oriented detail for snapshot content mismatches while keeping intentional child-process failures captured.
- Separate diagnostic rendering from CLI termination and provide actionable generator usage/error output where appropriate.
- Add formatting and compile-only checks ahead of the full test/stale-artifact checks in CI.
- Evaluate a Windows compile job and add it only if the existing cgo/toolchain boundary can be represented reliably.

## Done When

- A deliberately changed expected fixture reports the changed content and path without an uncaptured failed-command banner.
- CI runs `zig fmt --check`, `zig build check`, the existing test suite, and stale generated-output verification in a clear order.
- CLI parsing/validation failures produce concise user-facing diagnostics and all tests pass.
