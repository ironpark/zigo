---
depends_on:
- "207-zig-0-17-migration#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test` passes on 0.17.0.
> NEXT: none

# Language and std changes in src and tests

## Planned Work

- Port `@typeInfo` readers to the struct-of-arrays layout.
- Replace `**`, and port any other std API changes the compiler reports in
  src, tests, and the Zig the generator emits.

## Done When

- `zig build test` passes on 0.17.0.
