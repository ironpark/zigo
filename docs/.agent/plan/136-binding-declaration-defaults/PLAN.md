---
description: Define-level string defaults, callback contract defaults, and correct source-name enrichment
plan_status: in-progress
registered_at: "2026-09-06T14:40:15Z"
---
> NEXT: Fix the enrichment match so a renamed wrapper cannot inherit another ([Phase 0](phases/00-enrichment-correctness.md))

# Phases

- [ ] [Phase 00: Correct and widen name enrichment](phases/00-enrichment-correctness.md)
- [ ] [Phase 01: Define-level string defaults](phases/01-string-defaults.md)
- [ ] [Phase 02: Callback contract defaults](phases/02-callback-contract-defaults.md)
- [ ] [Phase 03: Integrate, document and land](phases/03-integrate-and-document.md)

# Shared Verification

- `zig fmt --check build.zig src tests examples`
- `zig build test --summary all`
- `scripts/update-generator-cases.sh` produces no diff for existing cases.
- `examples/09-type-relations`: `zig build go-check abi-check`, `go test ./...`.

# Decisions That Constrain Ordering

Phase 0 is a correctness fix and is independent of the other two; phases 1 and
2 both add define-level defaults and both touch `walk.zig`, so they are written
against the same base and merged in phase 3 rather than serialized.

# Next Implementation Target

Fix the enrichment match so a renamed wrapper cannot inherit another
