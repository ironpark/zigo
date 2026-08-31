---
description: "Add sealed-interface variant representation for tagged unions: per-variant types + Variant() so Go users type-switch instead of As* probing"
plan_status: in-progress
registered_at: "2026-08-31T20:02:17Z"
---
> NEXT: Emit sealed variant interfaces, concrete variant types, and the shared Variant builder. ([Phase 0](phases/00-emit-variant-types.md))

# Phases

- [x] [Phase 00: Emit sealed variant types and the shared builder](phases/00-emit-variant-types.md)
- [ ] [Phase 01: Snapshot fast path for scalar-only unions](phases/01-snapshot-fast-path.md)
- [ ] [Phase 02: Regenerate examples and add type-switch coverage](phases/02-regen-and-tests.md)

# Shared Verification

- `zig build test` after every phase (unit + golden comparisons, cgo and
  purego emission).
- Example 10 `go test ./...` for both variants after phases 0 and 2; all ten
  examples after phase 2, plus `gofmt -l` and `go vet`.
- Grep checks: single raw call in the scalar-only builder (phase 1); no
  `panic(` outside `Must*`/helpers preserved from plan 50.

# Decisions That Constrain Ordering

Phase 0 establishes the types and builder with the general strategy. Phase 1
optimizes the scalar-only case on top of it. Phase 2 regenerates everything
and locks behavior in with tests, so it runs last.

# Next Implementation Target

Emit sealed variant interfaces, concrete variant types, and the shared Variant builder.
