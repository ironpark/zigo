---
perf_phase: false
status: in-progress
---
> DONE-WHEN: A registration with `.fields` produces semantic.json entries for each accessor; bad paths and types produce the diagnostic; `zig build test` green.
> NEXT: none

# Reflect and validate fields

## Planned Work

- Add `.fields` to the type entry schema in `walk.zig`; resolve dotted paths at comptime; synthesize getter/setter `SemanticFn`s with an origin marker (`.field_access = .{ .path, .setter }` or equivalent) in `semantic.zig`.
- New diagnostic for unsupported field types and unknown paths with snapshot tests in `validate.zig` or the reflect test suite; document it in `docs/limitations.md` diagnostics table.
- Unit tests for path resolution across nested structs and through a single pointer hop.

## Done When

- A registration with `.fields` produces semantic.json entries for each accessor; bad paths and types produce the diagnostic; `zig build test` green.
