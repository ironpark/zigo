---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Emitter no longer scans for slots/flatten indexes/omitted variants/packed layout; goldens and examples unchanged; tests green.
> NEXT: none

# Slots, flatten indexes, omitted variants, packed layout

## Planned Work

- Add the IR fields, populate them in `lower.zig` with the existing ordering rules, replace the emitter scans and guards with field reads, delete the dead helpers. Add unit tests in `lower.zig` for slot numbering and flatten indexes.

## Done When

- Emitter no longer scans for slots/flatten indexes/omitted variants/packed layout; goldens and examples unchanged; tests green.
