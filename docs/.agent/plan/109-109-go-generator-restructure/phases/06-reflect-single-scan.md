---
completed_at: "2026-09-05T07:25:50Z"
perf_phase: false
status: done
---
> DONE-WHEN: A run of `coverage` reads and parses each `.zig` file at most once
> NEXT: none

# Reflect scans each source once

## Planned Work

- `names.apply` records the set of source paths it scanned and the root source
  text; `applyCoverageImports` takes that record instead of re-reading the root
  and seeds `visited` with every path already scanned.
- `src/reflect/main.zig` threads the record between the two calls.

## Done When

- A run of `coverage` reads and parses each `.zig` file at most once
  (verified with a unit test counting scans on a fixture with a shared import).
- Coverage report output for `tests/fixtures` is unchanged.
