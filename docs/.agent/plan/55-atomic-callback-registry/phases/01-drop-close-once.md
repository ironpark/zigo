---
completed_at: "2026-09-01T12:03:54Z"
depends_on:
- "55-atomic-callback-registry#0"
perf_phase: false
status: done
---
> DONE-WHEN: No generated handle struct contains `sync.Once`; concurrent double-Close
> NEXT: none

# Drop the redundant Close once and regenerate

## Planned Work

- Remove `once sync.Once` from the unified handle template; make Close's
  idempotency rest on the write lock + nil-pointer check as described in
  the target structure.
- Extend a lifecycle test with concurrent double-Close (many goroutines
  calling Close simultaneously) under `-race` in example 10's cgo tree.
- Update goldens (cgo and purego), regenerate all ten examples, and run the
  full fourteen-tree sweep.
- Update `docs/bindings.md` if it mentions the once-based lifecycle.

## Done When

- No generated handle struct contains `sync.Once`; concurrent double-Close
  test passes under `-race`; all fourteen trees pass `go test`, `gofmt -l`,
  `go vet`; `zig build test` green; `planr overview` shows the plan done.
