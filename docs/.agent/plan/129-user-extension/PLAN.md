---
description: Reserved zigo* names for generated unexported identifiers and .go type adapters on value structs
plan_status: in-progress
registered_at: "2026-09-06T01:10:46Z"
---
> NEXT: Reserved zigo names. ([Phase 0](phases/00-reserved-names.md))

# Phases

- [ ] [Phase 00: Reserved zigo names](phases/00-reserved-names.md)
- [ ] [Phase 01: Type adapters](phases/01-type-adapters.md)

# Shared Verification

- `zig build test --summary all`; examples `go vet`/`go test` (cgo, purego); `go-check` for all.

# Decisions That Constrain Ordering

0 → 1.

# Next Implementation Target

Reserved zigo names.
