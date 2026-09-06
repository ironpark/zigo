---
description: Add .semantic = .codepoint so u21/u32 values and slices surface as Go rune
plan_status: in-progress
registered_at: "2026-09-06T02:26:02Z"
---
> NEXT: Add the hint to the IR with validation and diff coverage. ([Phase 0](phases/00-ir-validation.md))

# Phases

- [x] [Phase 00: IR, validation and diff](phases/00-ir-validation.md)
- [x] [Phase 01: Public emission and generator cases](phases/01-emit.md)
- [ ] [Phase 02: Examples and docs](phases/02-examples-docs.md)

# Shared Verification

`zig build test --summary all`; `scripts/update-generator-cases.sh` output diff reviewed; example `go test` on cgo and `CGO_ENABLED=0`.

# Decisions That Constrain Ordering

0 → 1 → 2.

# Next Implementation Target

Add the hint to the IR with validation and diff coverage.
