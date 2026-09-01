---
completed_at: "2026-09-01T22:57:24Z"
description: Allow extern struct slice elements, string slice params, and caller-owned slice returns with release; fix slice-return copy bugs
plan_status: done
registered_at: "2026-09-01T21:30:55Z"
---
> NEXT: Fix the cgo `GoBytes` and purego `unsafe.Slice` slice-return paths and document the copy contract. ([Phase 0](phases/00-slice-return-copies.md))

# Phases

- [x] [Phase 00: Fix slice-return copies](phases/00-slice-return-copies.md)
- [x] [Phase 01: Extern struct slice elements](phases/01-struct-slice-elements.md)
- [x] [Phase 02: Sentinel byte pointers](phases/02-sentinel-byte-pointers.md)
- [x] [Phase 03: String slice parameters](phases/03-string-slice-params.md)
- [x] [Phase 04: Caller-owned slice returns with release](phases/04-caller-owned-slice-returns.md)

# Shared Verification

- `zig build test --summary all` at the root after every phase.
- Touched examples: `zig build test go-check abi-check --summary all`, then
  `zig build go` and `(cd go && go test -count=1 ./...)`; `git status --short`
  shows only intended generated changes.
- purego examples: `zig build purego-go purego-go-verify --summary all` and
  `CGO_ENABLED=0 go test ./...` in `go-purego`.
- Generator-case goldens regenerated through the case runner and
  `zig build snapshot --update-snapshots`; diffs reviewed by hand.
- Each new diagnostic has a validate snapshot test.

# Decisions That Constrain Ordering

Phase 0 first: it fixes the copy path every later slice feature builds on.
Phases 1 and 2 are independent of each other and of phase 0 and may run in
parallel. Phase 3 depends on phase 2 for the element type. Phase 4 depends on
phase 0 and benefits from phase 1 for struct elements but does not require it.

# Next Implementation Target

Fix the cgo `GoBytes` and purego `unsafe.Slice` slice-return paths and document the copy contract.
