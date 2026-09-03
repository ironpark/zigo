---
perf_phase: false
status: planned
---
> DONE-WHEN: A library whose error set has `Cancelled` binds without a wrapper and cancellation maps to `ctx.Err()`.
> NEXT: none

# Configurable cancel error name

## Planned Work

- `.cancel.canceled` metadata, semantic field with default, ZIGO026 using it, Go mapping using it, generator case, docs, CHANGELOG.

## Done When

- A library whose error set has `Cancelled` binds without a wrapper and cancellation maps to `ctx.Err()`.
