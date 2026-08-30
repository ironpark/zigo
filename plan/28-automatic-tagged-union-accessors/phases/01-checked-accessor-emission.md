---
depends_on:
- "28-automatic-tagged-union-accessors#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Emitter golden/unit tests prove no union layout crosses C, accessors check tags before payload reads, and generated Go compiles.
> NEXT: none

# Checked accessor emission

## Planned Work

- Treat tagged unions as opaque handles in Zig/C/cgo/Go type emission.
- Generate C symbols, shim bodies, raw Go bridges, and public `Tag`/`As*` methods for owned and borrowed handles.
- Cover void, scalar, enum, opaque-pointer, and scalar-slice variants plus mismatch behavior and naming collisions.

## Done When

- Emitter golden/unit tests prove no union layout crosses C, accessors check tags before payload reads, and generated Go compiles.
