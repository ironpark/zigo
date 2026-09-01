---
perf_phase: false
status: planned
---
> DONE-WHEN: Unit tests pass; no golden doc comment repeats a declaration name; `zig build test`
> NEXT: none

# Doc comment de-duplication

## Planned Work

- In writeGoDoc (src/gen/emit.zig), when the first word of the user doc equals the
  declaration's original Zig name or Go name (case-insensitive), drop it before the
  standard `// GoName ...` prefixing; keep continuesSentence behavior for the rest.
- Cover with emitter unit tests (name-leading doc, capitalized variant, unrelated
  first word) and refresh affected goldens/examples via the case runner + snapshot
  update.

## Done When

- Unit tests pass; no golden doc comment repeats a declaration name; `zig build test`
  green; committed.
