---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Regenerated example 10 contains the sealed interface, all seven `Value`
> NEXT: none

# Emit sealed variant types and the shared builder

## Planned Work

- In `src/gen/emit.zig` (with name derivation in `src/gen/naming.zig`), emit
  per union: the sealed `<Union>Variant` interface, one exported concrete
  type per variant with exported payload fields and the unexported marker
  method, and the shared builder `zigo<Union>Variant` implementing the
  tag-then-single-projection strategy (snapshot fast path deferred to the
  next phase).
- Implement deterministic collision handling for variant type names with a
  generator diagnostic on unresolvable clashes.
- Emit `Variant() (<Union>Variant, error)` and `MustVariant()` on handle and
  ref types as one-line delegations.
- Update golden fixtures for cgo and purego emission.

## Done When

- Regenerated example 10 contains the sealed interface, all seven `Value`
  variants and all six `Signal` variants as concrete types, and
  `Variant`/`MustVariant` on `Value`, `ValueRef`, `Signal`, `SignalRef`.
- `zig build test` passes; example 10 compiles under cgo and purego.
