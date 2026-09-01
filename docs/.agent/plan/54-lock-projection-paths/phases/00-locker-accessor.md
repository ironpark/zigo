---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Regenerated example 10 shows the locker on `Value`, `ValueRef`, `Signal`,
> NEXT: none

# Locker accessor and locked projection prologues

## Planned Work

- Extend the emitted `zigoHandle` interface with `zigoLocker()`; implement
  it on every owned handle and Ref type (recursing through Ref parents).
- Emit the read-lock prologue in every shared union
  projection/snapshot/variant implementation ahead of the pointer check;
  decide and document the variant-builder locking shape (single acquisition
  or release-between-calls) in the emitter.
- Update goldens (cgo and purego) and any emit unit tests pinned to the old
  runtime block.

## Done When

- Regenerated example 10 shows the locker on `Value`, `ValueRef`, `Signal`,
  `SignalRef`, `Child`, `ChildRef` and the prologue in every `zigo*`
  shared implementation in the union files.
- `zig build test` passes; example 10 compiles and its tests pass under
  cgo and purego.
