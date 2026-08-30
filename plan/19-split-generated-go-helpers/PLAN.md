---
description: Split generated package helper functions into pkgname_helpers_gen.go while preserving output atomicity and stale checks.
plan_status: in-progress
registered_at: "2026-08-30T05:24:34Z"
---
> NEXT: Implement the package helper emitter and carry the new output through the complete pipeline. ([Phase 0](phases/00-split-generated-go-helpers.md))

# Phases

- [ ] [Phase 00: Split Generated Go Helpers](phases/00-split-generated-go-helpers.md)

# Shared Verification

Run generator tests and golden cases, root `zig build test` and `check`, Windows cross-compilation, formatting and diff checks, every example's `go-check`/`abi-check`, and every Go test suite. Confirm helper symbols occur only in helper files and generated trees are current.

# Decisions That Constrain Ordering

Implement and test emitter/build support first, regenerate fixtures and examples second, update documentation and counts third, then perform full verification and commit.

# Next Implementation Target

Implement the package helper emitter and carry the new output through the complete pipeline.
