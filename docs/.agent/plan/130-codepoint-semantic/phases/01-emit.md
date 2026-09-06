---
completed_at: "2026-09-06T02:33:36Z"
depends_on:
- "130-codepoint-semantic#0"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` passes and the new cases' expected output is committed via `scripts/update-generator-cases.sh`.
> NEXT: none

# Public emission and generator cases

## Planned Work

- Public parameter/return spelling `rune` / `[]rune`; range checks add `< 0` for codepoints; call arguments and results convert; slice reinterpretation helpers emitted only when used.
- Generator case `codepoint` and `codepoint_purego` covering scalar in/return/error/optional, slice in/out/return with release, and a `u21` range failure.

## Done When

- `zig build test` passes and the new cases' expected output is committed via `scripts/update-generator-cases.sh`.
