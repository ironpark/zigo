---
completed_at: "2026-09-06T06:25:42Z"
description: Materialized layout v2 (compact widths, arrays, nested slices, extern struct and bytes fields), zero-copy Go decode, and .covers on enum type entries
plan_status: done
registered_at: "2026-09-06T06:04:33Z"
---
> NEXT: Layout version 2 with recursive shapes. ([Phase 0](phases/00-layout-v2.md))

# Phases

- [x] [Phase 00: Layout version 2 with recursive shapes](phases/00-layout-v2.md)
- [x] [Phase 01: Decode from the native buffer](phases/01-zero-copy-decode.md)
- [x] [Phase 02: `.covers` on enum type entries](phases/02-enum-covers.md)
- [x] [Phase 03: Documentation](phases/03-docs.md)

# Shared Verification

`zig build test`; example 12 `zig build go purego-go` and `go test ./...`
plus `go test -bench Decode` in both Go dirs; `zig build go-coverage` on a
sample with enum covers.

# Decisions That Constrain Ordering

Phase 0, then 1 (depends on decoder API), phase 2 independent, docs last.

# Next Implementation Target

Layout version 2 with recursive shapes.
