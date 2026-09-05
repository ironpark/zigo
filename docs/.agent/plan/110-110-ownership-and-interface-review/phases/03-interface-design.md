---
depends_on:
- "110-110-ownership-and-interface-review#2"
perf_phase: false
status: planned
---
> DONE-WHEN: The design document has the registration shape, the validation rules, the
> NEXT: none

# Interface design and recommendation

## Planned Work

- Design the registration: a `.interfaces` entry naming a Go interface, the
  method set (by Zig declaration name), and the registered handles that
  implement it; the reflector checks every listed type has each method with
  the same lowered signature and emits the Go interface plus compile-time
  `var _ Iface = (*T)(nil)` assertions.
- Decide whether `anytype` functions are exposable at all: only through
  explicit specializations listed per concrete type, one Go method per
  specialization, or a generic Go function constrained by the interface.
- Compare with the existing sealed-interface generation for tagged unions
  and reuse its naming and file placement.
- Recommend: implement, implement a subset (vtable and explicit
  specializations only), or decline. Estimate phases.

## Done When

- The design document has the registration shape, the validation rules, the
  emitted Go per pattern, and a recommendation.
