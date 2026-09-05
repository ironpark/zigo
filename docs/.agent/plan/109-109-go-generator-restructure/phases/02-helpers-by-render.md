---
depends_on:
- "109-109-go-generator-restructure#0"
perf_phase: false
status: planned
---
> DONE-WHEN: None of the listed predicates remain.
> NEXT: none

# Helper references from rendered text

## Planned Work

- Introduce `ReferencedHelpers` in `emit/common.zig`: render function bodies
  into a buffer, then decide helper emission by scanning for each helper's Go
  identifier, the way `writePublicImports` already decides imports.
- Delete `programUsesStructToRaw`, `programUsesStructFromRaw`,
  `programUsesStructSlice`, `programReturnsStructSlice`, `structConversionReaches`,
  `parameterStartsStructToRaw`, `nodeUsesBoolHelper`, `structConversionUsesBool`,
  `programUsesOptionalPointer`, `programUsesCallbackDiagnostics`,
  `programUsesMaterializedType`, `materializedRootUse`.
- Keep nested-struct conversions reachable: a conversion that references
  another conversion is itself rendered and scanned until the set is stable.

## Done When

- None of the listed predicates remain.
- Goldens unchanged, including the `referenced_helpers` cases; `zig build test` green.
