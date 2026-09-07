---
completed_at: "2026-09-07T13:12:49Z"
depends_on:
- "154-binding-authoring-v2#1"
perf_phase: false
status: done
---
> DONE-WHEN: All in-repository consumers use the new public authoring API and the full test suite passes.
> NEXT: none

# Switch public API and migrate consumers

## Planned Work

- Make define normalize the new Binding; keep the old data structs internal to reflection.
- Replace old DSL exports, migrate all example and fixture bindings, and integrate plugin target declarations.
- Verify examples preserve generated behavior and run the complete tests.
- Completed: migrated 13 examples and 3 fixtures; public define now normalizes scoped declaration trees.
- Added target-specific plugin options and compile-time attachment validation, explicit free role, and 17 compile-failure regression cases.
- Verification: zig build test completed 299/299 steps and 760/760 tests; all example go-check and configured purego checks passed, including the tagged-union -Dpurego build.
- Event-queue and stream output changed only by declaration order; semantic content was compared after sorting top-level arrays and was identical.

## Done When

- All in-repository consumers use the new public authoring API and the full test suite passes.
