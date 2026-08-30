---
completed_at: "2026-08-30T04:32:02Z"
description: Make ABI contract checking opt-in and detect document, symbol, and constructor compatibility breaks.
plan_status: done
registered_at: "2026-08-30T04:25:03Z"
---
> NEXT: Complete semantic contract comparison before changing the public build API. ([Phase 0](phases/00-complete-contract-diff.md))

# Phases

- [x] [Phase 00: Complete semantic contract comparison](phases/00-complete-contract-diff.md)
- [x] [Phase 01: Make compatibility policy opt-in](phases/01-opt-in-build-api.md)

# Shared Verification

Run focused ABI diff tests, `zig fmt --check build.zig src tests examples`, `zig build check`, `zig build test --summary all`, every example's `go-check abi-check`, and every example's Go tests. Confirm `git diff --check` before each phase commit.

# Decisions That Constrain Ordering

First make the comparison itself correct. Then expose it as an optional policy so examples and documentation point to a trustworthy feature.

# Next Implementation Target

Complete semantic contract comparison before changing the public build API.
