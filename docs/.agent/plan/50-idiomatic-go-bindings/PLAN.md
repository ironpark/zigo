---
completed_at: "2026-08-31T19:59:36Z"
description: "Make generated Go bindings more idiomatic: Must-naming inversion, handle/ref dedup, enum const blocks, Close() error, regen stale examples"
plan_status: done
registered_at: "2026-08-31T19:35:34Z"
---
> NEXT: none

# Phases

- [x] [Phase 00: Error-first naming: base methods return errors, Must variants panic](phases/00-error-first-naming.md)
- [x] [Phase 01: Deduplicate handle/ref method bodies](phases/01-handle-ref-dedup.md)
- [x] [Phase 02: Idiomatic small surface: enum blocks, Close() error, helper cleanup](phases/02-enum-and-close-idioms.md)
- [x] [Phase 03: Regenerate all examples and retire the stale lifecycle](phases/03-regen-all-examples.md)

# Shared Verification

- `zig build test` after every phase (generator unit tests plus golden
  comparisons).
- Per-example: `go test ./...` in each regenerated module (cgo and purego
  variants), plus `gofmt -l` and `go vet` in phase 2 and 3.
- Grep-based checks named in each phase's Done When (panic outside `Must*`,
  duplicate projection bodies, `sync.RWMutex` remnants).

# Decisions That Constrain Ordering

Phase 0 first because it changes the names every later phase touches. Phases 1
and 2 are independent of each other and both depend on 0. Phase 3 is the final
sweep and depends on both.

# Next Implementation Target

None: every phase is done. Two findings are recorded here as candidate
follow-up plans rather than work for this one.

- Sealed-interface (variant type) representation of tagged unions. Instead of
  `As<Variant>` projections, emit one interface per union and one type per
  variant so a type switch replaces the accessor chain. Explicitly out of
  scope here.
- `sync.RWMutex` in generated handles. It survives regeneration in examples
  04, 05, 07, and 08, but not because those trees were stale: the generator
  emits the mutex for every program that carries callbacks, to serialize
  `Close` against in-flight callback-bearing calls. Replacing it with the
  `sync.Once` plus `runtime.AddCleanup` scheme alone would change that
  lifecycle guarantee, so it needs its own plan.
