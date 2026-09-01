---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Docs explain the hazard; either the option exists with tests and a build-time
> NEXT: none

# Value struct append ABI policy

## Planned Work

- Document in `generated-code.md` and 03 §6.1 why trailing field appends are
  breaking (pointer-passed aggregates, newer native writing larger out structs
  into older Go buffers under purego/dynamic linking) and that static cgo is
  lockstep.
- Decide with the maintainer whether to add an opt-in `abi_check` policy such
  as `.value_struct_append = .compatible`. If added: accepted only when
  `link` is static cgo (panic in `build.zig` otherwise), classified as
  `.compatible` with the reason text naming the option, and covered by
  `abi_diff` tests for both settings.

## Done When

- Docs explain the hazard; either the option exists with tests and a build-time
  gate, or the decision to keep appends breaking is recorded in
  `limitations.md`; committed.
