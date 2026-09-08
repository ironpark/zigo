---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `cgo-windows` and `purego-windows` succeed on main and the fix is released.
> NEXT: none

# Portable path comparison

## Planned Work

- Add `eqlPath` and `portableAlloc` to `go_walk` with unit coverage.
- Use them in `PublishGeneratedGo` for both the prune and the stale walk, and
  in `sync_check.compare` for the obsolete check and the recorded labels.
- Push and confirm both Windows CI jobs pass, then release the fix.

## Done When

- `cgo-windows` and `purego-windows` succeed on main and the fix is released.
