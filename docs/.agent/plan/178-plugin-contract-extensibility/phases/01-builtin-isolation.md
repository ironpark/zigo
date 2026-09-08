---
depends_on:
- "178-plugin-contract-extensibility#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Built-ins compile only against public modules; generator and golden tests preserve output; commit changes.
> NEXT: none

# Built-in isolation and analysis

## Planned Work

- Expose public rendering services, compile built-ins as separate modules and migrate their internal dependencies.
- Add run-owned plugin facts and analysis; move Must emission policy off AbiFn.

## Done When

- Built-ins compile only against public modules; generator and golden tests preserve output; commit changes.
