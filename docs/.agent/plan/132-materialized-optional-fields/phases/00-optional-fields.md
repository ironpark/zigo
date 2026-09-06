---
completed_at: "2026-09-06T05:56:59Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` and example 12 `go test` on both backends pass.
> NEXT: none

# Optional scalar and string fields

## Planned Work

- Accept the two optional shapes in validation with a specific reason for
  the rest.
- Add the two kinds to the layout, lowering, encoder and decoder.
- Extend the `materialized` case (semantic, target, roundtrip, expected) and
  example 12 (fields, tests on both backends, regenerated Go).
- Update docs and CHANGELOG.

## Done When

- `zig build test` and example 12 `go test` on both backends pass.
