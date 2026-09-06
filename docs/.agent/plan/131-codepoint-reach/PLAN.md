---
depends_on:
- codepoint-semantic
description: "Codepoint hints: Unicode range check, u21 inference option, extern struct fields, and callback signatures"
plan_status: in-progress
registered_at: "2026-09-06T03:12:32Z"
---
> NEXT: Unicode range check and the inference option. ([Phase 0](phases/00-range-inference.md))

# Phases

- [x] [Phase 00: Unicode range and u21 inference](phases/00-range-inference.md)
- [x] [Phase 01: Extern struct fields](phases/01-struct-fields.md)
- [ ] [Phase 02: Callback signatures](phases/02-callbacks.md)

# Shared Verification

`zig build test --summary all`; `scripts/update-generator-cases.sh`; per-example `zig build go-check purego-go-check abi-check` plus `go vet`/`go test` on both backends.

# Decisions That Constrain Ordering

0 → 1 → 2 (1 and 2 are independent but share the docs section, so they run in order).

# Next Implementation Target

Unicode range check and the inference option.
