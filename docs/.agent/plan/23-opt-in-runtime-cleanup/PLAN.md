---
completed_at: "2026-08-30T08:33:41Z"
description: Add opt-in Go 1.24 runtime.AddCleanup fallback for generated owned handles with safe state isolation, KeepAlive, tests, and documentation.
plan_status: done
registered_at: "2026-08-30T08:22:11Z"
---
> NEXT: Propagate the opt-in and emit cleanup-safe Go wrappers with focused tests. ([Phase 0](phases/00-option-and-safe-emission.md))

# Phases

- [x] [Phase 00: Option and safe emission](phases/00-option-and-safe-emission.md)
- [x] [Phase 01: Runtime example and documentation](phases/01-runtime-example-and-documentation.md)
- [x] [Phase 02: Repository compatibility verification](phases/02-repository-compatibility-verification.md)

# Shared Verification

Run focused generator tests, `zig build test`, `zig build check`, Windows cross-check, `zig fmt --check .`, `git diff --check`, all example `go-check`/`abi-check` steps, all Go module tests, and available example Zig tests. Run the event-queue fallback test repeatedly to detect cleanup flakiness.

# Decisions That Constrain Ordering

Prove the emitted lifetime invariants before enabling a real example; prove runtime behavior before repository-wide compatibility checks.

# Next Implementation Target

Propagate the opt-in and emit cleanup-safe Go wrappers with focused tests.
