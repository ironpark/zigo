---
depends_on:
- "154-binding-authoring-v2#1"
perf_phase: false
status: planned
---
> DONE-WHEN: All in-repository consumers use the new public authoring API and the full test suite passes.
> NEXT: none

# Switch public API and migrate consumers

## Planned Work

- Make define normalize the new Binding; keep the old data structs internal to reflection.
- Replace old DSL exports, migrate all example and fixture bindings, and integrate plugin target declarations.
- Verify examples preserve generated behavior and run the complete tests.

## Done When

- All in-repository consumers use the new public authoring API and the full test suite passes.
