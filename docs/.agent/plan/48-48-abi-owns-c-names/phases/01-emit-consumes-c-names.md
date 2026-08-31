---
depends_on:
- "48-48-abi-owns-c-names#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Every generated artifact is byte-identical to before the plan: `zig build
> NEXT: none

# Emitter reads C names from the IR

## Planned Work

- Rewrite the header's opaque and enum typedef loops (`emit.zig:462-486`) to
  iterate `program.handles` and `program.enums` instead of filtering
  `program.types`.
- `writeCMemberType` looks the enum up in `program.enums` for its `c_name`
  rather than minting one.
- `writeUnionCParam` and the cgo cast at `emit.zig:1535` spell the receiver
  from the handle's `c_name`.
- Delete the now-unused `snakeAlloc`/`allocUpperString` calls at
  `emit.zig:467`, `473`, `479`, `483`, `542`, `590`, `1523`, `1553`.

## Done When

- Every generated artifact is byte-identical to before the plan: `zig build
  test` and the golden-artifact comparison pass with no snapshot update.
- `grep -n 'program.prefix' src/gen/emit.zig` returns only sites that are not
  type names, and no `naming.snakeAlloc` call in `emit.zig` feeds a C type or
  constant name.
