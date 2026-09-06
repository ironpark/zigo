---
completed_at: "2026-09-06T06:16:30Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` passes and example 12 `go test` passes on both backends.
> NEXT: none

# Layout version 2 with recursive shapes

## Planned Work

- Replace `Field.Kind` with `Shape`; compute natural widths, alignment and
  record sizes in lowering; bump the version and magic.
- Reflect `[N]T` fields as sequences, `?Node` as a nullable inline node, and
  `.field_meta` `.semantic = .opaque_bytes` on materialized entries.
- Validation accepts extern/packed value structs, nested slices and arrays.
- Rewrite the Zig encoder and Go decoder recursively over shapes.
- Update the `materialized` cases, round trip and example 12 tests.

## Done When

- `zig build test` passes and example 12 `go test` passes on both backends.
