---
depends_on:
- "136-binding-declaration-defaults#0"
- "136-binding-declaration-defaults#1"
- "136-binding-declaration-defaults#2"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test --summary all` passes, `zig fmt --check` is clean, examples
> NEXT: none

# Integrate, document and land

## Planned Work

- Merge the three phases, resolve the overlaps in `walk.zig`, and run the whole
  suite plus the examples.
- Document each default with its opt-out in the type, function and callback
  guides, add the rows to the cheatsheet, and write the changelog entry.

## Done When

- `zig build test --summary all` passes, `zig fmt --check` is clean, examples
  build and their goldens are current, and the docs describe every new key.
