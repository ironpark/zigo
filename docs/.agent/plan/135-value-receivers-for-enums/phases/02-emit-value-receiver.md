---
depends_on:
- "135-value-receivers-for-enums#1"
perf_phase: false
status: planned
---
> DONE-WHEN: The new cases' goldens compile and their Go tests pass under cgo and purego,
> NEXT: none

# Emit value-receiver methods

## Planned Work

- Split every `receiver != null` site that means "handle" onto
  `receiverIsHandle()`: the receiver spelling at `public.zig:408` (value
  receiver, no pointer), `needs_handle_check`, the retained callback sweeps, the
  borrowed-return and stream checks in `validate/functions.zig`.
- Pass the receiver to the raw layer as the enum's backing integer in the cgo and
  purego paths; the shim receives it as a normal parameter and calls
  `Receiver.method(value, ...)`.
- `abi_diff` reports a function moving between package level and a receiver, and
  a receiver kind change, as breaking.
- `report` names the receiver kind so `go-report` explains why a method has no
  handle bookkeeping.
- Generator case `enum_receiver` plus its purego twin: a method returning a
  scalar, one returning a `[]const u8` with `.semantic = .utf8_string`, one
  returning `u21` under `.codepoints = .infer_u21`, and one on an open enum.

## Done When

- The new cases' goldens compile and their Go tests pass under cgo and purego,
  `zig build test --summary all` passes, and pre-existing goldens are unchanged.
