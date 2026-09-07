---
completed_at: "2026-09-07T06:35:58Z"
perf_phase: false
status: done
---
> DONE-WHEN: Exact names retain their requested order and all invalid selector shapes produce intentional compile errors.
> NEXT: none

# Stable function lists and projections

## Planned Work

- Extend `FuncSelector` with mutually exclusive exact `names` selection and compile-time validation.
- Generalize `collect` to infer and enforce a single supported element type.
- Add `pathsOf` to derive fixed-size path arrays from function entries.
- Cover ordering, validation rules, compatibility, and path projection with focused tests.

## Done When

- Exact names retain their requested order and all invalid selector shapes produce intentional compile errors.
- Existing prefix/exclude tests and new collection/projection tests pass.
