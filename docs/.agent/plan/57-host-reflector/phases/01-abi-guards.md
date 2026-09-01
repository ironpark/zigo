---
depends_on:
- "57-host-reflector#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Guards present in every regenerated shim; the divergence fixture fails
> NEXT: none

# Comptime ABI guards in the shim

## Planned Work

- Extend reflection/ABI capture if needed so the generator knows every
  extern struct's reflected size and field offsets; emit a comptime
  assert block into the shim pinning them, with messages naming struct,
  field, expected/actual, and the target-divergent-C-type hint.
- Decide and implement handling for target-divergent C scalar types in
  non-struct positions (guard or generation-time diagnostic); record the
  decision in the phase notes.
- Add a test fixture using `c_long` in an extern struct: native build
  passes; `-Dtarget=x86_64-windows` fails with the guard message
  (assert via the build-failure fixture machinery like the ZIGO007 test).
- Update shim goldens for all examples; regenerate; generated Go
  unchanged.

## Done When

- Guards present in every regenerated shim; the divergence fixture fails
  for windows and passes natively; `zig build test` green; no Go drift.
