---
completed_at: "2026-09-03T03:32:49Z"
perf_phase: false
status: done
---
> DONE-WHEN: The listed positions accept `std.atomic.Value(T)` and round-trip in Go tests on both backends; goldens unchanged elsewhere.
> NEXT: none

# Atomic values as scalars

## Planned Work

- Reflection predicate and leaf acceptance; shim `load`/`store`/`.raw`/`.init` emission for fields, flatten, value structs, union payloads, by-value params/returns; copy path for structs with atomic fields; tests, generator case, example, docs, CHANGELOG.

## Done When

- The listed positions accept `std.atomic.Value(T)` and round-trip in Go tests on both backends; goldens unchanged elsewhere.
