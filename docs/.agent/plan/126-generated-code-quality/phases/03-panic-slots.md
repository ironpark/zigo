---
depends_on:
- "126-generated-code-quality#0"
perf_phase: true
status: planned
---
> DONE-WHEN: Panic tests in 03 and 07 still see the message; benchmark shows the pin gone.
> NEXT: none

# Panic message slots without LockOSThread

## Planned Work

- panic.c slot table and `zg_panic_message`; header declaration; cgo and
  purego raw readers; `errorForCode` mapping; remove `LockOSThread` emission
  and the `runtime` import predicate where it was the only reason.
- Regenerate cases and examples; run the benchmark; rewrite the
  `generated-runtime.md` section with the new measurements; update
  `generated-abi.md` codes and CHANGELOG (minor bump note).

## Done When

- Panic tests in 03 and 07 still see the message; benchmark shows the pin gone.
