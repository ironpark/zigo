---
completed_at: "2026-09-10T05:11:58Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` passes.
> NEXT: none

# Remove state and guards the Rust emitter does not need

## Planned Work

- Delete `Shape.Input.source_index` and `Shape.inputFor`; index `shape.inputs`
  directly at the three call sites, which already hold the source index.
- Delete `Shape.Input.text`; `writeRawType` reads `element.text` from the
  capture it already has.
- Drop the discarded `is_many` parameter from `writeRawPointee`.
- Drop the unused `program` parameter from `types.sliceElement` and
  `types.elementScalar`.
- Remove the three unreachable `types.unsupported(...) != null` skip guards in
  `renderRaw`, `renderExternBlock` and `renderLib`, leaving `unsupportedIssues`
  as the single call site. Note in the comment there that the gate is upstream
  in `appendRustCrate`.
- Hoist the three inline `@import("../emit/type_spelling.zig")` expressions in
  `Shape.of` to a file-level const beside the other imports.
- Delete the unused `const words` alias in `public.zig`.
- Correct `Shape.of`'s doc comment, which claims the shape is computed once
  while both wrappers call it.

## Done When

- `zig build test` passes.
- `scripts/update-generator-cases.sh` leaves `tests/generator_cases` clean.
- `grep -n "source_index\|inputFor" src/gen/emit_rust/raw.zig` matches only the
  `abi` parameter field the call sites read.
- `types.unsupported` has one caller.
