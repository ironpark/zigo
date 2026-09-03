---
depends_on:
- "96-abi-classification-in-lowering#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Emitter has no string/callback/struct classification predicates left; goldens and examples unchanged; tests green.
> NEXT: none

# Record classification on the lowered IR

## Planned Work

- Add string role, string slice form, callback/userdata pairing, callback type name, and struct castability to the lowered IR; populate in lowering with the current rules (including the optional C-string return behaviour); switch the emitter to read them and delete the emitter predicates; lowering unit tests for each classification.

## Done When

- Emitter has no string/callback/struct classification predicates left; goldens and examples unchanged; tests green.
