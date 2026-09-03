---
depends_on:
- "108-materialized-result-trees#2"
perf_phase: false
status: planned
---
> DONE-WHEN: The example passes on both backends in CI and the docs describe registration, positions, ownership and limits.
> NEXT: none

# Example, benchmark and docs

## Planned Work

- Example with a nested tree and a batch `[]T` function; Go tests and a benchmark against the accessor-handle form on both backends; CI matrix entries; `bindings.md`, `abi.md`, CHANGELOG.

## Done When

- The example passes on both backends in CI and the docs describe registration, positions, ownership and limits.
