---
completed_at: "2026-09-01T11:32:06Z"
depends_on:
- "53-unified-handle-lifecycle#1"
perf_phase: false
status: done
---
> DONE-WHEN: All fourteen trees pass `go test`, `gofmt -l`, `go vet`; grep confirms
> NEXT: none

# Regenerate all examples and document the lifecycle

## Planned Work

- Regenerate all ten examples (cgo and purego) with the final generator.
- Update `docs/bindings.md` (and any other doc describing handle lifecycle)
  to describe the single unified lifecycle: locking guarantee, GC safety
  net, and Close semantics.
- Verify no generated tree retains the old single-scheme artifacts
  (mutex-less owned handles, or callback fields on callback-less types).

## Done When

- All fourteen trees pass `go test`, `gofmt -l`, `go vet`; grep confirms
  every owned handle struct has `mu` and `cleanup`, and `callbackHandles`
  appears only on callback-owning types.
- Docs updated; `planr overview` shows the plan done.
