---
completed_at: "2026-09-07T06:39:40Z"
depends_on:
- "143-composable-declaration-dsl#0"
perf_phase: false
status: done
---
> DONE-WHEN: Every batch expands to ordered `zigo.Type` entries with the requested representation and exact Go name.
> NEXT: none

# Named type batches

## Planned Work

- Add exact-declaration batch helpers for handles, values, enumerations, and tagged unions.
- Define typed options only where the representation has meaningful batch defaults, including text/open enumeration behavior.
- Reuse generic collection to compose generated type arrays and exceptional literal entries.
- Add tests for declaration/name coupling, ordering, options, and invalid declarations.

## Done When

- Every batch expands to ordered `zigo.Type` entries with the requested representation and exact Go name.
- Missing declarations, wrong Zig kinds where applicable, and duplicate names are diagnosed at compile time.
