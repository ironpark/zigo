---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test` passes with the emitter still minting its own names, so
> NEXT: none

# IR records for enums and handles

## Planned Work

- Add to `abi.zig`: `AbiOpaque { name, c_name }` and `AbiEnum { name, c_name,
  tag: AbiScalar, constants: []const Constant }` where
  `Constant { name, c_name, value }` and `c_name` is the final uppercased
  form the header emits.
- Change `AbiScalar.opaque` from `[]const u8` to `AbiOpaque`.
- Add `enums: []const AbiEnum = &.{}` and `handles: []const AbiOpaque = &.{}`
  to `Program`.
- In `lower.zig`, populate both from `document.types`, reusing
  `cTypeNameAlloc`; fill the new `AbiScalar.opaque` field at its three
  construction sites (`lower.zig:29`, `498`, `520`).
- Update the `lower.zig` in-file tests that assert on `scalar.opaque` as a
  bare string (`lower.zig:682`, `712`).

## Done When

- `zig build test` passes with the emitter still minting its own names, so
  this phase is provably a pure IR addition.
- The new records are asserted in a `lower.zig` test: an enum's `c_name` and
  its constants' `c_name`s match what the header currently emits.
