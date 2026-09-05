---
description: Cheaper callback-panic sweep, stable receiver names and GoDoc, single-copy strings and struct slices, and a panic-message ABI that drops LockOSThread
plan_status: in-progress
registered_at: "2026-09-05T22:46:00Z"
---
> NEXT: Pending callback-panic counter. ([Phase 0](phases/00-panic-counter.md))

# Phases

- [x] [Phase 00: Pending callback-panic counter](phases/00-panic-counter.md)
- [x] [Phase 01: Receiver names and GoDoc first line](phases/01-receiver-godoc.md)
- [ ] [Phase 02: Single-copy strings and struct slices](phases/02-single-copy.md)
- [ ] [Phase 03: Panic message slots without LockOSThread](phases/03-panic-slots.md)

# Shared Verification

- `zig build test --summary all` after every phase.
- Examples 03, 04, 07, 08, 11, 12: `zig build go` (+ `purego-go`), `go-check`,
  `purego-go-check`, `abi-check`, `go test` (cgo and `CGO_ENABLED=0`).
- `go test -bench BenchmarkEnqueue -count=5` in 07 before and after phases 0 and 3.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3. Phase 3 depends on 0 so the benchmark isolates each gain.

# Next Implementation Target

Pending callback-panic counter.
