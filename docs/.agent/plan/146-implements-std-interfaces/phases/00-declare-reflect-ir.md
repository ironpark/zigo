---
completed_at: "2026-09-07T08:06:47Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test -Dtest-filter=implements` passes with the new reflection and IR tests;
> NEXT: none

# Declaration, reflection, IR

## Planned Work

- Add `Implements` enum and the `implements` field to `Function` and `FunctionOptions`
  in `src/declare.zig`; overlay it in `src/dsl.zig` where other options are merged.
- Copy it in `src/reflect/walk.zig` next to the `.iterator` copy; add a reflection test
  asserting the JSON carries `"implements": "writer"`.
- Add `SemanticFn.implements` with serialize/parse in `src/gen/ir/semantic.zig` and a
  round-trip test; keep absence = null.

## Done When

- `zig build test -Dtest-filter=implements` passes with the new reflection and IR tests;
  every existing golden still parses and re-serializes without diff.
