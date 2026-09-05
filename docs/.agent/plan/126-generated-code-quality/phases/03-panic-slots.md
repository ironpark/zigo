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

- Parked: the implementation lives on the `experiment/panic-slots` branch
  (sequence-tagged slot table, `{prefix}_caught_panic_message(code)`, panic
  status codes at -256 and below, no `LockOSThread` in generated functions).
  Measured after phase 0 it saves about 5 ns of a 260 ns call (2%), the same
  figure plan 68 recorded, so it stays below the threshold for changing the
  panic-message ABI. The 11% first seen was the per-slot mutex sweep that
  phase 0 removed, not the thread pin.
- If the entry condition is ever met: rebase the branch, fix the purego
  cancel path's `runtime` reference and the generator unit test, regenerate
  cases and examples, and document the code range in `generated-abi.md`.

## Done When

- Panic tests in 03 and 07 still see the message; benchmark shows the pin gone.
