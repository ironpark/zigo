---
completed_at: "2026-09-01T11:27:07Z"
depends_on:
- "53-unified-handle-lifecycle#0"
perf_phase: false
status: done
---
> DONE-WHEN: New tests pass under `go test -race` in the touched trees and are part of
> NEXT: none

# Lifecycle tests: race and GC reclamation

## Planned Work

- Add a `-race`-run test in example 04 (cgo and purego trees) where multiple
  goroutines call handle methods while another calls Close, asserting no
  race and that post-Close calls fail with the handle error rather than
  crashing.
- Add a GC-reclamation test: create a callback-carrying handle, record the
  callback registry population, drop the handle, force GC until the cleanup
  runs, and assert the registry returns to baseline (bounded retry loop, no
  arbitrary sleeps as the only mechanism).
- Mirror a lighter concurrent-Close test in a non-callback example (10) to
  lock in the newly added serialization there.

## Done When

- New tests pass under `go test -race` in the touched trees and are part of
  the normal suite; `zig build test` still passes.
