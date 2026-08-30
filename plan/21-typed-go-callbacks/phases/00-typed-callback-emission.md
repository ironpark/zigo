---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Focused generator and golden tests prove no callback value crosses the public helper as `any`, while raw assertions remain valid.
> NEXT: none

# Typed callback emission

## Planned Work

- Add deterministic callback type/helper naming derived from function owner and callback parameter.
- Emit public defined callback types and use them in function parameters.
- Emit per-callback typed handle helpers that store an explicit unnamed-function conversion.
- Cover multiple signatures, duplicate roles, retained/borrowed lifetimes, and raw trampoline compatibility in generator tests.

## Done When

- Focused generator and golden tests prove no callback value crosses the public helper as `any`, while raw assertions remain valid.
