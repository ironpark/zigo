---
depends_on:
- "51-sealed-union-variants#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Example 10's `Signal` variant builder performs a single native call
> NEXT: none

# Snapshot fast path for scalar-only unions

## Planned Work

- For unions the generator already classifies as snapshot-eligible, build the
  variant from one `raw.<Union>ReadSnapshot` call instead of tag +
  projection; non-eligible unions keep the phase-0 strategy.
- Add a golden fixture asserting the scalar-only union's builder contains
  exactly one raw call.

## Done When

- Example 10's `Signal` variant builder performs a single native call
  (verified in the golden and by grepping the regenerated file); `Value`
  still uses tag + matching projection.
- `zig build test` passes.
