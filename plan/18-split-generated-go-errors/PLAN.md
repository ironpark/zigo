---
completed_at: "2026-08-30T05:21:54Z"
description: Split package-level generated Go error declarations into pkgname_errors_gen.go while preserving atomic generation and stale checks.
plan_status: done
registered_at: "2026-08-30T05:15:31Z"
---
> NEXT: Implement and validate the dedicated generated Go errors file across the full pipeline. ([Phase 0](phases/00-split-generated-go-errors.md))

# Phases

- [x] [Phase 00: Split Generated Go Errors](phases/00-split-generated-go-errors.md)

# Shared Verification

Run generator/unit/snapshot tests, `zig build test`, `zig build check`, Windows cross-compilation, `zig fmt --check`, and `git diff --check`. Regenerate every example, run `go-check`, applicable `abi-check`, and every Go test suite, then confirm no stale or unexpected generated files remain.

# Decisions That Constrain Ordering

Implement emitter and build-graph support first, update fixtures and tests second, regenerate examples and documentation third, then perform full verification and commit before closing the phase.

# Next Implementation Target

Implement and validate the dedicated generated Go errors file across the full pipeline.
