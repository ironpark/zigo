---
completed_at: "2026-09-07T06:08:17Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig fmt --check` and `zig build test --summary all` pass, examples show both helpers, and the committed tree contains no wildcard path in a resulting `zigo.Function`.
> NEXT: none

# Initial Work

## Planned Work

- Implement and export `zigo.dsl.func` and `zigo.dsl.funcs` with typed selector/options structures.
- Add compile-time unit tests and user-facing documentation examples.
- Run formatting and the full Zig test suite.

## Done When

- `zig fmt --check` and `zig build test --summary all` pass, examples show both helpers, and the committed tree contains no wildcard path in a resulting `zigo.Function`.
