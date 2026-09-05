---
perf_phase: false
status: in-progress
---
> DONE-WHEN: No file under `src/gen/emit/` exceeds 3,000 lines.
> NEXT: none

# Split emit.zig by output file

## Planned Work

- Create `src/gen/emit/` with `emit.zig` (public surface), `shim.zig`, `header.zig`,
  `raw_cgo.zig`, `raw_purego.zig`, `callbacks.zig`, `public.zig`, `must.zig`,
  `materialized.zig`, `common.zig` (type writers, names, program predicates).
- Move functions verbatim; mark cross-file helpers `pub`; keep every test next to
  the code it exercises.
- Update `build.zig` module root and `generator.zig` import path.

## Done When

- No file under `src/gen/emit/` exceeds 3,000 lines.
- `zig build test` passes and every generator case golden is unchanged.
