---
completed_at: "2026-09-03T06:18:12Z"
perf_phase: false
status: done
---
> DONE-WHEN: A library whose error set has `Cancelled` binds without a wrapper and cancellation maps to `ctx.Err()`.
> NEXT: none

# Configurable cancel error name

## Planned Work

- `.cancel.canceled` metadata, semantic field with default, ZIGO026 using it, Go mapping using it, generator case, docs, CHANGELOG.

## Done When

- A library whose error set has `Cancelled` binds without a wrapper and cancellation maps to `ctx.Err()`.
