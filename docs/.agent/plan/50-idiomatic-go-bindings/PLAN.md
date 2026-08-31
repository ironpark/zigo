---
description: "Make generated Go bindings more idiomatic: Must-naming inversion, handle/ref dedup, enum const blocks, Close() error, regen stale examples"
plan_status: in-progress
registered_at: "2026-08-31T19:35:34Z"
---
> NEXT: Invert the generated naming so base methods return errors and Must variants panic. ([Phase 0](phases/00-error-first-naming.md))

# Phases

- [ ] [Phase 00: Error-first naming: base methods return errors, Must variants panic](phases/00-error-first-naming.md)
- [ ] [Phase 01: Deduplicate handle/ref method bodies](phases/01-handle-ref-dedup.md)
- [ ] [Phase 02: Idiomatic small surface: enum blocks, Close() error, helper cleanup](phases/02-enum-and-close-idioms.md)
- [ ] [Phase 03: Regenerate all examples and retire the stale lifecycle](phases/03-regen-all-examples.md)

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

Invert the generated naming so base methods return errors and Must variants panic.
