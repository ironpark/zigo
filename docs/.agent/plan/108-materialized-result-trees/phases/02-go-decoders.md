---
completed_at: "2026-09-03T07:15:17Z"
depends_on:
- "108-materialized-result-trees#1"
perf_phase: false
status: done
---
> DONE-WHEN: Both backends decode the case's tree into identical Go values with one native call plus one release.
> NEXT: none

# Go decoders on cgo and purego

## Planned Work

- Generated public Go structs and decoder for cgo and purego; slice-of-trees decode from one buffer; `.direction = .out` buffer reuse; generator case Go goldens; unit tests in `emit.zig`.

## Done When

- Both backends decode the case's tree into identical Go values with one native call plus one release.
