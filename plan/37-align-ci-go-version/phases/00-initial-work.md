---
perf_phase: false
status: in-progress
---
> DONE-WHEN: The affected `go.mod` files declare Go 1.24, no example requires a newer version, tests pass, and the scoped fix is committed.
> NEXT: none

# Initial Work

## Planned Work

- Lower the two incompatible module directives to Go 1.24, verify all example module directives, and run the affected Go tests.

## Done When

- The affected `go.mod` files declare Go 1.24, no example requires a newer version, tests pass, and the scoped fix is committed.
