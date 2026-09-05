---
description: "Tidy generated Go: borrowed-handle acquire shape, one empty-slice pointer helper, grouped raw imports, accurate Close docs"
plan_status: in-progress
registered_at: "2026-09-05T23:31:33Z"
---
> NEXT: Template cleanups. ([Phase 0](phases/00-cleanups.md))

# Phases

- [ ] [Phase 00: Template cleanups](phases/00-cleanups.md)

# Shared Verification

- `zig build test --summary all`; examples `go vet`/`go test` (cgo, purego); `go-check` for all.

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Template cleanups.
