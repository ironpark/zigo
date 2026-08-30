---
description: Discover supported public Zig functions automatically while preserving explicit metadata overrides and existing binding declarations.
plan_status: in-progress
registered_at: "2026-08-30T05:40:49Z"
---
> NEXT: Implement owner-qualified reflection identity and AST enrichment against the actual target source root. ([Phase 0](phases/00-qualified-reflection-model.md))

# Phases

- [x] [Phase 00: Qualified reflection model](phases/00-qualified-reflection-model.md)
- [x] [Phase 01: Opt-in automatic discovery](phases/01-opt-in-automatic-discovery.md)
- [x] [Phase 02: Broad fixture and documentation](phases/02-broad-fixture-and-documentation.md)
- [ ] [Phase 03: Full compatibility verification](phases/03-full-compatibility-verification.md)

# Shared Verification

- `zig version` reports 0.16.0.
- `zig build test` and `zig build check` pass at the repository root.
- `zig build check -Dtarget=x86_64-windows-gnu` passes.
- Every example passes its generation/stale checks and `go test ./...`.
- `zig fmt --check .` and `git diff --check` pass.

# Decisions That Constrain Ordering

Qualified identity must land before discovery so AST metadata cannot attach to the wrong method. Discovery must stabilize before migrating the broad fixture and documentation. Full verification follows all observable changes.

# Next Implementation Target

Implement owner-qualified reflection identity and AST enrichment against the actual target source root.
