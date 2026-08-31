---
completed_at: "2026-08-31T19:59:36Z"
depends_on:
- "50-idiomatic-go-bindings#1"
- "50-idiomatic-go-bindings#2"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -r "sync.RWMutex" examples/*/go*/*_gen.go` returns nothing; all ten
> NEXT: none

# Regenerate all examples and retire the stale lifecycle

## Planned Work

- Regenerate `go` and `go-purego` trees for all ten examples with the final
  generator; update any hand-written example tests still using old names.
- Verify no regenerated file still contains the `mu sync.RWMutex` lifecycle;
  confirm the `AddCleanup`-based scheme is used everywhere it applies.
- Record the sealed-interface tagged-union representation as a follow-up idea
  in the plan's NEXT notes (not implemented here).

## Done When

- `grep -r "sync.RWMutex" examples/*/go*/*_gen.go` returns nothing; all ten
  examples' Go tests pass for both cgo and purego variants where present.
- `planr overview` shows all phases of this plan done.
